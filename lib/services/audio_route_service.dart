import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

import 'native_call_audio.dart';

enum AudioRouteType {
  speaker,
  earpiece,
  bluetooth,
  wired,
  device,
}

class AudioRouteOption {
  const AudioRouteOption({
    required this.id,
    required this.label,
    required this.type,
    this.device,
  });

  final String id;
  final String label;
  final AudioRouteType type;
  final MediaDevice? device;

  bool get isDeviceBacked => device != null;
}

typedef AudioRouteDeviceEnumerator = Future<List<MediaDevice>> Function();
typedef AudioRouteSelector = Future<void> Function(
  AudioRouteOption option,
  Room? room,
);

class AudioRouteService extends ChangeNotifier {
  AudioRouteService({
    AudioRouteDeviceEnumerator? enumerateAudioOutputs,
    AudioRouteSelector? selectAudioRoute,
    Stream<List<MediaDevice>>? deviceChanges,
    List<AudioRouteOption>? initialRoutes,
    String? initialSelectedRouteId,
    bool? isMobilePlatform,
    // CA1: нативный аудиороутер (Android). Инъекция — для тестов; в
    // тестах передавай enableNativeAudio:false, чтобы остаться на
    // LiveKit-пути (тестовая платформа = android и иначе создался бы
    // реальный MethodChannel).
    CallAudioRouter? nativeAudio,
    bool? enableNativeAudio,
  })  : _enumerateAudioOutputs =
            enumerateAudioOutputs ?? _defaultEnumerateAudioOutputs,
        _selectAudioRoute = selectAudioRoute ?? _selectLiveKitRoute,
        _deviceChanges = deviceChanges,
        _isMobilePlatform = isMobilePlatform ?? _defaultIsMobilePlatform,
        _nativeAudio = nativeAudio ??
            ((enableNativeAudio ?? _defaultUseNativeAudio)
                ? NativeCallAudio()
                : null) {
    if (initialRoutes != null && initialRoutes.isNotEmpty) {
      _routes = List<AudioRouteOption>.unmodifiable(initialRoutes);
      _selectedRouteId = initialSelectedRouteId ?? initialRoutes.first.id;
    }
  }

  final AudioRouteDeviceEnumerator _enumerateAudioOutputs;
  final AudioRouteSelector _selectAudioRoute;
  final Stream<List<MediaDevice>>? _deviceChanges;
  final bool _isMobilePlatform;
  final CallAudioRouter? _nativeAudio;

  Room? _room;
  StreamSubscription<List<MediaDevice>>? _deviceChangesSubscription;
  StreamSubscription<void>? _nativeDeviceSubscription;
  List<AudioRouteOption> _routes = const <AudioRouteOption>[];
  String? _selectedRouteId;
  bool _isRefreshing = false;
  bool _isSelecting = false;
  String? _errorMessage;
  Timer? _postSelectRefreshTimer;
  // CA1 (ревью D): сериализация attachRoom — чтобы attachRoom(null) на
  // завершении и attachRoom(room) на параллельном коннекте не переплелись
  // на await native.stop()/start() и не оставили аудиосессию в
  // неконсистентном режиме (нет звука / утечка подписки).
  Future<void> _attachQueue = Future<void>.value();
  // CA1 (ревью E): коалесинг — не терять последний запрос, если событие
  // пришло во время уже идущей операции (иначе переключатель «залипает»
  // на устаревшем устройстве).
  bool _refreshPending = false;
  AudioRouteOption? _pendingSelectRoute;
  // Гигиена звонков: текущее желаемое состояние proximity-лока — guard
  // от повторных вызовов моста при каждом notify координатора.
  bool _proximityEnabled = false;
  // Ревью P2: маршрут, который выбрал ПОЛЬЗОВАТЕЛЬ (или дефолт на
  // attach). refreshRoutes реконсилирует _selectedRouteId с фактическим
  // OS-маршрутом, который во время SCO-переговоров транзиентен —
  // reassert по нему отменял бы недоделанное переключение на Bluetooth.
  // Reassert применяет ИМЕННО намерение, не OS-снимок.
  String? _lastUserSelectedRouteId;

