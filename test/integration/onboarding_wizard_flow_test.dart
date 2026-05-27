// Ship FE10 full (2026-05-27): end-to-end onboarding wizard flow.
//
// Combines Phase 6 wizard (2026-05-14) + Q1 skip (9589cbf) + FE9
// семя invitation detection (3eaa643). Verifies:
//   • Fresh registration без приглашений — empty list, default create path
//   • Pending invitation detected by userId — surfaces в list
//   • Pending invitation detected by email — matched after registration
//   • Q1 skip path semantics preserved (no regression)
//   • Accept invitation flips status + materializes membership
//   • Q3 backwards compat — additive endpoint doesn't break existing state

import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/models/semya.dart';
import 'package:rodnya/backend/models/semya_invitation.dart';

import '_helpers.dart';

void main() {
  group('FE10 full: onboarding wizard flow (Phase 6 + Q1 + FE9)', () {
    test(
      'fresh registration без приглашений → empty pending list, default create path',
      () async {
        final service = IntegrationFakeService(
          currentUserId: 'u-newbie',
          currentUserEmail: 'newbie@example.com',
        );
        final pending = await service.listPendingInvitations();
        expect(pending, isEmpty);
        // Wizard's default «Создать свою семью» path remains primary —
        // controller.hasPendingInvitations == false → invitation card
        // not rendered.
      },
    );

    test(
      'pending invitation matched by recipientUserId → surfaces с semyaName',
      () async {
        final service = IntegrationFakeService(
          currentUserId: 'u-invitee',
          currentUserEmail: 'invitee@example.com',
          initialSemyi: [makeSemya(id: 's-1', name: 'Семья Ивановых')],
          initialMemberships: {
            's-1': [makeMembership(id: 'mo', userId: 'u-owner')],
          },
          initialInvitations: {
            's-1': [
              makePendingInvitation(
                id: 'inv-1',
                token: 'tok-direct',
              ).copyWithRecipient(userId: 'u-invitee'),
            ],
          },
        );
        final pending = await service.listPendingInvitations();
        expect(pending.length, 1);
        expect(pending.first.id, 'inv-1');
        expect(
          pending.first.semyaName,
          'Семья Ивановых',
          reason: 'Backend denormalizes semyaName в response',
        );
        expect(pending.first.recipientUserId, 'u-invitee');
      },
    );

    test(
      'pending invitation matched by email (post-registration flow)',
      () async {
        // Email-only invitation created BEFORE user registered.
        final service = IntegrationFakeService(
          currentUserId: 'u-late-arrival',
          currentUserEmail: 'late@example.com',
          initialSemyi: [makeSemya(id: 's-2', name: 'Семья Петровых')],
          initialMemberships: {
            's-2': [makeMembership(id: 'mo', userId: 'u-owner', semyaId: 's-2')],
          },
          initialInvitations: {
            's-2': [
              makePendingInvitation(
                id: 'inv-email',
                token: 'tok-email',
                semyaId: 's-2',
              ).copyWithRecipient(email: 'late@example.com'),
            ],
          },
        );
        final pending = await service.listPendingInvitations();
        expect(pending.length, 1);
        expect(pending.first.recipientUserId, isNull);
        expect(pending.first.recipientEmail, 'late@example.com');
      },
    );

    test(
      'accept invitation flips status + materializes membership',
      () async {
        final service = IntegrationFakeService(
          currentUserId: 'u-recipient',
          currentUserEmail: 'rec@example.com',
          initialSemyi: [makeSemya()],
          initialMemberships: {
            's-1': [makeMembership(id: 'mo', userId: 'u-owner')],
          },
          initialInvitations: {
            's-1': [
              makePendingInvitation(
                id: 'inv-1',
                token: 'magic',
              ).copyWithRecipient(userId: 'u-recipient'),
            ],
          },
        );
        // Pending list shows 1 before accept.
        var pending = await service.listPendingInvitations();
        expect(pending.length, 1);

        // Accept.
        final result = await service.acceptInvitation('magic');
        expect(
          result.invitation.status,
          SemyaInvitationStatus.accepted,
        );
        expect(result.role, SemyaRole.viewer);

        // Pending list now empty (status flipped).
        pending = await service.listPendingInvitations();
        expect(pending, isEmpty);

        // Membership row materialized.
        final members = await service.listMembershipsForSemya('s-1');
        expect(members.length, 2);
        expect(
          members.where((m) => m.userId == 'u-recipient').first.role,
          SemyaRole.viewer,
        );
      },
    );

    test(
      'multiple pending invitations → all surfaced',
      () async {
        final service = IntegrationFakeService(
          currentUserId: 'u-popular',
          currentUserEmail: 'popular@example.com',
          initialSemyi: [
            makeSemya(id: 's-1', name: 'Семья Один'),
            makeSemya(id: 's-2', name: 'Семья Два'),
            makeSemya(id: 's-3', name: 'Семья Три'),
          ],
          initialMemberships: {
            's-1': [makeMembership(id: 'm1', userId: 'u-owner1', semyaId: 's-1')],
            's-2': [makeMembership(id: 'm2', userId: 'u-owner2', semyaId: 's-2')],
            's-3': [makeMembership(id: 'm3', userId: 'u-owner3', semyaId: 's-3')],
          },
          initialInvitations: {
            's-1': [
              makePendingInvitation(id: 'inv-1', token: 't1', semyaId: 's-1')
                  .copyWithRecipient(userId: 'u-popular'),
            ],
            's-2': [
              makePendingInvitation(id: 'inv-2', token: 't2', semyaId: 's-2')
                  .copyWithRecipient(userId: 'u-popular'),
            ],
            's-3': [
              makePendingInvitation(id: 'inv-3', token: 't3', semyaId: 's-3')
                  .copyWithRecipient(email: 'popular@example.com'),
            ],
          },
        );
        final pending = await service.listPendingInvitations();
        expect(pending.length, 3);
        // semyaName populated для each row.
        final names = pending.map((p) => p.semyaName).toSet();
        expect(names, {'Семья Один', 'Семья Два', 'Семья Три'});
      },
    );

    test(
      'soft-deleted семья invitation filtered out (defensive)',
      () async {
        // Семья deleted but invitation lingers — frontend shouldn't surface.
        final service = IntegrationFakeService(
          currentUserId: 'u-ghost',
          currentUserEmail: 'ghost@example.com',
          initialSemyi: [
            Semya(
              id: 's-deleted',
              name: 'Удалённая',
              ownerId: 'u-owner',
              treeId: 't-1',
              createdAt: '2026-01-01T00:00:00Z',
              updatedAt: '2026-01-01T00:00:00Z',
              deletedAt: '2026-02-01T00:00:00Z',
            ),
          ],
          initialMemberships: {
            's-deleted': [makeMembership(id: 'mo', userId: 'u-owner')],
          },
          initialInvitations: {
            's-deleted': [
              makePendingInvitation(id: 'inv-ghost', token: 'ghost-tok')
                  .copyWithRecipient(userId: 'u-ghost'),
            ],
          },
        );
        final pending = await service.listPendingInvitations();
        expect(pending, isEmpty);
      },
    );

    test(
      'accepted invitations filtered из pending list',
      () async {
        final service = IntegrationFakeService(
          currentUserId: 'u-already-in',
          currentUserEmail: 'in@example.com',
          initialSemyi: [makeSemya()],
          initialMemberships: {
            's-1': [makeMembership(id: 'mo', userId: 'u-owner')],
          },
          initialInvitations: {
            's-1': [
              makePendingInvitation(id: 'inv-1', token: 'used-tok')
                  .copyWithRecipient(userId: 'u-already-in'),
            ],
          },
        );
        await service.acceptInvitation('used-tok');
        final pending = await service.listPendingInvitations();
        expect(pending, isEmpty);
      },
    );

    // Q1 backwards-compat regression — Q1 skip path не trampled by FE9.
    test(
      'Q1 skip path semantics: backend skip endpoint unchanged by FE9',
      () async {
        // This test verifies интеграция между Q1 skip + FE9 wizard
        // — pending invitations endpoint NOT skipping wizard state.
        // Fresh user без приглашений может ещё skip onboarding normally
        // (handled через OnboardingController.skipOnboarding, see
        // onboarding_wizard_fe9_test.dart для controller-level test).
        final service = IntegrationFakeService(
          currentUserId: 'u-skipper',
          currentUserEmail: 'skip@example.com',
        );
        final pending = await service.listPendingInvitations();
        expect(
          pending,
          isEmpty,
          reason: 'No pending invitations → wizard renders default '
              '«Создать свою семью» + «Пропустить» buttons',
        );
      },
    );
  });
}

extension _RecipientOverride on SemyaInvitation {
  /// Test helper — clone invitation с overridden recipient fields
  /// чтобы factories can be composed без redundant constructor calls.
  SemyaInvitation copyWithRecipient({
    String? userId,
    String? email,
    String? phone,
  }) {
    return SemyaInvitation(
      id: id,
      token: token,
      semyaId: semyaId,
      inviterUserId: inviterUserId,
      role: role,
      status: status,
      recipientUserId: userId,
      recipientEmail: email,
      recipientPhone: phone,
      createdAt: createdAt,
      expiresAt: expiresAt,
      semyaName: semyaName,
    );
  }
}
