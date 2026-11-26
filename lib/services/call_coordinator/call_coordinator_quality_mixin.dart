part of '../call_coordinator_service.dart';

mixin _CallCoordinatorQualityMixin on _CallCoordinatorBase {
  @override
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

  @override
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

  @override
  void _clearInputDeviceState() {
    _microphoneDevices = const <MediaDevice>[];
    _cameraDevices = const <MediaDevice>[];
    _selectedMicrophoneDeviceId = null;
    _selectedCameraDeviceId = null;
    _isRefreshingInputDevices = false;
    _isSelectingMediaDevice = false;
    _devicePickerErrorMessage = null;
  }

  // Worst (lowest-quality) link across remotes, ignoring `unknown` (no data
  // yet). `ConnectionQuality` is declared worst→best (lost < poor < good <
  // excellent), so the smallest non-unknown `.index` wins. Group calls must
  // surface the peer most at risk, not whichever participant was iterated
  // first. Returns `unknown` only when no remote has reported quality yet.
  @override
  ConnectionQuality _worstRemoteQuality(Iterable<ConnectionQuality> qualities) {
    var worst = ConnectionQuality.unknown;
    for (final quality in qualities) {
      if (quality == ConnectionQuality.unknown) {
        continue;
      }
      if (worst == ConnectionQuality.unknown || quality.index < worst.index) {
        worst = quality;
      }
    }
    return worst;
  }

  @override
  void _syncConnectionQualityFromRoom(Room room) {
    _localConnectionQuality =
        room.localParticipant?.connectionQuality ?? ConnectionQuality.unknown;
    // Aggregate the WORST remote link so the group-call badge reflects the
    // peer most at risk rather than whichever participant iterated first.
    _remoteConnectionQuality = _worstRemoteQuality(
      room.remoteParticipants.values.map((p) => p.connectionQuality),
    );
  }

  @override
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
    // A remote's quality changed — recompute the worst across ALL remotes
    // (using this fresh value for the updated peer, since the room snapshot may
    // still lag the event) so one good link can't mask another's degraded one
    // in a group call.
    if (room == null) {
      _remoteConnectionQuality = quality;
      return;
    }
    final qualities = <ConnectionQuality>[quality];
    for (final other in room.remoteParticipants.values) {
      if (other.identity != participant.identity) {
        qualities.add(other.connectionQuality);
      }
    }
    _remoteConnectionQuality = _worstRemoteQuality(qualities);
  }

  @override
  void _showReconnectRestoredBannerForMoment() {
    _reconnectRestoredTimer?.cancel();
    _showReconnectRestoredBanner = true;
    _reconnectRestoredTimer = Timer(const Duration(seconds: 3), () {
      _showReconnectRestoredBanner = false;
      notifyListeners();
    });
  }

  @override
  void _clearReconnectRestoredBanner() {
    _reconnectRestoredTimer?.cancel();
    _reconnectRestoredTimer = null;
    _showReconnectRestoredBanner = false;
  }

  // P2: while «Переподключение» is shown, guarantee it can never wedge on
  // forever. If after the timeout the LiveKit transport is actually live
  // (the peer is audible), force-clear the overlay — the old code waited
  // for a RoomReconnectedEvent that, on a disposed or internally-recovered
  // room, may never arrive.
  @override
  void _armReconnectWatchdog() {
    _reconnectWatchdogTimer?.cancel();
    _reconnectWatchdogTimer = Timer(const Duration(seconds: 12), () {
      _reconnectWatchdogTimer = null;
      if (!_isReconnectingRoom) {
        return;
      }
      final room = _room;
      final live =
          room != null && room.connectionState == ConnectionState.connected;
      if (live) {
        // Room is actually back but RoomReconnectedEvent never cleared the
        // overlay — force-clear it (the original 0b254b7 deadlock backstop).
        _isReconnectingRoom = false;
        _connectionError = null;
        _showReconnectRestoredBannerForMoment();
        _syncConnectionQualityFromRoom(room);
        notifyListeners();
        return;
      }
      // Residual gap (was: no else branch → «Переподключение» wedged forever
      // with the timer nulled and nothing re-arming it). Still reconnecting and
      // NOT live at the deadline. Never lie that we reconnected; instead tie the
      // overlay to the call's real lifetime: drop it if the call is gone or
      // terminal, otherwise re-arm a self-perpetuating re-check so the moment
      // the room comes back (or the call ends) the overlay resolves on the next
      // tick instead of spinning indefinitely.
      final activeCall = _currentCall;
      if (activeCall == null || activeCall.state != CallState.active) {
        _isReconnectingRoom = false;
        notifyListeners();
        return;
      }
      _armReconnectWatchdog();
    });
  }

  @override
  void _cancelReconnectWatchdog() {
    _reconnectWatchdogTimer?.cancel();
    _reconnectWatchdogTimer = null;
  }

  @override
  void _clearConnectionQualityState() {
    _localConnectionQuality = ConnectionQuality.unknown;
    _remoteConnectionQuality = ConnectionQuality.unknown;
    _clearReconnectRestoredBanner();
  }

  @override
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
      // Камера поднимается заново если была включена ДО реконнекта —
      // это покрывает и видео-звонок, и audio→video upgrade (раньше
      // гейт `mediaMode.isVideo` терял камеру апгрейднутого аудио-
      // звонка). Была выключена — не трогаем: не включаем камеру
      // за спиной пользователя.
      if (_cameraEnabled) {
        _cameraPublishFailed = !(await _publishLocalCamera(room));
        _cameraEnabled = !_cameraPublishFailed;
      }
    } catch (_) {
      // LiveKit will continue reconnecting if media resume is not ready yet.
    }
    // CA1+: on reconnect LiveKit re-runs its connect-time audio config
    // (setAndroidAudioConfiguration(communication) = manageAudioFocus:true),
    // re-grabbing the route from the native bridge even when no track
    // (re)publish event fires. Re-assert so the speaker toggle and hardware
    // volume keep working after «Переподключение» clears.
    await _audioRouteService.reassertNativeAudioOwnership();
  }
}
