import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidCallAction {
  const AndroidCallAction({
    required this.action,
    required this.callId,
    this.chatId,
  });

  final String action;
  final String callId;
  final String? chatId;

  bool get isAccept => action == 'accept';
  bool get isReject => action == 'reject';
  bool get isDisconnect => action == 'disconnect';

  static AndroidCallAction? fromMap(Object? value) {
    if (value is! Map) {
      return null;
    }
    final action = value['action']?.toString().trim() ?? '';
    final callId = value['callId']?.toString().trim() ?? '';
    final chatId = value['chatId']?.toString().trim();
    if (action.isEmpty || callId.isEmpty) {
      return null;
    }
    return AndroidCallAction(
      action: action,
      callId: callId,
      chatId: chatId == null || chatId.isEmpty ? null : chatId,
    );
  }
}

class AndroidIncomingCallService {
  const AndroidIncomingCallService({
    MethodChannel channel = const MethodChannel('rodnya/android_calls'),
  }) : _channel = channel;

  final MethodChannel _channel;

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> registerPhoneAccount() async {
    if (!isSupported) {
      return false;
    }
    return _invokeBool('registerPhoneAccount');
  }

  Future<bool> showIncomingCall({
    required String callId,
    required String callerName,
    required bool isVideo,
    String? chatId,
  }) async {
    if (!isSupported || callId.trim().isEmpty) {
      return false;
    }
    return _invokeBool(
      'showIncomingCall',
      <String, Object?>{
        'callId': callId.trim(),
        'callerName': callerName.trim(),
        'isVideo': isVideo,
        'chatId': chatId?.trim(),
      },
    );
  }

  Future<bool> dismissCall(String callId) async {
    if (!isSupported || callId.trim().isEmpty) {
      return false;
    }
    return _invokeBool(
      'dismissCall',
      <String, Object?>{
        'callId': callId.trim(),
      },
    );
  }

  Future<AndroidCallAction?> consumePendingAction() async {
    if (!isSupported) {
      return null;
    }
    try {
      final value = await _channel.invokeMethod<Object?>(
        'consumePendingAction',
      );
      return AndroidCallAction.fromMap(value);
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
