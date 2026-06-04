// Ship Q4a frontend (2026-05-28, Ship 31b): FE2 «Удалённые» entry
// tile tests.
//
// Covers:
//   • Hidden (SizedBox.shrink) когда семья has no deleted persons
//   • Tile с counter renders когда count > 0
//   • Tap → navigates к SemyaDeletedPersonsScreen
//   • Hidden когда load fails (silent degrade)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/semya_capable_family_tree_service.dart';
import 'package:rodnya/backend/models/deleted_person.dart';
import 'package:rodnya/backend/models/deleted_post.dart';
import 'package:rodnya/backend/models/semya.dart';
import 'package:rodnya/backend/models/semya_browse_token.dart';
import 'package:rodnya/backend/models/semya_invitation.dart';
import 'package:rodnya/backend/models/semya_pull_person_result.dart';
import 'package:rodnya/screens/semya_deleted_persons_screen.dart';
import 'package:rodnya/widgets/deleted_persons_section.dart';

class _FakeSemyaService implements SemyaCapableFamilyTreeService {
  _FakeSemyaService({this.persons = const <DeletedPerson>[], this.throwOnLoad});

  List<DeletedPerson> persons;
  SemyaError? throwOnLoad;

  @override
  Future<List<DeletedPerson>> listDeletedPersonsForSemya(String semyaId) async {
    if (throwOnLoad != null) throw throwOnLoad!;
    return persons;
  }

  @override
  Future<List<DeletedPerson>> listMyDeletedPersons() async =>
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

  // ---- Unused interface surface.

  @override
  Future<List<Semya>> listMySemya() async => const <Semya>[];

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
  }) async =>
      throw UnimplementedError();

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
  Future<SemyaMembership> addMembership({
    required String semyaId,
    required String userId,
    required SemyaRole role,
    bool hasInviteGrant = false,
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
}

DeletedPerson _person(String id) {
  return DeletedPerson.fromJson({
    'id': id,
    'originalPersonId': 'orig-$id',
    'treeId': 't-1',
    'semyaId': 's-1',
    'snapshot': {'name': 'Person $id'},
    'deletedAt': '2026-05-28T00:00:00.000Z',
    'hardDeleteScheduledAt': '2026-06-27T00:00:00.000Z',
    'earliestHardDelete': '2026-05-27T00:00:00.000Z',
  });
}

Widget _wrap(SemyaCapableFamilyTreeService service) => MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            DeletedPersonsSection(
              semyaId: 's-1',
              semyaName: 'Ивановых',
              serviceOverride: service,
            ),
          ],
        ),
      ),
    );

void main() {
  testWidgets('hidden когда семья has no deleted persons', (tester) async {
    final service = _FakeSemyaService();
    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('semya-details-deleted-persons-section')),
      findsNothing,
    );
  });

  testWidgets('renders tile с counter когда count > 0', (tester) async {
    final service = _FakeSemyaService(
      persons: [_person('p-1'), _person('p-2'), _person('p-3')],
    );
    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('semya-details-deleted-persons-section')),
      findsOneWidget,
    );
    expect(find.text('Удалённые родственники (3)'), findsOneWidget);
  });

  testWidgets('tap navigates к SemyaDeletedPersonsScreen', (tester) async {
    final service = _FakeSemyaService(persons: [_person('p-1')]);
    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('semya-details-deleted-persons-section')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SemyaDeletedPersonsScreen), findsOneWidget);
  });

  testWidgets('hidden когда load fails (silent degrade)', (tester) async {
    final service = _FakeSemyaService(
      throwOnLoad: const SemyaError(code: 'FORBIDDEN', message: 'нет доступа'),
    );
    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('semya-details-deleted-persons-section')),
      findsNothing,
    );
  });
}
