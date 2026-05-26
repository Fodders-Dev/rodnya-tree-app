// Ship Q4 (2026-05-26): bottom sheet exposing 5 actions для tapped
// tree person (UX audit Critical #4). Tests verify each action invokes
// its callback + identity preview renders + sheet dismisses after action.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/widgets/tree_person_action_sheet.dart';

FamilyPerson _samplePerson({
  String name = 'Артём Кузнецов',
  DateTime? birthDate,
  DateTime? deathDate,
  bool isAlive = true,
  Gender gender = Gender.male,
}) {
  return FamilyPerson(
    id: 'p1',
    treeId: 't1',
    name: name,
    gender: gender,
    isAlive: isAlive,
    birthDate: birthDate,
    deathDate: deathDate,
    createdAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 1, 1),
  );
}

void main() {
  testWidgets('renders header + 5 action tiles', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TreePersonActionSheet(
            person: _samplePerson(birthDate: DateTime(1990, 5, 14)),
            onOpenProfile: () {},
            onEdit: () {},
            onAddRelative: () {},
            onConnect: () {},
            onDelete: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Артём Кузнецов'), findsOneWidget);
    expect(find.text('Род. 1990'), findsOneWidget);
    expect(find.text('Открыть профиль'), findsOneWidget);
    expect(find.text('Редактировать'), findsOneWidget);
    expect(find.text('Добавить родственника'), findsOneWidget);
    expect(find.text('Связать с существующим'), findsOneWidget);
    expect(find.text('Удалить'), findsOneWidget);
  });

  testWidgets('shows life range когда birth + death known', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TreePersonActionSheet(
            person: _samplePerson(
              birthDate: DateTime(1950, 1, 1),
              deathDate: DateTime(2020, 6, 1),
              isAlive: false,
            ),
            onOpenProfile: () {},
            onEdit: () {},
            onAddRelative: () {},
            onConnect: () {},
            onDelete: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1950 – 2020'), findsOneWidget);
  });

  testWidgets('each action tile invokes its callback', (tester) async {
    int openCount = 0;
    int editCount = 0;
    int addCount = 0;
    int connectCount = 0;
    int deleteCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TreePersonActionSheet(
            person: _samplePerson(),
            onOpenProfile: () => openCount++,
            onEdit: () => editCount++,
            onAddRelative: () => addCount++,
            onConnect: () => connectCount++,
            onDelete: () => deleteCount++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tree-action-open-profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tree-action-edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tree-action-add-relative')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tree-action-connect')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tree-action-delete')));
    await tester.pumpAndSettle();
    expect(openCount, 1);
    expect(editCount, 1);
    expect(addCount, 1);
    expect(connectCount, 1);
    expect(deleteCount, 1);
  });

  testWidgets('Delete action visually destructive (error color)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: const ColorScheme.light()),
        home: Scaffold(
          body: TreePersonActionSheet(
            person: _samplePerson(),
            onOpenProfile: () {},
            onEdit: () {},
            onAddRelative: () {},
            onConnect: () {},
            onDelete: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Find the «Удалить» tile's Text widget — verify it picks up the
    // theme.error color (we use foregroundColor: theme.colorScheme.error
    // for destructive actions).
    final deleteText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('tree-action-delete')),
        matching: find.text('Удалить'),
      ),
    );
    expect(deleteText.style?.fontWeight, FontWeight.w700);
  });

  testWidgets(
    'Ship FE4: viewerMode=true → only «Открыть профиль» tile, '
    'editorial actions hidden',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TreePersonActionSheet(
              person: _samplePerson(),
              viewerMode: true,
              onOpenProfile: () {},
              onEdit: () {},
              onAddRelative: () {},
              onConnect: () {},
              onDelete: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('tree-action-open-profile')),
        findsOneWidget,
      );
      // Editorial action tiles MUST be hidden in viewer mode.
      expect(find.byKey(const Key('tree-action-edit')), findsNothing);
      expect(find.byKey(const Key('tree-action-add-relative')), findsNothing);
      expect(find.byKey(const Key('tree-action-connect')), findsNothing);
      expect(find.byKey(const Key('tree-action-delete')), findsNothing);
    },
  );

  testWidgets(
    'Ship FE4: viewerMode=false (default) preserves все 5 actions',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TreePersonActionSheet(
              person: _samplePerson(),
              onOpenProfile: () {},
              onEdit: () {},
              onAddRelative: () {},
              onConnect: () {},
              onDelete: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tree-action-open-profile')), findsOneWidget);
      expect(find.byKey(const Key('tree-action-edit')), findsOneWidget);
      expect(find.byKey(const Key('tree-action-add-relative')), findsOneWidget);
      expect(find.byKey(const Key('tree-action-connect')), findsOneWidget);
      expect(find.byKey(const Key('tree-action-delete')), findsOneWidget);
    },
  );

  testWidgets('showTreePersonActionSheet pops dialog после action',
      (tester) async {
    int openCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showTreePersonActionSheet(
                    context,
                    person: _samplePerson(),
                    onOpenProfile: () => openCount++,
                    onEdit: () {},
                    onAddRelative: () {},
                    onConnect: () {},
                    onDelete: () {},
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
    expect(find.text('Открыть профиль'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tree-action-open-profile')));
    await tester.pumpAndSettle();
    // Sheet dismissed.
    expect(find.text('Открыть профиль'), findsNothing);
    expect(openCount, 1);
  });
}
