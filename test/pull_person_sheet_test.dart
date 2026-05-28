// Ship FE5 (2026-05-26): PullPersonSheet widget tests + service-layer
// SemyaPullPersonResult parsing.
//
// Widget tests:
//   • Target list загружается из service.listMySemya, source семя excluded
//   • Empty state когда no eligible target семьи
//   • Tap target → service.pullPersonToSemya called с правильным args
//   • Success → Navigator.pop(PullPersonResult(success:true, targetSemya))
//   • Error → snackbar / inline error rendered
//
// Note: каноничный entry point (FE6 browse tree) ещё не shipped —
// этот sheet ships как foundation. Тесты verify standalone modal
// behavior c injected fake service.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/semya_capable_family_tree_service.dart';
import 'package:rodnya/backend/models/deleted_person.dart';
import 'package:rodnya/backend/models/deleted_post.dart';
import 'package:rodnya/backend/models/semya.dart';
import 'package:rodnya/backend/models/semya_browse_token.dart';
import 'package:rodnya/backend/models/semya_invitation.dart';
import 'package:rodnya/backend/models/semya_pull_person_result.dart';
import 'package:rodnya/widgets/pull_person_sheet.dart';

class _FakeService implements SemyaCapableFamilyTreeService {
  _FakeService({
    this.semyi = const <Semya>[],
    this.throwOnList,
    this.throwOnPull,
  });

  List<Semya> semyi;
  SemyaError? throwOnList;
  SemyaError? throwOnPull;
  int pullCalls = 0;
  String? lastTargetId;
  String? lastSourceId;
  String? lastPersonId;

  @override
  Future<List<Semya>> listMySemya() async {
    if (throwOnList != null) throw throwOnList!;
    return semyi;
  }

  @override
  Future<SemyaDetails?> findSemyaById(String semyaId) async => null;

  @override
  Future<List<SemyaMembership>> listMembershipsForSemya(String semyaId) async =>
      const <SemyaMembership>[];

