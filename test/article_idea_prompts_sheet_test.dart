// Profile Phase 2a gender-agreement (2026-05-29): genderForm helper +
// gender-aware идея-prompt rendering.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/widgets/article_idea_prompts_sheet.dart';

Widget _host(String? gender) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () =>
                showArticleIdeaPromptsSheet(context, personGender: gender),
            child: const Text('open'),
          ),
        ),
      ),
    );

Future<void> _openSheet(WidgetTester tester, String? gender) async {
  await tester.pumpWidget(_host(gender));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('genderForm', () {
    test('female → feminine', () {
      expect(
        genderForm('female', masculine: 'родился', feminine: 'родилась'),
        'родилась',
      );
    });

    test('male → masculine', () {
      expect(
        genderForm('male', masculine: 'родился', feminine: 'родилась'),
        'родился',
      );
    });

    test('unknown/other/null → neutral when provided', () {
      for (final g in [null, 'unknown', 'other', 'whatever']) {
        expect(
          genderForm(g,
              masculine: 'родился', feminine: 'родилась', neutral: 'рождён'),
          'рождён',
          reason: 'gender=$g',
        );
      }
    });

    test('unknown → masculine fallback when no neutral supplied', () {
      expect(
        genderForm(null, masculine: 'родился', feminine: 'родилась'),
        'родился',
      );
    });
  });

  testWidgets('female persona → feminine prompts', (tester) async {
    await _openSheet(tester, 'female');
    expect(find.textContaining('родилась'), findsOneWidget);
    expect(find.textContaining('гордилась'), findsOneWidget);
    expect(find.textContaining('родился'), findsNothing);
  });

  testWidgets('male persona → masculine prompts', (tester) async {
    await _openSheet(tester, 'male');
    expect(find.textContaining('родился'), findsOneWidget);
    expect(find.textContaining('гордился'), findsOneWidget);
    expect(find.textContaining('родилась'), findsNothing);
  });

  testWidgets('unknown persona → neutral reformulation (no скобки)',
      (tester) async {
    await _openSheet(tester, null);
    expect(find.textContaining('Место и год рождения'), findsOneWidget);
    // No gendered verb + no ugly «родился(ась)» crutch.
    expect(find.textContaining('родился'), findsNothing);
    expect(find.textContaining('родилась'), findsNothing);
    expect(find.textContaining('(ась)'), findsNothing);
  });

  testWidgets('gender-neutral themes are identical across genders',
      (tester) async {
    // Семья / Свадьба / Война carry no person-gendered verb.
    await _openSheet(tester, 'female');
    expect(find.textContaining('Расскажите о родителях'), findsOneWidget);
    expect(find.textContaining('Как познакомились'), findsOneWidget);
    expect(find.textContaining('Как война коснулась семьи'), findsOneWidget);
  });
}
