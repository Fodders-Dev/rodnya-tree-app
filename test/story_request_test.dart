// «Спросить историю» MVP-1 (STORY-REQUEST-MVP1-BRIEF.md §1): StoryRequest
// DTO parsing + status/kind enums, mirroring kinship_check_test.dart's
// coverage style for the sibling capability.

import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/models/story_request.dart';

void main() {
  group('StoryRequestStatus.fromServerValue', () {
    test('maps known values', () {
      expect(StoryRequestStatus.fromServerValue('pending'), StoryRequestStatus.pending);
      expect(StoryRequestStatus.fromServerValue('answered'), StoryRequestStatus.answered);
      expect(StoryRequestStatus.fromServerValue('declined'), StoryRequestStatus.declined);
      expect(StoryRequestStatus.fromServerValue('expired'), StoryRequestStatus.expired);
      expect(StoryRequestStatus.fromServerValue('revoked'), StoryRequestStatus.revoked);
    });

    test('round-trips serverValue', () {
      for (final s in StoryRequestStatus.values) {
        expect(StoryRequestStatus.fromServerValue(s.serverValue), s, reason: s.name);
      }
    });

    test('defaults к unknown для незнакомых значений', () {
      expect(StoryRequestStatus.fromServerValue('weird'), StoryRequestStatus.unknown);
      expect(StoryRequestStatus.fromServerValue(null), StoryRequestStatus.unknown);
    });
  });

  group('StoryRequestAnswerKind.fromServerValue', () {
    test('maps audio|text|photo, video falls back to unknown (§0.4 — MVP-2)', () {
      expect(StoryRequestAnswerKind.fromServerValue('audio'), StoryRequestAnswerKind.audio);
      expect(StoryRequestAnswerKind.fromServerValue('text'), StoryRequestAnswerKind.text);
      expect(StoryRequestAnswerKind.fromServerValue('photo'), StoryRequestAnswerKind.photo);
      expect(StoryRequestAnswerKind.fromServerValue('video'), StoryRequestAnswerKind.unknown);
    });
  });

  group('StoryRequest.fromJson', () {
    test('parses a pending request без answer/вложений', () {
      final r = StoryRequest.fromJson({
        'id': 'sreq-1',
        'treeId': 'tree-1',
        'personId': 'person-1',
        'requesterUserId': 'u-a',
        'targetUserId': 'u-b',
        'question': {'text': 'Кто на фото?'},
        'status': 'pending',
        'createdAt': '2026-09-13T10:00:00Z',
        'expiresAt': '2026-10-13T10:00:00Z',
      });
      expect(r.id, 'sreq-1');
      expect(r.question.text, 'Кто на фото?');
      expect(r.question.themeKey, isNull);
      expect(r.status, StoryRequestStatus.pending);
      expect(r.isPending, isTrue);
      expect(r.answer, isNull);
      expect(r.person, isNull);
      expect(r.requester, isNull);
      expect(r.target, isNull);
    });

    test('parses question with themeKey + sourceQuestionId', () {
      final r = StoryRequest.fromJson({
        'id': 'sreq-2',
        'treeId': 't',
        'personId': 'p',
        'requesterUserId': 'u-a',
        'targetUserId': 'u-b',
        'question': {
          'text': 'Как познакомились?',
          'themeKey': 'love',
          'sourceQuestionId': 'grandparents_met',
        },
        'status': 'pending',
        'createdAt': 'c',
        'expiresAt': 'e',
      });
      expect(r.question.themeKey, 'love');
      expect(r.question.sourceQuestionId, 'grandparents_met');
    });

    test('parses answered request с answer + person/requester/target attachments', () {
      final r = StoryRequest.fromJson({
        'id': 'sreq-3',
        'treeId': 't',
        'personId': 'p-1',
        'requesterUserId': 'u-a',
        'targetUserId': 'u-b',
        'question': {'text': 'Q'},
        'status': 'answered',
        'answer': {
          'articleBlockId': 'block-1',
          'kind': 'audio',
          'answeredByUserId': 'u-b',
          'answeredAt': '2026-09-13T11:00:00Z',
        },
        'createdAt': 'c',
        'updatedAt': 'u',
        'expiresAt': 'e',
        'respondedAt': '2026-09-13T11:00:00Z',
        'person': {'id': 'p-1', 'name': 'Лида', 'photoUrl': 'https://x/lida.jpg'},
        'requester': {'id': 'u-a', 'displayName': 'Артём'},
        'target': {'id': 'u-b', 'displayName': 'Лида'},
      });
      expect(r.status, StoryRequestStatus.answered);
      expect(r.isPending, isFalse);
      expect(r.answer, isNotNull);
      expect(r.answer!.articleBlockId, 'block-1');
      expect(r.answer!.kind, StoryRequestAnswerKind.audio);
      expect(r.answer!.answeredByUserId, 'u-b');
      expect(r.person?.displayName, 'Лида');
      expect(r.person?.photoUrl, 'https://x/lida.jpg');
      expect(r.requester?.displayName, 'Артём');
      expect(r.target?.displayName, 'Лида');
    });

    test('person summary reads `name` key, requester/target read `displayName`', () {
      final r = StoryRequest.fromJson({
        'id': 'sreq-4',
        'treeId': 't',
        'personId': 'p',
        'requesterUserId': 'u-a',
        'targetUserId': 'u-b',
        'question': {'text': 'Q'},
        'status': 'pending',
        'createdAt': 'c',
        'expiresAt': 'e',
        'person': {'id': 'p', 'name': 'Только-name'},
        'requester': {'id': 'u-a', 'displayName': 'Только-displayName'},
      });
      expect(r.person?.displayName, 'Только-name');
      expect(r.requester?.displayName, 'Только-displayName');
    });
  });

  group('StoryRequestAnswerInput.toJson', () {
    test('audio payload', () {
      final json = StoryRequestAnswerInput.audio(mediaUrl: 'https://a', durationSec: 30).toJson();
      expect(json, {'kind': 'audio', 'mediaUrl': 'https://a', 'durationSec': 30});
    });

    test('text payload', () {
      final json = StoryRequestAnswerInput.text('Моя история').toJson();
      expect(json, {'kind': 'text', 'text': 'Моя история'});
    });

    test('photo payload — caption omitted when blank', () {
      final withCaption =
          StoryRequestAnswerInput.photo(mediaUrl: 'https://p', caption: '  Подпись  ').toJson();
      expect(withCaption, {'kind': 'photo', 'mediaUrl': 'https://p', 'caption': 'Подпись'});

      final withoutCaption = StoryRequestAnswerInput.photo(mediaUrl: 'https://p').toJson();
      expect(withoutCaption, {'kind': 'photo', 'mediaUrl': 'https://p'});
    });
  });

  group('StoryRequestQuestion.toJson', () {
    test('omits null optional fields', () {
      expect(
        const StoryRequestQuestion(text: 'Q').toJson(),
        {'text': 'Q'},
      );
      expect(
        const StoryRequestQuestion(text: 'Q', themeKey: 'k', sourceQuestionId: 's').toJson(),
        {'text': 'Q', 'themeKey': 'k', 'sourceQuestionId': 's'},
      );
    });
  });

  test('StoryRequestError carries code/message/statusCode для humanizeError', () {
    const error = StoryRequestError(
      code: 'DUPLICATE_PENDING',
      message: 'Такой вопрос уже ждёт ответа',
      statusCode: 409,
    );
    expect(error.code, 'DUPLICATE_PENDING');
    expect(error.message, 'Такой вопрос уже ждёт ответа');
    expect(error.statusCode, 409);
    expect(error.toString(), contains('DUPLICATE_PENDING'));
  });
}