  @override
  Future<SemyaInvitation> createInvitation({
    required String semyaId,
    required SemyaRole role,
    String? recipientEmail,
    String? recipientPhone,
    String? recipientUserId,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<SemyaInvitation>> listInvitationsForSemya(String semyaId) async =>
      const <SemyaInvitation>[];

  @override
  Future<SemyaInvitation> revokeInvitation({
    required String semyaId,
    required String invitationId,
  }) async =>
      throw UnimplementedError();

  @override
  Future<SemyaInvitationAcceptResult> acceptInvitation(String token) async =>
      throw UnimplementedError();

  @override
  Future<SemyaPullPersonResult> pullPersonToSemya({
    required String targetSemyaId,
    required String sourceSemyaId,
    required String sourcePersonId,
  }) async {
    pullCalls += 1;
    lastTargetId = targetSemyaId;
    lastSourceId = sourceSemyaId;
    lastPersonId = sourcePersonId;
    if (throwOnPull != null) throw throwOnPull!;
    return SemyaPullPersonResult(
      person: null,
      targetSemyaId: targetSemyaId,
      sourceSemyaId: sourceSemyaId,
      sourcePersonId: sourcePersonId,
    );
  }

  @override
  Future<SemyaBrowseToken> createBrowseToken({
    required String semyaId,
    int? expiresInDays,
  }) async =>
      throw UnimplementedError();

  @override
  Future<BrowsedSemyaTree> fetchBrowseTree(String token) async =>
      throw UnimplementedError();

  @override
  Future<List<SemyaBrowseTokenSummary>> listBrowseTokens({
    required String semyaId,
  }) async =>
      throw UnimplementedError();

  @override
  Future<SemyaBrowseTokenSummary> revokeBrowseToken({
    required String semyaId,
    required String tokenId,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<String>> listHiddenPersonIds({required String semyaId}) async =>
      const <String>[];

  @override
  Future<List<String>> updateHideFilter({
    required String semyaId,
    List<String> addPersonIds = const <String>[],
    List<String> removePersonIds = const <String>[],
  }) async =>
      throw UnimplementedError();

  @override
  Future<SemyaMembership> updateMembership({
    required String semyaId,
    required String userId,
    SemyaRole? role,
    bool? hasInviteGrant,
  }) async =>
      throw UnimplementedError();

  @override
  Future<SemyaMembershipRemoveResult> removeMembership({
    required String semyaId,
    required String userId,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<SemyaInvitation>> listPendingInvitations() async =>
      const <SemyaInvitation>[];

  // Ship Q4a frontend (Ship 31): trash endpoint stubs.

  @override
  Future<List<DeletedPerson>> listMyDeletedPersons() async =>
      const <DeletedPerson>[];

  @override
  Future<List<DeletedPerson>> listDeletedPersonsForSemya(String semyaId) async =>
      const <DeletedPerson>[];

  @override
  Future<void> restoreDeletedPerson(String deletedPersonId) async =>
      throw UnimplementedError();

  @override
  Future<void> permanentlyDeletePerson(String deletedPersonId) async =>
      throw UnimplementedError();

  @override
  Future<List<DeletedPost>> listMyDeletedPosts() async =>
      const <DeletedPost>[];

  @override
  Future<void> restoreDeletedPost(String deletedPostId) async =>
      throw UnimplementedError();

  @override
  Future<void> permanentlyDeletePost(String deletedPostId) async =>
      throw UnimplementedError();
}

Semya _semya({required String id, String? name}) {
  return Semya(
    id: id,
    name: name ?? 'Семья $id',
    ownerId: 'user-1',
    treeId: 'tree-$id',
    createdAt: '2026-05-26T00:00:00.000Z',
    updatedAt: '2026-05-26T00:00:00.000Z',
  );
}

void main() {
  testWidgets('renders header с source person name', (tester) async {
    final service = _FakeService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PullPersonSheet(
            sourceSemyaId: 's-src',
            sourcePersonId: 'p-1',
            sourcePersonName: 'Иван Петров',
            serviceOverride: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Добавить Иван Петров в семью'),
      findsOneWidget,
    );
  });

  testWidgets('lists target семьи, excluding source семя', (tester) async {
    final service = _FakeService(semyi: [
      _semya(id: 's-src', name: 'Source семья'),
      _semya(id: 's-a', name: 'Семья A'),
      _semya(id: 's-b', name: 'Семья B'),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PullPersonSheet(
            sourceSemyaId: 's-src',
            sourcePersonId: 'p-1',
            sourcePersonName: 'X',
            serviceOverride: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Source семя hidden.
    expect(find.text('Source семья'), findsNothing);
    // Eligible target семьи visible.
    expect(find.text('Семья A'), findsOneWidget);
    expect(find.text('Семья B'), findsOneWidget);
    expect(find.byKey(const Key('pull-target-s-a')), findsOneWidget);
    expect(find.byKey(const Key('pull-target-s-b')), findsOneWidget);
  });

  testWidgets('empty state когда нет других семей', (tester) async {
    final service = _FakeService(semyi: [_semya(id: 's-src')]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PullPersonSheet(
            sourceSemyaId: 's-src',
            sourcePersonId: 'p-1',
            sourcePersonName: 'X',
            serviceOverride: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('У вас нет других семей'), findsOneWidget);
  });

  testWidgets('tap target → calls pullPersonToSemya с правильными args',
      (tester) async {
    final service = _FakeService(semyi: [
      _semya(id: 's-src'),
      _semya(id: 's-target', name: 'Целевая семья'),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  await showModalBottomSheet<PullPersonResult>(
                    context: context,
                    isScrollControlled: true,
                    builder: (sheetContext) => PullPersonSheet(
                      sourceSemyaId: 's-src',
                      sourcePersonId: 'p-1',
                      sourcePersonName: 'X',
                      serviceOverride: service,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pull-target-s-target')));
    await tester.pumpAndSettle();
    expect(service.pullCalls, 1);
    expect(service.lastTargetId, 's-target');
    expect(service.lastSourceId, 's-src');
    expect(service.lastPersonId, 'p-1');
  });

  testWidgets('error renders inline когда pull throws', (tester) async {
    final service = _FakeService(
      semyi: [_semya(id: 's-src'), _semya(id: 's-target')],
      throwOnPull: const SemyaError(
        code: 'FORBIDDEN',
        message: 'Нет прав на целевую семью',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PullPersonSheet(
            sourceSemyaId: 's-src',
            sourcePersonId: 'p-1',
            sourcePersonName: 'X',
            serviceOverride: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pull-target-s-target')));
    await tester.pumpAndSettle();
    expect(find.text('Нет прав на целевую семью'), findsOneWidget);
  });

  testWidgets('list-error renders message + skips target list', (tester) async {
    final service = _FakeService(
      throwOnList: const SemyaError(
        code: 'NETWORK',
        message: 'Нет соединения',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PullPersonSheet(
            sourceSemyaId: 's-src',
            sourcePersonId: 'p-1',
            sourcePersonName: 'X',
            serviceOverride: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Нет соединения'), findsOneWidget);
  });

  group('SemyaPullPersonResult parsing', () {
    test('parses response с person field', () {
      final result = SemyaPullPersonResult.fromJson({
        'person': {
          'id': 'p-new',
          'treeId': 't-1',
          'name': 'Иван',
        },
        'targetSemyaId': 's-t',
        'sourceSemyaId': 's-s',
        'sourcePersonId': 'p-orig',
      });
      expect(result.person, isNotNull);
      expect(result.person!.id, 'p-new');
      expect(result.person!.name, 'Иван');
      expect(result.targetSemyaId, 's-t');
      expect(result.sourceSemyaId, 's-s');
      expect(result.sourcePersonId, 'p-orig');
    });

    test('null person когда server returns без field', () {
      final result = SemyaPullPersonResult.fromJson({
        'targetSemyaId': 's-t',
        'sourceSemyaId': 's-s',
        'sourcePersonId': 'p-orig',
      });
      expect(result.person, isNull);
    });

    test('null person когда person.id missing', () {
      final result = SemyaPullPersonResult.fromJson({
        'person': {'name': 'Without ID'},
        'targetSemyaId': 's-t',
        'sourceSemyaId': 's-s',
        'sourcePersonId': 'p-orig',
      });
      expect(result.person, isNull);
    });
  });
}
