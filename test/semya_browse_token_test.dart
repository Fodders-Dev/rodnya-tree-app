// Ship FE6a (2026-05-26): browse-token model + BrowsedSemyaTree
// parsing tests. Verify shape integrity + edge cases.

import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/models/semya_browse_token.dart';

void main() {
  group('SemyaBrowseToken.fromJson', () {
    test('parses full token shape', () {
      final t = SemyaBrowseToken.fromJson({
        'id': 't-1',
        'semyaId': 's-1',
        'token': 'capability-abc-xyz',
        'createdByUserId': 'u-1',
        'createdAt': '2026-05-26T00:00:00.000Z',
        'expiresAt': '2026-06-25T00:00:00.000Z',
      });
      expect(t.id, 't-1');
      expect(t.semyaId, 's-1');
      expect(t.token, 'capability-abc-xyz');
      expect(t.createdByUserId, 'u-1');
      expect(t.revokedAt, isNull);
      expect(t.lastUsedAt, isNull);
    });

    test('shareUrl composes к rodnya-tree.ru/browse/{token}', () {
      final t = SemyaBrowseToken.fromJson({
        'id': 't-1',
        'semyaId': 's-1',
        'token': 'abc123',
        'createdByUserId': 'u-1',
        'createdAt': '2026-05-26T00:00:00.000Z',
        'expiresAt': '2026-06-25T00:00:00.000Z',
      });
      expect(t.shareUrl, 'https://rodnya-tree.ru/browse/abc123');
    });

    test('isActive false когда revoked', () {
      final t = SemyaBrowseToken.fromJson({
        'id': 't-1',
        'semyaId': 's-1',
        'token': 'abc',
        'createdByUserId': 'u-1',
        'createdAt': '2026-05-01T00:00:00.000Z',
        'expiresAt': '2099-01-01T00:00:00.000Z',
        'revokedAt': '2026-05-15T00:00:00.000Z',
      });
      expect(t.isActive, isFalse);
    });

    test('isActive false когда expiresAt в прошлом', () {
      final t = SemyaBrowseToken.fromJson({
        'id': 't-1',
        'semyaId': 's-1',
        'token': 'abc',
        'createdByUserId': 'u-1',
        'createdAt': '2024-01-01T00:00:00.000Z',
        'expiresAt': '2024-01-02T00:00:00.000Z',
      });
      expect(t.isActive, isFalse);
    });

    test('isActive true для valid non-revoked future-expiry token', () {
      final t = SemyaBrowseToken.fromJson({
        'id': 't-1',
        'semyaId': 's-1',
        'token': 'abc',
        'createdByUserId': 'u-1',
        'createdAt': '2026-05-26T00:00:00.000Z',
        'expiresAt': '2099-01-01T00:00:00.000Z',
      });
      expect(t.isActive, isTrue);
    });
  });

  group('BrowsedSemyaTree.fromJson', () {
    test('parses full browse payload', () {
      final result = BrowsedSemyaTree.fromJson({
        'browse': {
          'semya': {
            'id': 's-1',
            'name': 'Семья Ивановых',
            'description': 'Тест',
          },
          'tree': {
            'id': 't-1',
            'name': 'Дерево',
            'kind': 'family',
          },
          'persons': [
            {
              'id': 'p-1',
              'treeId': 't-1',
              'name': 'Иван Иванов',
              'gender': 'male',
              'birthDate': '1990-05-14',
            },
            {
              'id': 'p-2',
              'treeId': 't-1',
              'name': 'Мария Иванова',
              'gender': 'female',
            },
          ],
          'relations': [
            {
              'id': 'r-1',
              'treeId': 't-1',
              'person1Id': 'p-1',
              'person2Id': 'p-2',
              'relation1to2': 'spouse',
              'relation2to1': 'spouse',
            },
          ],
          'readOnly': true,
          'sessionExpiresAt': '2026-06-25T00:00:00.000Z',
        },
      });
      expect(result.semyaId, 's-1');
      expect(result.semyaName, 'Семья Ивановых');
      expect(result.semyaDescription, 'Тест');
      expect(result.treeId, 't-1');
      expect(result.treeName, 'Дерево');
      expect(result.treeKind, 'family');
      expect(result.persons.length, 2);
      expect(result.persons[0].name, 'Иван Иванов');
      expect(result.persons[0].gender, 'male');
      expect(result.persons[1].gender, 'female');
      expect(result.relations.length, 1);
      expect(result.relations[0].relation1to2, 'spouse');
      expect(result.sessionExpiresAt, '2026-06-25T00:00:00.000Z');
    });

    test('throws когда browse field absent', () {
      expect(
        () => BrowsedSemyaTree.fromJson({'invalid': 'shape'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('handles empty persons/relations lists', () {
      final result = BrowsedSemyaTree.fromJson({
        'browse': {
          'semya': {'id': 's', 'name': 'X'},
          'tree': {'id': 't', 'name': 'T', 'kind': 'family'},
          'persons': [],
          'relations': [],
          'sessionExpiresAt': '2099-01-01',
        },
      });
      expect(result.persons, isEmpty);
      expect(result.relations, isEmpty);
    });

    test('person fields defaulted defensively', () {
      final result = BrowsedSemyaTree.fromJson({
        'browse': {
          'semya': {'id': 's', 'name': 'X'},
          'tree': {'id': 't', 'name': 'T', 'kind': 'family'},
          'persons': [
            {'id': 'p-1', 'treeId': 't', 'name': 'Только имя'},
          ],
          'relations': [],
          'sessionExpiresAt': '2099-01-01',
        },
      });
      expect(result.persons.first.name, 'Только имя');
      expect(result.persons.first.maidenName, isNull);
      expect(result.persons.first.birthDate, isNull);
    });
  });
}
