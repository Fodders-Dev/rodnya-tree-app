import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
// hide ConnectionState: Flutter's async ConnectionState collides with
// LiveKit's room ConnectionState; this file only needs LiveKit's.
import 'package:flutter/widgets.dart' hide ConnectionState;
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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

part 'call_coordinator/call_coordinator_base.dart';
part 'call_coordinator/call_coordinator_signaling_mixin.dart';
part 'call_coordinator/call_coordinator_livekit_mixin.dart';
part 'call_coordinator/call_coordinator_quality_mixin.dart';
part 'call_coordinator/call_coordinator_device_mixin.dart';

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
// Гигиена звонков (2026-07-04): держатель экрана на время живого звонка.
// Seam — тесты инжектят рекордер вместо реального WakelockPlus (platform
// channel в flutter_test кидает MissingPluginException).
typedef CallWakelockToggler = Future<void> Function(bool enable);

const AudioEncoding _callAudioEncoding = AudioEncoding(
  maxBitrate: 32000,
  bitratePriority: Priority.high,
);

// ВАЖНО: без bitratePriority. LiveKit подставляет его только в верхний
// simulcast-слой, авто-слои q/h остаются с дефолтным low, а нативный
// WebRTC требует одинаковый bitrate_priority у всех encodings — иначе
// addTransceiver падает целиком («C++ addTransceiver failed», камера
// не публикуется вовсе). Санитайзер в _publishLocalCamera страхует
// это инвариантом на случай будущих правок профиля.
const VideoEncoding _callVideoEncoding = VideoEncoding(
  maxFramerate: 30,
  maxBitrate: 2000 * 1000,
);

const RoomOptions _callRoomOptions = RoomOptions(
  defaultCameraCaptureOptions: CameraCaptureOptions(
    params: VideoParametersPresets.h720_169,
    maxFrameRate: 30,
  ),
  defaultAudioCaptureOptions: AudioCaptureOptions(
    noiseSuppression: true,
    echoCancellation: true,
    autoGainControl: true,
    highPassFilter: true,
    voiceIsolation: true,
    typingNoiseDetection: true,
  ),
  defaultAudioPublishOptions: AudioPublishOptions(
    encoding: _callAudioEncoding,
    dtx: true,
    red: true,
  ),
  defaultVideoPublishOptions: VideoPublishOptions(
    videoEncoding: _callVideoEncoding,
    simulcast: true,
    degradationPreference: DegradationPreference.balanced,
    backupVideoCodec: BackupVideoCodec(enabled: false),
  ),
  adaptiveStream: true,
  dynacast: true,
);

const ConnectOptions _callConnectOptions = ConnectOptions(
  rtcConfiguration: RTCConfiguration(isDscpEnabled: true),
);

Future<void> _defaultWakelockToggler(bool enable) {
  return WakelockPlus.toggle(enable: enable);
}

Future<void> _switchLiveKitCameraPosition(
  LocalVideoTrack track,
  CameraPosition position,
) {
  return track.setCameraPosition(position);
}

Future<List<MediaDevice>> _defaultAudioInputEnumerator() {
  return Hardware.instance.audioInputs();
}

Future<List<MediaDevice>> _defaultVideoInputEnumerator() {
  return Hardware.instance.videoInputs();
}

Future<void> _selectLiveKitMicrophoneDevice(
  Room room,
  MediaDevice device,
) {
  return room.setAudioInputDevice(device);
}

Future<void> _selectLiveKitCameraDevice(
  Room room,
  MediaDevice device,
) {
  return room.setVideoInputDevice(device);
}

Future<void> _defaultVibrationTrigger() {
  return HapticFeedback.mediumImpact();
}

Future<bool> _requestPlatformMediaPermissions(
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
Future<void> _requestBluetoothConnectPermissionIfNeeded() async {
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

class CallCoordinatorService extends _CallCoordinatorBase
    with
        _CallCoordinatorDeviceMixin,
        _CallCoordinatorQualityMixin,
        _CallCoordinatorLiveKitMixin,
        _CallCoordinatorSignalingMixin {
  CallCoordinatorService({
    required super.callService,
    super.realtimeService,
    super.pushMessages,
    super.mediaPermissionRequester,
    super.audioRouteService,
    super.cameraPositionSwitcher,
    super.audioInputEnumerator,
    super.videoInputEnumerator,
    super.microphoneDeviceSelector,
    super.cameraDeviceSelector,
    super.callPreferences,
    super.androidIncomingCallService,
    super.callForegroundService,
    super.vibrationTrigger,
    super.wakelockToggler,
    super.ringingRecoveryInterval,
    super.activeCallRecoveryInterval,
  });

  Future<void> reset() async {
    _connectGeneration++;
    final activeCall = _currentCall;
    if (activeCall != null) {
      _pushCallerNames.remove(activeCall.id);
      _locallyStartedCallIds.remove(activeCall.id);
    }
    _dismissStaleNativeIncomingCalls();
    _cancelRingingRecovery();
    _cancelActiveCallRecovery();
    _currentCall = null;
    _connectionError = null;
    _isConnectingRoom = false;
    _isReconnectingRoom = false;
    _microphoneEnabled = true;
    _microphonePublishFailed = false;
    _cameraPublishFailed = false;
    _cameraEnabled = false;
    _isSwitchingCamera = false;
    _cameraPosition = CameraPosition.front;
    _clearInputDeviceState();
    _clearConnectionQualityState();
    _hasMediaPermissionIssue = false;
    _hasSeenRemoteParticipant = false;
    _joinedOnAnotherDevice = false;
    _lastIncomingVibrationCallId = null;
    _activeSince = null;
    _locallyStartedCallIds.clear();
    await _setWakelockActive(false);
    await _stopForegroundService(force: true);
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
    _disposed = true;
    _connectGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _dismissStaleNativeIncomingCalls();
    _cancelRingingRecovery();
    _cancelActiveCallRecovery();
    _clearReconnectRestoredBanner();
    _cancelReconnectWatchdog();
    _audioRouteService.removeListener(_handleAudioRouteChanged);
    unawaited(_callEventsSubscription?.cancel());
    unawaited(_realtimeSubscription?.cancel());
    unawaited(_pushSubscription?.cancel());
    unawaited(_setWakelockActive(false));
    unawaited(_audioRouteService.setProximityEnabled(false));
    unawaited(_stopForegroundService(force: true));
    unawaited(_disposeRoom());
    super.dispose();
  }

  /// Test seam — exposes call media defaults without a real LiveKit Room.
  @visibleForTesting
  static RoomOptions get debugCallRoomOptions => _callRoomOptions;

  @visibleForTesting
  static ConnectOptions get debugCallConnectOptions => _callConnectOptions;

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

  /// Test seam — камерное зеркало [debugMarkMicrophonePublishFailed]:
  /// flip'ает `cameraPublishFailed` без настоящей LiveKit Room для
  /// unit-проверки getter + notifier boundary. Production-кода это
  /// никогда не вызывает.
  @visibleForTesting
  void debugMarkCameraPublishFailed(bool failed) {
    if (_cameraPublishFailed == failed) {
      return;
    }
    _cameraPublishFailed = failed;
    if (failed) {
      _cameraEnabled = false;
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
    if (camEnabled && _cameraPublishFailed) {
      _cameraPublishFailed = false;
      changed = true;
    }
    if (changed) {
      notifyListeners();
      unawaited(_updateForegroundService());
    }
  }
}
