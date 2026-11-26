part of '../call_coordinator_service.dart';

abstract class _CallCoordinatorBase extends ChangeNotifier
    with WidgetsBindingObserver {
  _CallCoordinatorBase({
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
    CallWakelockToggler? wakelockToggler,
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
        _wakelockToggler = wakelockToggler ?? _defaultWakelockToggler,
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
    // Proximity-политика зависит от аудио-маршрута (ушной/динамик) —
    // пересчитываем её на каждую смену маршрута.
    _audioRouteService.addListener(_handleAudioRouteChanged);
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

  final CallWakelockToggler _wakelockToggler;

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

  // P2: never let the «Переподключение» overlay wedge forever — if the
  // LiveKit transport is actually live while the flag is still up, this
  // watchdog force-clears it.
  Timer? _reconnectWatchdogTimer;

  String? _ringingRecoveryCallId;

  String? _activeCallRecoveryCallId;

  CallInvite? _currentCall;

  // Гигиена звонков: текущее желаемое состояние wakelock'а — guard от
  // повторных platform-вызовов на каждый recovery-snapshot (2s poll).
  bool _wakelockActive = false;

  // Момент, когда звонок стал active — база для таймера длительности.
  // Латчится ОДИН раз на звонок (`??=`): recovery-snapshot'ы и
  // reconnect'ы не сбрасывают отсчёт. Серверный acceptedAt
  // предпочтительнее (переживает рестарт приложения), локальный
  // DateTime.now() — fallback для снапшотов без acceptedAt.
  DateTime? _activeSince;

  Room? _room;

  EventsListener<RoomEvent>? _roomListener;

  String? _connectedRoomName;

  DateTime? _roomConnectStartedAt;

  bool _isConnectingRoom = false;

  bool _isReconnectingRoom = false;

  // P2: re-entrancy latch for an ACTUAL in-flight room connect. Kept
  // SEPARATE from the _isReconnectingRoom DISPLAY flag — previously
  // _handleRoomDisconnected set _isReconnectingRoom=true and then the
  // reconnect it triggered early-returned on that same flag (deadlock),
  // so the room never reconnected and «Переподключение» stuck forever
  // while audio was actually live.
  bool _connectAttemptInFlight = false;

  int _connectGeneration = 0;

  bool _disposed = false;

  bool _microphoneEnabled = true;

  // True когда LiveKit вернул успех на `setMicrophoneEnabled(true)` но
  // фактическая publication отсутствует (publication == null либо
  // `isMicrophoneEnabled()` после await вернул false). Симптом
  // соответствует Артёмов reported Bug 1 «собеседник не слышит» —
  // UI showed «mic on» хотя трек не публиковался. Surface'им через
  // separate flag чтобы CallScreen мог поднять banner / snackbar и
  // юзер увидел real state вместо silent fail.
  bool _microphonePublishFailed = false;

  // Камерный аналог `_microphonePublishFailed`: publish упал (нативный
  // отказ addTransceiver, permission, HAL) — UI обязан показать честное
  // «камера не подключилась» вместо перечёркнутой иконки без объяснений.
  bool _cameraPublishFailed = false;

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

  final Set<String> _locallyStartedCallIds = <String>{};

  // Caller display names captured from VKPNS push payloads, keyed
  // by callId. Push delivery beats the realtime hydrate (the push
  // arrives before the GET /v1/calls/:id response lands), so we
  // park the name here and pull it out when the Telecom-side
  // showIncomingCall fires from _applyCall.
  final Map<String, String> _pushCallerNames = <String, String>{};

  // Native incoming-call UIs (self-managed Telecom connection + ringtone
  // notification) currently shown, keyed by callId. This is a SET, not a
  // single slot: a superseded/orphaned incoming call (rapid successive
  // calls, or one that ends server-side while a different call is
  // _currentCall) must still be torn down — otherwise its Telecom
  // connection strands on paired watches and holds MODE_RINGTONE, killing
  // the phone's volume buttons. De-dupes showIncomingCall too (a call can
  // fan out via both push and notification.created realtime).
  final Set<String> _shownNativeIncomingCallIds = <String>{};

  String? get currentUserId => _callService.currentUserId;

  CallInvite? get currentCall => _currentCall;

  /// Момент перехода текущего звонка в active — база таймера
  /// длительности в UI. Null пока звонок не active (и после конца).
  DateTime? get activeSince => _activeSince;

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

  /// True если попытка включить камеру не дошла до публикации —
  /// CallScreen поднимает snackbar с «Повторить» (Q1-паттерн микрофона).
  bool get cameraPublishFailed => _cameraPublishFailed;

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
    // Group calls have N remotes — surface the WORST link, not the first seen.
    return _worstRemoteQuality(participants.map((p) => p.connectionQuality));
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

  bool isLocallyStartedCall(String? callId) {
    final normalizedCallId = callId?.trim();
    if (normalizedCallId == null || normalizedCallId.isEmpty) {
      return false;
    }
    return _locallyStartedCallIds.contains(normalizedCallId);
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

  /// Страховка инварианта нативного WebRTC: при simulcast у всех
  /// encodings должен быть ОДИНАКОВЫЙ bitrate_priority/network_priority.
  /// LiveKit подставляет приоритет из videoEncoding только в верхний
  /// слой (авто-слои q/h остаются с дефолтным low) → addTransceiver
  /// отвергает весь набор («C++ addTransceiver failed»), камера не
  /// публикуется вовсе. Срезаем приоритеты из videoEncoding, оставляя
  /// битрейт/fps — рабочую часть медиа-профиля.
  VideoPublishOptions _sanitizedVideoPublishOptions(Room room) {
    final options = room.roomOptions.defaultVideoPublishOptions;
    final encoding = options.videoEncoding;
    if (!options.simulcast ||
        encoding == null ||
        (encoding.bitratePriority == null &&
            encoding.networkPriority == null)) {
      return options;
    }
    return options.copyWith(
      videoEncoding: VideoEncoding(
        maxFramerate: encoding.maxFramerate,
        maxBitrate: encoding.maxBitrate,
      ),
    );
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

  /// Test seam — flag pretending что LiveKit Room is connected, чтобы
  /// `_applyCall` preservation path для Fix B можно было exercise без
  /// настоящего room mock. Production-кода это field никогда не sets.
  @visibleForTesting
  bool debugTreatRoomAsActive = false;

  // Forwarders for cross-mixin calls.
  void _applyParticipantConnectionQuality(
    Participant participant,
    ConnectionQuality quality,
  );
  Future<void> _applyPreferredAudioOutput(String? routeId);
  void _armReconnectWatchdog();
  CameraPosition? _cameraPositionFromDevice(MediaDevice device);
  void _cancelReconnectWatchdog();
  void _clearConnectionQualityState();
  void _clearInputDeviceState();
  void _clearReconnectRestoredBanner();
  void _dismissNativeIncomingCall(String callId);
  void _dismissStaleNativeIncomingCalls({String? keepCallId});
  Future<void> _disposeRoom();
  Future<void> _ensureConnected(
    CallInvite call, {
    bool reconnect = false,
  });
  Future<void> _ensureForegroundServiceStarted(CallInvite call);
  void _handleAudioRouteChanged();
  void _handleCallEvent(CallEvent event);
  Future<void> _handlePendingAndroidCallAction();
  void _handlePushMessage(RustorePushMessage message);
  Future<void> _maybeShowNativeIncomingCall(CallInvite call);
  Future<void> _maybeVibrateForIncomingCall(CallInvite call);
  Future<bool> _publishLocalCamera(Room room);
  Future<bool> _publishLocalMicrophone(Room room);
  Future<void> _resumeLocalMediaAfterReconnect();
  Future<void> _setWakelockActive(bool active);
  void _showReconnectRestoredBannerForMoment();
  Future<void> _stopForegroundService({bool force = false});
  void _syncConnectionQualityFromRoom(Room room);
  Future<void> _syncProximityWakeLock();
  Future<void> _updateForegroundService();
  int _uptimeSinceConnect();
  ConnectionQuality _worstRemoteQuality(Iterable<ConnectionQuality> qualities);
  Future<CallInvite> acceptCall([String? callId]);
  Future<void> activateCall(CallInvite call);
  Future<void> ensureRuntimeReady();
  Future<CallInvite?> finishCall([String? callId]);
  Future<CallInvite?> hydrateIncomingCall({
    String? callId,
    String? chatId,
  });
  Future<CallInvite?> refreshCurrentCall();
  Future<void> refreshInputDevices();
  Future<CallInvite?> resync({String? chatId});
  Future<void> toggleMicrophone();
}
