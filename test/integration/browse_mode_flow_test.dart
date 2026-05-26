// Ship FE10 partial (2026-05-26): end-to-end browse-mode flow.
//
// Ship 7 backend + FE6a/FE6b frontend. Verifies полный lifecycle:
//   • Owner creates token (FE6a share modal)
//   • Token appears в list (FE6b BrowseTokensListSection)
//   • Anonymous viewer fetches /browse/{token} → BrowsedSemyaTree
//   • Owner revokes (FE6b per-row action)
//   • Subsequent fetchBrowseTree returns TOKEN_REVOKED

import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/models/semya.dart';

import '_helpers.dart';

void main() {
  group('FE10: browse mode end-to-end (Ship 7 + FE6a/FE6b)', () {
    test('owner creates token → appears in list → fetchable anonymously',
        () async {
      final service = IntegrationFakeService(
        currentUserId: 'u-owner',
        initialSemyi: [makeSemya()],
        initialMemberships: {
          's-1': [makeMembership()],
        },
      );
      // Start state — нет tokens.
      var summaries = await service.listBrowseTokens(semyaId: 's-1');
      expect(summaries, isEmpty);

      // Owner creates token (FE6a share modal flow).
      final created = await service.createBrowseToken(semyaId: 's-1');
      expect(created.token, isNotEmpty);
      expect(created.shareUrl, contains(created.token));
      expect(service.createBrowseTokenCalls, 1);

      // FE6b management section lists active token.
      summaries = await service.listBrowseTokens(semyaId: 's-1');
      expect(summaries.length, 1);
      expect(summaries.first.status, 'active');
      expect(summaries.first.createdByUserId, 'u-owner');

      // Anonymous viewer resolves token → tree summary.
      final tree = await service.fetchBrowseTree(created.token);
      expect(tree.semyaId, 's-1');
      expect(tree.semyaName, 'Семья Тест');
      expect(tree.treeId, 't-1');
      expect(service.fetchBrowseTreeCalls, 1);
    });

    test('revoked token → fetchBrowseTree returns TOKEN_REVOKED',
        () async {
      final service = IntegrationFakeService(
        currentUserId: 'u-owner',
        initialSemyi: [makeSemya()],
        initialMemberships: {
          's-1': [makeMembership()],
        },
      );
      final created = await service.createBrowseToken(semyaId: 's-1');
      final summaries = await service.listBrowseTokens(semyaId: 's-1');
      expect(summaries.first.status, 'active');

      // Owner revokes.
      final revoked = await service.revokeBrowseToken(
        semyaId: 's-1',
        tokenId: summaries.first.id,
      );
      expect(revoked.status, 'revoked');

      // Subsequent anonymous fetch returns TOKEN_REVOKED.
      await expectLater(
        service.fetchBrowseTree(created.token),
        throwsA(
          isA<SemyaError>().having(
            (e) => e.code,
            'code',
            'TOKEN_REVOKED',
          ),
        ),
      );
    });

    test('double-revoke returns TOKEN_ALREADY_REVOKED', () async {
      final service = IntegrationFakeService(
        currentUserId: 'u-owner',
        initialSemyi: [makeSemya()],
        initialMemberships: {
          's-1': [makeMembership()],
        },
        initialBrowseTokens: {
          's-1': [makeBrowseTokenSummary(id: 'bt-1', status: 'active')],
        },
      );
      await service.revokeBrowseToken(semyaId: 's-1', tokenId: 'bt-1');
      await expectLater(
        service.revokeBrowseToken(semyaId: 's-1', tokenId: 'bt-1'),
        throwsA(
          isA<SemyaError>().having(
            (e) => e.code,
            'code',
            'TOKEN_ALREADY_REVOKED',
          ),
        ),
      );
    });

    test('unknown token → fetchBrowseTree returns TOKEN_NOT_FOUND',
        () async {
      final service = IntegrationFakeService(
        currentUserId: 'u-owner',
        initialSemyi: [makeSemya()],
        initialMemberships: {
          's-1': [makeMembership()],
        },
      );
      await expectLater(
        service.fetchBrowseTree('definitely-not-a-token'),
        throwsA(
          isA<SemyaError>().having(
            (e) => e.code,
            'code',
            'TOKEN_NOT_FOUND',
          ),
        ),
      );
    });

    test('multiple tokens — list returns все, revoke isolates only target',
        () async {
      final service = IntegrationFakeService(
        currentUserId: 'u-owner',
        initialSemyi: [makeSemya()],
        initialMemberships: {
          's-1': [makeMembership()],
        },
      );
      final t1 = await service.createBrowseToken(semyaId: 's-1');
      final t2 = await service.createBrowseToken(semyaId: 's-1');
      final t3 = await service.createBrowseToken(semyaId: 's-1');
      expect(t1.token != t2.token, isTrue);
      expect(t2.token != t3.token, isTrue);

      final summaries = await service.listBrowseTokens(semyaId: 's-1');
      expect(summaries.length, 3);

      // Revoke middle one.
      await service.revokeBrowseToken(
        semyaId: 's-1',
        tokenId: summaries[1].id,
      );

      // Others still active.
      final post = await service.listBrowseTokens(semyaId: 's-1');
      expect(post.where((s) => s.status == 'active').length, 2);
      expect(post.where((s) => s.status == 'revoked').length, 1);

      // Fetch still works для non-revoked.
      final tree1 = await service.fetchBrowseTree(t1.token);
      expect(tree1.semyaId, 's-1');
      final tree3 = await service.fetchBrowseTree(t3.token);
      expect(tree3.semyaId, 's-1');
    });
  });
}
