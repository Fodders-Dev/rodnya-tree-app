// Ship Audit 4.2 (2026-05-28): RelationPickerSheet widget tests.
//
// Covers:
//   • Sheet renders header «Кем приходится?» + 6 primary tiles
//   • «+Другой родственник» expand reveals secondary picker rows
//   • Primary tile tap pops sheet с correct RelationType + Gender hint
//   • Secondary tile (например, Тётя) pops с aunt + female
//   • «Другое родство — заполню сам» pops с null relation
//     (signal к AddRelativeScreen использовать default UI)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/models/family_relation.dart';
import 'package:rodnya/widgets/relation_picker_sheet.dart';

/// Reusable test harness — uses lower-level `showRelationPickerSheet`
/// (returns pick synchronously) к избежать GoRouter dependency.
/// Production wrapper `showRelationPickerAndNavigateAdd` adds
/// context.push на top — tested indirectly through wire-up sites.
RelationPickerResult? capturedResult;

Future<void> _openSheet(
  WidgetTester tester, {
  String? anchorName,
  bool isFriendsCircle = false,
}) async {
  capturedResult = null;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () async {
                capturedResult = await showRelationPickerSheet(
                  ctx,
                  anchorName: anchorName,
                  isFriendsCircle: isFriendsCircle,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sheet header + 6 primary relations rendered', (tester) async {
    await _openSheet(tester);
    expect(find.text('Кем приходится?'), findsOneWidget);
    // Primary tiles.
    expect(find.text('Мама'), findsOneWidget);
    expect(find.text('Папа'), findsOneWidget);
    expect(find.text('Ребёнок'), findsOneWidget);
    expect(find.text('Супруг / Партнёр'), findsOneWidget);
    expect(find.text('Брат / Сестра'), findsOneWidget);
    expect(find.text('Дедушка / Бабушка'), findsOneWidget);
    // «Другой» expand entry visible.
    expect(find.text('Другой родственник'), findsOneWidget);
  });

  testWidgets('«+Другой родственник» expand reveals secondary tiles',
      (tester) async {
    await _openSheet(tester);
    expect(find.text('Тётя'), findsNothing);
    await tester.tap(find.byKey(const Key('relation-picker-other-expand')));
    await tester.pumpAndSettle();
    // Expand collapses the button.
    expect(find.byKey(const Key('relation-picker-other-expand')), findsNothing);
    // Secondary tiles visible.
    expect(find.text('Тётя'), findsOneWidget);
    expect(find.text('Дядя'), findsOneWidget);
    expect(find.text('Племянник'), findsOneWidget);
    expect(find.text('Племянница'), findsOneWidget);
    expect(find.text('Кузен / Кузина'), findsOneWidget);
    expect(find.text('Прадед / Прабабка'), findsOneWidget);
    expect(find.text('Тесть / Тёща / Свёкр / Свекровь'), findsOneWidget);
    expect(find.text('Деверь / Золовка / Шурин'), findsOneWidget);
    // F2: сложные семьи.
    expect(find.text('Бывший муж / жена'), findsOneWidget);
    expect(find.text('Партнёр (без брака)'), findsOneWidget);
    expect(find.text('Сводный ребёнок'), findsOneWidget);
    expect(find.text('Другое родство — заполню сам'), findsOneWidget);
  });

  testWidgets('F2: tap «Бывший муж / жена» pops с ex_spouse', (tester) async {
    await _openSheet(tester);
    await tester.tap(find.byKey(const Key('relation-picker-other-expand')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Бывший муж / жена'));
    await tester.tap(find.text('Бывший муж / жена'));
    await tester.pumpAndSettle();
    expect(capturedResult, isNotNull);
    expect(capturedResult!.relationType, RelationType.ex_spouse);
    expect(capturedResult!.gender, isNull);
  });

  testWidgets('F2: tap «Сводный ребёнок» pops с stepchild', (tester) async {
    await _openSheet(tester);
    await tester.tap(find.byKey(const Key('relation-picker-other-expand')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Сводный ребёнок'));
    await tester.tap(find.text('Сводный ребёнок'));
    await tester.pumpAndSettle();
    expect(capturedResult, isNotNull);
    expect(capturedResult!.relationType, RelationType.stepchild);
  });

  testWidgets('tap «Мама» pops sheet с parent + female', (tester) async {
    await _openSheet(tester);
    await tester.tap(find.byKey(const Key('relation-picker-mama')));
    await tester.pumpAndSettle();
    expect(find.text('Кем приходится?'), findsNothing);
    expect(capturedResult?.relationType, RelationType.parent);
    expect(capturedResult?.gender, Gender.female);
  });

  testWidgets('tap «Папа» pops sheet с parent + male', (tester) async {
    await _openSheet(tester);
    await tester.tap(find.byKey(const Key('relation-picker-papa')));
    await tester.pumpAndSettle();
    expect(capturedResult?.relationType, RelationType.parent);
    expect(capturedResult?.gender, Gender.male);
  });

  testWidgets('tap «Тётя» from expanded → aunt + female', (tester) async {
    await _openSheet(tester);
    await tester.tap(find.byKey(const Key('relation-picker-other-expand')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('relation-picker-aunt')));
    await tester.pumpAndSettle();
    expect(capturedResult?.relationType, RelationType.aunt);
    expect(capturedResult?.gender, Gender.female);
  });

  testWidgets('«Другое родство — заполню сам» → null relation', (tester) async {
    await _openSheet(tester);
    await tester.tap(find.byKey(const Key('relation-picker-other-expand')));
    await tester.pumpAndSettle();
    // Scroll bottom row into view ПЕРЕД tap (small test viewport
    // may render «other» offscreen).
    await tester.ensureVisible(find.byKey(const Key('relation-picker-other')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('relation-picker-other')));
    await tester.pumpAndSettle();
    // Sheet returned RelationPickerResult с null relation —
    // signal к AddRelativeScreen использовать generic UI.
    expect(capturedResult, isNotNull);
    expect(capturedResult?.relationType, isNull);
    expect(capturedResult?.gender, isNull);
  });

  testWidgets(
      'B: node-anchored показывает заголовок «Кто это для X?» и только примитивы',
      (tester) async {
    await _openSheet(tester, anchorName: 'Анна Петрова');
    expect(find.text('Кто это для Анна Петрова?'), findsOneWidget);
    expect(find.text('Кем приходится?'), findsNothing);
    // Только 4 примитива относительно узла.
    expect(find.text('Мама'), findsOneWidget);
    expect(find.text('Папа'), findsOneWidget);
    expect(find.text('Ребёнок'), findsOneWidget);
    expect(find.text('Супруг / Партнёр'), findsOneWidget);
    expect(find.text('Брат / Сестра'), findsOneWidget);
    // Сложные/выводимые типы НЕ показываем — граф выведет сам.
    expect(find.text('Дедушка / Бабушка'), findsNothing);
    expect(find.text('Другой родственник'), findsNothing);
    expect(
      find.byKey(const Key('relation-picker-other-expand')),
      findsNothing,
    );
    expect(find.text('Другое родство — заполню сам'), findsNothing);
  });

  testWidgets('B: node-anchored «Мама» по-прежнему отдаёт parent + female',
      (tester) async {
    await _openSheet(tester, anchorName: 'Анна Петрова');
    await tester.tap(find.byKey(const Key('relation-picker-mama')));
    await tester.pumpAndSettle();
    expect(capturedResult?.relationType, RelationType.parent);
    expect(capturedResult?.gender, Gender.female);
  });

  testWidgets('B: пустой anchorName трактуется как FAB-режим (полный список)',
      (tester) async {
    await _openSheet(tester, anchorName: '   ');
    expect(find.text('Кем приходится?'), findsOneWidget);
    expect(find.text('Дедушка / Бабушка'), findsOneWidget);
    expect(find.text('Другой родственник'), findsOneWidget);
  });

  testWidgets('dismiss sheet без выбора returns null', (tester) async {
    await _openSheet(tester);
    expect(find.text('Кем приходится?'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Кем приходится?'), findsNothing);
    expect(capturedResult, isNull);
  });

  testWidgets(
      'regression: showRelationPickerAndNavigateAdd шлёт extra-ключ '
      '«relationType» (+ contextPersonId), а не «predefinedRelation» — '
      'иначе AddRelativeScreen отбрасывает якорь и цепляет к self',
      (tester) async {
    Map<String, dynamic>? capturedExtra;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (ctx, st) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showRelationPickerAndNavigateAdd(
                  ctx,
                  treeId: 'tree-1',
                  contextPersonId: 'person-anchor',
                  anchorName: 'Анна Петрова',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/relatives/add/:treeId',
          builder: (ctx, st) {
            capturedExtra = st.extra as Map<String, dynamic>?;
            return const Scaffold(body: Text('add-form'));
          },
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // node-anchored пикер — примитивы видны сразу.
    await tester.tap(find.text('Супруг / Партнёр'));
    await tester.pumpAndSettle();

    expect(capturedExtra, isNotNull,
        reason: 'навигация в /relatives/add должна была произойти');
    expect(capturedExtra!['contextPersonId'], 'person-anchor');
    // КЛЮЧ: AddRelativeScreen.initState читает extra['relationType'].
    expect(
      capturedExtra!.containsKey('relationType'),
      isTrue,
      reason: 'без ключа relationType contextPersonId отбрасывается → '
          'add-to-self вместо node-anchored',
    );
    expect(capturedExtra!['relationType'], RelationType.spouse);
    // Старый (битый) мёртвый ключ не должен возвращаться.
    expect(capturedExtra!.containsKey('predefinedRelation'), isFalse);
  });

  testWidgets(
      'Круг друзей: friends-first пикер вместо семейных примитивов '
      '(смоук 2026-07-04 — «Друг» отсутствовал вовсе)', (tester) async {
    await _openSheet(tester, isFriendsCircle: true);
    expect(find.text('Друг'), findsOneWidget);
    expect(find.text('Коллега'), findsOneWidget);
    expect(find.text('Другая связь — заполню сам'), findsOneWidget);
    // Семейные примитивы в круге не показываем.
    expect(find.text('Мама'), findsNothing);
    expect(find.text('Папа'), findsNothing);
    expect(find.text('Дедушка / Бабушка'), findsNothing);

    await tester.tap(find.text('Друг'));
    await tester.pumpAndSettle();
    expect(capturedResult?.relationType, RelationType.friend);
    expect(capturedResult?.gender, isNull);
  });

  testWidgets('Круг друзей: «Другая связь» pops null relation', (tester) async {
    await _openSheet(tester, isFriendsCircle: true);
    await tester.tap(find.text('Другая связь — заполню сам'));
    await tester.pumpAndSettle();
    expect(capturedResult, isNotNull);
    expect(capturedResult!.relationType, isNull);
  });
}
