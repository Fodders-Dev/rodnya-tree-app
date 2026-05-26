// Ship 2026-05-26 (UX audit Screen 4.1): empty-tree guided CTA tests.
// Verify все 5 buttons render с correct labels, тап fires callback с
// correct RelationType + Gender hint, header copy switches based on
// hasSelfPerson flag.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/models/family_relation.dart';
import 'package:rodnya/widgets/empty_tree_guided_cta.dart';

void main() {
  testWidgets('renders 5 CTAs + header for empty-tree state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyTreeGuidedCta(
            hasSelfPerson: false,
            onAddRelative: (_, __) {},
            onAddOther: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Начни своё семейное дерево'), findsOneWidget);
    expect(find.text('Добавить маму'), findsOneWidget);
    expect(find.text('Добавить папу'), findsOneWidget);
    expect(find.text('Добавить ребёнка'), findsOneWidget);
    expect(find.text('Добавить партнёра'), findsOneWidget);
    expect(find.text('Другой родственник'), findsOneWidget);
  });

  testWidgets('header switches to «Добавь близких» когда hasSelfPerson=true',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyTreeGuidedCta(
            hasSelfPerson: true,
            onAddRelative: (_, __) {},
            onAddOther: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Добавь близких'), findsOneWidget);
    expect(find.text('Начни своё семейное дерево'), findsNothing);
  });

  testWidgets('Мама CTA fires onAddRelative(parent, female)', (tester) async {
    RelationType? capturedRelation;
    Gender? capturedGender;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyTreeGuidedCta(
            hasSelfPerson: false,
            onAddRelative: (relation, gender) {
              capturedRelation = relation;
              capturedGender = gender;
            },
            onAddOther: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('empty-tree-cta-mama')));
    await tester.pumpAndSettle();
    expect(capturedRelation, RelationType.parent);
    expect(capturedGender, Gender.female);
  });

  testWidgets('Папа CTA fires onAddRelative(parent, male)', (tester) async {
    RelationType? capturedRelation;
    Gender? capturedGender;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyTreeGuidedCta(
            hasSelfPerson: true,
            onAddRelative: (relation, gender) {
              capturedRelation = relation;
              capturedGender = gender;
            },
            onAddOther: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('empty-tree-cta-papa')));
    await tester.pumpAndSettle();
    expect(capturedRelation, RelationType.parent);
    expect(capturedGender, Gender.male);
  });

  testWidgets('Ребёнок CTA fires onAddRelative(child, null gender)',
      (tester) async {
    RelationType? capturedRelation;
    Gender? capturedGender = Gender.female; // sentinel
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyTreeGuidedCta(
            hasSelfPerson: true,
            onAddRelative: (relation, gender) {
              capturedRelation = relation;
              capturedGender = gender;
            },
            onAddOther: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('empty-tree-cta-child')));
    await tester.pumpAndSettle();
    expect(capturedRelation, RelationType.child);
    expect(capturedGender, isNull,
        reason: 'child CTA должно передавать null gender (user picks)');
  });

  testWidgets('Партнёр CTA fires onAddRelative(spouse, null)', (tester) async {
    RelationType? capturedRelation;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyTreeGuidedCta(
            hasSelfPerson: false,
            onAddRelative: (relation, _) {
              capturedRelation = relation;
            },
            onAddOther: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('empty-tree-cta-partner')));
    await tester.pumpAndSettle();
    expect(capturedRelation, RelationType.spouse);
  });

  testWidgets('«Другой родственник» fires onAddOther', (tester) async {
    var otherCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyTreeGuidedCta(
            hasSelfPerson: false,
            onAddRelative: (_, __) {},
            onAddOther: () => otherCount++,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('empty-tree-cta-other')));
    await tester.pumpAndSettle();
    expect(otherCount, 1);
  });

  testWidgets('header copy + sub-copy differ between hasSelfPerson states',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyTreeGuidedCta(
            hasSelfPerson: false,
            onAddRelative: (_, __) {},
            onAddOther: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Добавь родственников, чтобы сохранить'),
      findsOneWidget,
    );

    // Switch к hasSelfPerson=true variant.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyTreeGuidedCta(
            hasSelfPerson: true,
            onAddRelative: (_, __) {},
            onAddOther: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Сохрани историю семьи'),
      findsOneWidget,
    );
  });
}
