import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rodnya/backend/backend_runtime_config.dart';
import 'package:rodnya/services/custom_api_auth_service.dart';
import 'package:rodnya/services/custom_api_realtime_service.dart';
import 'package:rodnya/services/invitation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('computes capped exponential reconnect backoff', () async {
    final authService = await _createAuthService();
    final realtimeService = CustomApiRealtimeService(
      authService: authService,
      runtimeConfig: const BackendRuntimeConfig(
        webSocketBaseUrl: 'wss://api.example.ru',
      ),
      reconnectJitterFactor: () => 1,
    );

    expect(
      realtimeService.debugBackoffDelayForFailureCount(1),
      const Duration(seconds: 1),
    );
    expect(
      realtimeService.debugBackoffDelayForFailureCount(2),
      const Duration(seconds: 2),
    );
    expect(
      realtimeService.debugBackoffDelayForFailureCount(3),
      const Duration(seconds: 4),
    );
    expect(
      realtimeService.debugBackoffDelayForFailureCount(4),
      const Duration(seconds: 8),
    );
    expect(
      realtimeService.debugBackoffDelayForFailureCount(5),
      const Duration(seconds: 16),
    );
    expect(
      realtimeService.debugBackoffDelayForFailureCount(6),
      const Duration(seconds: 30),
    );
    expect(
      realtimeService.debugBackoffDelayForFailureCount(7),
      const Duration(seconds: 30),
    );

    await realtimeService.dispose();
  });

  test('retries failed websocket connections with growing delay', () async {
    final authService = await _createAuthService();

    var attempts = 0;
    late StreamController<dynamic> activeController;
    final controllers = <StreamController<dynamic>>[];
    final scheduledDelays = <Duration>[];
    final scheduledCallbacks = <void Function()>[];

    final realtimeService = CustomApiRealtimeService(
      authService: authService,
      runtimeConfig: const BackendRuntimeConfig(
        webSocketBaseUrl: 'wss://api.example.ru',
      ),
      reconnectDelay: const Duration(milliseconds: 10),
      reconnectJitterFactor: () => 1,
      reconnectTimerFactory: (delay, callback) {
        scheduledDelays.add(delay);
        scheduledCallbacks.add(callback);
        return _FakeTimer();
      },
      channelFactory: (_) {
        attempts += 1;
        if (attempts <= 3) {
          return _FailingReadyWebSocketChannel();
        }

        activeController = StreamController<dynamic>.broadcast();
        controllers.add(activeController);
        return _FakeWebSocketChannel(activeController.stream);
      },
    );

    await realtimeService.connect();
    expect(attempts, 1);
    expect(scheduledDelays, [const Duration(milliseconds: 10)]);

    scheduledCallbacks.removeAt(0).call();
    await _flushAsyncWork();
    expect(attempts, 2);
    expect(
      scheduledDelays,
      [
        const Duration(milliseconds: 10),
        const Duration(milliseconds: 20),
      ],
    );

    scheduledCallbacks.removeAt(0).call();
    await _flushAsyncWork();
    expect(attempts, 3);
    expect(
      scheduledDelays,
      [
        const Duration(milliseconds: 10),
        const Duration(milliseconds: 20),
        const Duration(milliseconds: 40),
      ],
    );

    scheduledCallbacks.removeAt(0).call();
    await _flushAsyncWork();
    expect(attempts, 4);

    await activeController.close();
    await _flushAsyncWork();
    expect(
      scheduledDelays,
      [
        const Duration(milliseconds: 10),
        const Duration(milliseconds: 20),
        const Duration(milliseconds: 40),
        const Duration(milliseconds: 10),
      ],
    );

    scheduledCallbacks.removeAt(0).call();
    await _flushAsyncWork();
    expect(attempts, 5);

    await realtimeService.dispose();
    for (final controller in controllers) {
      if (!controller.isClosed) {
        await controller.close();
      }
    }
  });
}

Future<void> _flushAsyncWork() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Future<CustomApiAuthService> _createAuthService() async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.setString(
    'custom_api_session_v1',
    jsonEncode({
      'accessToken': 'access-token',
      'refreshToken': 'refresh-token',
      'userId': 'user-1',
      'email': 'dev@rodnya.app',
      'displayName': 'Dev User',
      'providerIds': ['password'],
      'isProfileComplete': true,
      'missingFields': const [],
    }),
  );

  return CustomApiAuthService.create(
    httpClient: MockClient((request) async {
      return http.Response('{"message":"not found"}', 404);
    }),
    preferences: preferences,
    runtimeConfig: const BackendRuntimeConfig(
      apiBaseUrl: 'https://api.example.ru',
    ),
    invitationService: InvitationService(),
  );
}

class _FailingReadyWebSocketChannel implements WebSocketChannel {
  final _sink = _FakeWebSocketSink();

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future<void>.error(Exception('connect failed'));

  @override
  _FakeWebSocketSink get sink => _sink;

  @override
  Stream<dynamic> get stream => const Stream<dynamic>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWebSocketChannel implements WebSocketChannel {
  _FakeWebSocketChannel(this._stream);

  final Stream<dynamic> _stream;
  final _FakeWebSocketSink _sink = _FakeWebSocketSink();

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready async {}

  @override
  Stream<dynamic> get stream => _stream;

  @override
  _FakeWebSocketSink get sink => _sink;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWebSocketSink implements WebSocketSink {
  @override
  void add(event) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream stream) async {}

  @override
  Future close([int? closeCode, String? closeReason]) async {}

  @override
  Future get done async {}
}

class _FakeTimer implements Timer {
  var _isActive = true;

  @override
  bool get isActive => _isActive;

  @override
  int get tick => 0;

  @override
  void cancel() {
    _isActive = false;
  }
}
