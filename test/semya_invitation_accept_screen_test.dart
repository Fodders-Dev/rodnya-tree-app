import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rodnya/backend/interfaces/semya_capable_family_tree_service.dart';
import 'package:rodnya/backend/models/deleted_person.dart';
import 'package:rodnya/backend/models/deleted_post.dart';
import 'package:rodnya/backend/models/semya.dart';
import 'package:rodnya/backend/models/semya_browse_token.dart';
import 'package:rodnya/backend/models/semya_invitation.dart';
import 'package:rodnya/backend/models/semya_pull_person_result.dart';
import 'package:rodnya/screens/semya_invitation_accept_screen.dart';
import 'package:rodnya/services/semya_invitation_deep_link_service.dart';

class _FakeSemyaService implements SemyaCapableFamilyTreeService {
  _FakeSemyaService({
    this.previewResult,
    this.previewError,
    this.acceptResult,
    this.acceptError,
    this.declineResult,
    this.holdPreview = false,
  });

  SemyaInvitation? previewResult;
  SemyaError? previewError;
  SemyaInvitationAcceptResult? acceptResult;
  SemyaError? acceptError;
  SemyaInvitation? declineResult;
  final bool holdPreview;
  int acceptCalls = 0;
  int declineCalls = 0;

  final Completer<SemyaInvitation?> _pendingPreview = Completer();

  @override
  Future<SemyaInvitation?> previewInvitation(String token) async {
    if (holdPreview) return _pendingPreview.future;
    if (previewError != null) throw previewError!;
    return previewResult;
  }

  @override
  Future<SemyaInvitationAcceptResult> acceptInvitation(String token) async {
    acceptCalls += 1;
    if (acceptError != null) throw acceptError!;
    return acceptResult!;
  }

  @override
  Future<SemyaInvitation> declineInvitation(String token) async {
    declineCalls += 1;
    return declineResult!;
  }

  @override
  Future<List<Semya>> listMySemya() async => const <Semya>[];

  @override
  Future<SemyaDetails?> findSemyaById(String semyaId) async => null;

  @override
  Future<List<SemyaMembership>> listMembershipsForSemya(
    String semyaId,
  ) async =>
      const <SemyaMembership>[];

