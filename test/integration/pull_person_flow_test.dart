// Ship FE10 partial (2026-05-26): end-to-end pull-person flow.
//
// Ship 6 backend + FE5 frontend + FE6a entry point. Verifies:
//   • Source person resolved via personRegistry seeding
//   • pullPersonToSemya succeeds → result carries person row
//   • Idempotent: re-pull same person returns same record
//   • Missing source person → PERSON_NOT_FOUND

import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/models/semya.dart';

import '_helpers.dart';

void main() {
  group('FE10: pull-person flow (Ship 6 + FE5 + FE6a entry)', () {
    test('owner pulls person из чужой семя → result has person + meta',
        () async {
      final sourcePerson = makePerson(
        id: 'p-source-1',
        name: 'Алина Соколова',
      );
      final service = IntegrationFakeService(
        currentUserId: 'u-puller',
        initialSemyi: [
          makeSemya(id: 's-source', name: 'Дальняя родня'),
          makeSemya(id: 's-target', name: 'Моя семья'),
        ],
        initialMemberships: {
          's-source': [
            makeMembership(
              id: 'mem-src',
              semyaId: 's-source',
              userId: 'u-puller',
              role: SemyaRole.viewer,
            ),
          ],
          's-target': [
            makeMembership(
              id: 'mem-tgt',
              semyaId: 's-target',
              userId: 'u-puller',
              role: SemyaRole.owner,
            ),
          ],
        },
        personRegistry: {sourcePerson.id: sourcePerson},
      );

      final result = await service.pullPersonToSemya(
        targetSemyaId: 's-target',
        sourceSemyaId: 's-source',
        sourcePersonId: 'p-source-1',
      );
      expect(service.pullCalls, 1);
      expect(result.person, isNotNull);
      expect(result.person!.name, 'Алина Соколова');
      expect(result.targetSemyaId, 's-target');
      expect(result.sourceSemyaId, 's-source');
      expect(result.sourcePersonId, 'p-source-1');
    });

    test('re-pull same person → idempotent (returns same record)', () async {
      final sourcePerson = makePerson(id: 'p-twin', name: 'Дубль');
      final service = IntegrationFakeService(
        currentUserId: 'u-puller',
        initialSemyi: [
          makeSemya(id: 's-source'),
          makeSemya(id: 's-target', treeId: 't-target'),
        ],
        initialMemberships: {
          's-source': [
            makeMembership(
              id: 'mem-src',
              semyaId: 's-source',
              userId: 'u-puller',
              role: SemyaRole.viewer,
            ),
          ],
          's-target': [
            makeMembership(
              id: 'mem-tgt',
              semyaId: 's-target',
              userId: 'u-puller',
              role: SemyaRole.editor,
            ),
          ],
        },
        personRegistry: {sourcePerson.id: sourcePerson},
      );

      final first = await service.pullPersonToSemya(
        targetSemyaId: 's-target',
        sourceSemyaId: 's-source',
        sourcePersonId: 'p-twin',
      );
      final second = await service.pullPersonToSemya(
        targetSemyaId: 's-target',
        sourceSemyaId: 's-source',
        sourcePersonId: 'p-twin',
      );
      expect(first.person!.id, second.person!.id);
      expect(first.person!.name, second.person!.name);
      expect(service.pullCalls, 2);
    });

    test('unknown source person → PERSON_NOT_FOUND', () async {
      final service = IntegrationFakeService(
        currentUserId: 'u-puller',
        initialSemyi: [
          makeSemya(id: 's-source'),
          makeSemya(id: 's-target'),
        ],
        initialMemberships: {
          's-source': [
            makeMembership(
              id: 'mem-src',
              semyaId: 's-source',
              userId: 'u-puller',
              role: SemyaRole.viewer,
            ),
          ],
          's-target': [
            makeMembership(
              id: 'mem-tgt',
              semyaId: 's-target',
              userId: 'u-puller',
              role: SemyaRole.owner,
            ),
          ],
        },
      );
      await expectLater(
        service.pullPersonToSemya(
          targetSemyaId: 's-target',
          sourceSemyaId: 's-source',
          sourcePersonId: 'p-ghost',
        ),
        throwsA(
          isA<SemyaError>().having(
            (e) => e.code,
            'code',
            'PERSON_NOT_FOUND',
          ),
        ),
      );
    });
  });
}
