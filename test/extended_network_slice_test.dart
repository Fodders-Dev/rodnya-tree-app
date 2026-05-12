import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/models/extended_network_slice.dart';

void main() {
  group('ExtendedNetworkSlice.fromJson', () {
    test('parse полного payload\'а с graphPersons, edges, ownerMap', () {
      final slice = ExtendedNetworkSlice.fromJson({
        'graphPersons': [
          {
            'id': 'gp-1',
            'name': 'Я',
            'gender': 'male',
            'birthDate': '1990-01-01',
            'deathDate': null,
            'photoUrl': null,
            'isAlive': true,
            'hopDistance': 0,
          },
          {
            'id': 'gp-2',
            'name': 'Бабушка',
            'gender': 'female',
            'birthDate': '1930-05-12',
            'deathDate': null,
            'photoUrl': 'https://example.com/p2.jpg',
            'isAlive': true,
            'hopDistance': 2,
          },
        ],
        'graphRelations': [
          {
            'id': 'r-1',
            'person1Id': 'gp-2',
            'person2Id': 'gp-1',
            'relation1to2': 'grandmother',
            'relation2to1': 'grandchild',
          },
        ],
        'branchMembership': {
          'gp-1': ['tree-mine'],
          'gp-2': ['tree-mine', 'tree-cousin'],
        },
        'ownerMap': {
          'gp-2': {
            'userId': 'user-cousin',
            'displayName': 'Кузина Маша',
            'photoUrl': null,
          },
        },
        'stats': {
          'totalCount': 2,
          'myCount': 1,
          'extendedCount': 1,
          'anonymousCount': 0,
          'maxHopsReached': false,
          'capReached': false,
        },
      });

      expect(slice.graphPersons.length, 2);
      expect(slice.graphPersons.first.id, 'gp-1');
      expect(slice.graphPersons.first.hopDistance, 0);
      expect(slice.graphPersons.last.name, 'Бабушка');

      expect(slice.graphRelations.length, 1);
      expect(slice.graphRelations.first.relation1to2, 'grandmother');

      expect(slice.branchMembership['gp-2'], ['tree-mine', 'tree-cousin']);

      // Sparse: gp-1 НЕ в ownerMap (viewer-owned).
      expect(slice.ownerMap.containsKey('gp-1'), isFalse);
      expect(slice.ownerMap.containsKey('gp-2'), isTrue);
      expect(slice.ownerMap['gp-2']!.displayName, 'Кузина Маша');

      expect(slice.stats.totalCount, 2);
      expect(slice.stats.myCount, 1);
      expect(slice.stats.capReached, isFalse);
    });

    test('sparse ownerMap helpers: getOwnerInfo / isForeignNode', () {
      final slice = ExtendedNetworkSlice.fromJson({
        'graphPersons': [
          {'id': 'gp-1', 'name': 'Я', 'isAlive': true, 'hopDistance': 0},
          {'id': 'gp-2', 'name': 'Чужой', 'isAlive': true, 'hopDistance': 2},
        ],
        'graphRelations': [],
        'branchMembership': {},
        'ownerMap': {
          'gp-2': {
            'userId': 'user-other',
            'displayName': 'Other',
            'photoUrl': null,
          },
        },
        'stats': {
          'totalCount': 2,
          'myCount': 1,
          'extendedCount': 1,
          'anonymousCount': 0,
          'maxHopsReached': false,
          'capReached': false,
        },
      });
      expect(slice.getOwnerInfo('gp-1'), isNull);
      expect(slice.getOwnerInfo('gp-2'), isNotNull);
      expect(slice.isForeignNode('gp-1'), isFalse);
      expect(slice.isForeignNode('gp-2'), isTrue);
    });

    test('defensive parsing: missing graphPersons → empty list', () {
      final slice = ExtendedNetworkSlice.fromJson({
        'stats': {
          'totalCount': 0,
          'myCount': 0,
          'extendedCount': 0,
          'anonymousCount': 0,
          'maxHopsReached': false,
          'capReached': false,
        },
      });
      expect(slice.graphPersons, isEmpty);
      expect(slice.graphRelations, isEmpty);
      expect(slice.branchMembership, isEmpty);
      expect(slice.ownerMap, isEmpty);
    });

    test('defensive parsing: malformed list entries skipped', () {
      final slice = ExtendedNetworkSlice.fromJson({
        'graphPersons': [
          {'id': 'gp-1', 'isAlive': true, 'hopDistance': 0},
          'not-a-map',
          null,
          {'id': 'gp-2', 'isAlive': true, 'hopDistance': 1},
        ],
        'graphRelations': null,
        'stats': {
          'totalCount': 2,
          'myCount': 0,
          'extendedCount': 0,
          'anonymousCount': 0,
          'maxHopsReached': false,
          'capReached': false,
        },
      });
      expect(slice.graphPersons.length, 2);
      expect(slice.graphRelations, isEmpty);
    });

    test('isAlive default true когда missing', () {
      final slice = ExtendedNetworkSlice.fromJson({
        'graphPersons': [
          {'id': 'gp-1', 'hopDistance': 0},
        ],
      });
      expect(slice.graphPersons.first.isAlive, isTrue);
    });

    test('hopDistance numeric coercion', () {
      final slice = ExtendedNetworkSlice.fromJson({
        'graphPersons': [
          {'id': 'gp-1', 'isAlive': true, 'hopDistance': '3'},
          {'id': 'gp-2', 'isAlive': true, 'hopDistance': 2.7},
          {'id': 'gp-3', 'isAlive': true, 'hopDistance': 'abc'},
          {'id': 'gp-4', 'isAlive': true, 'hopDistance': null},
        ],
      });
      expect(slice.graphPersons[0].hopDistance, 3);
      expect(slice.graphPersons[1].hopDistance, 2);
      expect(slice.graphPersons[2].hopDistance, 0);
      expect(slice.graphPersons[3].hopDistance, 0);
    });

    test('nullable strings: empty strings → null', () {
      final slice = ExtendedNetworkSlice.fromJson({
        'graphPersons': [
          {
            'id': 'gp-1',
            'name': '',
            'photoUrl': '',
            'birthDate': '1990',
            'isAlive': true,
            'hopDistance': 0,
          },
        ],
      });
      expect(slice.graphPersons.first.name, isNull);
      expect(slice.graphPersons.first.photoUrl, isNull);
      expect(slice.graphPersons.first.birthDate, '1990');
    });
  });

  group('ExtendedNetworkSlice round-trip', () {
    test('toJson → fromJson preserves all fields', () {
      const original = ExtendedNetworkSlice(
        graphPersons: [
          ExtendedNetworkPerson(
            id: 'gp-1',
            name: 'Я',
            gender: 'male',
            birthDate: '1990-01-01',
            deathDate: null,
            photoUrl: null,
            isAlive: true,
            hopDistance: 0,
          ),
        ],
        graphRelations: [
          ExtendedNetworkRelation(
            id: 'r-1',
            person1Id: 'gp-1',
            person2Id: 'gp-2',
            relation1to2: 'parent',
            relation2to1: 'child',
          ),
        ],
        branchMembership: {
          'gp-1': ['tree-mine'],
        },
        ownerMap: {
          'gp-2': ExtendedNetworkOwnerInfo(
            userId: 'user-other',
            displayName: 'Other',
            photoUrl: 'https://example.com/p.jpg',
          ),
        },
        stats: ExtendedNetworkStats(
          totalCount: 1,
          myCount: 1,
          extendedCount: 0,
          anonymousCount: 0,
          maxHopsReached: false,
          capReached: false,
        ),
      );
      final roundtrip =
          ExtendedNetworkSlice.fromJson(original.toJson());
      expect(roundtrip.graphPersons.length, 1);
      expect(roundtrip.graphPersons.first.id, 'gp-1');
      expect(roundtrip.graphRelations.first.relation1to2, 'parent');
      expect(roundtrip.branchMembership['gp-1'], ['tree-mine']);
      expect(roundtrip.ownerMap['gp-2']!.displayName, 'Other');
      expect(roundtrip.stats.totalCount, 1);
    });

    test('empty constant', () {
      expect(ExtendedNetworkSlice.empty.graphPersons, isEmpty);
      expect(ExtendedNetworkSlice.empty.stats.totalCount, 0);
    });
  });

  group('ExtendedNetworkStats.fromJson', () {
    test('coerces numeric values, defaults для missing', () {
      final stats = ExtendedNetworkStats.fromJson({
        'totalCount': '42',
        'myCount': 10,
      });
      expect(stats.totalCount, 42);
      expect(stats.myCount, 10);
      expect(stats.extendedCount, 0);
      expect(stats.maxHopsReached, isFalse);
      expect(stats.capReached, isFalse);
    });
  });
}
