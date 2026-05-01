import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/services/android_incoming_call_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('rodnya/android_calls');
  final binding = TestDefaultBinaryMessengerBinding.instance;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('AndroidIncomingCallService forwards incoming call to platform channel',
      () async {
    final calls = <MethodCall>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return true;
    });

    const service = AndroidIncomingCallService(channel: channel);
    final result = await service.showIncomingCall(
      callId: ' call-1 ',
      callerName: ' Семья ',
      isVideo: true,
      chatId: ' chat-1 ',
    );

    expect(result, isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'showIncomingCall');
    expect(calls.single.arguments, <String, Object?>{
      'callId': 'call-1',
      'callerName': 'Семья',
      'isVideo': true,
      'chatId': 'chat-1',
    });
  });

  test('AndroidIncomingCallService consumes pending telecom action', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      expect(call.method, 'consumePendingAction');
      return <String, Object?>{
        'action': 'accept',
        'callId': 'call-1',
        'chatId': 'chat-1',
      };
    });

    const service = AndroidIncomingCallService(channel: channel);
    final action = await service.consumePendingAction();

    expect(action?.isAccept, isTrue);
    expect(action?.callId, 'call-1');
    expect(action?.chatId, 'chat-1');
  });

  test('AndroidIncomingCallService is a no-op off Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var invoked = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      invoked = true;
      return true;
    });

    const service = AndroidIncomingCallService(channel: channel);
    final result = await service.registerPhoneAccount();

    expect(result, isFalse);
    expect(invoked, isFalse);
  });
}
