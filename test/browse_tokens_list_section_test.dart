// Ship FE6b (2026-05-26): browse-tokens management section tests.
//
// Covers:
//   • Empty state copy
//   • Populated state с newest-first sort
//   • Permission gate: owner sees revoke for all; non-owner-non-creator
//     sees no revoke; editor (creator) sees revoke for own tokens only
//   • Revoke flow: tap → confirm dialog → service call → list refresh
//   • Revoke cancel: no service call
//   • Inline error rendering on list failure
//   • Status badge render для active/expired/revoked

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/semya_capable_family_tree_service.dart';
import 'package:rodnya/backend/models/semya.dart';
import 'package:rodnya/backend/models/semya_browse_token.dart';
import 'package:rodnya/backend/models/semya_invitation.dart';
import 'package:rodnya/backend/models/semya_pull_person_result.dart';
import 'package:rodnya/widgets/browse_tokens_list_section.dart';

class _FakeService implements SemyaCapableFamilyTreeService {
  _FakeService({this.tokens = const [], this.throwOnList, this.throwOnRevoke});

  final List<SemyaBrowseTokenSummary> tokens;
  final SemyaError? throwOnList;
  final SemyaError? throwOnRevoke;

  int listCalls = 0;
  int revokeCalls = 0;
  String? lastRevokeId;

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
  }) async {
    listCalls += 1;
    if (throwOnList != null) throw throwOnList!;
    return tokens;
  }

  @override
  Future<SemyaBrowseTokenSummary> revokeBrowseToken({
    required String semyaId,
    required String tokenId,
  }) async {
    revokeCalls += 1;
    lastRevokeId = tokenId;
    if (throwOnRevoke != null) throw throwOnRevoke!;
    final orig = tokens.firstWhere((t) => t.id == tokenId);
    return SemyaBrowseTokenSummary(
      id: orig.id,
      semyaId: orig.semyaId,
      createdByUserId: orig.createdByUserId,
      createdAt: orig.createdAt,
      expiresAt: orig.expiresAt,
      status: 'revoked',
      revokedAt: '2026-05-26T12:00:00.000Z',
    );
  }

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
}

