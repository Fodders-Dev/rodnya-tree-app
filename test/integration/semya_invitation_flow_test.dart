// Ship FE10 partial (2026-05-26): end-to-end invitation flow.
//
// Combines Ship 3 (create) + Ship 4 (accept) backend + FE3 frontend
// (controller + screen). Verifies:
//   • Owner creates invitation → list now contains pending row
//   • Service.createCalls counter increments
//   • Recipient simulates accept (с другим userId) → status flips
//     к accepted + new membership row materialized
//   • Revoke flow flips status к revoked

import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/models/semya.dart';
import 'package:rodnya/backend/models/semya_invitation.dart';
import 'package:rodnya/providers/semya_invitations_controller.dart';

import '_helpers.dart';

void main() {
  group('FE10: invitation flow (Ship 3+4 backend + FE3 frontend)', () {
    test('owner создаёт invitation → list contains pending row', () async {
      final service = IntegrationFakeService(
        currentUserId: 'u-owner',
        initialSemyi: [makeSemya()],
        initialMemberships: {
          's-1': [makeMembership()],
        },
      );
      final controller =
          SemyaInvitationsController(semyaId: 's-1', service: service);
      await controller.load();
      expect(controller.invitations, isEmpty);

      final ok = await controller.sendInvitation(
        role: SemyaRole.editor,
        recipientEmail: 'newbie@example.com',
      );
      expect(ok, isTrue);
      expect(service.createInvitationCalls, 1);

      await controller.load();
      expect(controller.invitations.length, 1);
      expect(controller.invitations.first.role, SemyaRole.editor);
      expect(
        controller.invitations.first.status,
        SemyaInvitationStatus.pending,
      );
      expect(controller.invitations.first.recipientEmail, 'newbie@example.com');
    });

    test(
      'recipient accepts → status accepted + new membership materialized',
      () async {
        // Pre-seed semya + pending invitation (same backend instance —
        // but recipient session uses different userId).
        final ownerSession = IntegrationFakeService(
          currentUserId: 'u-owner',
          initialSemyi: [makeSemya()],
          initialMemberships: {
            's-1': [makeMembership()],
          },
          initialInvitations: {
            's-1': [
              makePendingInvitation(token: 'magic-tok'),
            ],
          },
        );
        // Pre-existing pending invitation observable.
        final ownerCtrl =
            SemyaInvitationsController(semyaId: 's-1', service: ownerSession);
        await ownerCtrl.load();
        expect(ownerCtrl.invitations.first.status, SemyaInvitationStatus.pending);

        // Simulate recipient accepting на той же backend state. В
        // production это две сессии — здесь модель approximates через
        // direct call к service (same fake instance), что mirrors
        // POST /v1/invitation/:token/accept.
        final acceptResult = await ownerSession.acceptInvitation('magic-tok');
        expect(acceptResult.invitation.status, SemyaInvitationStatus.accepted);
        expect(acceptResult.role, SemyaRole.viewer);

        // Membership row materialized.
        final members = await ownerSession.listMembershipsForSemya('s-1');
        expect(members.length, 2); // owner + новый member
        expect(
          members.where((m) => m.userId == 'u-owner').first.role,
          SemyaRole.owner,
        );

        // Frontend list now shows accepted status.
        await ownerCtrl.load();
        expect(
          ownerCtrl.invitations.first.status,
          SemyaInvitationStatus.accepted,
        );
      },
    );

    test('revoke flow flips pending → revoked', () async {
      final service = IntegrationFakeService(
        currentUserId: 'u-owner',
        initialSemyi: [makeSemya()],
        initialMemberships: {
          's-1': [makeMembership()],
        },
        initialInvitations: {
          's-1': [makePendingInvitation(id: 'inv-revoke')],
        },
      );
      final controller =
          SemyaInvitationsController(semyaId: 's-1', service: service);
      await controller.load();
      expect(controller.invitations.first.status, SemyaInvitationStatus.pending);

      final ok = await controller.revoke('inv-revoke');
      expect(ok, isTrue);
      expect(service.revokeInvitationCalls, 1);

      await controller.load();
      expect(controller.invitations.first.status, SemyaInvitationStatus.revoked);
    });

    test(
      'accept rejects уже accepted invitation с INVITATION_NOT_PENDING',
      () async {
        final service = IntegrationFakeService(
          currentUserId: 'u-recipient',
          initialSemyi: [makeSemya()],
          initialMemberships: {
            's-1': [makeMembership()],
          },
          initialInvitations: {
            's-1': [makePendingInvitation(token: 'one-shot-tok')],
          },
        );
        // First accept succeeds.
        await service.acceptInvitation('one-shot-tok');
        // Second accept rejected.
        await expectLater(
          service.acceptInvitation('one-shot-tok'),
          throwsA(
            isA<SemyaError>().having(
              (e) => e.code,
              'code',
              'INVITATION_NOT_PENDING',
            ),
          ),
        );
      },
    );
  });
}
