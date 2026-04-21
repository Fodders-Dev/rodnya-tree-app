import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:rodnya/backend/interfaces/call_service_interface.dart';
import 'package:rodnya/models/call_event.dart';
import 'package:rodnya/models/call_invite.dart';
import 'package:rodnya/models/call_media_mode.dart';
import 'package:rodnya/models/call_state.dart';
import 'package:rodnya/screens/call_screen.dart';
import 'package:rodnya/services/call_coordinator_service.dart';

void main() {
  testWidgets(
    'CallScreen shows settings CTA and hides media toggles when media permission is denied',
    (tester) async {
      final coordinator = _FakeCallCoordinator(
        call:
            _buildCall(state: CallState.active, mediaMode: CallMediaMode.video),
        connectionErrorValue:
            'Нет доступа к микрофону или камере. Разрешите доступ в настройках приложения.',
        hasMediaPermissionIssueValue: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CallScreen(
            initialCall: coordinator.currentCall!,
            title: 'Web QA',
            coordinator: coordinator,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Открыть настройки'), findsOneWidget);
      expect(find.textContaining('Нет доступа к микрофону'), findsOneWidget);
      expect(find.byTooltip('Выключить микрофон'), findsNothing);
      expect(find.byTooltip('Выключить камеру'), findsNothing);
      expect(find.byTooltip('Завершить звонок'), findsOneWidget);
    },
  );

  testWidgets('CallScreen pops when coordinator clears the active call',
      (tester) async {
    final coordinator = _FakeCallCoordinator(
      call: _buildCall(state: CallState.active),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CallScreen(
                    initialCall: coordinator.currentCall!,
                    title: 'Web QA',
                    coordinator: coordinator,
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Web QA'), findsOneWidget);

    coordinator.clearCall();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(CallScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}

CallInvite _buildCall({
  required CallState state,
  CallMediaMode mediaMode = CallMediaMode.audio,
}) {
  return CallInvite(
    id: 'call-1',
    chatId: 'chat-1',
    initiatorId: 'user-1',
    recipientId: 'user-2',
    participantIds: const ['user-1', 'user-2'],
    mediaMode: mediaMode,
    state: state,
    createdAt: DateTime(2026, 4, 20, 10),
    updatedAt: DateTime(2026, 4, 20, 10, 1),
  );
}

class _FakeCallCoordinator extends CallCoordinatorService {
  _FakeCallCoordinator({
    required CallInvite call,
    this.connectionErrorValue,
    this.hasMediaPermissionIssueValue = false,
  })  : _currentCall = call,
        super(callService: _FakeCallService());

  CallInvite? _currentCall;
  final String? connectionErrorValue;
  final bool hasMediaPermissionIssueValue;

  @override
  String? get currentUserId => 'user-1';

  @override
  CallInvite? get currentCall => _currentCall;

  @override
  Room? get room => null;

  @override
  String? get connectionError => connectionErrorValue;

  @override
  bool get hasMediaPermissionIssue => hasMediaPermissionIssueValue;

  @override
  bool get microphoneEnabled => true;

  @override
  bool get cameraEnabled => true;

  void clearCall() {
    _currentCall = null;
    notifyListeners();
  }

  @override
  Future<void> activateCall(CallInvite call) async {
    _currentCall = call;
    notifyListeners();
  }
}

class _FakeCallService implements CallServiceInterface {
  @override
  String? get currentUserId => 'user-1';

  @override
  Stream<CallEvent> get events => const Stream<CallEvent>.empty();

  @override
  Future<CallInvite> acceptCall(String callId) async => _buildCall(
        state: CallState.active,
      );

  @override
  Future<CallInvite> cancelCall(String callId) async => _buildCall(
        state: CallState.cancelled,
      );

  @override
  Future<CallInvite?> getActiveCall({String? chatId}) async => null;

  @override
  Future<CallInvite?> getCall(String callId) async => null;

  @override
  Future<CallInvite> hangUp(String callId) async => _buildCall(
        state: CallState.ended,
      );

  @override
  Future<CallInvite> rejectCall(String callId) async => _buildCall(
        state: CallState.rejected,
      );

  @override
  Future<void> startRealtimeBridge() async {}

  @override
  Future<CallInvite> startCall({
    required String chatId,
    required CallMediaMode mediaMode,
  }) async =>
      _buildCall(
        state: CallState.ringing,
        mediaMode: mediaMode,
      );

  @override
  Future<void> stopRealtimeBridge() async {}
}
