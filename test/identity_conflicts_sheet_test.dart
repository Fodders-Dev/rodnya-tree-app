import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/models/identity_field_conflict.dart';
import 'package:rodnya/widgets/identity_conflicts_sheet.dart';

IdentityFieldConflict _conflict({
  required String id,
  required String field,
  dynamic targetValue,
  dynamic sourceValue,
}) {
  return IdentityFieldConflict(
    id: id,
    identityId: 'identity-1',
    sourcePersonId: 'src-1',
    sourceTreeId: 'tree-src',
    targetPersonId: 'tgt-1',
    targetTreeId: 'tree-tgt',
    field: field,
    sourceValue: sourceValue,
    targetValue: targetValue,
    createdAt: '2026-04-01T00:00:00Z',
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: child),
    ),
  );
}

void main() {
  testWidgets('IdentityConflictsSheet: одно расхождение → header singular',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        IdentityConflictsSheet(
          conflicts: [
            _conflict(
              id: 'c-1',
              field: 'name',
              targetValue: 'Иван Петров',
              sourceValue: 'Иван П.',
            ),
          ],
          onChoice: (conflict, choice) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Расхождение в одной ветке'), findsOneWidget);
    expect(find.text('ФИО'), findsOneWidget);
    expect(find.text('Иван Петров'), findsOneWidget);
    expect(find.text('Иван П.'), findsOneWidget);
    expect(find.text('Оставить'), findsOneWidget);
    expect(find.text('Принять'), findsOneWidget);
  });

  testWidgets('IdentityConflictsSheet: несколько → header plural',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        IdentityConflictsSheet(
          conflicts: [
            _conflict(
              id: 'c-1',
              field: 'name',
              targetValue: 'Иван',
              sourceValue: 'Иоанн',
            ),
            _conflict(
              id: 'c-2',
              field: 'birthDate',
              targetValue: '1949-01-01',
              sourceValue: '1948-12-31',
            ),
          ],
          onChoice: (conflict, choice) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Расхождения в 2 полях'), findsOneWidget);
    expect(find.text('ФИО'), findsOneWidget);
    expect(find.text('Дата рождения'), findsOneWidget);
  });

  testWidgets(
      'IdentityConflictsSheet: tap «Оставить» → onChoice("keep")',
      (tester) async {
    String? lastChoice;
    String? lastConflictId;
    await tester.pumpWidget(
      _wrap(
        IdentityConflictsSheet(
          conflicts: [
            _conflict(
              id: 'c-1',
              field: 'name',
              targetValue: 'A',
              sourceValue: 'B',
            ),
          ],
          onChoice: (conflict, choice) async {
            lastChoice = choice;
            lastConflictId = conflict.id;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Оставить'));
    await tester.pumpAndSettle();

    expect(lastChoice, 'keep');
    expect(lastConflictId, 'c-1');
  });

  testWidgets(
      'IdentityConflictsSheet: tap «Принять» → onChoice("overwrite")',
      (tester) async {
    String? lastChoice;
    await tester.pumpWidget(
      _wrap(
        IdentityConflictsSheet(
          conflicts: [
            _conflict(
              id: 'c-1',
              field: 'name',
              targetValue: 'A',
              sourceValue: 'B',
            ),
          ],
          onChoice: (conflict, choice) async {
            lastChoice = choice;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Принять'));
    await tester.pumpAndSettle();

    expect(lastChoice, 'overwrite');
  });

  testWidgets(
      'IdentityConflictsSheet: photoGallery значение форматируется '
      'как «N фото»', (tester) async {
    await tester.pumpWidget(
      _wrap(
        IdentityConflictsSheet(
          conflicts: [
            _conflict(
              id: 'c-1',
              field: 'photoGallery',
              targetValue: const <String>['a', 'b'],
              sourceValue: const <String>['c', 'd', 'e'],
            ),
          ],
          onChoice: (conflict, choice) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Галерея фото'), findsOneWidget);
    expect(find.text('2 фото'), findsOneWidget);
    expect(find.text('3 фото'), findsOneWidget);
  });

  testWidgets(
      'IdentityConflictsSheet: null value → «— пусто —» rendering',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        IdentityConflictsSheet(
          conflicts: [
            _conflict(
              id: 'c-1',
              field: 'birthPlace',
              targetValue: null,
              sourceValue: 'Москва',
            ),
          ],
          onChoice: (conflict, choice) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('— пусто —'), findsOneWidget);
    expect(find.text('Москва'), findsOneWidget);
  });
}
