import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/call_service_interface.dart';
import 'package:rodnya/backend/interfaces/semya_capable_family_tree_service.dart';
import 'package:rodnya/backend/models/onboarding_state.dart';
import 'package:rodnya/backend/models/semya.dart';
import 'package:rodnya/models/call_event.dart';
import 'package:rodnya/models/call_invite.dart';
import 'package:rodnya/models/call_media_mode.dart';
import 'package:rodnya/models/call_session.dart';
import 'package:rodnya/models/call_state.dart';
import 'package:rodnya/providers/onboarding_controller.dart';
import 'package:rodnya/providers/semya_details_controller.dart';
import 'package:rodnya/screens/complete_profile_screen.dart';
import 'package:rodnya/services/call_coordinator_service.dart';
import 'package:rodnya/services/chat_pin_store.dart';
import 'package:rodnya/widgets/call_floating_pip.dart';

class _MemoryPinStore implements ChatPinStore {
  final Map<String, ChatPinnedMessageSnapshot> _data =
      <String, ChatPinnedMessageSnapshot>{};

  @override
  Future<void> clearPinnedMessage(String key) async {
    _data.remove(key);
  }

  @override
  Future<ChatPinnedMessageSnapshot?> getPinnedMessage(String key) async {
    return _data[key];
  }

  @override
  Future<void> savePinnedMessage(
    String key,
    ChatPinnedMessageSnapshot snapshot,
  ) async {
    _data[key] = snapshot;
  }
}

class _FakeRemotePinClient implements RemoteChatPinClient {
  ChatPinnedMessageSnapshot? nextResult;
  bool shouldThrow = false;

  @override
  Future<void> clearChatPinnedMessage(String chatId) async {
    nextResult = null;
  }

  @override
  Future<ChatPinnedMessageSnapshot?> getChatPinnedMessage(String chatId) async {
    if (shouldThrow) {
      throw StateError('network offline');
    }
    return nextResult;
  }

  @override
  Future<ChatPinnedMessageSnapshot?> pinChatMessage({
    required String chatId,
    required String messageId,
  }) async {
    return nextResult;
  }
}

class _FakeSemyaService implements SemyaCapableFamilyTreeService {
  Completer<SemyaDetails?> detailsCompleter = Completer<SemyaDetails?>();

  @override
  Future<SemyaDetails?> findSemyaById(String semyaId) =>
      detailsCompleter.future;