  List<AudioRouteOption> get routes => _routes;
  String? get selectedRouteId => _selectedRouteId;
  bool get isRefreshing => _isRefreshing;
  bool get isSelecting => _isSelecting;
  String? get errorMessage => _errorMessage;

  AudioRouteOption? get selectedRoute => _routes.firstWhereOrNull(
        (route) => route.id == _selectedRouteId,
      );

  Future<void> attachRoom(Room? room, {bool isVideo = false}) {
    // CA1 (ревью D): прогоняем через очередь, чтобы соседние attach не
    // переплелись на своих await'ах (native start/stop, отписки).
    final next =
        _attachQueue.then((_) => _attachRoomLocked(room, isVideo: isVideo));
    _attachQueue = next.catchError((_) {});
    return next;
  }

  Future<void> _attachRoomLocked(Room? room, {bool isVideo = false}) async {
    if (identical(_room, room)) {
      return;
    }
    _room = room;
    await _deviceChangesSubscription?.cancel();
    _deviceChangesSubscription = null;
    await _nativeDeviceSubscription?.cancel();
    _nativeDeviceSubscription = null;
    if (room == null) {
      // FR1: звонок завершён — отпускаем фокус, чистим маршрут, mode.
      // FR-E: гасим отложенный тап, чтобы он не применился после stop.
      _pendingSelectRoute = null;
      _lastUserSelectedRouteId = null;
      // Kotlin-мост отпустит proximity-лок внутри stop(); синхронизируем
      // Dart-флаг, чтобы следующий звонок начал с чистого состояния.
      _proximityEnabled = false;
      await _nativeAudio?.stop();
      // Call over → hand audio-focus management back to webrtc default.
      await _setWebrtcManageAudioFocus(true);
      _routes = const <AudioRouteOption>[];
      _selectedRouteId = null;
      _errorMessage = null;
      notifyListeners();
      return;
    }
    final native = _nativeAudio;
    if (native != null) {
      // FR1: режим связи + аудиофокус на старте звонка.
      await native.start();
      // CA1+: flutter-webrtc grabs Android audio focus/mode/route on connect
      // (livekit calls setAndroidAudioConfiguration(communication) =
      // manageAudioFocus:true), which fought the bridge — «Динамик» did
      // nothing and hardware volume buttons missed STREAM_VOICE_CALL. Tell
      // webrtc to STOP managing focus so the bridge is the SOLE owner.
      await _setWebrtcManageAudioFocus(false);
      // FR5: реальные смены аудиоустройств (BT/провод) → пересобрать.
      _nativeDeviceSubscription = native.deviceChanges.listen((_) {
        unawaited(refreshRoutes());
      });
    }
    final deviceChanges =
        _deviceChanges ?? Hardware.instance.onDeviceChange.stream;
    _deviceChangesSubscription = deviceChanges.listen((_) {
      unawaited(refreshRoutes());
    });
    await refreshRoutes();
    // FR3: применить дефолтный маршрут на коннекте даже без сохранённой
    // преференции — ушной для аудио, динамик для видео (Telegram-поведение).
    // Это и есть причина «на ушном тишина» на первом звонке.
    if (native != null) {
      final defaultId = isVideo ? 'speaker' : 'earpiece';
      final defaultOption =
          _routes.firstWhereOrNull((route) => route.id == defaultId);
      if (defaultOption != null) {
        await selectRoute(defaultOption);
      }
    }
  }

