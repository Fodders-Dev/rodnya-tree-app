part of '../call_coordinator_service.dart';

mixin _CallCoordinatorSignalingMixin on _CallCoordinatorBase {
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

  @override
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
      final normalizedChatId = chatId?.trim();
      nextCall ??= await _callService.getActiveCall(chatId: normalizedChatId);
      // Global fallback only makes sense when the first lookup was actually
      // scoped to a chat — otherwise it's the exact same request repeated
      // (perf: this used to fire unconditionally, doubling GET
      // /v1/calls/active on every cold-start incoming-call check).
      if (nextCall == null &&
          normalizedChatId != null &&
          normalizedChatId.isNotEmpty) {
        nextCall = await _callService.getActiveCall();
      }
      if (nextCall == null || nextCall.state.isTerminal) {
        return null;
      }
      await _applyCall(nextCall);
      return nextCall;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> activateCall(CallInvite call) async {
    await _applyCall(call);
  }

  // GP5: a one-shot "the user explicitly asked to see this call now" flag. Set
  // by requestForegroundPresentation (e.g. tapping «Позвонить» on a chat whose
  // call is already live but was minimized). The runtime host consumes it to
  // force-present, overriding a stale dismissal (_suppressedCallId).
  String? _foregroundPresentationCallId;

  // Bring an already-live call to the foreground on an EXPLICIT user request,
  // overriding any prior minimize/dismiss. _applyCall can early-return via the
  // ignore-gate without notifying when the call is unchanged (the exact case:
  // the user minimized this very call), so force a notify to make the host
  // re-evaluate and consume the request.
  Future<void> requestForegroundPresentation(CallInvite call) async {
    if (call.state.isTerminal) {
      return;
    }
    _foregroundPresentationCallId = call.id;
    await _applyCall(call);
    notifyListeners();
  }

  bool consumeForegroundPresentationRequest(String callId) {
    if (_foregroundPresentationCallId != null &&
        _foregroundPresentationCallId == callId) {
      _foregroundPresentationCallId = null;
      return true;
    }
    return false;
  }

  @override
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
        if (_currentCall == null && !_disposed) {
          await resync();
        }
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

  Future<CallInvite?> getCall(String callId) {
    return _callService.getCall(callId);
  }

  Future<CallInvite?> getActiveCall({String? chatId}) {
    return _callService.getActiveCall(chatId: chatId);
  }

  @override
  Future<CallInvite?> resync({String? chatId}) async {
    final currentUser = currentUserId?.trim();
    if (currentUser == null || currentUser.isEmpty) {
      if (chatId == null || _currentCall?.chatId == chatId) {
        await _applyCall(null);
      }
      return null;
    }

    final callIdBeforeFetch = _currentCall?.id;
    try {
      final activeCall = await _callService.getActiveCall(chatId: chatId);
      if (_disposed) {
        return null;
      }
      if (activeCall == null) {
        if (callIdBeforeFetch == _currentCall?.id &&
            (chatId == null || _currentCall?.chatId == chatId)) {
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

  @override
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
    final normalizedCallId = invite.id.trim();
    if (normalizedCallId.isNotEmpty) {
      _locallyStartedCallIds.add(normalizedCallId);
    }
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

  /// GP3: add NEW chat members to the live call. Feature-detects the
  /// [CallParticipantAdder] capability (only the live backend implements it)
  /// so the base [CallServiceInterface] — and every fake — stays untouched.
  /// Re-applies the grown roster to the current call so the UI updates.
  Future<CallInvite> addCallParticipants(
    String callId, {
    required List<String> participantIds,
  }) async {
    final service = _callService;
    if (service is CallParticipantAdder) {
      final adder = service as CallParticipantAdder;
      final invite = await adder.addCallParticipants(
        callId,
        participantIds: participantIds,
      );
      if (_currentCall?.id == invite.id) {
        await _applyCall(invite);
      }
      return invite;
    }
    throw UnsupportedError(
      'Добавление участников не поддерживается этим бэкендом',
    );
  }

  // Дебаунс lifecycle-действий (UX-аудит P1): double-tap по «Принять»/
  // «Завершить» на лагающем устройстве давал дубль state-dependent
  // API-вызова (повторный reject/cancel/hangUp по уже меняющемуся
  // звонку). Memo-future: повторный вызов для того же callId получает
  // УЖЕ идущую операцию. Покрывает все входы разом — кнопки экрана,
  // Telecom pending actions, кнопки FGS-уведомления.
  Future<CallInvite>? _acceptInFlight;

  String? _acceptInFlightCallId;

  Future<CallInvite>? _joinInFlight;

  String? _joinInFlightCallId;

  Future<CallInvite?>? _finishInFlight;

  String? _finishInFlightCallId;

  @override
  Future<CallInvite> acceptCall([String? callId]) {
    final resolvedCallId = callId ?? _currentCall?.id;
    if (resolvedCallId == null || resolvedCallId.isEmpty) {
      throw StateError('Нет активного звонка для принятия.');
    }
    final inFlight = _acceptInFlight;
    if (inFlight != null && _acceptInFlightCallId == resolvedCallId) {
      return inFlight;
    }
    late final Future<CallInvite> future;
    Future<CallInvite> run() async {
      try {
        final invite = await _callService.acceptCall(resolvedCallId);
        await _applyCall(invite);
        return invite;
      } finally {
        // Чистим memo ТОЛЬКО если он всё ещё наш: медленный accept
        // звонка A не должен затирать memo уже стартовавшего B.
        if (identical(_acceptInFlight, future)) {
          _acceptInFlight = null;
          _acceptInFlightCallId = null;
        }
      }
    }

    future = run();
    _acceptInFlight = future;
    _acceptInFlightCallId = resolvedCallId;
    return future;
  }

  /// P1: «залететь в группу» — enter an already-active group call the user
  /// belongs to but hasn't joined yet. POST /join mints the per-participant
  /// token, then _applyCall connects to the room exactly like accept.
  Future<CallInvite> joinActiveCall([String? callId]) {
    final resolvedCallId = callId ?? _currentCall?.id;
    if (resolvedCallId == null || resolvedCallId.isEmpty) {
      throw StateError('Нет звонка для входа.');
    }
    final inFlight = _joinInFlight;
    if (inFlight != null && _joinInFlightCallId == resolvedCallId) {
      return inFlight;
    }
    late final Future<CallInvite> future;
    Future<CallInvite> run() async {
      try {
        final invite = await _callService.joinCall(resolvedCallId);
        await _applyCall(invite);
        return invite;
      } finally {
        if (identical(_joinInFlight, future)) {
          _joinInFlight = null;
          _joinInFlightCallId = null;
        }
      }
    }

    future = run();
    _joinInFlight = future;
    _joinInFlightCallId = resolvedCallId;
    return future;
  }

  @override
  Future<CallInvite?> finishCall([String? callId]) {
    final resolvedForDedup = callId ?? _currentCall?.id;
    final inFlight = _finishInFlight;
    if (inFlight != null &&
        resolvedForDedup != null &&
        _finishInFlightCallId == resolvedForDedup) {
      return inFlight;
    }
    late final Future<CallInvite?> future;
    Future<CallInvite?> run() async {
      try {
        return await _finishCallInner(callId);
      } finally {
        if (identical(_finishInFlight, future)) {
          _finishInFlight = null;
          _finishInFlightCallId = null;
        }
      }
    }

    future = run();
    if (resolvedForDedup != null) {
      _finishInFlight = future;
      _finishInFlightCallId = resolvedForDedup;
    }
    return future;
  }

  Future<CallInvite?> _finishCallInner(String? callId) async {
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

  Future<void> _applyCall(CallInvite? nextCall) async {
    final currentCall = _currentCall;
    // A terminal snapshot must ALWAYS tear down its native incoming UI,
    // even when it isn't the tracked _currentCall — a superseded/orphaned
    // call reaches terminal while a different call is current, and both the
    // ignore-gate (_shouldIgnoreCallSnapshot) and the terminal branch below
    // return early for a non-current call. Without this, the orphan's
    // Telecom connection strands on paired watches + holds MODE_RINGTONE.
    if (nextCall != null && nextCall.state.isTerminal) {
      _dismissNativeIncomingCall(nextCall.id);
    }
    if (nextCall == null) {
      if (currentCall != null) {
        _pushCallerNames.remove(currentCall.id);
        _locallyStartedCallIds.remove(currentCall.id);
      }
      // No active call server-side → sweep every shown native incoming UI,
      // not just _currentCall's (rapid successive calls can leave more than
      // one Telecom connection registered).
      _dismissStaleNativeIncomingCalls();
      _cancelRingingRecovery();
      _cancelActiveCallRecovery();
      _connectGeneration++;
      _currentCall = null;
      _isConnectingRoom = false;
      _isReconnectingRoom = false;
      _isSwitchingCamera = false;
      _cameraPosition = CameraPosition.front;
      _clearInputDeviceState();
      _connectionError = null;
      _hasMediaPermissionIssue = false;
      _microphonePublishFailed = false;
      _cameraPublishFailed = false;
      _hasSeenRemoteParticipant = false;
      _joinedOnAnotherDevice = false;
      _lastIncomingVibrationCallId = null;
      _activeSince = null;
      _clearConnectionQualityState();
      notifyListeners();
      await _setWakelockActive(false);
      await _stopForegroundService(force: true);
      await _disposeRoom();
      return;
    }

    if (nextCall.state.isTerminal) {
      _locallyStartedCallIds.remove(nextCall.id);
    }

    if (_shouldIgnoreCallSnapshot(nextCall)) {
      return;
    }

    if (nextCall.state.isTerminal) {
      if (currentCall == null || currentCall.id != nextCall.id) {
        return;
      }
      _dismissNativeIncomingCall(nextCall.id);
      _pushCallerNames.remove(nextCall.id);
      _locallyStartedCallIds.remove(nextCall.id);
      _cancelRingingRecovery();
      _cancelActiveCallRecovery();
      _connectGeneration++;
      _currentCall = null;
      _isConnectingRoom = false;
      _isReconnectingRoom = false;
      _isSwitchingCamera = false;
      _cameraPosition = CameraPosition.front;
      _clearInputDeviceState();
      _connectionError = null;
      _hasMediaPermissionIssue = false;
      _microphonePublishFailed = false;
      _cameraPublishFailed = false;
      _hasSeenRemoteParticipant = false;
      _joinedOnAnotherDevice = false;
      _lastIncomingVibrationCallId = null;
      _activeSince = null;
      _clearConnectionQualityState();
      notifyListeners();
      await _setWakelockActive(false);
      await _stopForegroundService(force: true);
      await _disposeRoom();
      return;
    }

    final previousCallId = _currentCall?.id;
    final previousRoomName = _connectedRoomName;
    _currentCall = nextCall;
    // A different call just became current — tear down any earlier native
    // incoming UI so a superseded call can't keep ringing on a paired watch.
    _dismissStaleNativeIncomingCalls(keepCallId: nextCall.id);
    // Живой звонок (ringing/active) — экран не должен гаснуть. Гейт на
    // joinedOnAnotherDevice: иначе recovery-poll (2s) чередовал бы
    // enable здесь / disable в joined-ветке ниже весь звонок (ревью P1).
    unawaited(_setWakelockActive(!nextCall.joinedOnAnotherDevice));
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
      if (currentCall?.id == nextCall.id &&
          currentCall?.state == CallState.ringing) {
        _dismissNativeIncomingCall(nextCall.id);
      }
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
      _activeSince = null;
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
    if (nextCall.state == CallState.active && _activeSince == null) {
      // Живой переход ringing→active наблюдали сами → локальные часы
      // (без серверного дрейфа). Иначе (рестарт приложения / late-join
      // уже active звонка) — серверный acceptedAt, клампнутый «не из
      // будущего»: устройство с отстающими часами не должно видеть
      // замороженный 0:00 (ревью P2).
      final observedLiveTransition = currentCall?.id == nextCall.id &&
          currentCall?.state == CallState.ringing;
      final now = DateTime.now();
      final accepted = nextCall.acceptedAt;
      _activeSince = observedLiveTransition || accepted == null
          ? now
          : (accepted.isAfter(now) ? now : accepted);
    }
    _joinedOnAnotherDevice = nextCall.joinedOnAnotherDevice;
    notifyListeners();

    if (nextCall.state == CallState.active) {
      if (nextCall.joinedOnAnotherDevice) {
        _isConnectingRoom = false;
        _isReconnectingRoom = false;
        _connectionError = null;
        _activeSince = null;
        _clearReconnectRestoredBanner();
        notifyListeners();
        // Звонок продолжается на другом устройстве — ЭТОТ девайс
        // отпускает экран и сервис.
        await _setWakelockActive(false);
        await _stopForegroundService(force: true);
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
      // Медиаканал (пере)подключён — пересчитать proximity-политику
      // (маршрут по умолчанию уже применён внутри attachRoom).
      unawaited(_syncProximityWakeLock());
      return;
    }

    if (previousCallId != null && previousCallId != nextCall.id) {
      await _stopForegroundService(force: true);
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

  @override
  void _handleCallEvent(CallEvent event) {
    unawaited(_applyCall(event.call));
  }

  @override
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

  @override
  int _uptimeSinceConnect() {
    final startedAt = _roomConnectStartedAt;
    if (startedAt == null) {
      return -1;
    }
    return DateTime.now().difference(startedAt).inMilliseconds;
  }
}
