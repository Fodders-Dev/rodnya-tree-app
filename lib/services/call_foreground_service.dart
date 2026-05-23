import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Notification action payload вернённый из Android-side
/// `consumePendingNotificationAction`. Mirror Kotlin
/// `RodnyaCallForegroundService.NOTIFICATION_ACTION_*` constants.
class CallForegroundNotificationAction {
  const CallForegroundNotificationAction({
    required this.action,
    required this.callId,
  });

  final String action;
  final String callId;

  bool get isToggleMic => action == 'toggle_mic';
  bool get isEndCall => action == 'end_call';

  static CallForegroundNotificationAction? fromMap(Object? value) {
    if (value is! Map) {
      return null;
    }
    final action = value['action']?.toString().trim() ?? '';
    final callId = value['callId']?.toString().trim() ?? '';
    if (action.isEmpty || callId.isEmpty) {
      return null;
    }
    return CallForegroundNotificationAction(action: action, callId: callId);
  }
}

/// Dart client для `rodnya.calls/foreground` MethodChannel.
///
/// Lifecycle:
/// - [start] вызывается когда call transitions в active state.
///   Запускает Kotlin `RodnyaCallForegroundService` с persistent
///   notification — это держит mic capture alive на Android 14+.
/// - [update] вызывается на mic toggle / peer name resolved /
///   media mode flipped, чтобы notification reflected latest state.
/// - [stop] вызывается на terminal/disconnect.
/// - [consumePendingNotificationAction] polled из app resume / lifecycle
///   hook — возвращает pending mute/end action from notification button.
///
/// На non-Android платформах все методы no-op.
class CallForegroundService {
  CallForegroundService({
    MethodChannel channel =
        const MethodChannel('rodnya.calls/foreground'),
  }) : _channel = channel;

  final MethodChannel _channel;

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> start({
    required String callId,
    String? peerName,
    required bool isVideo,
    required bool micEnabled,
  }) {
    if (!isSupported || callId.trim().isEmpty) {
      return Future.value(false);
    }
    return _invokeBool('startCallService', <String, Object?>{
      'callId': callId.trim(),
      'peerName': peerName?.trim(),
      'isVideo': isVideo,
      'micEnabled': micEnabled,
    });
  }

  Future<bool> update({
    required String callId,
    String? peerName,
    required bool isVideo,
    required bool micEnabled,
  }) {
    if (!isSupported || callId.trim().isEmpty) {
      return Future.value(false);
    }
    return _invokeBool('updateCallService', <String, Object?>{
      'callId': callId.trim(),
      'peerName': peerName?.trim(),
      'isVideo': isVideo,
      'micEnabled': micEnabled,
    });
  }

  Future<bool> stop() {
    if (!isSupported) {
      return Future.value(false);
    }
    return _invokeBool('stopCallService');
  }

  Future<CallForegroundNotificationAction?>
      consumePendingNotificationAction() async {
    if (!isSupported) {
      return null;
    }
    try {
      final value = await _channel
          .invokeMethod<Object?>('consumePendingNotificationAction');
      return CallForegroundNotificationAction.fromMap(value);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<bool> _invokeBool(
    String method, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) async {
    try {
      final result = await _channel.invokeMethod<Object?>(method, arguments);
      return result == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