  // CA1+: relinquish (false) / restore (true) flutter-webrtc's Android audio
  // focus management. Only meaningful on the native-bridge path (Android);
  // best-effort — a native failure must never break the call. Re-asserted on
  // every route change because webrtc may re-grab on audio (un)publish.
  Future<void> _setWebrtcManageAudioFocus(bool manage) async {
    if (_nativeAudio == null) {
      return;
    }
    try {
      await rtc.Helper.setAndroidAudioConfiguration(
        rtc.AndroidAudioConfiguration(
          manageAudioFocus: manage,
          androidAudioMode: rtc.AndroidAudioMode.inCommunication,
          androidAudioStreamType: rtc.AndroidAudioStreamType.voiceCall,
          androidAudioAttributesUsageType:
              rtc.AndroidAudioAttributesUsageType.voiceCommunication,
          androidAudioAttributesContentType:
              rtc.AndroidAudioAttributesContentType.speech,
          forceHandleAudioRouting: false,
        ),
      );
    } catch (error) {
      debugPrint('[call-audio] setAndroidAudioConfiguration failed: $error');
    }
  }

  // CA1+: re-assert that flutter-webrtc must NOT manage the Android audio
  // focus/mode, keeping the native bridge the SOLE route owner. LiveKit
  // re-grabs focus on every local track (un)publish — mic/camera toggle and
  // post-reconnect republish — which silently yanks the route back from the
  // bridge mid-call: «Динамик» stops switching and hardware volume drops off
  // STREAM_VOICE_CALL. Callers invoke this after any local-media transition.
  // No-op off the native path and once the call ended (room detached) so we
  // never re-grab focus for a finished call.
  Future<void> reassertNativeAudioOwnership() async {
    final native = _nativeAudio;
    if (native == null || _room == null) {
      return;
    }
    await _setWebrtcManageAudioFocus(false);
    // Ревью P2: во время идущего переключения не вмешиваемся — иначе
    // track-событие в SCO-окне реассертнуло бы транзиентный маршрут и
    // отменило выбор пользователя.
    if (_isSelecting) {
      return;
    }
    final intentId = _lastUserSelectedRouteId;
    final route = (intentId == null
            ? null
            : _routes.firstWhereOrNull((option) => option.id == intentId)) ??
        selectedRoute;
    if (route == null || !_isNativeBridgeRoute(route.type)) {
      return;
    }
    try {
      await native.setRoute(route.id);
    } catch (error) {
      debugPrint('[call-audio] reassert route failed: $error');
    }
  }

  /// Гигиена звонков: включить/выключить гашение экрана у уха
  /// (PROXIMITY_SCREEN_OFF_WAKE_LOCK). Политику (active + ушной +
  /// камера опущена) считает CallCoordinatorService; здесь — только
  /// доставка до нативного моста. No-op вне Android-пути. Включение
  /// требует живого звонка (room attached) — отложенный enable после
  /// завершения не должен захватить лок для законченного звонка;
  /// выключение проходит всегда.
  Future<void> setProximityEnabled(bool enabled) async {
    final native = _nativeAudio;
    if (native == null) {
      return;
    }
    final effective = enabled && _room != null;
    if (_proximityEnabled == effective) {
      return;
    }
    _proximityEnabled = effective;
    try {
      await native.setProximityEnabled(effective);
    } catch (error) {
      debugPrint('[call-audio] setProximityEnabled failed: $error');
    }
  }

  static bool _isNativeBridgeRoute(AudioRouteType type) {
    switch (type) {
      case AudioRouteType.speaker:
      case AudioRouteType.earpiece:
      case AudioRouteType.bluetooth:
      case AudioRouteType.wired:
        return true;
      case AudioRouteType.device:
        return false;
    }
  }

  Future<void> refreshRoutes() async {
    if (_isRefreshing) {
      // CA1 (ревью E): не теряем событие — перезапустимся после текущего
      // прохода, чтобы итоговое состояние устройств всегда отразилось.
      _refreshPending = true;
      return;
    }
    _isRefreshing = true;
    _refreshPending = false;
    _errorMessage = null;
    notifyListeners();

    try {
      final devices = await _enumerateAudioOutputs();
      final nextRoutes = _buildRoutes(devices);
      _routes = List<AudioRouteOption>.unmodifiable(nextRoutes);
      // FR5: если есть нативный роутер — выбранный маршрут берём из
      // ФАКТИЧЕСКОГО устройства, а не из локального стейта.
      final native = _nativeAudio;
      final actual = native == null ? null : await native.currentRoute();
      if (actual != null && nextRoutes.any((route) => route.id == actual)) {
        _selectedRouteId = actual;
      } else {
        _selectedRouteId = _resolveSelectedRouteId(nextRoutes);
      }
    } catch (_) {
      _errorMessage = 'Не удалось обновить список аудиовыходов.';
      if (_routes.isEmpty) {
        _routes = List<AudioRouteOption>.unmodifiable(_mobileFallbackRoutes());
        _selectedRouteId ??= _routes.firstOrNull?.id;
      }
    } finally {
      _isRefreshing = false;
      notifyListeners();
      if (_refreshPending) {
        _refreshPending = false;
        unawaited(refreshRoutes());
      }
    }
  }

