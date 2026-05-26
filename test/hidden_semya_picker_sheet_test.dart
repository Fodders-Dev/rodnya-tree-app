// Ship FE7b (2026-05-26): семя picker sheet rendering tests.
//
// Covers:
//   • Header copy
//   • One tile per семя
//   • Keys включают семя id для test-targetability
//   • Tap pops sheet (navigation to SemyaDetailsScreen verified
//     indirectly via Navigator interaction)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/models/semya.dart';
import 'package:rodnya/widgets/hidden_semya_picker_sheet.dart';

Semya _makeSemya({required String id, required String name}) {
  return Semya(
    id: id,
    name: name,
    ownerId: 'u-owner',
    treeId: 't-$id',
    createdAt: '2026-05-26T00:00:00.000Z',
    updatedAt: '2026-05-26T00:00:00.000Z',
  );
}

void main() {
  testWidgets('renders header + tile per семя', (tester) async {
    final semyi = [
      _makeSemya(id: 's-1', name: 'Семья Ивановых'),
      _makeSemya(id: 's-2', name: 'Семья Кузнецовых'),
      _makeSemya(id: 's-3', name: 'Семья Петровых'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showHiddenSemyaPickerSheet(ctx, semyi: semyi),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('В какой семье?'), findsOneWidget);
    expect(find.text('Семья Ивановых'), findsOneWidget);
    expect(find.text('Семья Кузнецовых'), findsOneWidget);
    expect(find.text('Семья Петровых'), findsOneWidget);
    expect(find.byKey(const Key('hidden-semya-picker-s-1')), findsOneWidget);
    expect(find.byKey(const Key('hidden-semya-picker-s-2')), findsOneWidget);
    expect(find.byKey(const Key('hidden-semya-picker-s-3')), findsOneWidget);
  });

  testWidgets('tap tile pops sheet', (tester) async {
    final semyi = [_makeSemya(id: 's-1', name: 'Семья Одна')];

    await tester.pumpWidget(
      MaterialApp(
        // Use direct nav stack — tap pushes via rootNavigator (production
        // wiring). В тесте substitute с onGenerateRoute стаб'ом чтобы
        // навигация не падала.
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('stub-route')),
        ),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showHiddenSemyaPickerSheet(ctx, semyi: semyi),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Семья Одна'), findsOneWidget);

    await tester.tap(find.byKey(const Key('hidden-semya-picker-s-1')));
    await tester.pumpAndSettle();
    // Sheet dismissed.
    expect(find.text('В какой семье?'), findsNothing);
  });
}
