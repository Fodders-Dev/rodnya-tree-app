part of '../call_coordinator_service.dart';

mixin _CallCoordinatorLiveKitMixin on _CallCoordinatorBase {
  @override
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
    if (nextValue) {
      // Enable-путь зеркалит микрофон (Q1): проверяем что публикация
      // реально состоялась, иначе иконка врала бы «камера включена»
      // при молчаливом фейле (Samsung S20 FE, 2026-07-04: нативный
      // addTransceiver отверг simulcast-энкодинги — камера открылась
      // на HAL, но в комнату не публиковалась, без единой ошибки в UI).
      final published = await _publishLocalCamera(room);
      _cameraPublishFailed = !published;
      _cameraEnabled = published;
    } else {
      try {
        await room.localParticipant?.setCameraEnabled(
          false,
          cameraCaptureOptions: _cameraCaptureOptionsFor(room),
        );
      } catch (error) {
        debugPrint('[call] toggle camera off threw: $error');
      }
      // Выключение не может «навредить» юзеру — состояние honest-off,
      // flag чистим чтобы следующий enable retry'нулся свежим.
      _cameraEnabled = false;
      _cameraPublishFailed = false;
    }
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

  bool _isConnectStillValid(int gen, String callId) {
    return !_disposed &&
        gen == _connectGeneration &&
        _currentCall?.id == callId &&
        _currentCall?.state == CallState.active;
  }

  Future<void> _disposeOrphanedAttemptRoom(
    Room room,
    EventsListener<RoomEvent> listener,
  ) async {
    try {
      if (identical(_roomListener, listener)) {
        _roomListener = null;
      }
      await listener.dispose();
    } catch (_) {}
    try {
      if (identical(_room, room)) {
        _room = null;
        _connectedRoomName = null;
      }
      await room.disconnect();
      await room.dispose();
    } catch (_) {}
  }

  @override
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
    // P2: gate only on an ACTUAL in-flight connect — NOT on the
    // _isReconnectingRoom display flag, which _handleRoomDisconnected
    // sets before triggering this very reconnect (the old deadlock).
    if (_connectAttemptInFlight) {
      return;
    }

    _connectAttemptInFlight = true;
    final myGen = ++_connectGeneration;
    if (reconnect) {
      _isReconnectingRoom = true;
      _armReconnectWatchdog();
    } else {
      _isConnectingRoom = true;
    }
    _connectionError = null;
    _hasMediaPermissionIssue = false;
    _microphonePublishFailed = false;
    _cameraPublishFailed = false;
    notifyListeners();

    final hasMediaPermissions =
        await _mediaPermissionRequester.call(call.mediaMode);
    if (!_isConnectStillValid(myGen, call.id)) {
      _isConnectingRoom = false;
      _isReconnectingRoom = false;
      _connectAttemptInFlight = false;
      _cancelReconnectWatchdog();
      if (!_disposed) notifyListeners();
      return;
    }
    if (!hasMediaPermissions) {
      _hasMediaPermissionIssue = true;
      // UX-аудит P1: для аудио-звонка камера не запрашивается вовсе —
      // говорим конкретно про микрофон, а не пугаем «или камере».
      _connectionError = call.mediaMode.isVideo
          ? 'Нет доступа к микрофону или камере. Разрешите доступ в настройках приложения.'
          : 'Нет доступа к микрофону. Разрешите доступ в настройках приложения.';
      _isConnectingRoom = false;
      _isReconnectingRoom = false;
      _connectAttemptInFlight = false;
      _cancelReconnectWatchdog();
      notifyListeners();
      return;
    }

    await _disposeRoom(bumpGeneration: false);
    if (!_isConnectStillValid(myGen, call.id)) {
      _isConnectingRoom = false;
      _isReconnectingRoom = false;
      _connectAttemptInFlight = false;
      _cancelReconnectWatchdog();
      if (!_disposed) notifyListeners();
      return;
    }

    final room = Room(roomOptions: _callRoomOptions);
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
        _armReconnectWatchdog();
        notifyListeners();
      })
      ..on<RoomReconnectedEvent>((_) {
        debugPrint(
          '[call] room reconnected uptime=${_uptimeSinceConnect()}ms',
        );
        _isReconnectingRoom = false;
        _connectionError = null;
        _cancelReconnectWatchdog();
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
      ..on<TrackSubscribedEvent>((_) {
        // A REMOTE track (esp. the peer's audio) just subscribed. LiveKit
        // reconfigures Android audio on subscribe and re-grabs the route from
        // the native bridge — which silently kills the «Динамик» toggle and
        // drops hardware volume off the call stream the instant the other
        // person's audio connects. This was the uncovered re-grab point that
        // made the speaker fix flaky («раз работает, раз нет»). Re-assert.
        unawaited(_audioRouteService.reassertNativeAudioOwnership());
      })
      ..on<TrackUnsubscribedEvent>((_) {
        unawaited(_audioRouteService.reassertNativeAudioOwnership());
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
      await room.connect(
        session.url,
        session.token,
        connectOptions: _callConnectOptions,
      );
      if (!_isConnectStillValid(myGen, call.id)) {
        await _disposeOrphanedAttemptRoom(room, listener);
        return;
      }
      debugPrint(
        '[call] room.connect ok uptime=${_uptimeSinceConnect()}ms',
      );
      _microphoneEnabled = true;
      // Publish mic separately от room.connect — на Android 14+ без
      // FOREGROUND_SERVICE_MICROPHONE permission setMicrophoneEnabled
      // может silently fail (publication == null) даже когда room
      // успешно connected. Этот fix surface'ит failure через
      // `microphonePublishFailed` flag вместо silently lying в UI.
      final micPublished = await _publishLocalMicrophone(room);
      if (!_isConnectStillValid(myGen, call.id)) {
        await _disposeOrphanedAttemptRoom(room, listener);
        return;
      }
      _microphonePublishFailed = !micPublished;
      // Камеру для видео-звонка публикуем БЕЗУСЛОВНО по mediaMode, а
      // `_cameraEnabled` выставляем из РЕЗУЛЬТАТА. Раньше здесь было
      // «_cameraEnabled = isVideo (до mic-await) … setCameraEnabled(
      // _cameraEnabled)» — гонка: пока ждали publish микрофона, его
      // LocalTrackPublishedEvent триггерил _syncMediaStateFromLiveKit,
      // тот читал «камера ещё не опубликована» и затирал intent-флаг в
      // false → setCameraEnabled(false) → тихий no-op, видео-звонок
      // поднимался без видео (S20 FE, 2026-07-04). Failure камеры
      // больше не роняет весь connect (звук живёт, юзеру — Q1-баннер).
      if (call.mediaMode.isVideo) {
        final published = await _publishLocalCamera(room);
        if (!_isConnectStillValid(myGen, call.id)) {
          await _disposeOrphanedAttemptRoom(room, listener);
          return;
        }
        _cameraPublishFailed = !published;
        _cameraEnabled = published;
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
      if (!_isConnectStillValid(myGen, call.id)) {
        await _disposeOrphanedAttemptRoom(room, listener);
        return;
      }
      await refreshInputDevices();
      if (!_isConnectStillValid(myGen, call.id)) {
        await _disposeOrphanedAttemptRoom(room, listener);
        return;
      }
      await _applyCallPreferences(room, call);
      if (!_isConnectStillValid(myGen, call.id)) {
        await _disposeOrphanedAttemptRoom(room, listener);
        return;
      }
    } catch (error) {
      await _disposeOrphanedAttemptRoom(room, listener);
      if (_disposed) {
        return;
      }
      _hasMediaPermissionIssue = _looksLikeMediaPermissionIssue(error);
      // Mode-aware и здесь (ревью батча): аудио-звонок не должен пугать
      // «или камере» и на connect-catch пути, не только на pre-flight.
      _connectionError = _hasMediaPermissionIssue
          ? (call.mediaMode.isVideo
              ? 'Нет доступа к микрофону или камере. Разрешите доступ в настройках приложения.'
              : 'Нет доступа к микрофону. Разрешите доступ в настройках приложения.')
          : 'Не удалось подключиться к звонку.';
      // Connection-level failure уже surface'ится через connectionError —
      // mic-specific signal на этом этапе redundant. Clear чтобы не
      // surface'ить stale mic banner поверх banner'а connection failure.
      _microphonePublishFailed = false;
      _cameraPublishFailed = false;
    } finally {
      _isConnectingRoom = false;
      _isReconnectingRoom = false;
      _connectAttemptInFlight = false;
      // The attempt is over: success cleared _connectionError (and set
      // _room); failure set a real error. Either way the watchdog's job
      // is done — a stuck overlay can't outlive a finished attempt.
      _cancelReconnectWatchdog();
      if (!_disposed) {
        notifyListeners();
      }
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
    _armReconnectWatchdog();
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
    // Симметрично для камеры: publication реально поднялась — stale
    // «камера не подключилась» баннер должен уйти.
    if (camActual && _cameraPublishFailed) {
      _cameraPublishFailed = false;
      changed = true;
    }
    if (changed) {
      notifyListeners();
      unawaited(_updateForegroundService());
    }
    // CA1+: a local track (un)publish just settled (this runs from the
    // LocalTrackPublished/Unpublished + mute listeners) — LiveKit re-grabs the
    // Android audio focus/route on publish, so re-assert the native bridge's
    // ownership now, or «Динамик» and hardware volume silently stop working
    // after a mic/camera toggle. No-op off-Android and after the call ends.
    unawaited(_audioRouteService.reassertNativeAudioOwnership());
    // Камера могла подняться/опуститься (audio→video upgrade) —
    // proximity-политика зависит от неё.
    unawaited(_syncProximityWakeLock());
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
  @override
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

  /// Публикует локальную камеру. true при успехе, false при failure
  /// (на failure `_cameraEnabled = false` для truthful UI state) —
  /// зеркало [_publishLocalMicrophone].
  ///
  /// Первую публикацию делаем вручную (createCameraTrack +
  /// publishVideoTrack) вместо `setCameraEnabled(true)`: в
  /// livekit_client 2.7.0 setCameraEnabled при падении publish бросает,
  /// а созданный им трек НЕ останавливает — камера остаётся захваченной
  /// на уровне HAL до перезапуска приложения (наблюдали 6+ минут live
  /// capture после единственного тапа; конкурирующие приложения
  /// получали «Too many cameras already open»). Владея треком сами,
  /// глушим его в catch. Повторное включение после mute идёт через
  /// setCameraEnabled — там unmute существующей publication, трек не
  /// создаётся и утечка невозможна.
  @override
  Future<bool> _publishLocalCamera(Room room) async {
    final participant = room.localParticipant;
    if (participant == null) {
      _cameraEnabled = false;
      return false;
    }
    try {
      final existing =
          participant.getTrackPublicationBySource(TrackSource.camera);
      if (existing != null) {
        final publication = await participant.setCameraEnabled(
          true,
          cameraCaptureOptions: _cameraCaptureOptionsFor(room),
        );
        return publication != null;
      }
      final track = await LocalVideoTrack.createCameraTrack(
        _cameraCaptureOptionsFor(room),
      );
      try {
        await participant.publishVideoTrack(
          track,
          publishOptions: _sanitizedVideoPublishOptions(room),
        );
        return true;
      } catch (_) {
        await track.stop();
        await track.dispose();
        rethrow;
      }
    } catch (error, stack) {
      _cameraEnabled = false;
      debugPrint('[call] camera publish threw: $error\n$stack');
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

  CameraCaptureOptions _cameraCaptureOptionsFor(Room room) {
    return room.roomOptions.defaultCameraCaptureOptions.copyWith(
      cameraPosition: _cameraPosition,
    );
  }

  @override
  Future<void> _disposeRoom({bool bumpGeneration = true}) async {
    if (bumpGeneration) {
      _connectGeneration++;
    }
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
}
