import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../backend/interfaces/call_service_interface.dart';
import '../models/call_event.dart';
import '../models/call_invite.dart';
import '../models/call_media_mode.dart';
import '../models/call_state.dart';
import 'android_incoming_call_service.dart';
import 'audio_route_service.dart';
import 'call_foreground_service.dart';
import 'call_preferences.dart';
import 'custom_api_realtime_service.dart';
import 'rustore_service.dart';

typedef MediaPermissionRequester = Future<bool> Function(
  CallMediaMode mediaMode,
);
typedef CameraPositionSwitcher = Future<void> Function(
  LocalVideoTrack track,
  CameraPosition position,
);
typedef CallMediaDeviceEnumerator = Future<List<MediaDevice>> Function();
typedef CallMediaDeviceSelector = Future<void> Function(
  Room room,
  MediaDevice device,
);
typedef CallVibrationTrigger = Future<void> Function();

class CallCoordinatorService extends ChangeNotifier
    with WidgetsBindingObserver {
  CallCoordinatorService({
    required CallServiceInterface callService,
    CustomApiRealtimeService? realtimeService,
    Stream<RustorePushMessage>? pushMessages,
    MediaPermissionRequester? mediaPermissionRequester,
    AudioRouteService? audioRouteService,
    CameraPositionSwitcher? cameraPositionSwitcher,
    CallMediaDeviceEnumerator? audioInputEnumerator,
    CallMediaDeviceEnumerator? videoInputEnumerator,
    CallMediaDeviceSelector? microphoneDeviceSelector,
    CallMediaDeviceSelector? cameraDeviceSelector,
    CallPreferences? callPreferences,
    AndroidIncomingCallService? androidIncomingCallService,
    CallForegroundService? callForegroundService,
    CallVibrationTrigger? vibrationTrigger,
    Duration ringingRecoveryInterval = const Duration(seconds: 2),
    Duration activeCallRecoveryInterval = const Duration(seconds: 2),
  })  : _callService = callService,
        _realtimeService = realtimeService,
        _pushMessages = pushMessages,
        _audioRouteService = audioRouteService ?? AudioRouteService(),
        _cameraPositionSwitcher =
            cameraPositionSwitcher ?? _switchLiveKitCameraPosition,
        _audioInputEnumerator =
            audioInputEnumerator ?? _defaultAudioInputEnumerator,
        _videoInputEnumerator =
            videoInputEnumerator ?? _defaultVideoInputEnumerator,
        _microphoneDeviceSelector =
            microphoneDeviceSelector ?? _selectLiveKitMicrophoneDevice,
        _cameraDeviceSelector =
            cameraDeviceSelector ?? _selectLiveKitCameraDevice,
        _callPreferences = callPreferences ?? const DisabledCallPreferences(),
        _androidIncomingCallService = androidIncomingCallService,
        _callForegroundService = callForegroundService,
        _vibrationTrigger = vibrationTrigger ?? _defaultVibrationTrigger,
        _ringingRecoveryInterval = ringingRecoveryInterval,
        _activeCallRecoveryInterval = activeCallRecoveryInterval,
        _mediaPermissionRequester =
            mediaPermissionRequester ?? _requestPlatformMediaPermissions {
    WidgetsFlutterBinding.ensureInitialized();
    WidgetsBinding.instance.addObserver(this);
    _callEventsSubscription = _callService.events.listen(_handleCallEvent);
    final activeRealtimeService = _realtimeService;
    if (activeRealtimeService != null) {
      _realtimeSubscription = activeRealtimeService.events.listen((event) {
        if (event.type == 'connection.ready') {
          unawaited(resync());
        }
      });
    }
    final activePushMessages = _pushMessages;
    if (activePushMessages != null) {
      _pushSubscription = activePushMessages.listen(_handlePushMessage);
    }
    unawaited(_androidIncomingCallService?.registerPhoneAccount());
    unawaited(ensureRuntimeReady());
    unawaited(_handlePendingAndroidCallAction());
  }

  final CallServiceInterface _callService;
  final CustomApiRealtimeService? _realtimeService;
  final Stream<RustorePushMessage>? _pushMessages;
  final MediaPermissionRequester _mediaPermissionRequester;
  final AudioRouteService _audioRouteService;
  final CameraPositionSwitcher _cameraPositionSwitcher;
  final CallMediaDeviceEnumerator _audioInputEnumerator;
  final CallMediaDeviceEnumerator _videoInputEnumerator;
  final CallMediaDeviceSelector _microphoneDeviceSelector;
  final CallMediaDeviceSelector _cameraDeviceSelector;
  final CallPreferences _callPreferences;
  final AndroidIncomingCallService? _androidIncomingCallService;
  // Foreground service для активного звонка (Bug A 2026-05-22).
  // Запускается на active transition, обновляется на mic toggle /
  // peer name resolved, останавливается на terminal. Null на
  // non-Android либо когда test'ы инжектят null explicitly.
  final CallForegroundService? _callForegroundService;
  // Tracks current foreground-service active callId — null когда
  // service не запущен. Reused чтобы избежать redundant start
  // calls (idempotency на rapid `_applyCall(active)` re-fires).
  String? _foregroundServiceCallId;
  final CallVibrationTrigger _vibrationTrigger;
  final Duration _ringingRecoveryInterval;
  final Duration _activeCallRecoveryInterval;

  StreamSubscription<CallEvent>? _callEventsSubscription;
  StreamSubscription<CustomApiRealtimeEvent>? _realtimeSubscription;
  StreamSubscription<RustorePushMessage>? _pushSubscription;
  Future<void>? _runtimeReadyFuture;
  Future<void>? _androidCallActionFuture;
  Timer? _ringingRecoveryTimer;
  Timer? _activeCallRecoveryTimer;
  Timer? _reconnectRestoredTimer;
  String? _ringingRecoveryCallId;
  String? _activeCallRecoveryCallId;

  CallInvite? _currentCall;
  Room? _room;
  EventsListener<RoomEvent>? _roomListener;
  String? _connectedRoomName;
  DateTime? _roomConnectStartedAt;
  bool _isConnectingRoom = false;
  bool _isReconnectingRoom = false;
  bool _microphoneEnabled = true;
  // True когда LiveKit вернул успех на `setMicrophoneEnabled(true)` но
  // фактическая publication отсутствует (publication == null либо
  // `isMicrophoneEnabled()` после await вернул false). Симптом
  // соответствует Артёмов reported Bug 1 «собеседник не слышит» —
  // UI showed «mic on» хотя трек не публиковался. Surface'им через
  // separate flag чтобы CallScreen мог поднять banner / snackbar и
  // юзер увидел real state вместо silent fail.
  bool _microphonePublishFailed = false;
  bool _cameraEnabled = false;
  bool _isSwitchingCamera = false;
  CameraPosition _cameraPosition = CameraPosition.front;
  List<MediaDevice> _microphoneDevices = const <MediaDevice>[];
  List<MediaDevice> _cameraDevices = const <MediaDevice>[];
  String? _selectedMicrophoneDeviceId;
  String? _selectedCameraDeviceId;
  bool _isRefreshingInputDevices = false;
  bool _isSelectingMediaDevice = false;
  String? _devicePickerErrorMessage;
  ConnectionQuality _localConnectionQuality = ConnectionQuality.unknown;
  ConnectionQuality _remoteConnectionQuality = ConnectionQuality.unknown;
  bool _showReconnectRestoredBanner = false;
  String? _connectionError;
  bool _hasMediaPermissionIssue = false;
  bool _hasSeenRemoteParticipant = false;
  bool _joinedOnAnotherDevice = false;
  String? _lastIncomingVibrationCallId;
  final Set<String> _visibleCallScreenIds = <String>{};
  // Caller display names captured from VKPNS push payloads, keyed
  // by callId. Push delivery beats the realtime hydrate (the push
  // arrives before the GET /v1/calls/:id response lands), so we
  // park the name here and pull it out when the Telecom-side
  // showIncomingCall fires from _applyCall.
  final Map<String, String> _pushCallerNames = <String, String>{};
  // De-dupe Telecom showIncomingCall — a single call can fan out
  // both via push and notification.created realtime, and we don't
  // want addNewIncomingCall to fire twice for the same callId.
  String? _lastNativeIncomingCallId;

  String? get currentUserId => _callService.currentUserId;
  CallInvite? get currentCall => _currentCall;
  Room? get room => _room;
  bool get isConnectingRoom => _isConnectingRoom;
  bool get isReconnectingRoom => _isReconnectingRoom;
  bool get joinedOnAnotherDevice => _joinedOnAnotherDevice;
  bool get microphoneEnabled => _microphoneEnabled;

  /// True если попытка enable microphone в активном звонке отказала
  /// silently — `setMicrophoneEnabled(true)` либо вернул null
  /// publication, либо `isMicrophoneEnabled()` после await вернул
  /// false. CallScreen listens и поднимает banner/snackbar чтобы
  /// surface'ить факт пользователю (без этого UI lies about mic
  /// state и собеседник просто не слышит).
  bool get microphonePublishFailed => _microphonePublishFailed;
  bool get cameraEnabled => _cameraEnabled;
  bool get isSwitchingCamera => _isSwitchingCamera;
  CameraPosition get cameraPosition => _cameraPosition;
  List<MediaDevice> get microphoneDevices => _microphoneDevices;
  List<MediaDevice> get cameraDevices => _cameraDevices;
  String? get selectedMicrophoneDeviceId => _selectedMicrophoneDeviceId;
  String? get selectedCameraDeviceId => _selectedCameraDeviceId;
  bool get isRefreshingInputDevices => _isRefreshingInputDevices;
  bool get isSelectingMediaDevice => _isSelectingMediaDevice;
  String? get devicePickerErrorMessage => _devicePickerErrorMessage;
  ConnectionQuality get localConnectionQuality => _localConnectionQuality;
  ConnectionQuality get remoteConnectionQuality {
    if (_isReconnectingRoom) {
      return ConnectionQuality.lost;
    }
    if (_remoteConnectionQuality != ConnectionQuality.unknown) {
      return _remoteConnectionQuality;
    }
    final participants = _room?.remoteParticipants.values;
    if (participants == null) {
      return ConnectionQuality.unknown;
    }
    for (final participant in participants) {
      if (participant.connectionQuality != ConnectionQuality.unknown) {
        return participant.connectionQuality;
      }
    }
    return ConnectionQuality.unknown;
  }

  ConnectionQuality get displayedConnectionQuality {
    if (_isReconnectingRoom || _connectionError != null) {
      return ConnectionQuality.lost;
    }
    final remoteQuality = remoteConnectionQuality;
    if (remoteQuality != ConnectionQuality.unknown) {
      return remoteQuality;
    }
    return _localConnectionQuality;
  }

  bool get showReconnectRestoredBanner => _showReconnectRestoredBanner;
  String? get connectionError => _connectionError;
  bool get hasMediaPermissionIssue => _hasMediaPermissionIssue;
  AudioRouteService get audioRouteService => _audioRouteService;

  bool isCallScreenVisible(String? callId) {
    if (callId == null || callId.isEmpty) {
      return false;
    }
    return _visibleCallScreenIds.contains(callId);
  }

  void setCallScreenVisible(
    String callId, {
    required bool isVisible,
  }) {
    if (callId.isEmpty) {
      return;
    }
    final hasChanged = isVisible
        ? _visibleCallScreenIds.add(callId)
        : _visibleCallScreenIds.remove(callId);
    if (hasChanged) {
      notifyListeners();
    }
  }

  Future<CallInvite?> hydrateIncomingCall({
    String? callId,
    String? chatId,
  }) async {
    final currentUser = currentUserId?.trim();
    if (currentUser == null || currentUser.isEmpty) {
      return null;
    }

    final activeCall = _currentCall;
    final normalizedCallId = callId?.trim();
    if (activeCall != null &&
        !activeCall.state.isTerminal &&
        (normalizedCallId == null ||
            normalizedCallId.isEmpty ||
            activeCall.id == normalizedCallId)) {
      return activeCall;
    }

    try {
      CallInvite? nextCall;
      if (normalizedCallId != null && normalizedCallId.isNotEmpty) {
        nextCall = await _callService.getCall(normalizedCallId);
      }
      nextCall ??= await _callService.getActiveCall(chatId: chatId?.trim());
      nextCall ??= await _callService.getActiveCall();
      if (nextCall == null || nextCall.state.isTerminal) {
        return null;
      }
      await _applyCall(nextCall);
      return nextCall;
    } catch (_) {
      return null;
    }
  }

  Future<void> activateCall(CallInvite call) async {
    await _applyCall(call);
  }

  Future<void> ensureRuntimeReady() {
    final existingFuture = _runtimeReadyFuture;
    if (existingFuture != null) {
      return existingFuture;
    }

    final completer = Completer<void>();
    _runtimeReadyFuture = completer.future;
    unawaited(() async {
      try {
        await _callService.startRealtimeBridge();
        await resync();
        completer.complete();
      } catch (_) {
        _runtimeReadyFuture = null;
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    }());
    return completer.future;
  }

  Future<void> _handlePendingAndroidCallAction() {
    final existingFuture = _androidCallActionFuture;
    if (existingFuture != null) {
      return existingFuture;
    }

    final future = _consumePendingAndroidCallAction();
    _androidCallActionFuture = future;
    future.whenComplete(() {
      if (identical(_androidCallActionFuture, future)) {
        _androidCallActionFuture = null;
      }
    });
    return future;
  }

  Future<void> _consumePendingAndroidCallAction() async {
    final service = _androidIncomingCallService;
    if (service == null) {
      return;
    }

    final action = await service.consumePendingAction();
    if (action == null) {
      return;
    }

    await ensureRuntimeReady();
    final call = await hydrateIncomingCall(
      callId: action.callId,
      chatId: action.chatId,
    );
    if (call == null) {
      return;
    }

    if (action.isAccept) {
      if (call.state == CallState.ringing &&
          call.isIncomingFor(currentUserId ?? '')) {
        await acceptCall(call.id);
      } else {
        await activateCall(call);
      }
      return;
    }

    if (action.isReject || action.isDisconnect) {
      await finishCall(call.id);
    }
  }

  /// Consume pending action from foreground service notification
  /// button tap. Called on app resume — если юзер ткнул «Микрофон»
  /// либо «Завершить» в notification action, бэкенд (Kotlin bridge)
  /// сохранил action в SharedPreferences, мы вычитываем + applyим.
  /// No-op если service не инжектирован либо нет pending action.
  Future<void> _consumePendingForegroundNotificationAction() async {
    final service = _callForegroundService;
    if (service == null || !service.isSupported) {
      return;
    }
    final action = await service.consumePendingNotificationAction();
    if (action == null) {
      return;
    }
    final activeCall = _currentCall;
    if (activeCall == null || activeCall.id != action.callId) {
      // Action для другого звонка — ignore (звонок мог уже завершиться).
      return;
    }
    if (action.isToggleMic) {
      await toggleMicrophone();
      return;
    }
    if (action.isEndCall) {
      await finishCall(action.callId);
    }
  }

  Future<CallInvite?> getCall(String callId) {
    return _callService.getCall(callId);
  }

  Future<CallInvite?> getActiveCall({String? chatId}) {
    return _callService.getActiveCall(chatId: chatId);
  }

  Future<CallInvite?> resync({String? chatId}) async {
    final currentUser = currentUserId?.trim();
    if (currentUser == null || currentUser.isEmpty) {
      if (chatId == null || _currentCall?.chatId == chatId) {
        await _applyCall(null);
      }
      return null;
    }

    try {
      final activeCall = await _callService.getActiveCall(chatId: chatId);
      if (activeCall == null) {
        if (chatId == null || _currentCall?.chatId == chatId) {
          await _applyCall(null);
        }
        return null;
      }

      await _applyCall(activeCall);
      return activeCall;
    } catch (_) {
      return null;
    }
  }

  Future<CallInvite?> refreshCurrentCall() async {
    final currentCall = _currentCall;
    if (currentCall == null) {
      return null;
    }
    final refreshedCall = await _callService.getCall(currentCall.id);
    await _applyCall(refreshedCall);
    return refreshedCall;
  }

  Future<CallInvite> startCall({
    required String chatId,
    required CallMediaMode mediaMode,
    List<String>? participantIds,
  }) async {
    final invite = await _callService.startCall(
      chatId: chatId,
      mediaMode: mediaMode,
      participantIds: participantIds,
    );
    await _applyCall(invite);
    return invite;
  }

  Future<CallInvite> nudgeCallParticipants(
    String callId, {
    List<String>? participantIds,
  }) async {
    final invite = await _callService.nudgeCallParticipants(
      callId,
      participantIds: participantIds,
    );
    if (_currentCall?.id == invite.id) {
      await _applyCall(invite);
    }
    return invite;
  }

  Future<CallInvite> acceptCall([String? callId]) async {
    final resolvedCallId = callId ?? _currentCall?.id;
    if (resolvedCallId == null || resolvedCallId.isEmpty) {
      throw StateError('Нет активного звонка для принятия.');
    }
    final invite = await _callService.acceptCall(resolvedCallId);
    await _applyCall(invite);
    return invite;
  }

  Future<CallInvite?> finishCall([String? callId]) async {
    final activeCall = _currentCall;
    final resolvedCallId = callId ?? activeCall?.id;
    if (resolvedCallId == null || resolvedCallId.isEmpty) {
      return null;
    }

    CallInvite? result;
    final callToFinish = resolvedCallId == activeCall?.id
        ? activeCall
        : await _callService.getCall(resolvedCallId);
    if (callToFinish == null) {
      await _applyCall(null);
      return null;
    }

    if (callToFinish.state == CallState.ringing) {
      if (callToFinish.isIncomingFor(currentUserId ?? '')) {
        result = await _callService.rejectCall(resolvedCallId);
      } else {
        result = await _callService.cancelCall(resolvedCallId);
      }
    } else if (callToFinish.state == CallState.active) {
      result = await _callService.hangUp(resolvedCallId);
    } else {
      result = callToFinish;
    }

    await _applyCall(result);
    return result;
  }

  Future<void> toggleMicrophone() async {
    final room = _room;
    if (room == null) {
      return;
    }

    final nextValue = !_microphoneEnabled;
    if (nextValue) {
      // Re-enable path — verify publication actually attached иначе
      // юзер увидит «mic on» а собеседник продолжит nothing hear.
      final published = await _publishLocalMicrophone(room);
      _microphonePublishFailed = !published;
      // Fix A (2026-05-22): без этой строки `_microphoneEnabled`
      // застревал в false после un-mute, и UI showed «mic off» хотя
      // publication успешно active (Bug 2 desync). _publishLocalMicrophone
      // только sets к false на failure; success case caller обязан
      // explicitly toggle к true.
      _microphoneEnabled = published;
    } else {
      try {
        await room.localParticipant?.setMicrophoneEnabled(false);
      } catch (error) {
        debugPrint('[call] toggle mic off threw: $error');
      }
      _microphoneEnabled = false;
      // Mute не может «silent fail» в смысле Bug 1 — даже если
      // localParticipant.setMicrophoneEnabled(false) кидает, эффект
      // юзеру (микрофон тише) хуже-не-станет. Clear publish failure
      // flag — следующий enable retry'нется свежим.
      _microphonePublishFailed = false;
    }
    notifyListeners();
    // Update Android foreground notification чтобы action button
    // label «Заглушить/Включить микрофон» reflected actual state.
    unawaited(_updateForegroundService());
  }

  Future<void> toggleCamera() async {
    final room = _room;
    final activeCall = _currentCall;
    // Was: also bailed when `!activeCall.mediaMode.isVideo`. That
    // turned the camera-toggle button into a no-op inside audio
    // calls, blocking the "upgrade to video" path the user asked
    // for. We now allow the toggle in any active call as long as
    // there's a live room — flipping the local camera on/off is a
    // pure local-participant operation.
    if (room == null || activeCall == null) {
      return;
    }

    final nextValue = !_cameraEnabled;
    await room.localParticipant?.setCameraEnabled(
      nextValue,
      cameraCaptureOptions: CameraCaptureOptions(
        cameraPosition: _cameraPosition,
      ),
    );
    _cameraEnabled = nextValue;
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final track = _localCameraTrack();
    if (track == null || _isSwitchingCamera) {
      return;
    }

    final nextPosition = _cameraPosition.switched();
    _isSwitchingCamera = true;
    notifyListeners();
    try {
      await _cameraPositionSwitcher(track, nextPosition);
      _cameraPosition = nextPosition;
      _selectedCameraDeviceId = null;
      _cameraEnabled = true;
    } finally {
      _isSwitchingCamera = false;
      notifyListeners();
    }
  }

  Future<void> refreshInputDevices() async {
    if (_isRefreshingInputDevices) {
      return;
    }
    _isRefreshingInputDevices = true;
    _devicePickerErrorMessage = null;
    notifyListeners();
    try {
      final results = await Future.wait<List<MediaDevice>>([
        _audioInputEnumerator(),
        _videoInputEnumerator(),
      ]);
      _microphoneDevices = List<MediaDevice>.unmodifiable(results[0]);
      _cameraDevices = List<MediaDevice>.unmodifiable(results[1]);
      _selectedMicrophoneDeviceId = _resolveSelectedDeviceId(
        _microphoneDevices,
        _selectedMicrophoneDeviceId,
      );
      _selectedCameraDeviceId = _resolveSelectedDeviceId(
        _cameraDevices,
        _selectedCameraDeviceId,
      );
    } catch (_) {
      _devicePickerErrorMessage =
          'Не удалось обновить список микрофонов и камер.';
    } finally {
      _isRefreshingInputDevices = false;
      notifyListeners();
    }
  }

  Future<void> selectMicrophoneDevice(MediaDevice device) async {
    final room = _room;
    if (room == null || _isSelectingMediaDevice) {
      return;
    }
    _isSelectingMediaDevice = true;
    _devicePickerErrorMessage = null;
    notifyListeners();
    try {
      await _microphoneDeviceSelector(room, device);
      _selectedMicrophoneDeviceId = device.deviceId;
    } catch (_) {
      _devicePickerErrorMessage = 'Не удалось выбрать микрофон.';
    } finally {
      _isSelectingMediaDevice = false;
      notifyListeners();
    }
  }

  Future<void> selectCameraDevice(MediaDevice device) async {
    final room = _room;
    if (room == null || _isSelectingMediaDevice) {
      return;
    }
    _isSelectingMediaDevice = true;
    _devicePickerErrorMessage = null;
    notifyListeners();
    try {
      await _cameraDeviceSelector(room, device);
      _selectedCameraDeviceId = device.deviceId;
      _cameraPosition = _cameraPositionFromDevice(device) ?? _cameraPosition;
      _cameraEnabled = true;
    } catch (_) {
      _devicePickerErrorMessage = 'Не удалось выбрать камеру.';
    } finally {
      _isSelectingMediaDevice = false;
      notifyListeners();
    }
  }

  Future<void> _applyCall(CallInvite? nextCall) async {
    final currentCall = _currentCall;
    if (nextCall == null) {
      if (currentCall != null) {
        unawaited(_androidIncomingCallService?.dismissCall(currentCall.id));
        _pushCallerNames.remove(currentCall.id);
        if (_lastNativeIncomingCallId == currentCall.id) {
          _lastNativeIncomingCallId = null;
        }
      }
      _cancelRingingRecovery();
      _cancelActiveCallRecovery();
      _currentCall = null;
      _isConnectingRoom = false;
      _isReconnectingRoom = false;
      _isSwitchingCamera = false;
      _cameraPosition = CameraPosition.front;
      _clearInputDeviceState();
      _connectionError = null;
      _hasMediaPermissionIssue = false;
      _microphonePublishFailed = false;
      _hasSeenRemoteParticipant = false;
      _joinedOnAnotherDevice = false;
      _lastIncomingVibrationCallId = null;
      _clearConnectionQualityState();
      notifyListeners();
      await _stopForegroundService();
      await _disposeRoom();
      return;
    }

    if (_shouldIgnoreCallSnapshot(nextCall)) {
      return;
    }

    if (nextCall.state.isTerminal) {
      if (currentCall == null || currentCall.id != nextCall.id) {
        return;
      }
      unawaited(_androidIncomingCallService?.dismissCall(nextCall.id));
      _pushCallerNames.remove(nextCall.id);
      if (_lastNativeIncomingCallId == nextCall.id) {
        _lastNativeIncomingCallId = null;
      }
      _cancelRingingRecovery();
      _cancelActiveCallRecovery();
      _currentCall = null;
      _isConnectingRoom = false;
      _isReconnectingRoom = false;
      _isSwitchingCamera = false;
      _cameraPosition = CameraPosition.front;
      _clearInputDeviceState();
      _connectionError = null;
      _hasMediaPermissionIssue = false;
      _microphonePublishFailed = false;
      _hasSeenRemoteParticipant = false;
      _joinedOnAnotherDevice = false;
      _lastIncomingVibrationCallId = null;
      _clearConnectionQualityState();
      notifyListeners();
      await _stopForegroundService();
      await _disposeRoom();
      return;
    }

    final previousCallId = _currentCall?.id;
    final previousRoomName = _connectedRoomName;
    _currentCall = nextCall;
    if (nextCall.state == CallState.ringing) {
      _scheduleRingingRecovery(nextCall);
      _cancelActiveCallRecovery();
      unawaited(_maybeVibrateForIncomingCall(nextCall));
      // User-reported: «приложение свернуто — звонок на устройство
      // не проходит». Корень: в backgrounded состоянии CallScreen
      // не примонтирован к навигатору, поэтому
      // `notifyListeners` не приводит к появлению UI. Раньше единственный
      // путь к лаунчеру системного звонка проходил через
      // `notification.created` → notification_service →
      // showIncomingCallNotification → AndroidIncomingCallService.
      // Но push приходит как push-message и попадает сюда напрямую,
      // обходя notification.created. Пингуем Telecom отсюда — он
      // самостоятельный и работает поверх любого app state.
      // addNewIncomingCall идемпотентен по callId (через registry),
      // так что параллельный путь из notification_service не
      // создаст дубль.
      unawaited(_maybeShowNativeIncomingCall(nextCall));
    } else {
      _cancelRingingRecovery();
      if (_lastIncomingVibrationCallId == nextCall.id) {
        _lastIncomingVibrationCallId = null;
      }
    }
    if (nextCall.state == CallState.active) {
      _scheduleActiveCallRecovery(nextCall);
    } else {
      _cancelActiveCallRecovery();
    }
    if (previousCallId != nextCall.id) {
      _connectionError = null;
      _hasMediaPermissionIssue = false;
      _hasSeenRemoteParticipant = false;
      _clearReconnectRestoredBanner();
      _lastIncomingVibrationCallId = null;
      _cameraPosition = CameraPosition.front;
      _isSwitchingCamera = false;
    }
    if (!nextCall.mediaMode.isVideo) {
      // Fix B (2026-05-22): не reset'им cameraEnabled пока room
      // connected — user мог upgrade audio→video через local
      // `toggleCamera`, backend `mediaMode` за этим не следит и
      // recovery snapshot каждые 2s триггерил reset. Preview
      // disappeared, peer всё ещё видел камеру (Bug 3 desync).
      // Reset только когда room dispose'нут — actual track gone anyway.
      // `debugTreatRoomAsActive` — test seam (visibleForTesting) чтобы
      // экзерсайз preservation path без real LiveKit Room mock.
      if (_room == null && !debugTreatRoomAsActive) {
        _cameraEnabled = false;
      }
    }
    _joinedOnAnotherDevice = nextCall.joinedOnAnotherDevice;
    notifyListeners();

    if (nextCall.state == CallState.active) {
      if (nextCall.joinedOnAnotherDevice) {
        _isConnectingRoom = false;
        _isReconnectingRoom = false;
        _connectionError = null;
        _clearReconnectRestoredBanner();
        notifyListeners();
        await _stopForegroundService();
        await _disposeRoom();
        return;
      }
      if (_hasMediaPermissionIssue &&
          previousCallId == nextCall.id &&
          _room == null) {
        notifyListeners();
        return;
      }
      // Start foreground service ДО room.connect — Android 14+
      // нуждается в running foreground service с
      // foregroundServiceType="microphone" чтобы mic capture не
      // revoked'нулся. Без этого собеседник перестаёт слышать как
      // только screen blank / app backgrounded (Bug A).
      await _ensureForegroundServiceStarted(nextCall);
      final shouldReconnect = previousCallId == nextCall.id &&
          previousRoomName != null &&
          _room == null;
      await _ensureConnected(nextCall, reconnect: shouldReconnect);
      return;
    }

    if (previousCallId != null && previousCallId != nextCall.id) {
      await _stopForegroundService();
      await _disposeRoom();
    }
  }

  void _scheduleRingingRecovery(CallInvite call) {
    if (_ringingRecoveryInterval <= Duration.zero) {
      return;
    }
    if (_ringingRecoveryCallId == call.id &&
        _ringingRecoveryTimer?.isActive == true) {
      return;
    }
    _cancelRingingRecovery();
    _ringingRecoveryCallId = call.id;
    _ringingRecoveryTimer = Timer.periodic(_ringingRecoveryInterval, (_) {
      unawaited(_refreshRingingCall(call.id));
    });
  }

  void _cancelRingingRecovery() {
    _ringingRecoveryTimer?.cancel();
    _ringingRecoveryTimer = null;
    _ringingRecoveryCallId = null;
  }

  void _scheduleActiveCallRecovery(CallInvite call) {
    if (_activeCallRecoveryInterval <= Duration.zero) {
      return;
    }
    if (_activeCallRecoveryCallId == call.id &&
        _activeCallRecoveryTimer?.isActive == true) {
      return;
    }
    _cancelActiveCallRecovery();
    _activeCallRecoveryCallId = call.id;
    _activeCallRecoveryTimer = Timer.periodic(_activeCallRecoveryInterval, (_) {
      unawaited(_refreshActiveCall(call.id));
    });
  }

  void _cancelActiveCallRecovery() {
    _activeCallRecoveryTimer?.cancel();
    _activeCallRecoveryTimer = null;
    _activeCallRecoveryCallId = null;
  }

  Future<void> _refreshRingingCall(String callId) async {
    final activeCall = _currentCall;
    if (activeCall == null ||
        activeCall.id != callId ||
        activeCall.state != CallState.ringing) {
      _cancelRingingRecovery();
      return;
    }

    try {
      final refreshedCall = await _callService.getCall(callId);
      if (_currentCall == null || _currentCall!.id != callId) {
        return;
      }
      if (refreshedCall != null) {
        await _applyCall(refreshedCall);
        return;
      }

      final refreshedActiveCall =
          await _callService.getActiveCall(chatId: activeCall.chatId);
      if (_currentCall == null || _currentCall!.id != callId) {
        return;
      }
      if (refreshedActiveCall == null || refreshedActiveCall.id != callId) {
        await _applyCall(null);
        return;
      }
      await _applyCall(refreshedActiveCall);
    } catch (_) {
      // Keep the current ringing state and retry on the next interval.
    }
  }

  Future<void> _refreshActiveCall(String callId) async {
    final activeCall = _currentCall;
    if (activeCall == null ||
        activeCall.id != callId ||
        activeCall.state != CallState.active) {
      _cancelActiveCallRecovery();
      return;
    }

    try {
      final refreshedCall = await _callService.getCall(callId);
      if (_currentCall == null || _currentCall!.id != callId) {
        return;
      }
      if (refreshedCall == null) {
        await _applyCall(null);
        return;
      }
      await _applyCall(refreshedCall);
    } catch (_) {
      // Keep the current active state and retry on the next interval.
    }
  }

  Future<void> _ensureConnected(
    CallInvite call, {
    bool reconnect = false,
  }) async {
    final session = call.session;
    if (session == null ||
        session.url.trim().isEmpty ||
        session.token.trim().isEmpty) {
      _connectionError = 'Сеанс звонка ещё готовится.';
      _isConnectingRoom = false;
      _isReconnectingRoom = false;
      notifyListeners();
      return;
    }

    if (_room != null && _connectedRoomName == session.roomName) {
      return;
    }
    if (_isConnectingRoom || _isReconnectingRoom) {
      return;
    }

    if (reconnect) {
      _isReconnectingRoom = true;
    } else {
      _isConnectingRoom = true;
    }
    _connectionError = null;
    _hasMediaPermissionIssue = false;
    _microphonePublishFailed = false;
    notifyListeners();

    final hasMediaPermissions =
        await _mediaPermissionRequester.call(call.mediaMode);
    if (!hasMediaPermissions) {
      _hasMediaPermissionIssue = true;
      _connectionError =
          'Нет доступа к микрофону или камере. Разрешите доступ в настройках приложения.';
      _isConnectingRoom = false;
      _isReconnectingRoom = false;
      notifyListeners();
      return;
    }

    await _disposeRoom();

    final room = Room();
    final listener = room.createListener();
    listener
      ..on<RoomDisconnectedEvent>((event) {
        debugPrint(
          '[call] room disconnected reason=${event.reason} '
          'uptime=${_uptimeSinceConnect()}ms '
          'localQuality=${room.localParticipant?.connectionQuality} '
          'remoteCount=${room.remoteParticipants.length}',
        );
        unawaited(_handleRoomDisconnected());
      })
      ..on<RoomReconnectingEvent>((_) {
        debugPrint(
          '[call] room reconnecting uptime=${_uptimeSinceConnect()}ms '
          'localQuality=${room.localParticipant?.connectionQuality}',
        );
        _isReconnectingRoom = true;
        _connectionError = 'Связь прервалась. Переподключаем...';
        _clearReconnectRestoredBanner();
        notifyListeners();
      })
      ..on<RoomReconnectedEvent>((_) {
        debugPrint(
          '[call] room reconnected uptime=${_uptimeSinceConnect()}ms',
        );
        _isReconnectingRoom = false;
        _connectionError = null;
        _showReconnectRestoredBannerForMoment();
        _syncConnectionQualityFromRoom(room);
        notifyListeners();
        unawaited(_resumeLocalMediaAfterReconnect());
      })
      ..on<ParticipantConnectionQualityUpdatedEvent>((event) {
        _applyParticipantConnectionQuality(
          event.participant,
          event.connectionQuality,
        );
        notifyListeners();
      })
      ..on<ParticipantConnectedEvent>((_) {
        _hasSeenRemoteParticipant = true;
        _syncConnectionQualityFromRoom(room);
        notifyListeners();
      })
      ..on<ParticipantDisconnectedEvent>((_) {
        unawaited(_handleRemoteParticipantDisconnected());
      })
      // Fix C (2026-05-22): treat LiveKit publication state as source
      // of truth для mic/camera UI buttons. Без этих listener'ов Dart
      // booleans могли desync от actual publications (Bug 2/3 mute &
      // camera state mismatch). Local-only filter на TrackMuted/Unmuted
      // — иначе remote participant mute events корруптили бы наш state.
      ..on<LocalTrackPublishedEvent>((_) {
        _syncMediaStateFromLiveKit(room);
      })
      ..on<LocalTrackUnpublishedEvent>((_) {
        _syncMediaStateFromLiveKit(room);
      })
      ..on<TrackMutedEvent>((event) {
        if (identical(event.participant, room.localParticipant)) {
          _syncMediaStateFromLiveKit(room);
        }
      })
      ..on<TrackUnmutedEvent>((event) {
        if (identical(event.participant, room.localParticipant)) {
          _syncMediaStateFromLiveKit(room);
        }
      })
      ..on<ParticipantEvent>((_) {
        notifyListeners();
      })
      ..on<RoomEvent>((_) {
        notifyListeners();
      });

    try {
      _roomConnectStartedAt = DateTime.now();
      debugPrint(
        '[call] room.connect start url=${session.url} '
        'roomName=${session.roomName} reconnect=$reconnect',
      );
      await room.connect(session.url, session.token);
      debugPrint(
        '[call] room.connect ok uptime=${_uptimeSinceConnect()}ms',
      );
      _microphoneEnabled = true;
      _cameraEnabled = call.mediaMode.isVideo;
      // Publish mic separately от room.connect — на Android 14+ без
      // FOREGROUND_SERVICE_MICROPHONE permission setMicrophoneEnabled
      // может silently fail (publication == null) даже когда room
      // успешно connected. Этот fix surface'ит failure через
      // `microphonePublishFailed` flag вместо silently lying в UI.
      _microphonePublishFailed = !(await _publishLocalMicrophone(room));
      if (call.mediaMode.isVideo) {
        await room.localParticipant?.setCameraEnabled(
          _cameraEnabled,
          cameraCaptureOptions: CameraCaptureOptions(
            cameraPosition: _cameraPosition,
          ),
        );
      }
      _connectionError = null;
      _hasMediaPermissionIssue = false;
      _hasSeenRemoteParticipant = room.remoteParticipants.isNotEmpty;
      _room = room;
      _roomListener = listener;
      _connectedRoomName = session.roomName;
      _syncConnectionQualityFromRoom(room);
      if (reconnect) {
        _showReconnectRestoredBannerForMoment();
      }
      // CA1 FR3: дефолт маршрута на коннекте — ушной для аудио, динамик
      // для видео; применяется внутри attachRoom (даже без сохранённой
      // преференции).
      await _audioRouteService.attachRoom(room,
          isVideo: call.mediaMode.isVideo);
      await refreshInputDevices();
      await _applyCallPreferences(room, call);
    } catch (error) {
      await listener.dispose();
      await room.dispose();
      _hasMediaPermissionIssue = _looksLikeMediaPermissionIssue(error);
      _connectionError = _hasMediaPermissionIssue
          ? 'Нет доступа к микрофону или камере. Разрешите доступ в настройках приложения.'
          : 'Не удалось подключиться к звонку.';
      // Connection-level failure уже surface'ится через connectionError —
      // mic-specific signal на этом этапе redundant. Clear чтобы не
      // surface'ить stale mic banner поверх banner'а connection failure.
      _microphonePublishFailed = false;
    } finally {
      _isConnectingRoom = false;
      _isReconnectingRoom = false;
      notifyListeners();
    }
  }

  Future<void> _handleRoomDisconnected() async {
    await _disposeRoom();

    final activeCall = _currentCall;
    if (activeCall == null || activeCall.state != CallState.active) {
      notifyListeners();
      return;
    }
    if (_hasMediaPermissionIssue) {
      notifyListeners();
      return;
    }

    _connectionError = 'Связь прервалась. Переподключаем...';
    _isReconnectingRoom = true;
    _clearReconnectRestoredBanner();
    notifyListeners();
    await refreshCurrentCall();
  }

  Future<void> _handleRemoteParticipantDisconnected() async {
    final activeCall = _currentCall;
    final room = _room;
    if (activeCall == null ||
        activeCall.state != CallState.active ||
        room == null) {
      notifyListeners();
      return;
    }
    if (!_hasSeenRemoteParticipant || room.remoteParticipants.isNotEmpty) {
      _syncConnectionQualityFromRoom(room);
      notifyListeners();
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (_currentCall?.id != activeCall.id || _room == null) {
      return;
    }
    if (_room!.remoteParticipants.isNotEmpty) {
      _syncConnectionQualityFromRoom(_room!);
      notifyListeners();
      return;
    }
    await refreshCurrentCall();
  }

  bool _looksLikeMediaPermissionIssue(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('permission') ||
        message.contains('microphone') ||
        message.contains('camera') ||
        message.contains('device');
  }

  LocalVideoTrack? _localCameraTrack() {
    final publications = _room?.localParticipant?.videoTrackPublications;
    if (publications == null || publications.isEmpty) {
      return null;
    }
    for (final publication in publications) {
      if (publication.source == TrackSource.camera) {
        return publication.track;
      }
    }
    return null;
  }

  String? _resolveSelectedDeviceId(
    List<MediaDevice> devices,
    String? currentId,
  ) {
    if (currentId != null &&
        devices.any((device) => device.deviceId == currentId)) {
      return currentId;
    }
    return devices.isEmpty ? null : devices.first.deviceId;
  }

  CameraPosition? _cameraPositionFromDevice(MediaDevice device) {
    final haystack =
        '${device.deviceId} ${device.label} ${device.groupId ?? ''}'
            .toLowerCase();
    if (haystack.contains('back') ||
        haystack.contains('rear') ||
        haystack.contains('environment') ||
        haystack.contains('зад') ||
        haystack.contains('основ')) {
      return CameraPosition.back;
    }
    if (haystack.contains('front') ||
        haystack.contains('user') ||
        haystack.contains('face') ||
        haystack.contains('фронт') ||
        haystack.contains('перед')) {
      return CameraPosition.front;
    }
    return null;
  }

  void _clearInputDeviceState() {
    _microphoneDevices = const <MediaDevice>[];
    _cameraDevices = const <MediaDevice>[];
    _selectedMicrophoneDeviceId = null;
    _selectedCameraDeviceId = null;
    _isRefreshingInputDevices = false;
    _isSelectingMediaDevice = false;
    _devicePickerErrorMessage = null;
  }

  void _syncConnectionQualityFromRoom(Room room) {
    _localConnectionQuality =
        room.localParticipant?.connectionQuality ?? ConnectionQuality.unknown;
    _remoteConnectionQuality = ConnectionQuality.unknown;
    for (final participant in room.remoteParticipants.values) {
      if (participant.connectionQuality != ConnectionQuality.unknown) {
        _remoteConnectionQuality = participant.connectionQuality;
        break;
      }
    }
  }

  void _applyParticipantConnectionQuality(
    Participant participant,
    ConnectionQuality quality,
  ) {
    final room = _room;
    if (room != null && participant == room.localParticipant) {
      _localConnectionQuality = quality;
      return;
    }
    if (participant is LocalParticipant) {
      _localConnectionQuality = quality;
      return;
    }
    _remoteConnectionQuality = quality;
  }

  void _showReconnectRestoredBannerForMoment() {
    _reconnectRestoredTimer?.cancel();
    _showReconnectRestoredBanner = true;
    _reconnectRestoredTimer = Timer(const Duration(seconds: 3), () {
      _showReconnectRestoredBanner = false;
      notifyListeners();
    });
  }

  void _clearReconnectRestoredBanner() {
    _reconnectRestoredTimer?.cancel();
    _reconnectRestoredTimer = null;
    _showReconnectRestoredBanner = false;
  }

  void _clearConnectionQualityState() {
    _localConnectionQuality = ConnectionQuality.unknown;
    _remoteConnectionQuality = ConnectionQuality.unknown;
    _clearReconnectRestoredBanner();
  }

  Future<void> _resumeLocalMediaAfterReconnect() async {
    final room = _room;
    final activeCall = _currentCall;
    if (room == null ||
        activeCall == null ||
        activeCall.state != CallState.active) {
      return;
    }
    try {
      if (_microphoneEnabled) {
        _microphonePublishFailed = !(await _publishLocalMicrophone(room));
      }
      if (activeCall.mediaMode.isVideo) {
        await room.localParticipant?.setCameraEnabled(
          _cameraEnabled,
          cameraCaptureOptions: CameraCaptureOptions(
            cameraPosition: _cameraPosition,
          ),
        );
      }
    } catch (_) {
      // LiveKit will continue reconnecting if media resume is not ready yet.
    }
  }

  /// Запускает Kotlin foreground service для активного звонка
  /// (либо update если уже running для того же callId). Idempotent
  /// на re-fires `_applyCall(active)` для того же звонка.
  /// No-op на non-Android либо когда service не инжектирован
  /// (некоторые tests).
  Future<void> _ensureForegroundServiceStarted(CallInvite call) async {
    final service = _callForegroundService;
    if (service == null || !service.isSupported) {
      return;
    }
    final callId = call.id.trim();
    if (callId.isEmpty) {
      return;
    }
    final peerName = _resolvePeerName(call);
    final isVideo = call.mediaMode.isVideo;
    if (_foregroundServiceCallId == callId) {
      // Already running для этого звонка — update notification на
      // случай если peer name / mic state поменялись.
      await service.update(
        callId: callId,
        peerName: peerName,
        isVideo: isVideo,
        micEnabled: _microphoneEnabled,
      );
      return;
    }
    final started = await service.start(
      callId: callId,
      peerName: peerName,
      isVideo: isVideo,
      micEnabled: _microphoneEnabled,
    );
    if (started) {
      _foregroundServiceCallId = callId;
    }
  }

  /// Останавливает foreground service. No-op если он не был
  /// запущен этим coordinator instance (защищает tests/idle path
  /// от phantom stop invocations).
  Future<void> _stopForegroundService() async {
    final service = _callForegroundService;
    final callId = _foregroundServiceCallId;
    _foregroundServiceCallId = null;
    if (service == null || !service.isSupported || callId == null) {
      return;
    }
    await service.stop();
  }

  /// Update notification text без restart service. Вызывается на
  /// mic toggle reflection (icon в notification отражает on/off).
  /// No-op если service не running.
  Future<void> _updateForegroundService() async {
    final service = _callForegroundService;
    final callId = _foregroundServiceCallId;
    if (service == null || !service.isSupported || callId == null) {
      return;
    }
    final activeCall = _currentCall;
    await service.update(
      callId: callId,
      peerName: activeCall != null ? _resolvePeerName(activeCall) : null,
      isVideo: activeCall?.mediaMode.isVideo ?? false,
      micEnabled: _microphoneEnabled,
    );
  }

  /// Resolve peer display name из CallInvite — push payload-side
  /// name preferred, fallback на participant identity. Empty string
  /// если ничего нет (notification покажет «Идёт голосовой/видео-
  /// звонок» вместо «Идёт звонок с»).
  String? _resolvePeerName(CallInvite call) {
    final pushName = _pushCallerNames[call.id]?.trim();
    if (pushName != null && pushName.isNotEmpty) {
      return pushName;
    }
    return null;
  }

  /// Fix C (2026-05-22): pull local track state from LiveKit
  /// (`participant.isMicrophoneEnabled()` / `isCameraEnabled()`)
  /// и обновляет Dart fields на разнице. Source of truth — LiveKit
  /// publication state, Dart fields — reflected mirror для UI.
  ///
  /// Triggered events listener'ом в `_connectRoom` на
  /// `LocalTrackPublishedEvent`, `LocalTrackUnpublishedEvent`,
  /// `TrackMutedEvent` (local), `TrackUnmutedEvent` (local). Catches
  /// any future code path который mutates track state без touching
  /// Dart booleans — например notification action handler (Bug A
  /// added 2 entry points), server-side mute permissions, auto-republish
  /// после reconnect.
  ///
  /// Infinite loop prevention: change detection — `notifyListeners`
  /// fires только когда фактический value diff. Setter sequence
  /// (`_microphoneEnabled = ...` → `notifyListeners` → UI rebuild →
  /// читает getter — no LiveKit invocation → no event re-fire).
  void _syncMediaStateFromLiveKit(Room? room) {
    final participant = room?.localParticipant;
    if (participant == null) {
      return;
    }
    final micActual = participant.isMicrophoneEnabled();
    final camActual = participant.isCameraEnabled();
    var changed = false;
    if (_microphoneEnabled != micActual) {
      _microphoneEnabled = micActual;
      changed = true;
    }
    if (_cameraEnabled != camActual) {
      _cameraEnabled = camActual;
      changed = true;
    }
    // Defensive reconciliation (2026-05-22 Q1 false-positive fix
    // follow-up): если mic actually published per LiveKit, clear
    // any stale `microphonePublishFailed` flag. Без этого ранее
    // false-positive Q1 banner оставался стуком висеть после event-
    // driven sync corrected `_microphoneEnabled` к true.
    if (micActual && _microphonePublishFailed) {
      _microphonePublishFailed = false;
      changed = true;
    }
    if (changed) {
      notifyListeners();
      unawaited(_updateForegroundService());
    }
  }

  /// Try to publish the local microphone. Возвращает true при
  /// успехе, false при failure. На failure обновляет
  /// `_microphoneEnabled = false` для truthful UI state.
  ///
  /// **Success signal**: non-null publication object от
  /// `setMicrophoneEnabled(true)` — это LiveKit API contract на
  /// successful publish. Throwing exception либо null return
  /// considered failure.
  ///
  /// **Removed (2026-05-22)**: post-await `participant.isMicrophoneEnabled()`
  /// race-prone secondary check. Та lookup traversal происходит до
  /// того как track publications list propagate'нулся, fire'ила
  /// false positive «микрофон не подключился» banner хотя peer
  /// actually слышит. После Fix C (commit `207245a`) async truth
  /// sync handles это event-driven через `LocalTrackPublishedEvent`
  /// listener — `_syncMediaStateFromLiveKit` updates Dart booleans
  /// AND clears `_microphonePublishFailed` когда mic actually
  /// published. Race window больше не surfaces.
  ///
  /// На Android 14+ это первая линия защиты от Bug 1 (audio one-way):
  /// LiveKit shortcut может вернуть null publication когда microphone
  /// capture revoked'нут OS-ью (foreground service не запущен → mic
  /// stream killed). Bug A foreground service shipped 2026-05-22
  /// closed основной trigger, но Q1 backup remains для других
  /// failure modes (codec init, HAL error, etc.).
  Future<bool> _publishLocalMicrophone(Room room) async {
    final participant = room.localParticipant;
    if (participant == null) {
      _microphoneEnabled = false;
      return false;
    }
    try {
      final publication = await participant.setMicrophoneEnabled(true);
      final published = publication != null;
      if (!published) {
        _microphoneEnabled = false;
        debugPrint(
          '[call] microphone publish failed — LiveKit returned null '
          'publication (likely OS revoked mic capture)',
        );
      }
      return published;
    } catch (error, stack) {
      _microphoneEnabled = false;
      debugPrint('[call] microphone publish threw: $error\n$stack');
      return false;
    }
  }

  Future<void> _applyCallPreferences(Room room, CallInvite call) async {
    final preferences = await _callPreferences.load();
    await _applyPreferredMicrophone(
        room, preferences.defaultMicrophoneDeviceId);
    if (call.mediaMode.isVideo) {
      await _applyPreferredCamera(room, preferences.defaultCameraDeviceId);
    }
    await _applyPreferredAudioOutput(preferences.defaultAudioOutputId);
  }

  Future<void> _applyPreferredMicrophone(
    Room room,
    String? deviceId,
  ) async {
    final device = _findMediaDevice(_microphoneDevices, deviceId);
    if (device == null) {
      return;
    }
    try {
      await _microphoneDeviceSelector(room, device);
      _selectedMicrophoneDeviceId = device.deviceId;
    } catch (_) {
      // Keep the system-selected input when the saved device is stale.
    }
  }

  Future<void> _applyPreferredCamera(Room room, String? deviceId) async {
    final device = _findMediaDevice(_cameraDevices, deviceId);
    if (device == null) {
      return;
    }
    try {
      await _cameraDeviceSelector(room, device);
      _selectedCameraDeviceId = device.deviceId;
      _cameraPosition = _cameraPositionFromDevice(device) ?? _cameraPosition;
      _cameraEnabled = true;
    } catch (_) {
      // Keep the system-selected camera when the saved device is stale.
    }
  }

  Future<void> _applyPreferredAudioOutput(String? routeId) async {
    if (routeId == null || routeId.trim().isEmpty) {
      return;
    }
    AudioRouteOption? preferredRoute;
    for (final route in _audioRouteService.routes) {
      if (route.id == routeId) {
        preferredRoute = route;
        break;
      }
    }
    if (preferredRoute == null) {
      return;
    }
    await _audioRouteService.selectRoute(preferredRoute);
  }

  MediaDevice? _findMediaDevice(
    List<MediaDevice> devices,
    String? deviceId,
  ) {
    final normalizedDeviceId = deviceId?.trim();
    if (normalizedDeviceId == null || normalizedDeviceId.isEmpty) {
      return null;
    }
    for (final device in devices) {
      if (device.deviceId == normalizedDeviceId) {
        return device;
      }
    }
    return null;
  }

  Future<void> _maybeVibrateForIncomingCall(CallInvite call) async {
    final currentUser = currentUserId;
    if (currentUser == null ||
        !call.isIncomingFor(currentUser) ||
        _lastIncomingVibrationCallId == call.id) {
      return;
    }
    final preferences = await _callPreferences.load();
    if (!preferences.vibrationOnIncoming) {
      return;
    }
    _lastIncomingVibrationCallId = call.id;
    try {
      await _vibrationTrigger();
    } catch (_) {}
  }

  /// Lift the system-level incoming-call UI (Telecom self-managed
  /// connection) for an incoming ringing call. Idempotent per
  /// callId so a parallel `notification.created` path doesn't
  /// trigger a second `addNewIncomingCall`.
  ///
  /// This is the path that lets the user see + answer the call
  /// when the app is BACKGROUNDED (process alive, no UI mounted).
  /// Without it, push delivery hydrates the call into Dart state
  /// and notifies listeners, but no one is rendering — so the user
  /// gets vibration and silence. With Telecom in the picture, the
  /// system itself shows the native ringer screen over whatever
  /// the user is doing, identical to a phone call.
  Future<void> _maybeShowNativeIncomingCall(CallInvite call) async {
    final service = _androidIncomingCallService;
    if (service == null || !service.isSupported) {
      return;
    }
    final currentUser = currentUserId;
    if (currentUser == null || !call.isIncomingFor(currentUser)) {
      return;
    }
    if (_lastNativeIncomingCallId == call.id) {
      return;
    }
    _lastNativeIncomingCallId = call.id;
    final callerName = _pushCallerNames[call.id]?.trim().isNotEmpty == true
        ? _pushCallerNames[call.id]!
        : (call.initiatorId.isNotEmpty ? call.initiatorId : 'Родня');
    try {
      await service.showIncomingCall(
        callId: call.id,
        callerName: callerName,
        isVideo: call.mediaMode.isVideo,
        chatId: call.chatId,
      );
    } catch (_) {
      // Telecom registration races vs. permissions are non-fatal —
      // the native push service builds a full-screen intent
      // notification as a parallel safety net so the user still
      // sees the call.
    }
  }

  static Future<void> _switchLiveKitCameraPosition(
    LocalVideoTrack track,
    CameraPosition position,
  ) {
    return track.setCameraPosition(position);
  }

  static Future<List<MediaDevice>> _defaultAudioInputEnumerator() {
    return Hardware.instance.audioInputs();
  }

  static Future<List<MediaDevice>> _defaultVideoInputEnumerator() {
    return Hardware.instance.videoInputs();
  }

  static Future<void> _selectLiveKitMicrophoneDevice(
    Room room,
    MediaDevice device,
  ) {
    return room.setAudioInputDevice(device);
  }

  static Future<void> _selectLiveKitCameraDevice(
    Room room,
    MediaDevice device,
  ) {
    return room.setVideoInputDevice(device);
  }

  static Future<void> _defaultVibrationTrigger() {
    return HapticFeedback.mediumImpact();
  }

  static Future<bool> _requestPlatformMediaPermissions(
    CallMediaMode mediaMode,
  ) async {
    if (kIsWeb) {
      return true;
    }
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return true;
    }

    final microphoneStatus = await Permission.microphone.request();
    if (!(microphoneStatus.isGranted || microphoneStatus.isLimited)) {
      return false;
    }
    // Bug B (audit 2026-05-22): запрашиваем BLUETOOTH_CONNECT
    // best-effort параллельно. Android 12+ silently rejects
    // enumeration paired BT гарнитур без этого grant'а — user
    // подключил наушники, но в audio picker они не видны → fallback
    // на speaker/earpiece. Не gate'им room.connect — BT-permission
    // отказ не ломает звонок (просто без BT routing options).
    unawaited(_requestBluetoothConnectPermissionIfNeeded());

    if (!mediaMode.isVideo) {
      return true;
    }

    final cameraStatus = await Permission.camera.request();
    return cameraStatus.isGranted || cameraStatus.isLimited;
  }

  /// Best-effort BLUETOOTH_CONNECT runtime permission request на
  /// Android 12+ (API 31+). No-op на других платформах либо когда
  /// already-granted/permanently-denied (не спамим dialog).
  ///
  /// Не gate'ит call connect — denied BT permission означает только
  /// что BT гарнитуры не показываются в audio device picker. User
  /// останется на speaker/earpiece, не surfaceит fatal error.
  static Future<void> _requestBluetoothConnectPermissionIfNeeded() async {
    if (kIsWeb) {
      return;
    }
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      final status = await Permission.bluetoothConnect.status;
      if (status.isGranted ||
          status.isLimited ||
          status.isPermanentlyDenied ||
          status.isRestricted) {
        // Already settled — no point re-asking.
        return;
      }
      final result = await Permission.bluetoothConnect.request();
      if (kDebugMode) {
        debugPrint(
          '[call] BLUETOOTH_CONNECT permission result=$result',
        );
      }
    } catch (error) {
      debugPrint(
        '[call] BLUETOOTH_CONNECT permission request threw: $error',
      );
    }
  }

  void _handleCallEvent(CallEvent event) {
    unawaited(_applyCall(event.call));
  }

  void _handlePushMessage(RustorePushMessage message) {
    if (!message.isCallInvite) {
      return;
    }
    final callId = message.callId;
    if (callId != null && callId.isNotEmpty) {
      // Stash the caller name from the push payload before we
      // hydrate — _applyCall will read it back from this cache
      // when it fires the native Telecom UI. CallInvite from
      // /v1/calls/:id only carries initiatorId, not the display
      // name, so without this hop the lockscreen would show the
      // raw user id (or worse, a generic «Звонок» fallback).
      final pushCallerName = message.data['callerName']?.trim();
      if (pushCallerName != null && pushCallerName.isNotEmpty) {
        _pushCallerNames[callId] = pushCallerName;
      }
    }
    unawaited(
      hydrateIncomingCall(
        callId: callId,
        chatId: message.chatId,
      ),
    );
  }

  bool _shouldIgnoreCallSnapshot(CallInvite nextCall) {
    final currentCall = _currentCall;
    if (currentCall == null) {
      return false;
    }
    if (currentCall.id != nextCall.id) {
      return nextCall.state.isTerminal;
    }
    if (nextCall.state.isTerminal) {
      return false;
    }

    final currentUpdatedAt = currentCall.updatedAt.millisecondsSinceEpoch;
    final nextUpdatedAt = nextCall.updatedAt.millisecondsSinceEpoch;
    if (nextUpdatedAt < currentUpdatedAt) {
      return true;
    }
    if (nextUpdatedAt > currentUpdatedAt) {
      return false;
    }

    final currentRank = _callStatePriority(currentCall);
    final nextRank = _callStatePriority(nextCall);
    if (nextRank < currentRank) {
      return true;
    }

    if (currentCall.state == CallState.active &&
        nextCall.state == CallState.active &&
        currentCall.session != null &&
        nextCall.session == null) {
      return true;
    }

    return false;
  }

  int _callStatePriority(CallInvite call) {
    if (call.state == CallState.active) {
      return call.session != null ? 4 : 3;
    }
    if (call.state == CallState.ringing) {
      return 2;
    }
    return 1;
  }

  Future<void> _disposeRoom() async {
    await _audioRouteService.attachRoom(null);
    await _roomListener?.dispose();
    _roomListener = null;
    if (_room != null) {
      await _room!.disconnect();
      await _room!.dispose();
    }
    _room = null;
    _connectedRoomName = null;
    _roomConnectStartedAt = null;
    _hasSeenRemoteParticipant = false;
  }

  int _uptimeSinceConnect() {
    final startedAt = _roomConnectStartedAt;
    if (startedAt == null) {
      return -1;
    }
    return DateTime.now().difference(startedAt).inMilliseconds;
  }

  Future<void> reset() async {
    _cancelRingingRecovery();
    _cancelActiveCallRecovery();
    _currentCall = null;
    _connectionError = null;
    _isConnectingRoom = false;
    _isReconnectingRoom = false;
    _microphoneEnabled = true;
    _microphonePublishFailed = false;
    _cameraEnabled = false;
    _isSwitchingCamera = false;
    _cameraPosition = CameraPosition.front;
    _clearInputDeviceState();
    _clearConnectionQualityState();
    _hasMediaPermissionIssue = false;
    _hasSeenRemoteParticipant = false;
    _joinedOnAnotherDevice = false;
    _lastIncomingVibrationCallId = null;
    await _stopForegroundService();
    await _disposeRoom();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_hasMediaPermissionIssue) {
        _hasMediaPermissionIssue = false;
        _connectionError = null;
      }
      unawaited(ensureRuntimeReady().then((_) => resync()));
      unawaited(_handlePendingAndroidCallAction());
      // Pending notification button tap (Микрофон/Завершить) ждёт
      // в SharedPreferences пока app resumes — consume & apply.
      unawaited(_consumePendingForegroundNotificationAction());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelRingingRecovery();
    _cancelActiveCallRecovery();
    _clearReconnectRestoredBanner();
    unawaited(_callEventsSubscription?.cancel());
    unawaited(_realtimeSubscription?.cancel());
    unawaited(_pushSubscription?.cancel());
    unawaited(_stopForegroundService());
    unawaited(_disposeRoom());
    super.dispose();
  }

  /// Test seam — позволяет flip'ать `microphonePublishFailed` без
  /// настоящей LiveKit Room. Используется unit-test'ом для проверки
  /// что getter + notifier работают на boundary. Production-кода это
  /// никогда не вызывает.
  @visibleForTesting
  void debugMarkMicrophonePublishFailed(bool failed) {
    if (_microphonePublishFailed == failed) {
      return;
    }
    _microphonePublishFailed = failed;
    if (failed) {
      _microphoneEnabled = false;
    }
    notifyListeners();
  }

  /// Test seam — direct set `_cameraEnabled` для проверки Fix B
  /// preservation flow. Production-кода не использует.
  @visibleForTesting
  void debugSetCameraEnabled(bool value) {
    if (_cameraEnabled == value) {
      return;
    }
    _cameraEnabled = value;
    notifyListeners();
  }

  /// Test seam — flag pretending что LiveKit Room is connected, чтобы
  /// `_applyCall` preservation path для Fix B можно было exercise без
  /// настоящего room mock. Production-кода это field никогда не sets.
  @visibleForTesting
  bool debugTreatRoomAsActive = false;

  /// Test seam — directly invokes the same diff-apply logic как
  /// `_syncMediaStateFromLiveKit`, но без необходимости Room/Participant
  /// instance. Verifies change detection + notify-on-diff invariant
  /// (Fix C). Production-кода не использует.
  @visibleForTesting
  void debugApplyMediaSync({
    required bool micEnabled,
    required bool camEnabled,
  }) {
    var changed = false;
    if (_microphoneEnabled != micEnabled) {
      _microphoneEnabled = micEnabled;
      changed = true;
    }
    if (_cameraEnabled != camEnabled) {
      _cameraEnabled = camEnabled;
      changed = true;
    }
    // Mirror production `_syncMediaStateFromLiveKit` defensive
    // reconciliation: clear stale microphonePublishFailed когда
    // mic actually published per LiveKit truth.
    if (micEnabled && _microphonePublishFailed) {
      _microphonePublishFailed = false;
      changed = true;
    }
    if (changed) {
      notifyListeners();
      unawaited(_updateForegroundService());
    }
  }
}
