// Ship FE6a (2026-05-26): share modal — verify create button fires
// createBrowseToken, success view shows link с copy/share buttons,
// error inline rendering.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/semya_capable_family_tree_service.dart';
import 'package:rodnya/backend/models/deleted_person.dart';
import 'package:rodnya/backend/models/deleted_post.dart';
import 'package:rodnya/backend/models/semya.dart';
import 'package:rodnya/backend/models/semya_browse_token.dart';
import 'package:rodnya/backend/models/semya_invitation.dart';
import 'package:rodnya/backend/models/semya_pull_person_result.dart';
import 'package:rodnya/widgets/share_browse_token_modal.dart';

class _FakeService implements SemyaCapableFamilyTreeService {
  _FakeService({this.tokenResult, this.throwOnCreate});

  SemyaBrowseToken? tokenResult;
  SemyaError? throwOnCreate;
  int createCalls = 0;
  String? lastSemyaId;

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
  }) async {
    createCalls += 1;
    lastSemyaId = semyaId;
    if (throwOnCreate != null) throw throwOnCreate!;
    if (tokenResult == null) {
      throw const SemyaError(code: 'UNKNOWN', message: 'fake-no-result');
    }
    return tokenResult!;
  }

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

SemyaBrowseToken _sampleToken({String token = 'abc-secret-xyz'}) {
  return SemyaBrowseToken.fromJson({
    'id': 't-1',
    'semyaId': 's-1',
    'token': token,
    'createdByUserId': 'u-1',
    'createdAt': '2026-05-26T00:00:00.000Z',
    'expiresAt': '2026-06-25T00:00:00.000Z',
  });
}

void main() {
  testWidgets('renders header + create button initially', (tester) async {
    final service = _FakeService(tokenResult: _sampleToken());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShareBrowseTokenModal(
            semyaId: 's-1',
            semyaName: 'Семья Тест',
            serviceOverride: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Поделиться деревом'), findsOneWidget);
    expect(find.byKey(const Key('share-browse-create')), findsOneWidget);
    expect(find.textContaining('Семья Тест'), findsOneWidget);
  });

  testWidgets('Create button fires createBrowseToken с semyaId',
      (tester) async {
    final service = _FakeService(tokenResult: _sampleToken());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShareBrowseTokenModal(
            semyaId: 's-active',
            semyaName: 'X',
            serviceOverride: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('share-browse-create')));
    await tester.pumpAndSettle();
    expect(service.createCalls, 1);
    expect(service.lastSemyaId, 's-active');
  });

  testWidgets('Success view renders share link + copy/share buttons',
      (tester) async {
    final service = _FakeService(tokenResult: _sampleToken(token: 'XYZ123'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShareBrowseTokenModal(
            semyaId: 's-1',
            semyaName: 'X',
            serviceOverride: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('share-browse-create')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('share-browse-link')), findsOneWidget);
    expect(
      find.textContaining('https://rodnya-tree.ru/browse/XYZ123'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('share-browse-copy')), findsOneWidget);
    expect(find.byKey(const Key('share-browse-share')), findsOneWidget);
  });

  testWidgets('Error inline rendering когда create fails', (tester) async {
    final service = _FakeService(
      throwOnCreate: const SemyaError(
        code: 'FORBIDDEN',
        message: 'Нет прав на создание ссылки',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShareBrowseTokenModal(
            semyaId: 's-1',
            semyaName: 'X',
            serviceOverride: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('share-browse-create')));
    await tester.pumpAndSettle();
    expect(find.text('Нет прав на создание ссылки'), findsOneWidget);
  });
}
