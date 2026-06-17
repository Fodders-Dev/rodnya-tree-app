import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/widgets/family_story_questions_sheet.dart';

void main() {
  testWidgets('family story sheet selects a question and returns save action',
      (tester) async {
    FamilyStoryQuestionAction? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showFamilyStoryQuestionsSheet(
                  context,
                  personName: 'Кузнецова Валентина',
                  relation: 'Бабушка',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Спросить историю'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('family-story-question-old_photos')),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('family-story-question-old_photos')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('family-story-save-answer')));
    await tester.pumpAndSettle();

    expect(result?.type, FamilyStoryQuestionActionType.saveAnswer);
    expect(result?.question.id, 'old_photos');
  });

  testWidgets('family story sheet can return share action', (tester) async {
    FamilyStoryQuestionAction? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showFamilyStoryQuestionsSheet(
                  context,
                  personName: 'Кузнецов Андрей',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('family-story-share-question')));
    await tester.pumpAndSettle();

    expect(result?.type, FamilyStoryQuestionActionType.share);
    expect(result?.question.id, 'parents_birthplace');
  });
}
