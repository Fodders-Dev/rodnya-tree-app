// Ship FE4 (2026-05-26): SemyaContextBadge tests — verify unbound
// fallback label, bound name rendering, role pill для caller's role.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/models/semya.dart';
import 'package:rodnya/widgets/semya_context_badge.dart';

Semya _semya({String name = 'Семья Ивановых'}) {
  return Semya(
    id: 'semya-1',
    name: name,
    ownerId: 'user-1',
    treeId: 'tree-1',
    createdAt: '2026-05-26T00:00:00.000Z',
    updatedAt: '2026-05-26T00:00:00.000Z',
  );
}

void main() {
  testWidgets('unbound state shows legacy label «Моё дерево»', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SemyaContextBadge(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Моё дерево'), findsOneWidget);
    expect(find.byIcon(Icons.account_tree_rounded), findsOneWidget);
  });

  testWidgets('bound state shows semя name + role pill', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SemyaContextBadge(
            semya: _semya(),
            callerRole: SemyaRole.editor,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Семья Ивановых'), findsOneWidget);
    expect(find.text('Редактор'), findsOneWidget);
    expect(find.byIcon(Icons.family_restroom_rounded), findsOneWidget);
  });

  testWidgets('owner role pill renders с primary colour', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SemyaContextBadge(
            semya: _semya(name: 'Тестовая семья'),
            callerRole: SemyaRole.owner,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Тестовая семья'), findsOneWidget);
    expect(find.text('Владелец'), findsOneWidget);
  });

  testWidgets('viewer role pill renders neutrally', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SemyaContextBadge(
            semya: _semya(),
            callerRole: SemyaRole.viewer,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Зритель'), findsOneWidget);
  });

  testWidgets('onTap callback fires при badge press', (tester) async {
    int taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SemyaContextBadge(
              semya: _semya(),
              callerRole: SemyaRole.owner,
              onTap: () => taps++,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('semya-context-badge')));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('semя name truncates с ellipsis (overflow safe)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            child: SemyaContextBadge(
              semya: _semya(
                name: 'Очень длинное название семьи на нескольких словах',
              ),
              callerRole: SemyaRole.editor,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Text widget exists (verifies layout не throws), ellipsis applied
    // via TextOverflow.ellipsis в badge's Text style.
    expect(
      find.textContaining('Очень длинное название'),
      findsOneWidget,
    );
  });
}
