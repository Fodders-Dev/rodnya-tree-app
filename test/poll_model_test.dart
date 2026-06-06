import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/models/poll.dart';
import 'package:rodnya/models/post.dart' show TreeContentScopeType;

void main() {
  test('Poll round-trips through json with options + responses', () {
    final json = <String, dynamic>{
      'id': 'p1',
      'treeId': 'tree-1',
      'branchIds': ['tree-1'],
      'authorId': 'u1',
      'authorName': 'Анна',
      'authorPhotoUrl': null,
      'imageUrls': ['https://example.com/1.jpg'],
      'question': 'Когда собираемся?',
      'options': [
        {'id': 'o1', 'text': 'Суббота'},
        {'id': 'o2', 'text': 'Воскресенье'},
      ],
      'allowMultiple': false,
      'closesAt': '2026-07-10T00:00:00.000Z',
      'scopeType': 'branches',
      'anchorPersonIds': ['per1'],
      'circleId': 'circle-1',
      'createdAt': '2026-06-01T10:00:00.000Z',
      'updatedAt': '2026-06-01T10:00:00.000Z',
      'responses': [
        {
          'userId': 'u2',
          'optionIds': ['o1'],
        },
        {
          'userId': 'u3',
          'optionIds': ['o1', 'o2'],
        },
      ],
    };

    final poll = Poll.fromJson(json);
    expect(poll.question, 'Когда собираемся?');
    expect(poll.options.length, 2);
    expect(poll.options.first.id, 'o1');
    expect(poll.options.first.text, 'Суббота');
    expect(poll.allowMultiple, isFalse);
    expect(poll.closesAt, DateTime.parse('2026-07-10T00:00:00.000Z'));
    expect(poll.scopeType, TreeContentScopeType.branches);
    expect(poll.renderableImageUrls.length, 1);

    // Tallies.
    expect(poll.totalVoters, 2);
    expect(poll.votesFor('o1'), 2); // u2 + u3
    expect(poll.votesFor('o2'), 1); // u3 only
    expect(poll.myVotedOptionIds('u3'), ['o1', 'o2']);
    expect(poll.myVotedOptionIds('nobody'), isEmpty);

    final back = poll.toJson();
    expect(back['question'], 'Когда собираемся?');
    expect((back['options'] as List).length, 2);
    expect(back['allowMultiple'], false);
    expect(back['scopeType'], 'branches');
    expect((back['responses'] as List).length, 2);

    final reparsed = Poll.fromJson(back);
    expect(reparsed.question, poll.question);
    expect(reparsed.options.length, poll.options.length);
    expect(reparsed.votesFor('o1'), 2);
  });

  test('Poll defaults branchIds to [treeId] and tolerates missing fields', () {
    final poll = Poll.fromJson(<String, dynamic>{
      'id': 'p2',
      'treeId': 'tree-9',
      'authorId': 'u',
      'authorName': 'X',
      'question': 'Опрос',
      'options': [
        {'id': 'a', 'text': 'А'},
        {'id': 'b', 'text': 'Б'},
      ],
      'createdAt': '2026-07-01T12:00:00.000Z',
    });

    expect(poll.branchIds, ['tree-9']);
    expect(poll.allowMultiple, isFalse);
    expect(poll.closesAt, isNull);
    expect(poll.responses, isEmpty);
    expect(poll.totalVoters, 0);
    expect(poll.scopeType, TreeContentScopeType.wholeTree);
  });
}