  Future<void> selectRoute(AudioRouteOption option) async {
    if (_isSelecting) {
      // CA1 (ревью E): быстрый второй тап не теряем — применим последний
      // выбранный маршрут после завершения текущего переключения.
      _pendingSelectRoute = option;
      return;
    }
    _isSelecting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final native = _nativeAudio;
      if (native != null) {
        // FR-E (ревью CA1): звонок уже завершён (room отвязан, бридж
        // остановлен) → НЕ применяем маршрут. Иначе отложенный/коалесцированный
        // selectRoute выстрелил бы нативным setRoute уже ПОСЛЕ stop() и заново
        // поднял mode для законченного звонка, испортив следующий. _room
        // обнуляется синхронно в _attachRoomLocked до await stop().
        if (_room == null) {
          return;
        }
        // FR2: маршрутизация нативом (setCommunicationDevice).
        final ok = await native.setRoute(option.id);
        if (ok) {
          // Намерение пользователя для reassert (ревью P2) — фиксируем
          // только на подтверждённом переключении.
          _lastUserSelectedRouteId = option.id;
          // CA1+: re-assert webrtc-relinquish — livekit may have re-grabbed
          // audio focus on a track (un)publish since connect, which would
          // otherwise yank the route back from the bridge.
          await _setWebrtcManageAudioFocus(false);
          // Android may report the previous communication device for a short
          // moment after setCommunicationDevice(). Show the user's accepted
          // choice immediately, then reconcile with the OS a bit later.
          _selectedRouteId = option.id;
          _schedulePostSelectRefresh();
        } else {
          _errorMessage = 'Не удалось переключить аудиовыход.';
        }
      } else {
        await _selectAudioRoute(option, _room);
        _selectedRouteId = option.id;
      }
    } catch (_) {
      _errorMessage = 'Не удалось переключить аудиовыход.';
    } finally {
      _isSelecting = false;
      notifyListeners();
      // CA1 (ревью E): отложенный тап применяем, если он отличается от
      // фактически выбранного сейчас маршрута.
      final pending = _pendingSelectRoute;
      _pendingSelectRoute = null;
      if (pending != null && pending.id != _selectedRouteId) {
        unawaited(selectRoute(pending));
      }
    }
  }

  void _schedulePostSelectRefresh() {
    _postSelectRefreshTimer?.cancel();
    // Android OEM/WebRTC stacks can briefly pull the route back and the
    // native bridge reinforces the requested device inside the first second.
    // Reconcile after that window so the UI doesn't prematurely flip away
    // from the user's accepted "Динамик"/"Наушник" choice.
    _postSelectRefreshTimer = Timer(const Duration(milliseconds: 900), () {
      _postSelectRefreshTimer = null;
      if (_room != null) {
        unawaited(refreshRoutes());
      }
    });
  }

  List<AudioRouteOption> _buildRoutes(List<MediaDevice> devices) {
    final routes = <AudioRouteOption>[];
    final seenIds = <String>{};

    void add(AudioRouteOption route) {
      if (seenIds.add(route.id)) {
        routes.add(route);
      }
    }

    if (_isMobilePlatform) {
      for (final route in _mobileFallbackRoutes()) {
        add(route);
      }
    }

    for (final device
        in devices.where((device) => device.kind == 'audiooutput')) {
      final route = _routeFromDevice(device);
      if (route != null) {
        add(route);
      }
    }

    if (routes.isEmpty) {
      routes.addAll(_mobileFallbackRoutes());
    }

    return routes;
  }

  String? _resolveSelectedRouteId(List<AudioRouteOption> routes) {
    if (routes.isEmpty) {
      return null;
    }
    if (_selectedRouteId != null &&
        routes.any((route) => route.id == _selectedRouteId)) {
      return _selectedRouteId;
    }
    if (routes.any((route) => route.id == 'speaker')) {
      return 'speaker';
    }
    return routes.first.id;
  }

  static List<AudioRouteOption> _mobileFallbackRoutes() {
    return const <AudioRouteOption>[
      AudioRouteOption(
        id: 'speaker',
        label: 'Динамик',
        type: AudioRouteType.speaker,
      ),
      AudioRouteOption(
        id: 'earpiece',
        label: 'Наушник',
        type: AudioRouteType.earpiece,
      ),
    ];
  }

  static AudioRouteOption? _routeFromDevice(MediaDevice device) {
    final id = device.deviceId.trim();
    if (id.isEmpty) {
      return null;
    }

    final normalized = id.toLowerCase();
    final rawLabel = device.label.trim();
    switch (normalized) {
      case 'speaker':
        return AudioRouteOption(
          id: 'speaker',
          label: 'Динамик',
          type: AudioRouteType.speaker,
          device: device,
        );
      case 'earpiece':
        return AudioRouteOption(
          id: 'earpiece',
          label: 'Наушник',
          type: AudioRouteType.earpiece,
          device: device,
        );
      case 'bluetooth':
        return AudioRouteOption(
          id: 'bluetooth',
          label: rawLabel.isNotEmpty ? rawLabel : 'Bluetooth',
          type: AudioRouteType.bluetooth,
          device: device,
        );
      case 'wired-headset':
      case 'wired':
        return AudioRouteOption(
          id: 'wired-headset',
          label: rawLabel.isNotEmpty ? rawLabel : 'Проводные',
          type: AudioRouteType.wired,
          device: device,
        );
    }

    return AudioRouteOption(
      id: id,
      label: rawLabel.isNotEmpty ? rawLabel : 'Аудиовыход',
      type: AudioRouteType.device,
      device: device,
    );
  }

  static Future<void> _selectLiveKitRoute(
    AudioRouteOption option,
    Room? room,
  ) async {
    if (room == null) {
      return;
    }

    switch (option.type) {
      case AudioRouteType.speaker:
        await room.setSpeakerOn(true, forceSpeakerOutput: true);
        return;
      case AudioRouteType.earpiece:
        await room.setSpeakerOn(false);
        return;
      case AudioRouteType.bluetooth:
      case AudioRouteType.wired:
        if (option.device != null) {
          await room.setAudioOutputDevice(option.device!);
        }
        await room.setSpeakerOn(false);
        return;
      case AudioRouteType.device:
        if (option.device != null) {
          await room.setAudioOutputDevice(option.device!);
        }
        return;
    }
  }

  static Future<List<MediaDevice>> _defaultEnumerateAudioOutputs() {
    return Hardware.instance.audioOutputs();
  }

  static bool get _defaultIsMobilePlatform {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  // CA1: нативный аудиороутинг только на Android (там сломан
  // setSpeakerphoneOn-путь). iOS/web остаются на LiveKit.
  static bool get _defaultUseNativeAudio {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  }

  @override
  void dispose() {
    _postSelectRefreshTimer?.cancel();
    unawaited(_deviceChangesSubscription?.cancel());
    unawaited(_nativeDeviceSubscription?.cancel());
    // Hand audio-focus management back to webrtc's default BEFORE tearing down
    // the native bridge. A dispose() during an active call skips the
    // room==null branch (which already restores it), so without this our
    // relinquish leaks and the global webrtc config stays manageAudioFocus:
    // false for the next call/session. No-op off the native path.
    unawaited(_setWebrtcManageAudioFocus(true));
    unawaited(_nativeAudio?.stop());
    _nativeAudio?.dispose();
    super.dispose();
  }
}