  @override
  Future<List<SemyaMembership>> listMembershipsForSemya(String semyaId) async =>
      const <SemyaMembership>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeCallService implements CallServiceInterface {
  final StreamController<CallEvent> _events =
      StreamController<CallEvent>.broadcast();

  @override
  String? get currentUserId => 'user-1';

  @override
  Stream<CallEvent> get events => _events.stream;

  @override
  Future<CallInvite> acceptCall(String callId) {
    throw UnimplementedError();
  }

  @override
  Future<CallInvite> cancelCall(String callId) {
    throw UnimplementedError();
  }

  @override
  Future<CallInvite?> getActiveCall({String? chatId}) async => null;

  @override
  Future<CallInvite?> getCall(String callId) async => null;

  @override
  Future<CallInvite> hangUp(String callId) {
    throw UnimplementedError();
  }

  @override
  Future<CallInvite> joinCall(String callId) {
    throw UnimplementedError();
  }

  @override
  Future<CallInvite> nudgeCallParticipants(
    String callId, {
    List<String>? participantIds,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<CallInvite> rejectCall(String callId) {
    throw UnimplementedError();
  }

  @override
  Future<CallInvite> startCall({
    required String chatId,
    required CallMediaMode mediaMode,
    List<String>? participantIds,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> startRealtimeBridge() async {}

  @override
  Future<void> stopRealtimeBridge() async {}

  void dispose() {
    unawaited(_events.close());
  }
}

void main() {
  test('Wave 4: HybridChatPinStore clears stale local pin on remote null',
      () async {
    final local = _MemoryPinStore();
    final remote = _FakeRemotePinClient();
    final store = HybridChatPinStore(localStore: local, remoteClient: remote);
    final key = HybridChatPinStore.keyForChatId('chat-1');
    final cached = ChatPinnedMessageSnapshot(
      messageId: 'm-1',
      senderId: 'u-1',
      senderName: 'Анна',
      text: 'Старое закрепление',
      attachmentCount: 0,
      pinnedAt: DateTime.utc(2026, 5, 1),
    );
    await local.savePinnedMessage(key, cached);

    // Offline / error -> falls back to local snapshot.
    remote.shouldThrow = true;
    final offlineResult = await store.getPinnedMessage(key);
    expect(offlineResult?.messageId, 'm-1');

    // Server succeeds with null -> clears stale local pin and returns null.
    remote.shouldThrow = false;
    remote.nextResult = null;
    final clearedResult = await store.getPinnedMessage(key);
    expect(clearedResult, isNull);
    expect(await local.getPinnedMessage(key), isNull);
  });

  test('Wave 4: CompleteProfileScreen parses +7, +375, and +1 numbers cleanly',
      () {
    final ru = CompleteProfileScreen.parsePhoneWithCountryCode('+79991234567');
    expect(ru.key, '+7');
    expect(ru.value, '9991234567');

    final by = CompleteProfileScreen.parsePhoneWithCountryCode('+375291234567');
    expect(by.key, '+375');
    expect(by.value, '291234567');

    final us = CompleteProfileScreen.parsePhoneWithCountryCode('+14155550100');
    expect(us.key, '+1');
    expect(us.value, '4155550100');
  });

  test(
      'Wave 4: SemyaDetailsController ignores late async completions after dispose',
      () async {
    final service = _FakeSemyaService();
    final controller = SemyaDetailsController(
      semyaId: 's-1',
      service: service,
    );
    final loadFuture = controller.load();
    controller.dispose();
    service.detailsCompleter.complete(null);
    await loadFuture;
    controller.clearMutationError();
  });

  test('Wave 4: OnboardingRelativeDraft keeps stable id across copyWith', () {
    final draft = OnboardingRelativeDraft(name: 'Мама');
    final copy = draft.copyWith(relationToMe: OnboardingRelationToMe.mother);
    expect(copy.id, draft.id);
    expect(copy.name, 'Мама');
    expect(copy.relationToMe, OnboardingRelationToMe.mother);
  });

  testWidgets(
      'Wave 4: CallFloatingPip tracks coordinator updates and drags from bottom-right',
      (tester) async {
    final fakeCallSvc = _FakeCallService();
    addTearDown(fakeCallSvc.dispose);
    final coordinator = CallCoordinatorService(
      callService: fakeCallSvc,
      ringingRecoveryInterval: Duration.zero,
      activeCallRecoveryInterval: Duration.zero,
      wakelockToggler: (_) async {},
    );
    addTearDown(coordinator.dispose);

    final invite = CallInvite(
      id: 'call-1',
      chatId: 'chat-1',
      initiatorId: 'user-2',
      recipientId: 'user-1',
      participantIds: const <String>['user-2', 'user-1'],
      state: CallState.active,
      mediaMode: CallMediaMode.audio,
      createdAt: DateTime.utc(2026, 5, 1),
      updatedAt: DateTime.utc(2026, 5, 1),
      session: const CallSession(
        roomName: 'room-1',
        url: 'wss://livekit.example.test',
        token: 'tok',
        participantIdentity: 'user-1',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: CallFloatingPip(
              call: invite,
              title: 'Бабушка',
              coordinator: coordinator,
              onRestore: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Звонок идет'), findsOneWidget);
    coordinator.debugMarkMicrophonePublishFailed(true);
    await tester.pump();
    expect(find.byIcon(Icons.mic_off_rounded), findsOneWidget);

    final beforeTopLeft = tester.getTopLeft(find.text('Бабушка'));
    expect(beforeTopLeft.dx, greaterThan(400));

    await tester.drag(find.text('Бабушка'), const Offset(-40, -30));
    await tester.pump();

    final afterTopLeft = tester.getTopLeft(find.text('Бабушка'));
    expect(afterTopLeft.dx, lessThan(beforeTopLeft.dx));
    expect(afterTopLeft.dy, lessThan(beforeTopLeft.dy));
    expect(afterTopLeft.dx, greaterThan(400));
  });
}
