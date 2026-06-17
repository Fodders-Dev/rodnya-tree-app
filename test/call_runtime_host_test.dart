import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:rodnya/backend/interfaces/call_service_interface.dart';
import 'package:rodnya/models/call_event.dart';
import 'package:rodnya/models/call_invite.dart';
import 'package:rodnya/models/call_media_mode.dart';
import 'package:rodnya/models/call_state.dart';
import 'package:rodnya/navigation/app_router_shared.dart';
import 'package:rodnya/screens/call_screen.dart';
import 'package:rodnya/services/call_coordinator_service.dart';
import 'package:rodnya/widgets/call_floating_pip.dart';
import 'package:rodnya/widgets/call_runtime_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await GetIt.I.reset();
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets(
    'CallRuntimeHost opens incoming call screen outside ChatScreen',
    (tester) async {
      final coordinator = _HostFakeCallCoordinator();
      GetIt.I.registerSingleton<CallCoordinatorService>(coordinator);

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: const CallRuntimeHost(
            child: Scaffold(
              body: Center(child: Text('home')),
            ),
          ),
        ),
      );
      await tester.pump();

      coordinator.setCall(_buildCall(state: CallState.ringing));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(CallScreen), findsOneWidget);
      expect(find.text('Входящий звонок'), findsOneWidget);
    },
  );

  testWidgets(
    'CallRuntimeHost does not show banner while CallScreen is already visible',
    (tester) async {
      final coordinator = _HostFakeCallCoordinator();
      GetIt.I.registerSingleton<CallCoordinatorService>(coordinator);

      final activeCall = _buildCall(state: CallState.active);

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: CallRuntimeHost(
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => CallScreen(
                            initialCall: activeCall,
                            title: 'Phone QA',
                            coordinator: coordinator,
                          ),
                        ),
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pumpAndSettle();

      coordinator.setCall(activeCall);
      await tester.pump();

      expect(find.byType(CallScreen), findsOneWidget);
      expect(find.text('Открыть экран звонка'), findsNothing);
      expect(find.text('Подключаем звонок...'), findsNothing);
    },
  );

  testWidgets(
    'CallRuntimeHost shows floating mini-window for active calls and restores',
    (tester) async {
      final coordinator = _HostFakeCallCoordinator();
      GetIt.I.registerSingleton<CallCoordinatorService>(coordinator);
      final activeCall = _buildCall(
        state: CallState.active,
        initiatorId: 'user-1',
        recipientId: 'user-2',
      );

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: const CallRuntimeHost(
            child: Scaffold(
              body: Center(child: Text('home')),
            ),
          ),
        ),
      );

      coordinator.setCall(activeCall);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(CallFloatingPip), findsOneWidget);
      expect(find.text('Звонок идет'), findsOneWidget);
      expect(find.text('Открыть экран звонка'), findsNothing);

      await tester.tap(find.text('Звонок идет'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(CallScreen), findsOneWidget);
      expect(find.byType(CallFloatingPip), findsNothing);
    },
  );

  testWidgets(
    'CallRuntimeHost floating mini-window can hang up active call',
    (tester) async {
      final coordinator = _HostFakeCallCoordinator();
      GetIt.I.registerSingleton<CallCoordinatorService>(coordinator);
      final activeCall = _buildCall(
        state: CallState.active,
        initiatorId: 'user-1',
        recipientId: 'user-2',
      );

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: const CallRuntimeHost(
            child: Scaffold(
              body: Center(child: Text('home')),
            ),
          ),
        ),
      );

      coordinator.setCall(activeCall);
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.call_end_rounded));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(coordinator.finishCallCount, 1);
      expect(find.byType(CallFloatingPip), findsNothing);
    },
  );
}

CallInvite _buildCall({
  required CallState state,
  CallMediaMode mediaMode = CallMediaMode.audio,
  String initiatorId = 'user-2',
  String recipientId = 'user-1',
}) {
  return CallInvite(
    id: 'call-1',
    chatId: 'chat-1',
    initiatorId: initiatorId,
    recipientId: recipientId,
    participantIds: const ['user-1', 'user-2'],
    mediaMode: mediaMode,
    state: state,
    createdAt: DateTime(2026, 4, 20, 10),
    updatedAt: DateTime(2026, 4, 20, 10, 1),
  );
}

class _HostFakeCallCoordinator extends CallCoordinatorService {
  _HostFakeCallCoordinator()
      : super(
          callService: _HostFakeCallService(),
        );

  CallInvite? _currentCall;
  int finishCallCount = 0;

  @override
  String? get currentUserId => 'user-1';

  @override
  CallInvite? get currentCall => _currentCall;

  @override
  Future<void> ensureRuntimeReady() async {}

  void setCall(CallInvite? call) {
    _currentCall = call;
    notifyListeners();
  }

  @override
  Future<void> activateCall(CallInvite call) async {
    _currentCall = call;
    notifyListeners();
  }

  @override
  Future<CallInvite?> finishCall([String? callId]) async {
    finishCallCount += 1;
    _currentCall = null;
    notifyListeners();
    return _buildCall(state: CallState.ended);
  }
}

class _HostFakeCallService implements CallServiceInterface {
  @override
  String? get currentUserId => 'user-1';

  @override
  Stream<CallEvent> get events => const Stream<CallEvent>.empty();

  @override
  Future<CallInvite> acceptCall(String callId) async =>
      _buildCall(state: CallState.active);

  @override
  Future<CallInvite> cancelCall(String callId) async =>
      _buildCall(state: CallState.cancelled);

  @override
  Future<CallInvite?> getActiveCall({String? chatId}) async => null;

  @override
  Future<CallInvite?> getCall(String callId) async => null;

  @override
  Future<CallInvite> hangUp(String callId) async =>
      _buildCall(state: CallState.ended);

  @override
  Future<CallInvite> rejectCall(String callId) async =>
      _buildCall(state: CallState.rejected);

  @override
  Future<void> startRealtimeBridge() async {}

  @override
  Future<CallInvite> startCall({
    required String chatId,
    required CallMediaMode mediaMode,
    List<String>? participantIds,
  }) async =>
      _buildCall(
        state: CallState.ringing,
        mediaMode: mediaMode,
      );

  @override
  Future<void> stopRealtimeBridge() async {}
}
