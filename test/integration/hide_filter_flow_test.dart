// Ship FE10 partial (2026-05-26): end-to-end hide-filter flow.
//
// Ship 8 backend + FE7 frontend. Verifies per-user privacy invariant:
//   • Hide affects ТОЛЬКО caller; не affects other members
//   • Cross-семя hides isolated (twin person в другой семе не hidden)
//   • Idempotent mutations (re-add no-op, unknown remove no-op)
//   • Empty add+remove rejected с INVALID_INPUT

import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/models/semya.dart';

import '_helpers.dart';

void main() {
  group('FE10: hide filter end-to-end (Ship 8 + FE7)', () {
    test('initial state empty → add person → listed', () async {
      final service = IntegrationFakeService(
        currentUserId: 'u-me',
        initialSemyi: [makeSemya()],
        initialMemberships: {
          's-1': [
            makeMembership(userId: 'u-me', role: SemyaRole.viewer),
          ],
        },
      );
      var hidden = await service.listHiddenPersonIds(semyaId: 's-1');
      expect(hidden, isEmpty);

      final updated = await service.updateHideFilter(
        semyaId: 's-1',
        addPersonIds: const ['p-skeleton'],
      );
      expect(updated, contains('p-skeleton'));
      expect(service.updateHideCalls, 1);

      hidden = await service.listHiddenPersonIds(semyaId: 's-1');
      expect(hidden, ['p-skeleton']);
    });

    test('hide → unhide cycle clears list', () async {
      final service = IntegrationFakeService(
        currentUserId: 'u-me',
        initialSemyi: [makeSemya()],
        initialMemberships: {
          's-1': [makeMembership(userId: 'u-me', role: SemyaRole.editor)],
        },
        initialHideFilter: {
          's-1': {'p-A', 'p-B'},
        },
      );
      var hidden = await service.listHiddenPersonIds(semyaId: 's-1');
      expect(hidden.toSet(), {'p-A', 'p-B'});

      await service.updateHideFilter(
        semyaId: 's-1',
        removePersonIds: const ['p-A'],
      );
      hidden = await service.listHiddenPersonIds(semyaId: 's-1');
      expect(hidden, ['p-B']);

      await service.updateHideFilter(
        semyaId: 's-1',
        removePersonIds: const ['p-B'],
      );
      hidden = await service.listHiddenPersonIds(semyaId: 's-1');
      expect(hidden, isEmpty);
    });

    test(
      'mutations idempotent — re-add no-op, unknown remove no-op',
      () async {
        final service = IntegrationFakeService(
          currentUserId: 'u-me',
          initialSemyi: [makeSemya()],
          initialMemberships: {
            's-1': [makeMembership(userId: 'u-me')],
          },
          initialHideFilter: {
            's-1': {'p-existing'},
          },
        );
        // Re-add already-hidden — no duplicate.
        await service.updateHideFilter(
          semyaId: 's-1',
          addPersonIds: const ['p-existing'],
        );
        final after = await service.listHiddenPersonIds(semyaId: 's-1');
        expect(after.length, 1);

        // Remove unknown — silent no-op.
        await service.updateHideFilter(
          semyaId: 's-1',
          removePersonIds: const ['p-doesnt-exist'],
        );
        final stillThere = await service.listHiddenPersonIds(semyaId: 's-1');
        expect(stillThere, ['p-existing']);
      },
    );

    test('empty add+remove → INVALID_INPUT', () async {
      final service = IntegrationFakeService(
        currentUserId: 'u-me',
        initialSemyi: [makeSemya()],
        initialMemberships: {
          's-1': [makeMembership(userId: 'u-me')],
        },
      );
      await expectLater(
        service.updateHideFilter(semyaId: 's-1'),
        throwsA(
          isA<SemyaError>().having(
            (e) => e.code,
            'code',
            'INVALID_INPUT',
          ),
        ),
      );
    });

    test(
      'privacy invariant: hide scoped per-user — другой user sees pristine',
      () async {
        // User A hides person P.
        final serviceA = IntegrationFakeService(
          currentUserId: 'u-A',
          initialSemyi: [makeSemya()],
          initialMemberships: {
            's-1': [
              makeMembership(id: 'mA', userId: 'u-A'),
              makeMembership(id: 'mB', userId: 'u-B'),
            ],
          },
        );
        await serviceA.updateHideFilter(
          semyaId: 's-1',
          addPersonIds: const ['p-private'],
        );
        final hiddenA = await serviceA.listHiddenPersonIds(semyaId: 's-1');
        expect(hiddenA, ['p-private']);

        // User B (separate session, separate fake instance) — empty.
        final serviceB = IntegrationFakeService(
          currentUserId: 'u-B',
          initialSemyi: [makeSemya()],
          initialMemberships: {
            's-1': [
              makeMembership(id: 'mA', userId: 'u-A'),
              makeMembership(id: 'mB', userId: 'u-B'),
            ],
          },
        );
        final hiddenB = await serviceB.listHiddenPersonIds(semyaId: 's-1');
        expect(
          hiddenB,
          isEmpty,
          reason: 'hide filter rows are per-(semya, user) — другой user не affected',
        );
      },
    );
  });
}
