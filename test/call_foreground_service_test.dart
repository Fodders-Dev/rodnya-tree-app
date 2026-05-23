import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/services/call_foreground_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('rodnya.calls/foreground');
  final binding = TestDefaultBinaryMessengerBinding.instance;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('CallForegroundService.start forwards args к platform channel',
      () async {
    final calls = <MethodCall>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return true;
    });

    final service = CallForegroundService(channel: channel);
    final result = await service.start(
      callId: ' call-1 ',
      peerName: ' Бабушка ',
      isVideo: true,
      micEnabled: true,
    );

    expect(result, isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'startCallService');
    expect(calls.single.arguments, <String, Object?>{
      'callId': 'call-1',
      'peerName': 'Бабушка',
      'isVideo': true,
      'micEnabled': true,
    });
  });

  test('CallForegroundService.update forwards args к platform channel',
      () async {
    final calls = <MethodCall>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return true;
    });

    final service = CallForegroundService(channel: channel);
    final result = await service.update(
      callId: 'call-1',
      peerName: 'Дедушка',
      isVideo: false,
      micEnabled: false,
    );

    expect(result, isTrue);
    expect(calls.single.method, 'updateCallService');
    expect(calls.single.arguments, <String, Object?>{
      'callId': 'call-1',
      'peerName': 'Дедушка',
      'isVideo': false,
      'micEnabled': false,
    });
  });

  test('CallForegroundService.stop invokes stopCallService', () async {
    final calls = <MethodCall>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return true;
    });

    final service = CallForegroundService(channel: channel);
    final result = await service.stop();

    expect(result, isTrue);
    expect(calls.single.method, 'stopCallService');
  });

  test(
      'CallForegroundService.consumePendingNotificationAction parses payload',
      () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      expect(call.method, 'consumePendingNotificationAction');
      return <String, Object?>{
        'action': 'toggle_mic',
        'callId': 'call-1',
      };
    });

    final service = CallForegroundService(channel: channel);
    final action = await service.consumePendingNotificationAction();

    expect(action, isNotNull);
    expect(action!.isToggleMic, isTrue);
    expect(action.isEndCall, isFalse);
    expect(action.callId, 'call-1');
  });

  test(
      'CallForegroundService.consumePendingNotificationAction returns null on '
      'empty payload', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async => null);

    final service = CallForegroundService(channel: channel);
    final action = await service.consumePendingNotificationAction();

    expect(action, isNull);
  });

  test('CallForegroundService is a no-op off Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var invoked = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      invoked = true;
      return true;
    });

    final service = CallForegroundService(channel: channel);
    final startResult = await service.start(
      callId: 'call-1',
      peerName: 'X',
      isVideo: false,
      micEnabled: true,
    );
    final stopResult = await service.stop();
    final action = await service.consumePendingNotificationAction();

    expect(startResult, isFalse);
    expect(stopResult, isFalse);
    expect(action, isNull);
    expect(invoked, isFalse);
  });

  test('CallForegroundService.start no-op for empty callId', () async {
    var invoked = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      invoked = true;
      return true;
    });

    final service = CallForegroundService(channel: channel);
    final result = await service.start(
      callId: '   ',
      peerName: null,
      isVideo: false,
      micEnabled: true,
    );

    expect(result, isFalse);
    expect(invoked, isFalse);
  });

  test(
      'CallForegroundService swallows MissingPluginException и returns false',
      () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      throw MissingPluginException('not registered');
    });

    final service = CallForegroundService(channel: channel);
    final result = await service.stop();

    expect(result, isFalse);
  });
}
