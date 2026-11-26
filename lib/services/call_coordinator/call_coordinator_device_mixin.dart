part of '../call_coordinator_service.dart';

mixin _CallCoordinatorDeviceMixin on _CallCoordinatorBase {
  @override
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

  /// Запускает Kotlin foreground service для активного звонка
  /// (либо update если уже running для того же callId). Idempotent
  /// на re-fires `_applyCall(active)` для того же звонка.
  /// No-op на non-Android либо когда service не инжектирован
  /// (некоторые tests).
  /// Гигиена звонков: держим экран включённым пока звонок живой
  /// (ringing/active), отпускаем на любом terminal/teardown-пути.
  /// Идемпотентно — guard на _wakelockActive, потому что _applyCall
  /// re-fire'ится каждые 2s recovery-poll'ом.
  @override
  Future<void> _setWakelockActive(bool active) async {
    if (_wakelockActive == active) {
      return;
    }
    _wakelockActive = active;
    try {
      await _wakelockToggler(active);
    } catch (error) {
      // Best-effort: сбой wakelock не должен ломать звонок.
      debugPrint('[call-wakelock] toggle($active) failed: $error');
    }
  }

  @override
  void _handleAudioRouteChanged() {
    unawaited(_syncProximityWakeLock());
  }

  /// Proximity-политика (Telegram-поведение): гасим экран у уха ТОЛЬКО
  /// в чисто аудио-состоянии — звонок active, медиаканал подключён,
  /// маршрут «ушной», камера не поднята (mediaMode video или локальный
  /// audio→video upgrade выключают датчик). AudioRouteService сам
  /// no-op'ит вне Android-пути, а Kotlin-мост дополнительно отпускает
  /// лок в stop()/teardown() — страховка от пропущенного false.
  @override
  Future<void> _syncProximityWakeLock() async {
    final call = _currentCall;
    final desired = call != null &&
        call.state == CallState.active &&
        _room != null &&
        !call.mediaMode.isVideo &&
        !_cameraEnabled &&
        _audioRouteService.selectedRoute?.type == AudioRouteType.earpiece;
    await _audioRouteService.setProximityEnabled(desired);
  }

  @override
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

  /// Останавливает foreground service. По умолчанию no-op если он не был
  /// запущен этим coordinator instance; cleanup paths pass [force], чтобы
  /// погасить возможный Android service, переживший Dart-state race/restart.
  @override
  Future<void> _stopForegroundService({bool force = false}) async {
    final service = _callForegroundService;
    final callId = _foregroundServiceCallId;
    _foregroundServiceCallId = null;
    if (service == null || !service.isSupported || (!force && callId == null)) {
      return;
    }
    await service.stop();
  }

  /// Update notification text без restart service. Вызывается на
  /// mic toggle reflection (icon в notification отражает on/off).
  /// No-op если service не running.
  @override
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

  /// Public read of the push-payload caller name for a call. The incoming-call
  /// FCM push carries the caller's name (the native notification already shows
  /// it); the in-app call screen uses this so it shows WHO is calling instead
  /// of a bare «Звонок» when getChatDetails is slow / the chat isn't cached.
  /// Empty/absent → null.
  String? pushCallerNameFor(String callId) {
    final name = _pushCallerNames[callId.trim()]?.trim();
    return (name != null && name.isNotEmpty) ? name : null;
  }

  @override
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

  @override
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
  @override
  Future<void> _maybeShowNativeIncomingCall(CallInvite call) async {
    final service = _androidIncomingCallService;
    if (service == null || !service.isSupported) {
      return;
    }
    final currentUser = currentUserId;
    if (currentUser == null || !call.isIncomingFor(currentUser)) {
      return;
    }
    if (_shownNativeIncomingCallIds.contains(call.id)) {
      return;
    }
    _shownNativeIncomingCallIds.add(call.id);
    // Never surface the raw initiatorId (a UUID): the Telecom side turns it
    // into a bogus «phone number» on paired watches (they strip non-digits
    // → «21433289429097»). The VKPNS push carries the real display name and
    // lands before hydrate; without it we fall back to an empty string so
    // the native side shows its neutral «Родня» label, not a user id.
    final pushCallerName = _pushCallerNames[call.id]?.trim();
    final callerName = (pushCallerName != null && pushCallerName.isNotEmpty)
        ? pushCallerName
        : '';
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

  @override
  void _dismissNativeIncomingCall(String callId) {
    final normalizedCallId = callId.trim();
    if (normalizedCallId.isEmpty) {
      return;
    }
    unawaited(_androidIncomingCallService?.dismissCall(normalizedCallId));
    _shownNativeIncomingCallIds.remove(normalizedCallId);
  }

  /// Tears down every shown native incoming-call UI except [keepCallId].
  /// Called when a call is superseded by another, or when the server
  /// reports no active call — orphaned Telecom connections must not linger
  /// (phantom call on paired watch + stuck MODE_RINGTONE). Iterates a copy
  /// because [_dismissNativeIncomingCall] mutates the set.
  @override
  void _dismissStaleNativeIncomingCalls({String? keepCallId}) {
    if (_shownNativeIncomingCallIds.isEmpty) {
      return;
    }
    final stale = _shownNativeIncomingCallIds
        .where((id) => id != keepCallId)
        .toList(growable: false);
    for (final id in stale) {
      _dismissNativeIncomingCall(id);
      _pushCallerNames.remove(id);
    }
  }
}