SemyaBrowseTokenSummary _summary({
  required String id,
  required String createdBy,
  String created = '2026-05-25T00:00:00.000Z',
  String expires = '2026-06-25T00:00:00.000Z',
  String status = 'active',
}) {
  return SemyaBrowseTokenSummary(
    id: id,
    semyaId: 's-1',
    createdByUserId: createdBy,
    createdAt: created,
    expiresAt: expires,
    status: status,
  );
}

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  testWidgets('empty state copy when no tokens', (tester) async {
    final service = _FakeService();
    await tester.pumpWidget(_wrap(
      BrowseTokensListSection(
        semyaId: 's-1',
        callerRole: SemyaRole.owner,
        currentUserId: 'u-1',
        serviceOverride: service,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Активные ссылки'), findsOneWidget);
    expect(find.byKey(const Key('browse-tokens-empty')), findsOneWidget);
    expect(service.listCalls, 1);
  });

  testWidgets('populated state — newest first sort', (tester) async {
    final service = _FakeService(tokens: [
      _summary(id: 't-old', createdBy: 'u-1', created: '2026-05-01T00:00:00Z'),
      _summary(id: 't-new', createdBy: 'u-1', created: '2026-05-26T00:00:00Z'),
      _summary(id: 't-mid', createdBy: 'u-1', created: '2026-05-15T00:00:00Z'),
    ]);
    await tester.pumpWidget(_wrap(
      BrowseTokensListSection(
        semyaId: 's-1',
        callerRole: SemyaRole.owner,
        currentUserId: 'u-1',
        serviceOverride: service,
      ),
    ));
    await tester.pumpAndSettle();
    final rowsFinder = find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith('browse-token-row-'));
    expect(rowsFinder, findsNWidgets(3));
    // First card after section header — newest = t-new.
    final firstKey =
        ((tester.widgetList(rowsFinder).first.key as ValueKey<String>).value);
    expect(firstKey, 'browse-token-row-t-new');
  });

  testWidgets('owner sees revoke for всех active tokens', (tester) async {
    final service = _FakeService(tokens: [
      _summary(id: 't-mine', createdBy: 'u-me'),
      _summary(id: 't-other', createdBy: 'u-other'),
    ]);
    await tester.pumpWidget(_wrap(
      BrowseTokensListSection(
        semyaId: 's-1',
        callerRole: SemyaRole.owner,
        currentUserId: 'u-me',
        serviceOverride: service,
      ),
    ));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('browse-token-revoke-t-mine')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('browse-token-revoke-t-other')),
      findsOneWidget,
    );
  });

  testWidgets(
    'editor sees revoke только для своих созданных tokens',
    (tester) async {
      final service = _FakeService(tokens: [
        _summary(id: 't-mine', createdBy: 'u-me'),
        _summary(id: 't-other', createdBy: 'u-other'),
      ]);
      await tester.pumpWidget(_wrap(
        BrowseTokensListSection(
          semyaId: 's-1',
          callerRole: SemyaRole.editor,
          currentUserId: 'u-me',
          serviceOverride: service,
        ),
      ));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('browse-token-revoke-t-mine')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('browse-token-revoke-t-other')),
        findsNothing,
      );
    },
  );

  testWidgets('revoked/expired tokens — no revoke button', (tester) async {
    final service = _FakeService(tokens: [
      _summary(id: 't-revoked', createdBy: 'u-me', status: 'revoked'),
      _summary(id: 't-expired', createdBy: 'u-me', status: 'expired'),
    ]);
    await tester.pumpWidget(_wrap(
      BrowseTokensListSection(
        semyaId: 's-1',
        callerRole: SemyaRole.owner,
        currentUserId: 'u-me',
        serviceOverride: service,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('browse-token-revoke-t-revoked')), findsNothing);
    expect(find.byKey(const Key('browse-token-revoke-t-expired')), findsNothing);
    expect(find.text('Отозвана'), findsOneWidget);
    expect(find.text('Истекла'), findsOneWidget);
  });

  testWidgets('revoke flow: tap → confirm → service call → row updated',
      (tester) async {
    final service = _FakeService(tokens: [
      _summary(id: 't-1', createdBy: 'u-me'),
    ]);
    await tester.pumpWidget(_wrap(
      BrowseTokensListSection(
        semyaId: 's-1',
        callerRole: SemyaRole.owner,
        currentUserId: 'u-me',
        serviceOverride: service,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('browse-token-revoke-t-1')));
    await tester.pumpAndSettle();
    expect(find.text('Отозвать ссылку?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('revoke-confirm')));
    await tester.pumpAndSettle();
    expect(service.revokeCalls, 1);
    expect(service.lastRevokeId, 't-1');
    // Row status badge becomes «Отозвана» (status changed via in-place
    // replacement).
    expect(find.text('Отозвана'), findsOneWidget);
  });

  testWidgets('revoke cancel — no service call', (tester) async {
    final service = _FakeService(tokens: [
      _summary(id: 't-1', createdBy: 'u-me'),
    ]);
    await tester.pumpWidget(_wrap(
      BrowseTokensListSection(
        semyaId: 's-1',
        callerRole: SemyaRole.owner,
        currentUserId: 'u-me',
        serviceOverride: service,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('browse-token-revoke-t-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('revoke-cancel')));
    await tester.pumpAndSettle();
    expect(service.revokeCalls, 0);
  });

  testWidgets('revoke failure surfaces snackbar', (tester) async {
    final service = _FakeService(
      tokens: [_summary(id: 't-1', createdBy: 'u-me')],
      throwOnRevoke: const SemyaError(
        code: 'TOKEN_ALREADY_REVOKED',
        message: 'Эта ссылка уже отозвана',
      ),
    );
    await tester.pumpWidget(_wrap(
      BrowseTokensListSection(
        semyaId: 's-1',
        callerRole: SemyaRole.owner,
        currentUserId: 'u-me',
        serviceOverride: service,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('browse-token-revoke-t-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('revoke-confirm')));
    await tester.pumpAndSettle();
    expect(service.revokeCalls, 1);
    expect(find.text('Эта ссылка уже отозвана'), findsOneWidget);
  });

  testWidgets('inline error rendering when list fails', (tester) async {
    final service = _FakeService(
      throwOnList: const SemyaError(
        code: 'FORBIDDEN',
        message: 'Нет прав на просмотр',
      ),
    );
    await tester.pumpWidget(_wrap(
      BrowseTokensListSection(
        semyaId: 's-1',
        callerRole: SemyaRole.owner,
        currentUserId: 'u-me',
        serviceOverride: service,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('browse-tokens-error')), findsOneWidget);
    expect(find.text('Нет прав на просмотр'), findsOneWidget);
    expect(find.byKey(const Key('browse-tokens-retry')), findsOneWidget);
  });
}
