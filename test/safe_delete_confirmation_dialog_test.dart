// Ship 2026-05-26 (UX audit Screen 3.5 polish): shared destructive-
// action confirmation dialog. Tests cover render shape, Cancel returns
// false, Confirm returns true, barrierDismissible=false блок outside
// tap, custom labels surface correctly.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/widgets/safe_delete_confirmation_dialog.dart';

void main() {
  testWidgets('renders title + body + default buttons', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SafeDeleteConfirmationDialog(
            title: 'Удалить публикацию?',
            body: 'Пост исчезнет у всех родственников.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Удалить публикацию?'), findsOneWidget);
    expect(find.text('Пост исчезнет у всех родственников.'), findsOneWidget);
    expect(find.text('Отмена'), findsOneWidget);
    expect(find.text('Удалить'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
  });

  testWidgets('custom confirm/cancel labels surface', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SafeDeleteConfirmationDialog(
            title: 'Удалить аккаунт?',
            body: 'Backend wipes everything.',
            confirmLabel: 'Удалить навсегда',
            cancelLabel: 'Не сейчас',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Удалить навсегда'), findsOneWidget);
    expect(find.text('Не сейчас'), findsOneWidget);
  });

  testWidgets('Cancel button returns false', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showSafeDeleteConfirmation(
                    context,
                    title: 't',
                    body: 'b',
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
    await tester.tap(find.byKey(const Key('safe-delete-cancel')));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('Confirm button returns true', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showSafeDeleteConfirmation(
                    context,
                    title: 't',
                    body: 'b',
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
    await tester.tap(find.byKey(const Key('safe-delete-confirm')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('barrierDismissible=false — outside tap не закрывает',
      (tester) async {
    bool? result = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showSafeDeleteConfirmation(
                    context,
                    title: 't',
                    body: 'b',
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
    // Try tap on barrier — should NOT dismiss.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    // Dialog still visible.
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    // Result still false (initial — not affected).
    expect(result, isFalse);
  });

  testWidgets('helper returns false when system back closes dialog',
      (tester) async {
    bool? result = true; // distinct sentinel from helper's false default
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showSafeDeleteConfirmation(
                    context,
                    title: 't',
                    body: 'b',
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
    // System back via Navigator pop без value — helper coerces к false.
    Navigator.of(tester.element(find.byKey(const Key('safe-delete-cancel'))))
        .pop();
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
