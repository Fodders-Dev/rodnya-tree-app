import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/models/family_story_question.dart';

void main() {
  test('family story questions cover the MVP prompt set', () {
    expect(familyStoryQuestions, hasLength(8));
    expect(
      familyStoryQuestions.map((q) => q.question),
      containsAll([
        'Где родились твои родители?',
        'Как познакомились бабушка и дедушка?',
        'Какая история в семье передаётся из поколения в поколение?',
        'Кто изображён на старых фотографиях?',
        'Что ты хочешь, чтобы дети и внуки помнили?',
        'Какие семейные традиции были в детстве?',
        'Откуда родом наша фамилия?',
        'Что ты помнишь о своих бабушках и дедушках?',
      ]),
    );
  });

  test('share message is warm and ties the question to the person card', () {
    final message = buildFamilyStoryShareMessage(
      question: familyStoryQuestions.first,
      personName: 'Кузнецова Валентина',
      relation: 'Бабушка',
    );

    expect(message, contains('Кузнецова Валентина (Бабушка)'));
    expect(message, contains('Где родились твои родители?'));
    expect(message, contains('сохраню ответ в семейной памяти'));
    expect(message, isNot(contains('null')));
  });

  test('editor hint preserves the selected question', () {
    final hint = buildFamilyStoryEditorHint(familyStoryQuestions[4]);

    expect(hint, contains('Что ты хочешь, чтобы дети и внуки помнили?'));
    expect(hint, contains('нажмите «Голос»'));
  });
}
