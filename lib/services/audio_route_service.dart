import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

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
  })  : _enumerateAudioOutputs =
            enumerateAudioOutputs ?? _defaultEnumerateAudioOutputs,
        _selectAudioRoute = selectAudioRoute ?? _selectLiveKitRoute,
        _deviceChanges = deviceChanges,
        _isMobilePlatform = isMobilePlatform ?? _defaultIsMobilePlatform {
    if (initialRoutes != null && initialRoutes.isNotEmpty) {
      _routes = List<AudioRouteOption>.unmodifiable(initialRoutes);
      _selectedRouteId = initialSelectedRouteId ?? initialRoutes.first.id;
    }
  }

  final AudioRouteDeviceEnumerator _enumerateAudioOutputs;
  final AudioRouteSelector _selectAudioRoute;
  final Stream<List<MediaDevice>>? _deviceChanges;
  final bool _isMobilePlatform;

  Room? _room;
  StreamSubscription<List<MediaDevice>>? _deviceChangesSubscription;
  List<AudioRouteOption> _routes = const <AudioRouteOption>[];
  String? _selectedRouteId;
  bool _isRefreshing = false;
  bool _isSelecting = false;
  String? _errorMessage;

  List<AudioRouteOption> get routes => _routes;
  String? get selectedRouteId => _selectedRouteId;
  bool get isRefreshing => _isRefreshing;
  bool get isSelecting => _isSelecting;
  String? get errorMessage => _errorMessage;

  AudioRouteOption? get selectedRoute => _routes.firstWhereOrNull(
        (route) => route.id == _selectedRouteId,
      );

  Future<void> attachRoom(Room? room) async {
    if (identical(_room, room)) {
      return;
    }
    _room = room;
    await _deviceChangesSubscription?.cancel();
    _deviceChangesSubscription = null;
    if (room == null) {
      _routes = const <AudioRouteOption>[];
      _selectedRouteId = null;
      _errorMessage = null;
      notifyListeners();
      return;
    }
    final deviceChanges =
        _deviceChanges ?? Hardware.instance.onDeviceChange.stream;
    _deviceChangesSubscription = deviceChanges.listen((_) {
      unawaited(refreshRoutes());
    });
    await refreshRoutes();
  }

  Future<void> refreshRoutes() async {
    if (_isRefreshing) {
      return;
    }
    _isRefreshing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final devices = await _enumerateAudioOutputs();
      final nextRoutes = _buildRoutes(devices);
      final currentId = _resolveSelectedRouteId(nextRoutes);
      _routes = List<AudioRouteOption>.unmodifiable(nextRoutes);
      _selectedRouteId = currentId;
    } catch (_) {
      _errorMessage = 'Не удалось обновить список аудиовыходов.';
      if (_routes.isEmpty) {
        _routes = List<AudioRouteOption>.unmodifiable(_mobileFallbackRoutes());
        _selectedRouteId ??= _routes.firstOrNull?.id;
      }
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  Future<void> selectRoute(AudioRouteOption option) async {
    if (_isSelecting) {
      return;
    }
    _isSelecting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _selectAudioRoute(option, _room);
      _selectedRouteId = option.id;
    } catch (_) {
      _errorMessage = 'Не удалось переключить аудиовыход.';
    } finally {
      _isSelecting = false;
      notifyListeners();
    }
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

  @override
  void dispose() {
    unawaited(_deviceChangesSubscription?.cancel());
    super.dispose();
  }
}
