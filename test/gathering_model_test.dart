import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/models/gathering.dart';
import 'package:rodnya/models/post.dart' show TreeContentScopeType;

void main() {
  test('Gathering round-trips through json', () {
    final json = <String, dynamic>{
      'id': 'g1',
      'treeId': 'tree-1',
      'branchIds': ['tree-1', 'tree-2'],
      'authorId': 'u1',
      'authorName': 'Анна',
      'authorPhotoUrl': null,
      'title': 'Шашлыки',
      'description': 'Приезжайте',
      'startAt': '2026-07-01T15:00:00.000Z',
      'endAt': '2026-07-01T20:00:00.000Z',
      'isAllDay': false,
      'place': 'Дача',
      'imageUrls': ['https://example.com/1.jpg', 'https://example.com/2.jpg'],
      'scopeType': 'branches',
      'anchorPersonIds': ['p1', 'p2'],
      'circleId': 'circle-1',
      'createdAt': '2026-06-01T10:00:00.000Z',
      'updatedAt': '2026-06-01T10:00:00.000Z',
      'rsvps': [],
    };

    final g = Gathering.fromJson(json);
    expect(g.id, 'g1');
    expect(g.title, 'Шашлыки');
    expect(g.description, 'Приезжайте');
    expect(g.startAt, DateTime.parse('2026-07-01T15:00:00.000Z'));
    expect(g.endAt, DateTime.parse('2026-07-01T20:00:00.000Z'));
    expect(g.place, 'Дача');
    expect(g.scopeType, TreeContentScopeType.branches);
    expect(g.branchIds, ['tree-1', 'tree-2']);
    expect(g.anchorPersonIds, ['p1', 'p2']);
    expect(g.circleId, 'circle-1');
    expect(g.isAllDay, isFalse);
    expect(g.imageUrls,
        ['https://example.com/1.jpg', 'https://example.com/2.jpg']);
    expect(g.renderableImageUrls.length, 2);

    final back = g.toJson();
    expect(back['title'], 'Шашлыки');
    expect(back['startAt'], '2026-07-01T15:00:00.000Z');
    expect(back['endAt'], '2026-07-01T20:00:00.000Z');
    expect(back['scopeType'], 'branches');
    expect(back['branchIds'], ['tree-1', 'tree-2']);
    expect(back['place'], 'Дача');
    expect(back['imageUrls'],
        ['https://example.com/1.jpg', 'https://example.com/2.jpg']);

    // Re-parsing the serialised form yields the same values.
    final g2 = Gathering.fromJson(back);
    expect(g2.title, g.title);
    expect(g2.startAt, g.startAt);
    expect(g2.scopeType, g.scopeType);
    expect(g2.branchIds, g.branchIds);
  });

  test('Gathering defaults branchIds to [treeId] and tolerates missing fields',
      () {
    final g = Gathering.fromJson(<String, dynamic>{
      'id': 'g2',
      'treeId': 'tree-9',
      'authorId': 'u',
      'authorName': 'X',
      'title': 'Обед',
      'startAt': '2026-08-01T12:00:00.000Z',
      'createdAt': '2026-07-01T12:00:00.000Z',
    });

    expect(g.branchIds, ['tree-9']);
    expect(g.isAllDay, isFalse);
    expect(g.description, isNull);
    expect(g.endAt, isNull);
    expect(g.place, isNull);
    expect(g.rsvps, isEmpty);
    expect(g.scopeType, TreeContentScopeType.wholeTree);
  });
}
