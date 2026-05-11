import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/widgets/sensitive_contacts_section.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      )),
    ),
  );
}

void main() {
  testWidgets(
      'SensitiveContactsSection: non-owner полностью скрыт (privacy)',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SensitiveContactsSection(
          isOwner: false,
          phoneNumber: '+7 999 1234567',
          email: 'anna@example.com',
          addressLine: 'Москва, ул. Невская',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Section полностью невидим — ни заголовка, ни значений.
    expect(find.text('Контакты'), findsNothing);
    expect(find.text('+7 999 1234567'), findsNothing);
    expect(find.text('anna@example.com'), findsNothing);
    expect(find.text('Видно тебе'), findsNothing);
  });

  testWidgets(
      'SensitiveContactsSection: owner с заполненными значениями — '
      'все 3 строки + badges + footnote', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SensitiveContactsSection(
          isOwner: true,
          phoneNumber: '+7 999 1234567',
          email: 'anna@example.com',
          addressLine: 'Москва, ул. Невская',
          onEdit: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Контакты'), findsOneWidget);
    expect(find.text('Телефон:'), findsOneWidget);
    expect(find.text('+7 999 1234567'), findsOneWidget);
    expect(find.text('E-mail:'), findsOneWidget);
    expect(find.text('anna@example.com'), findsOneWidget);
    expect(find.text('Адрес:'), findsOneWidget);
    expect(find.text('Москва, ул. Невская'), findsOneWidget);

    // Badge на каждой строке (3 поля).
    expect(find.text('Видно тебе'), findsNWidgets(3));

    // Footnote (хотя бы фрагмент).
    expect(
      find.textContaining('Эти поля видны только тебе'),
      findsOneWidget,
    );
  });

  testWidgets(
      'SensitiveContactsSection: owner с пустыми значениями — empty state',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        SensitiveContactsSection(
          isOwner: true,
          phoneNumber: null,
          email: '',
          addressLine: '   ',
          onEdit: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Контакты'), findsOneWidget);
    expect(find.text('Контакты ещё не указаны'), findsOneWidget);
    // В empty state нет «Видно тебе» badge'ей.
    expect(find.text('Видно тебе'), findsNothing);
    // Кнопка добавления присутствует.
    expect(find.text('Добавить'), findsOneWidget);
  });

  testWidgets(
      'SensitiveContactsSection: tap «Изменить» вызывает onEdit',
      (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      _wrap(
        SensitiveContactsSection(
          isOwner: true,
          phoneNumber: '+7 999 1234567',
          onEdit: () => tapped++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Изменить'));
    await tester.pumpAndSettle();

    expect(tapped, 1);
  });

  testWidgets(
      'SensitiveContactsSection: только phone заполнен — только одна row '
      '(+ один badge), footnote всё равно показан', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SensitiveContactsSection(
          isOwner: true,
          phoneNumber: '+7 999 1234567',
          email: null,
          addressLine: null,
          onEdit: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Телефон:'), findsOneWidget);
    expect(find.text('E-mail:'), findsNothing);
    expect(find.text('Адрес:'), findsNothing);
    expect(find.text('Видно тебе'), findsOneWidget);
    expect(
      find.textContaining('Эти поля видны только тебе'),
      findsOneWidget,
    );
  });

  testWidgets(
      'SensitiveContactsSection: onEdit == null → нет кнопки «Изменить»',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SensitiveContactsSection(
          isOwner: true,
          phoneNumber: '+7 999 1234567',
          email: 'anna@example.com',
          addressLine: 'Москва',
          // ignore: avoid_redundant_argument_values
          onEdit: null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Изменить'), findsNothing);
    // Поля и footnote всё равно отображаются.
    expect(find.text('+7 999 1234567'), findsOneWidget);
    expect(
      find.textContaining('Эти поля видны только тебе'),
      findsOneWidget,
    );
  });
}
