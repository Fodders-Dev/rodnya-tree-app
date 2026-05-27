// Ship FE10 full (2026-05-27): end-to-end membership mutation flow.
//
// Combines Ship 3 (PATCH/DELETE membership) backend + FE8 frontend
// (controller + per-row menu + self-leave tile). Verifies:
//   • Role transitions (promote viewer → editor → owner; demote)
//   • Invite-grant toggle (editor-only constraint)
//   • Kick + self-leave happy paths
//   • 4 backend-enforced invariants:
//     - SELF_ROLE_CHANGE_FORBIDDEN
//     - LAST_OWNER_DEMOTE_FORBIDDEN
//     - LAST_OWNER_REMOVE_FORBIDDEN
//     - INVITE_GRANT_ONLY_EDITOR

import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/models/semya.dart';

import '_helpers.dart';

void main() {
  group('FE10 full: membership management (Ship 3 + FE8)', () {
    test('owner promotes viewer → editor → owner via sequential updates',
        () async {
      final service = IntegrationFakeService(
        currentUserId: 'u-owner',
        initialSemyi: [makeSemya()],
        initialMemberships: {
          's-1': [
            makeMembership(id: 'mo', userId: 'u-owner', role: SemyaRole.owner),
            makeMembership(id: 'mv', userId: 'u-target', role: SemyaRole.viewer),
          ],
        },
      );

      // viewer → editor
      final mid = await service.updateMembership(
        semyaId: 's-1',
        userId: 'u-target',
        role: SemyaRole.editor,
      );
      expect(mid.role, SemyaRole.editor);

      // editor → owner
      final final_ = await service.updateMembership(
        semyaId: 's-1',
        userId: 'u-target',
        role: SemyaRole.owner,
      );
      expect(final_.role, SemyaRole.owner);

      // Now 2 owners total.
      final members = await service.listMembershipsForSemya('s-1');
      expect(
        members.where((m) => m.role == SemyaRole.owner).length,
        2,
      );
    });

    test('demote editor → viewer auto-clears hasInviteGrant', () async {
      final service = IntegrationFakeService(
        currentUserId: 'u-owner',
        initialSemyi: [makeSemya()],
        initialMemberships: {
          's-1': [
            makeMembership(id: 'mo', userId: 'u-owner', role: SemyaRole.owner),
            makeMembership(
              id: 'me',
              userId: 'u-editor',
              role: SemyaRole.editor,
              hasInviteGrant: true,
            ),
          ],
        },
      );
      final updated = await service.updateMembership(
        semyaId: 's-1',
        userId: 'u-editor',
        role: SemyaRole.viewer,
      );
      expect(updated.role, SemyaRole.viewer);
      expect(updated.hasInviteGrant, isFalse);
    });

    test('toggle invite-grant on editor row', () async {
      final service = IntegrationFakeService(
        currentUserId: 'u-owner',
        initialSemyi: [makeSemya()],
        initialMemberships: {
          's-1': [
            makeMembership(id: 'mo', userId: 'u-owner', role: SemyaRole.owner),
            makeMembership(id: 'me', userId: 'u-editor', role: SemyaRole.editor),
          ],
        },
      );
      // Grant
      final granted = await service.updateMembership(
        semyaId: 's-1',
        userId: 'u-editor',
        hasInviteGrant: true,
      );
      expect(granted.hasInviteGrant, isTrue);
      // Revoke
      final revoked = await service.updateMembership(
        semyaId: 's-1',
        userId: 'u-editor',
        hasInviteGrant: false,
      );
      expect(revoked.hasInviteGrant, isFalse);
    });

    test('kick non-self member → list shrinks', () async {
      final service = IntegrationFakeService(
        currentUserId: 'u-owner',
        initialSemyi: [makeSemya()],
        initialMemberships: {
          's-1': [
            makeMembership(id: 'mo', userId: 'u-owner', role: SemyaRole.owner),
            makeMembership(id: 'mt', userId: 'u-target', role: SemyaRole.editor),
          ],
        },
      );
      final result = await service.removeMembership(
        semyaId: 's-1',
        userId: 'u-target',
      );
      expect(result.wasSelfLeave, isFalse);
      final members = await service.listMembershipsForSemya('s-1');
      expect(members.length, 1);
      expect(members.first.userId, 'u-owner');
    });

    test('self-leave as non-last-owner succeeds', () async {
      final service = IntegrationFakeService(
        currentUserId: 'u-editor',
        initialSemyi: [makeSemya()],
        initialMemberships: {
          's-1': [
            makeMembership(id: 'mo', userId: 'u-owner', role: SemyaRole.owner),
            makeMembership(id: 'me', userId: 'u-editor', role: SemyaRole.editor),
          ],
        },
      );
      final result = await service.removeMembership(
        semyaId: 's-1',
        userId: 'u-editor',
      );
      expect(result.wasSelfLeave, isTrue);
      final members = await service.listMembershipsForSemya('s-1');
      expect(members.length, 1);
      expect(members.first.userId, 'u-owner');
    });

    // ============== Invariants ==============

    test(
      'SELF_ROLE_CHANGE_FORBIDDEN: actor cannot change own role',
      () async {
        final service = IntegrationFakeService(
          currentUserId: 'u-owner',
          initialSemyi: [makeSemya()],
          initialMemberships: {
            's-1': [
              makeMembership(id: 'mo', userId: 'u-owner', role: SemyaRole.owner),
              makeMembership(id: 'm2', userId: 'u-other', role: SemyaRole.owner),
            ],
          },
        );
        await expectLater(
          service.updateMembership(
            semyaId: 's-1',
            userId: 'u-owner',
            role: SemyaRole.editor,
          ),
          throwsA(
            isA<SemyaError>().having(
              (e) => e.code,
              'code',
              'SELF_ROLE_CHANGE_FORBIDDEN',
            ),
          ),
        );
      },
    );

    test(
      'LAST_OWNER_DEMOTE_FORBIDDEN: cannot demote sole owner',
      () async {
        final service = IntegrationFakeService(
          currentUserId: 'u-actor',
          initialSemyi: [makeSemya()],
          initialMemberships: {
            's-1': [
              makeMembership(id: 'mo', userId: 'u-owner', role: SemyaRole.owner),
              makeMembership(id: 'ma', userId: 'u-actor', role: SemyaRole.owner),
            ],
          },
        );
        // First demote u-owner — leaves u-actor as sole owner.
        await service.updateMembership(
          semyaId: 's-1',
          userId: 'u-owner',
          role: SemyaRole.editor,
        );
        // Now demoting u-actor would leave 0 owners — but u-actor cannot
        // demote self (SELF_ROLE_CHANGE_FORBIDDEN fires first).
        // Construct fresh service где actor != last owner.
        final service2 = IntegrationFakeService(
          currentUserId: 'u-actor',
          initialSemyi: [makeSemya()],
          initialMemberships: {
            's-1': [
              makeMembership(id: 'mo', userId: 'u-lone', role: SemyaRole.owner),
              makeMembership(id: 'ma', userId: 'u-actor', role: SemyaRole.editor),
            ],
          },
        );
        await expectLater(
          service2.updateMembership(
            semyaId: 's-1',
            userId: 'u-lone',
            role: SemyaRole.editor,
          ),
          throwsA(
            isA<SemyaError>().having(
              (e) => e.code,
              'code',
              'LAST_OWNER_DEMOTE_FORBIDDEN',
            ),
          ),
        );
      },
    );

    test(
      'LAST_OWNER_REMOVE_FORBIDDEN: cannot remove last owner',
      () async {
        final service = IntegrationFakeService(
          currentUserId: 'u-owner',
          initialSemyi: [makeSemya()],
          initialMemberships: {
            's-1': [
              makeMembership(id: 'mo', userId: 'u-owner', role: SemyaRole.owner),
              makeMembership(id: 'me', userId: 'u-editor', role: SemyaRole.editor),
            ],
          },
        );
        // Self-leave as sole owner → forbidden.
        await expectLater(
          service.removeMembership(
            semyaId: 's-1',
            userId: 'u-owner',
          ),
          throwsA(
            isA<SemyaError>().having(
              (e) => e.code,
              'code',
              'LAST_OWNER_REMOVE_FORBIDDEN',
            ),
          ),
        );
      },
    );

    test(
      'INVITE_GRANT_ONLY_EDITOR: toggle на non-editor rejected',
      () async {
        final service = IntegrationFakeService(
          currentUserId: 'u-owner',
          initialSemyi: [makeSemya()],
          initialMemberships: {
            's-1': [
              makeMembership(id: 'mo', userId: 'u-owner', role: SemyaRole.owner),
              makeMembership(id: 'mv', userId: 'u-viewer', role: SemyaRole.viewer),
            ],
          },
        );
        await expectLater(
          service.updateMembership(
            semyaId: 's-1',
            userId: 'u-viewer',
            hasInviteGrant: true,
          ),
          throwsA(
            isA<SemyaError>().having(
              (e) => e.code,
              'code',
              'INVITE_GRANT_ONLY_EDITOR',
            ),
          ),
        );
      },
    );

    test(
      'promote к owner clears hasInviteGrant — owners implicit invite power',
      () async {
        final service = IntegrationFakeService(
          currentUserId: 'u-owner',
          initialSemyi: [makeSemya()],
          initialMemberships: {
            's-1': [
              makeMembership(id: 'mo', userId: 'u-owner', role: SemyaRole.owner),
              makeMembership(
                id: 'me',
                userId: 'u-editor',
                role: SemyaRole.editor,
                hasInviteGrant: true,
              ),
            ],
          },
        );
        final promoted = await service.updateMembership(
          semyaId: 's-1',
          userId: 'u-editor',
          role: SemyaRole.owner,
        );
        expect(promoted.role, SemyaRole.owner);
        expect(
          promoted.hasInviteGrant,
          isFalse,
          reason: 'Owner role auto-clears explicit invite grant',
        );
      },
    );
  });
}