  @override
  Future<SemyaInvitation> createInvitation({
    required String semyaId,
    required SemyaRole role,
    String? recipientEmail,
    String? recipientPhone,
    String? recipientUserId,
    String? personId,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<SemyaInvitation>> listInvitationsForSemya(
    String semyaId,
  ) async =>
      const <SemyaInvitation>[];

  @override
  Future<SemyaInvitation> revokeInvitation({
    required String semyaId,
    required String invitationId,
  }) async =>
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
  Future<SemyaMembershipRemoveResult> removeMembership({
    required String semyaId,
    required String userId,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<SemyaInvitation>> listPendingInvitations() async =>
      const <SemyaInvitation>[];

  @override
  Future<SemyaMembership> addMembership({
    required String semyaId,
    required String userId,
    required SemyaRole role,
    bool hasInviteGrant = false,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<DeletedPerson>> listMyDeletedPersons() async =>
      const <DeletedPerson>[];

  @override
  Future<List<DeletedPerson>> listDeletedPersonsForSemya(
    String semyaId,
  ) async =>
      const <DeletedPerson>[];

  @override
  Future<void> restoreDeletedPerson(String deletedPersonId) async {}

  @override
  Future<void> permanentlyDeletePerson(String deletedPersonId) async {}

  @override
  Future<List<DeletedPost>> listMyDeletedPosts() async => const <DeletedPost>[];

  @override
  Future<void> restoreDeletedPost(String deletedPostId) async {}

  @override
  Future<void> permanentlyDeletePost(String deletedPostId) async {}
}

class _FakeDeepLinkService implements SemyaInvitationDeepLinkService {
  int clearCalls = 0;

  @override
  void clearPendingToken() {
    clearCalls += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GoRouter _buildRouter(Widget accept) {
  return GoRouter(
    initialLocation: '/invite/tok',
    routes: [
      GoRoute(
        path: '/invite/tok',
        builder: (context, state) => accept,
      ),
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const Scaffold(body: Text('Главный экран')),
      ),
    ],
  );
}

SemyaInvitation _samplePendingInvitation({
  SemyaInvitationStatus status = SemyaInvitationStatus.pending,
}) {
  return SemyaInvitation(
    id: 'inv-1',
    token: 'tok',
    semyaId: 'semya-1',
    inviterUserId: 'user-owner',
    role: SemyaRole.editor,
    status: status,
    createdAt: '2026-11-27T00:00:00Z',
    expiresAt: '2026-12-27T00:00:00Z',
    semyaName: 'Семья Ивановых',
    inviterName: 'Артём',
    targetPersonName: 'Дядя Павел',
  );
}

void main() {
  testWidgets(
    'density chunk 25: error state — icon/text/CTA fit compactly, CTA is 52dp',
    (tester) async {
      final service = _FakeSemyaService(
        previewError: const SemyaError(
          code: 'INVITATION_NOT_FOUND',
          message: 'not found',
        ),
      );
      final deepLink = _FakeDeepLinkService();
      final router = _buildRouter(
        SemyaInvitationAcceptScreen(
          token: 'tok',
          serviceOverride: service,
          deepLinkServiceOverride: deepLink,
        ),
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text('Приглашение не найдено'), findsWidgets);
      expect(deepLink.clearCalls, 1);

      final cta =
          tester.getRect(find.byKey(const Key('invitation-accept-go-home')));
      expect(
        cta.height,
        52,
        reason: 'CTA «Вернуться на главную» — фиксированные 52dp.',
      );
      expect(
        cta.bottom,
        lessThanOrEqualTo(500),
        reason: 'Ошибка + CTA должны помещаться в верхние 500dp экрана.',
      );

      await tester.tap(find.byKey(const Key('invitation-accept-go-home')));
      await tester.pumpAndSettle();
      expect(find.text('Главный экран'), findsOneWidget);
    },
  );

  testWidgets('processing state renders spinner + label', (tester) async {
    final service = _FakeSemyaService(holdPreview: true);
    final router = _buildRouter(
      SemyaInvitationAcceptScreen(
        token: 'tok',
        serviceOverride: service,
        deepLinkServiceOverride: _FakeDeepLinkService(),
      ),
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Проверяем приглашение...'), findsOneWidget);
    expect(service.acceptCalls, 0);
  });

  testWidgets('preview renders metadata and requires confirm before accept',
      (tester) async {
    final inv = _samplePendingInvitation();
    final service = _FakeSemyaService(
      previewResult: inv,
      acceptResult: SemyaInvitationAcceptResult(
        invitation: inv,
        semyaId: inv.semyaId,
        role: inv.role,
        membershipId: 'mem-1',
      ),
    );
    final deepLink = _FakeDeepLinkService();
    final router = _buildRouter(
      SemyaInvitationAcceptScreen(
        token: 'tok',
        serviceOverride: service,
        deepLinkServiceOverride: deepLink,
      ),
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Семья Ивановых'), findsOneWidget);
    expect(find.textContaining('Артём приглашает вас'), findsOneWidget);
    expect(find.text('Карточка в дереве: Дядя Павел'), findsOneWidget);
    expect(service.acceptCalls, 0);

    await tester.tap(find.byKey(const Key('invitation-accept-confirm')));
    await tester.pumpAndSettle();

    expect(service.acceptCalls, 1);
    expect(deepLink.clearCalls, 1);
    expect(find.text('Главный экран'), findsOneWidget);
  });

  testWidgets('decline button calls declineInvitation and returns home',
      (tester) async {
    final inv = _samplePendingInvitation();
    final declined = _samplePendingInvitation(
      status: SemyaInvitationStatus.declined,
    );
    final service = _FakeSemyaService(
      previewResult: inv,
      declineResult: declined,
    );
    final deepLink = _FakeDeepLinkService();
    final router = _buildRouter(
      SemyaInvitationAcceptScreen(
        token: 'tok',
        serviceOverride: service,
        deepLinkServiceOverride: deepLink,
      ),
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('invitation-accept-decline')));
    await tester.pumpAndSettle();

    expect(service.declineCalls, 1);
    expect(deepLink.clearCalls, 1);
    expect(find.text('Главный экран'), findsOneWidget);
  });

  testWidgets('INVITATION_EXPIRED and FORBIDDEN clear pending token',
      (tester) async {
    for (final code in ['INVITATION_EXPIRED', 'FORBIDDEN']) {
      final service = _FakeSemyaService(
        previewResult: _samplePendingInvitation(),
        acceptError: SemyaError(code: code, message: 'err'),
      );
      final deepLink = _FakeDeepLinkService();
      final router = _buildRouter(
        SemyaInvitationAcceptScreen(
          token: 'tok',
          serviceOverride: service,
          deepLinkServiceOverride: deepLink,
        ),
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('invitation-accept-confirm')));
      await tester.pumpAndSettle();
      expect(deepLink.clearCalls, 1, reason: 'Failed to clear token on $code');
    }
  });
}
