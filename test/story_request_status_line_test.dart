// «Спросить историю» MVP-1 (STORY-REQUEST-MVP1-BRIEF.md §3.6):
// StoryRequestStatusLine — the initiator-only «Ждём ответа: {имя} ·
// Отозвать» line above «Семейные истории».

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/auth_service_interface.dart';
import 'package:rodnya/backend/interfaces/story_request_capable_family_tree_service.dart';
import 'package:rodnya/models/story_request.dart';
import 'package:rodnya/widgets/story_request_status_line.dart';

class _FakeAuth implements AuthServiceInterface {
  _FakeAuth(this._userId);
  final String _userId;

  @override
  String? get currentUserId => _userId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeService implements StoryRequestCapableFamilyTreeService {
  _FakeService(this._issued);
  final List<StoryRequest> _issued;
  String? revokedId;

  @override
  Future<List<StoryRequest>> listStoryRequests({
    required String role,
    StoryRequestStatus? status,
  }) async {
    if (role != 'issued') return const <StoryRequest>[];
    return _issued
        .where((r) => status == null || r.status == status)
        .toList(growable: false);
  }

  @override
  Future<StoryRequest?> revokeStoryRequest({required String requestId}) async {
    revokedId = requestId;
    final target = _issued.firstWhere((r) => r.id == requestId);
    return StoryRequest(
      id: target.id,
      treeId: target.treeId,
      personId: target.personId,
      requesterUserId: target.requesterUserId,
      targetUserId: target.targetUserId,
      question: target.question,
      status: StoryRequestStatus.revoked,
      createdAt: target.createdAt,
      expiresAt: target.expiresAt,
      target: target.target,
    );
  }

  @override
  Future<StoryRequest?> createStoryRequest({
    required String treeId,
    required String personId,
    required String targetUserId,
    required StoryRequestQuestion question,
  }) async =>
      throw UnimplementedError();

  @override
  Future<StoryRequest?> getStoryRequest({required String requestId}) async => null;

  @override
  Future<StoryRequest?> answerStoryRequest({
    required String requestId,
    required StoryRequestAnswerInput answer,
  }) async =>
      null;

  @override
  Future<StoryRequest?> declineStoryRequest({required String requestId}) async => null;
}

StoryRequest _pending({
  required String id,
  required String personId,
  String requesterUserId = 'u-me',
  String targetName = 'Артём',
}) {
  return StoryRequest(
    id: id,
    treeId: 'tree-1',
    personId: personId,
    requesterUserId: requesterUserId,
    targetUserId: 'u-target',
    question: const StoryRequestQuestion(text: 'Q'),
    status: StoryRequestStatus.pending,
    createdAt: 'c',
    expiresAt: 'e',
    target: StoryRequestPersonSummary(id: 'u-target', displayName: targetName),
  );
}

void main() {
  testWidgets('shows «Ждём ответа: {имя}» for a pending issued request about this person',
      (tester) async {
    final service = _FakeService([_pending(id: 'sreq-1', personId: 'p-1')]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StoryRequestStatusLine(
            personId: 'p-1',
            serviceOverride: service,
            authServiceOverride: _FakeAuth('u-me'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ждём ответа: Артём'), findsOneWidget);
    expect(find.byKey(const Key('story-request-revoke-sreq-1')), findsOneWidget);
  });

  testWidgets('hides when there is no pending issued request for this person',
      (tester) async {
    final service = _FakeService([_pending(id: 'sreq-1', personId: 'other-person')]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StoryRequestStatusLine(
            personId: 'p-1',
            serviceOverride: service,
            authServiceOverride: _FakeAuth('u-me'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('story-request-status-line')), findsNothing);
  });

  testWidgets('«Отозвать» calls revokeStoryRequest and removes the line',
      (tester) async {
    final service = _FakeService([_pending(id: 'sreq-1', personId: 'p-1')]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StoryRequestStatusLine(
            personId: 'p-1',
            serviceOverride: service,
            authServiceOverride: _FakeAuth('u-me'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('story-request-revoke-sreq-1')));
    await tester.pumpAndSettle();

    expect(service.revokedId, 'sreq-1');
    expect(find.byKey(const Key('story-request-status-line')), findsNothing);
  });
}
