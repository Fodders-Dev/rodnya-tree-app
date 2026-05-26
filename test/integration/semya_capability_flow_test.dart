// Ship FE10 partial (2026-05-26): семя capability detection + listMySemya
// flow.
//
// FE1 foundation: capability mixin detection + listMySemya endpoint
// wrapping. Tests cross-cutting behaviors:
//   • listMySemya filters soft-deleted семья
//   • findSemyaById returns combined details + caller's membership
//   • Forbidden access throws FORBIDDEN
//   • SEMYA_NOT_FOUND для unknown id
//
// Complements per-controller tests с integrated flow assertions.

import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/models/semya.dart';

import '_helpers.dart';

void main() {
  group('FE10: семя capability + listMySemya (FE1)', () {
    test('listMySemya returns active семья, filters soft-deleted', () async {
      final service = IntegrationFakeService(
        currentUserId: 'u-me',
        initialSemyi: [
          makeSemya(id: 's-active', name: 'Активная'),
          Semya(
            id: 's-deleted',
            name: 'Удалённая',
            ownerId: 'u-me',
            treeId: 't-2',
            createdAt: '2026-01-01T00:00:00Z',
            updatedAt: '2026-01-01T00:00:00Z',
            deletedAt: '2026-02-01T00:00:00Z',
          ),
        ],
      );
      final list = await service.listMySemya();
      expect(list.length, 1);
      expect(list.first.id, 's-active');
      expect(list.first.isActive, isTrue);
      expect(service.listMySemyaCalls, 1);
    });

    test('findSemyaById returns details + membership для member', () async {
      final service = IntegrationFakeService(
        currentUserId: 'u-me',
        initialSemyi: [makeSemya()],
        initialMemberships: {
          's-1': [
            makeMembership(userId: 'u-me', role: SemyaRole.editor),
          ],
        },
      );
      final details = await service.findSemyaById('s-1');
      expect(details, isNotNull);
      expect(details!.semya.id, 's-1');
      expect(details.membership.userId, 'u-me');
      expect(details.callerRole, SemyaRole.editor);
    });

    test('findSemyaById throws FORBIDDEN для non-member', () async {
      final service = IntegrationFakeService(
        currentUserId: 'u-outsider',
        initialSemyi: [makeSemya()],
        initialMemberships: {
          's-1': [makeMembership(userId: 'u-owner')],
        },
      );
      await expectLater(
        service.findSemyaById('s-1'),
        throwsA(
          isA<SemyaError>().having((e) => e.code, 'code', 'FORBIDDEN'),
        ),
      );
    });

    test('findSemyaById throws SEMYA_NOT_FOUND для unknown id', () async {
      final service = IntegrationFakeService(
        currentUserId: 'u-me',
        initialSemyi: [makeSemya()],
      );
      await expectLater(
        service.findSemyaById('s-ghost'),
        throwsA(
          isA<SemyaError>().having((e) => e.code, 'code', 'SEMYA_NOT_FOUND'),
        ),
      );
    });

    test('listMembershipsForSemya returns all members с roles', () async {
      final service = IntegrationFakeService(
        currentUserId: 'u-me',
        initialSemyi: [makeSemya()],
        initialMemberships: {
          's-1': [
            makeMembership(id: 'mo', userId: 'u-owner', role: SemyaRole.owner),
            makeMembership(id: 'me', userId: 'u-ed', role: SemyaRole.editor),
            makeMembership(id: 'mv', userId: 'u-v', role: SemyaRole.viewer),
          ],
        },
      );
      final members = await service.listMembershipsForSemya('s-1');
      expect(members.length, 3);
      expect(members.map((m) => m.role).toSet(), {
        SemyaRole.owner,
        SemyaRole.editor,
        SemyaRole.viewer,
      });
    });
  });
}
