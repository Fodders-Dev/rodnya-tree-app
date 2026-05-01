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
    CallVibrationTrigger? vibrationTrigger,
    Duration ringingRecoveryInterval = const Duration(seconds: 5),
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
  bool _isConnectingRoom = false;
  bool _isReconnectingRoom = false;
  bool _microphoneEnabled = true;
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
  String? _lastIncomingVibrationCallId;
  final Set<String> _visibleCallScreenIds = <String>{};

  String? get currentUserId => _callService.currentUserId;
  CallInvite? get currentCall => _currentCall;
  Room? get room => _room;
  bool get isConnectingRoom => _isConnectingRoom;
  bool get isReconnectingRoom => _isReconnectingRoom;
  bool get microphoneEnabled => _microphoneEnabled;
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
  }) async {
    final invite = await _callService.startCall(
      chatId: chatId,
      mediaMode: mediaMode,
    );
    await _applyCall(invite);
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
    await room.localParticipant?.setMicrophoneEnabled(nextValue);
    _microphoneEnabled = nextValue;
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    final room = _room;
    final activeCall = _currentCall;
    if (room == null || activeCall == null || !activeCall.mediaMode.isVideo) {
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
      _hasSeenRemoteParticipant = false;
      _lastIncomingVibrationCallId = null;
      _clearConnectionQualityState();
      notifyListeners();
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
      _hasSeenRemoteParticipant = false;
      _lastIncomingVibrationCallId = null;
      _clearConnectionQualityState();
      notifyListeners();
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
      _cameraEnabled = false;
    }
    notifyListeners();

    if (nextCall.state == CallState.active) {
      if (_hasMediaPermissionIssue &&
          previousCallId == nextCall.id &&
          _room == null) {
        notifyListeners();
        return;
      }
      final shouldReconnect = previousCallId == nextCall.id &&
          previousRoomName != null &&
          _room == null;
      await _ensureConnected(nextCall, reconnect: shouldReconnect);
      return;
    }

    if (previousCallId != null && previousCallId != nextCall.id) {
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
      ..on<RoomDisconnectedEvent>((_) {
        unawaited(_handleRoomDisconnected());
      })
      ..on<RoomReconnectingEvent>((_) {
        _isReconnectingRoom = true;
        _connectionError = 'Связь прервалась. Переподключаем...';
        _clearReconnectRestoredBanner();
        notifyListeners();
      })
      ..on<RoomReconnectedEvent>((_) {
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
      ..on<ParticipantEvent>((_) {
        notifyListeners();
      })
      ..on<RoomEvent>((_) {
        notifyListeners();
      });

    try {
      await room.connect(session.url, session.token);
      _microphoneEnabled = true;
      _cameraEnabled = call.mediaMode.isVideo;
      await room.localParticipant?.setMicrophoneEnabled(_microphoneEnabled);
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
      await _audioRouteService.attachRoom(room);
      await refreshInputDevices();
      await _applyCallPreferences(room, call);
    } catch (error) {
      await listener.dispose();
      await room.dispose();
      _hasMediaPermissionIssue = _looksLikeMediaPermissionIssue(error);
      _connectionError = _hasMediaPermissionIssue
          ? 'Нет доступа к микрофону или камере. Разрешите доступ в настройках приложения.'
          : 'Не удалось подключиться к звонку.';
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
      await room.localParticipant?.setMicrophoneEnabled(_microphoneEnabled);
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
    if (!mediaMode.isVideo) {
      return true;
    }

    final cameraStatus = await Permission.camera.request();
    return cameraStatus.isGranted || cameraStatus.isLimited;
  }

  void _handleCallEvent(CallEvent event) {
    unawaited(_applyCall(event.call));
  }

  void _handlePushMessage(RustorePushMessage message) {
    if (!message.isCallInvite) {
      return;
    }
    unawaited(
      hydrateIncomingCall(
        callId: message.callId,
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
    _hasSeenRemoteParticipant = false;
  }

  Future<void> reset() async {
    _cancelRingingRecovery();
    _cancelActiveCallRecovery();
    _currentCall = null;
    _connectionError = null;
    _isConnectingRoom = false;
    _isReconnectingRoom = false;
    _microphoneEnabled = true;
    _cameraEnabled = false;
    _isSwitchingCamera = false;
    _cameraPosition = CameraPosition.front;
    _clearInputDeviceState();
    _clearConnectionQualityState();
    _hasMediaPermissionIssue = false;
    _hasSeenRemoteParticipant = false;
    _lastIncomingVibrationCallId = null;
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
    unawaited(_disposeRoom());
    super.dispose();
  }
}
