import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/call_service_interface.dart';
import 'package:rodnya/models/call_event.dart';
import 'package:rodnya/models/call_invite.dart';
import 'package:rodnya/models/call_media_mode.dart';
import 'package:rodnya/models/call_session.dart';
import 'package:rodnya/models/call_state.dart';
import 'package:rodnya/services/call_coordinator_service.dart';
import 'package:rodnya/services/rustore_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'CallCoordinatorService resyncs active call on resume even without a current call',
    () async {
      final service = _CountingCallService(
        activeCall: _buildCall(state: CallState.ringing),
      );
      final coordinator = CallCoordinatorService(callService: service);

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      service.resetCounters();

      coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(service.activeCallRequests, greaterThanOrEqualTo(1));
      expect(coordinator.currentCall?.id, 'call-1');

      coordinator.dispose();
    },
  );

  test(
    'CallCoordinatorService exposes media permission issue before room connect',
    () async {
      final service = _CountingCallService(activeCall: null);
      final coordinator = CallCoordinatorService(
        callService: service,
        mediaPermissionRequester: (_) async => false,
      );

      await coordinator.activateCall(
        _buildCall(
          state: CallState.active,
          session: const CallSession(
            roomName: 'room-1',
            url: 'wss://livekit.example.test',
            token: 'token-1',
            participantIdentity: 'user-1',
          ),
        ),
      );

      expect(coordinator.hasMediaPermissionIssue, isTrue);
      expect(
        coordinator.connectionError,
        'Нет доступа к микрофону или камере. Разрешите доступ в настройках приложения.',
      );
      expect(coordinator.isConnectingRoom, isFalse);
      expect(coordinator.room, isNull);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      coordinator.dispose();
    },
  );

  test(
    'CallCoordinatorService hydrates incoming call from RuStore push payload',
    () async {
      final pushMessages = StreamController<RustorePushMessage>.broadcast();
      final pushedCall = _buildCall(state: CallState.ringing);
      final service = _CountingCallService(
        activeCall: null,
        callById: pushedCall,
      );
      final coordinator = CallCoordinatorService(
        callService: service,
        pushMessages: pushMessages.stream,
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      service.resetCounters();

      pushMessages.add(
        const RustorePushMessage(
          messageId: 'push-1',
          data: <String, String>{
            'type': 'call_invite',
            'callId': 'call-1',
            'chatId': 'chat-1',
          },
          title: 'Caller',
          body: 'Видеозвонок',
        ),
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(service.callByIdRequests, 1);
      expect(coordinator.currentCall?.id, 'call-1');
      expect(coordinator.currentCall?.state, CallState.ringing);

      await pushMessages.close();
      coordinator.dispose();
    },
  );

  test(
    'CallCoordinatorService ignores terminal updates for another call id',
    () async {
      final events = StreamController<CallEvent>.broadcast();
      final activeCall = _buildCall(
        state: CallState.active,
        session: const CallSession(
          roomName: 'room-1',
          url: 'wss://livekit.example.test',
          token: 'token-1',
          participantIdentity: 'user-1',
        ),
      );
      final service = _CountingCallService(
        activeCall: activeCall,
        events: events.stream,
      );
      final coordinator = CallCoordinatorService(
        callService: service,
        mediaPermissionRequester: (_) async => false,
      );

      await coordinator.activateCall(activeCall);
      expect(coordinator.currentCall?.id, 'call-1');
      expect(coordinator.currentCall?.state, CallState.active);

      events.add(
        CallEvent(
          type: CallEventType.stateUpdated,
          call: _buildCall(
            id: 'call-legacy',
            state: CallState.missed,
          ),
        ),
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(coordinator.currentCall?.id, 'call-1');
      expect(coordinator.currentCall?.state, CallState.active);

      await events.close();
      coordinator.dispose();
    },
  );

  test(
    'CallCoordinatorService ignores stale same-call downgrade snapshot',
    () async {
      final events = StreamController<CallEvent>.broadcast();
      final activeCall = _buildCall(
        state: CallState.active,
        updatedAt: DateTime(2026, 4, 20, 10, 5),
        session: const CallSession(
          roomName: 'room-1',
          url: 'wss://livekit.example.test',
          token: 'token-1',
          participantIdentity: 'user-1',
        ),
      );
      final service = _CountingCallService(
        activeCall: activeCall,
        events: events.stream,
      );
      final coordinator = CallCoordinatorService(
        callService: service,
        mediaPermissionRequester: (_) async => false,
      );

      await coordinator.activateCall(activeCall);

      events.add(
        CallEvent(
          type: CallEventType.inviteCreated,
          call: _buildCall(
            state: CallState.ringing,
            updatedAt: DateTime(2026, 4, 20, 10, 1),
          ),
        ),
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(coordinator.currentCall?.state, CallState.active);
      expect(coordinator.currentCall?.session, isNotNull);

      await events.close();
      coordinator.dispose();
    },
  );

  test(
    'CallCoordinatorService refreshes stale ringing call until terminal state',
    () async {
      final service = _CountingCallService(
        activeCall: _buildCall(state: CallState.ringing),
      );
      final coordinator = CallCoordinatorService(
        callService: service,
        ringingRecoveryInterval: const Duration(milliseconds: 20),
      );

      await coordinator.activateCall(_buildCall(state: CallState.ringing));
      service.callById = _buildCall(
        state: CallState.missed,
        updatedAt: DateTime(2026, 4, 20, 10, 2),
      );

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(service.callByIdRequests, greaterThanOrEqualTo(1));
      expect(coordinator.currentCall, isNull);

      coordinator.dispose();
    },
  );
}

CallInvite _buildCall({
  String id = 'call-1',
  required CallState state,
  CallMediaMode mediaMode = CallMediaMode.audio,
  CallSession? session,
  DateTime? updatedAt,
}) {
  return CallInvite(
    id: id,
    chatId: 'chat-1',
    initiatorId: 'user-2',
    recipientId: 'user-1',
    participantIds: const ['user-1', 'user-2'],
    mediaMode: mediaMode,
    state: state,
    createdAt: DateTime(2026, 4, 20, 10),
    updatedAt: updatedAt ?? DateTime(2026, 4, 20, 10, 1),
    session: session,
  );
}

class _CountingCallService implements CallServiceInterface {
  CallInvite? activeCall;
  CallInvite? callById;
  final Stream<CallEvent> _events;
  int activeCallRequests = 0;
  int callByIdRequests = 0;

  _CountingCallService._internal({
    required this.activeCall,
    required Stream<CallEvent> events,
    this.callById,
  }) : _events = events;

  factory _CountingCallService({
    required CallInvite? activeCall,
    CallInvite? callById,
    Stream<CallEvent>? events,
  }) {
    return _CountingCallService._internal(
      activeCall: activeCall,
      callById: callById,
      events: events ?? const Stream<CallEvent>.empty(),
    );
  }

  void resetCounters() {
    activeCallRequests = 0;
    callByIdRequests = 0;
  }

  @override
  String? get currentUserId => 'user-1';

  @override
  Stream<CallEvent> get events => _events;

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
  Future<CallInvite?> getCall(String callId) async {
    callByIdRequests += 1;
    return callById ?? activeCall;
  }

  @override
  Future<CallInvite> hangUp(String callId) async => activeCall!;

  @override
  Future<CallInvite> rejectCall(String callId) async => activeCall!;

  @override
  Future<void> startRealtimeBridge() async {}

  @override
  Future<CallInvite> startCall({
    required String chatId,
    required CallMediaMode mediaMode,
  }) async =>
      activeCall!;

  @override
  Future<void> stopRealtimeBridge() async {}
}
