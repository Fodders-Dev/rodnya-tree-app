import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/call_service_interface.dart';
import 'package:rodnya/models/call_event.dart';
import 'package:rodnya/models/call_invite.dart';
import 'package:rodnya/models/call_media_mode.dart';
import 'package:rodnya/models/call_state.dart';
import 'package:rodnya/services/call_coordinator_service.dart';
import 'package:rodnya/services/custom_api_realtime_service.dart';
import 'package:rodnya/services/incoming_call_watcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('IncomingCallWatcher hydrates ringing call on realtime reconnect',
      () async {
    final realtimeEvents = StreamController<CustomApiRealtimeEvent>.broadcast();
    final service = _IncomingCallService(activeCall: null);
    final coordinator = CallCoordinatorService(callService: service);
    final watcher = IncomingCallWatcher(
      coordinator: coordinator,
      realtimeEvents: realtimeEvents.stream,
    )..start();

    await _settle();
    service.resetCounters();
    service.activeCall = _buildCall(state: CallState.ringing);

    realtimeEvents.add(
      const CustomApiRealtimeEvent(
        type: 'connection.ready',
        payload: <String, dynamic>{'type': 'connection.ready'},
      ),
    );

    await _settle();

    expect(service.activeCallRequests, greaterThanOrEqualTo(1));
    expect(coordinator.currentCall?.id, 'call-1');
    expect(coordinator.currentCall?.state, CallState.ringing);

    await watcher.dispose();
    await realtimeEvents.close();
    coordinator.dispose();
  });

  test('IncomingCallWatcher polls active call while realtime is disconnected',
      () async {
    final realtimeEvents = StreamController<CustomApiRealtimeEvent>.broadcast();
    final timerCallbacks = <VoidCallback>[];
    final timers = <_FakeTimer>[];
    final service = _IncomingCallService(activeCall: null);
    final coordinator = CallCoordinatorService(callService: service);
    final watcher = IncomingCallWatcher(
      coordinator: coordinator,
      realtimeEvents: realtimeEvents.stream,
      timerFactory: (delay, callback) {
        final timer = _FakeTimer();
        timerCallbacks.add(() {
          timer.markFired();
          callback();
        });
        timers.add(timer);
        return timer;
      },
    )..start();

    await _settle();
    service.resetCounters();
    service.activeCall = _buildCall(state: CallState.ringing);

    realtimeEvents.add(
      const CustomApiRealtimeEvent(
        type: 'connection.disconnected',
        payload: <String, dynamic>{'type': 'connection.disconnected'},
      ),
    );
    await _settle();

    expect(watcher.isFallbackPolling, isTrue);
    expect(timerCallbacks.length, 1);

    timerCallbacks.removeAt(0)();
    await _settle();

    expect(service.activeCallRequests, greaterThanOrEqualTo(1));
    expect(coordinator.currentCall?.id, 'call-1');
    expect(timerCallbacks.length, 1);

    await watcher.dispose();
    expect(timers.every((timer) => !timer.isActive), isTrue);
    await realtimeEvents.close();
    coordinator.dispose();
  });

  test('IncomingCallWatcher polls in background and refreshes on resume',
      () async {
    final timerCallbacks = <VoidCallback>[];
    final timers = <_FakeTimer>[];
    final service = _IncomingCallService(activeCall: null);
    final coordinator = CallCoordinatorService(callService: service);
    final watcher = IncomingCallWatcher(
      coordinator: coordinator,
      timerFactory: (delay, callback) {
        timerCallbacks.add(callback);
        final timer = _FakeTimer();
        timers.add(timer);
        return timer;
      },
    )..start();

    await _settle();
    service.resetCounters();
    service.activeCall = _buildCall(state: CallState.ringing);

    watcher.didChangeAppLifecycleState(AppLifecycleState.paused);
    await _settle();

    expect(watcher.isFallbackPolling, isTrue);
    expect(timerCallbacks.length, 1);

    watcher.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _settle();

    expect(watcher.isFallbackPolling, isFalse);
    expect(timers.first.isActive, isFalse);
    expect(service.activeCallRequests, greaterThanOrEqualTo(1));
    expect(coordinator.currentCall?.id, 'call-1');

    await watcher.dispose();
    coordinator.dispose();
  });
}

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(const Duration(milliseconds: 10));
}

CallInvite _buildCall({
  String id = 'call-1',
  CallState state = CallState.ringing,
}) {
  final now = DateTime.utc(2026, 5);
  return CallInvite(
    id: id,
    chatId: 'chat-1',
    initiatorId: 'user-2',
    recipientId: 'user-1',
    participantIds: const <String>['user-1', 'user-2'],
    mediaMode: CallMediaMode.audio,
    state: state,
    createdAt: now,
    updatedAt: now,
  );
}

class _IncomingCallService implements CallServiceInterface {
  _IncomingCallService({
    required this.activeCall,
  });

  @override
  final String currentUserId = 'user-1';

  @override
  final Stream<CallEvent> events = const Stream<CallEvent>.empty();

  CallInvite? activeCall;
  int activeCallRequests = 0;
  int realtimeStarts = 0;

  void resetCounters() {
    activeCallRequests = 0;
    realtimeStarts = 0;
  }

  @override
  Future<CallInvite> acceptCall(String callId) async => activeCall!;

  @override
  Future<CallInvite> cancelCall(String callId) async => activeCall!;

  @override
  Future<CallInvite?> getActiveCall({String? chatId}) async {
    activeCallRequests += 1;
    return activeCall;
  }

  @override
  Future<CallInvite?> getCall(String callId) async => activeCall;

  @override
  Future<CallInvite> hangUp(String callId) async => activeCall!;

  @override
  Future<CallInvite> rejectCall(String callId) async => activeCall!;

  @override
  Future<void> startRealtimeBridge() async {
    realtimeStarts += 1;
  }

  @override
  Future<CallInvite> startCall({
    required String chatId,
    required CallMediaMode mediaMode,
    List<String>? participantIds,
  }) async =>
      activeCall!;

  @override
  Future<CallInvite> nudgeCallParticipants(
    String callId, {
    List<String>? participantIds,
  }) async =>
      activeCall!;

  @override
  Future<void> stopRealtimeBridge() async {}
}

class _FakeTimer implements Timer {
  bool _isActive = true;

  @override
  void cancel() {
    _isActive = false;
  }

  @override
  bool get isActive => _isActive;

  @override
  int get tick => 0;

  void markFired() {
    _isActive = false;
  }
}
