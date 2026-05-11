import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/widgets/identity_conflicts_badge.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: child,
      ),
    ),
  );
}

void main() {
  group('IdentityConflictsBadge', () {
    testWidgets('count == 0 → SizedBox.shrink (badge не отображается)',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const IdentityConflictsBadge(count: 0)),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('non-compact: иконка + число chip', (tester) async {
      await tester.pumpWidget(
        _wrap(const IdentityConflictsBadge(count: 3)),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('compact: только иконка (без числа)', (tester) async {
      await tester.pumpWidget(
        _wrap(const IdentityConflictsBadge(count: 5, compact: true)),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.text('5'), findsNothing);
    });

    testWidgets('onTap вызывается при tap (interactive badge)',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        _wrap(IdentityConflictsBadge(
          count: 2,
          onTap: () => tapped++,
        )),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.error_outline_rounded));
      await tester.pumpAndSettle();

      expect(tapped, 1);
    });

    testWidgets(
        'Semantics label содержит число + правильную форму слова '
        '«расхождение/расхождения/расхождений»', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Column(
            children: [
              const IdentityConflictsBadge(count: 1),
              const IdentityConflictsBadge(count: 2),
              const IdentityConflictsBadge(count: 5),
              const IdentityConflictsBadge(count: 21),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final handle = tester.ensureSemantics();
      try {
        expect(
          find.bySemanticsLabel('1 расхождение'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('2 расхождения'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('5 расхождений'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('21 расхождение'),
          findsOneWidget,
        );
      } finally {
        handle.dispose();
      }
    });
  });

  group('IdentityConflictsHeaderBanner', () {
    testWidgets('count == 0 → SizedBox.shrink', (tester) async {
      await tester.pumpWidget(
        _wrap(IdentityConflictsHeaderBanner(count: 0, onTap: () {})),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('расхождение'), findsNothing);
    });

    testWidgets(
        'scope=singlePerson, count=1 → «одно расхождение с другой веткой»',
        (tester) async {
      await tester.pumpWidget(
        _wrap(IdentityConflictsHeaderBanner(
          count: 1,
          onTap: () {},
        )),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Найдено одно расхождение с другой веткой'),
        findsOneWidget,
      );
      expect(find.text('Посмотреть и решить'), findsOneWidget);
    });

    testWidgets(
        'scope=singlePerson, count=3 → «3 расхождения с другими ветками»',
        (tester) async {
      await tester.pumpWidget(
        _wrap(IdentityConflictsHeaderBanner(
          count: 3,
          onTap: () {},
        )),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Найдено 3 расхождения с другими ветками'),
        findsOneWidget,
      );
    });

    testWidgets('scope=tree, count=5 → «5 карточек требуют внимания»',
        (tester) async {
      await tester.pumpWidget(
        _wrap(IdentityConflictsHeaderBanner(
          count: 5,
          onTap: () {},
          scope: ConflictBannerScope.tree,
        )),
      );
      await tester.pumpAndSettle();

      expect(find.text('5 карточек требуют внимания'), findsOneWidget);
      expect(find.text('Открыть список'), findsOneWidget);
    });

    testWidgets('tap вызывает onTap', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        _wrap(IdentityConflictsHeaderBanner(
          count: 2,
          onTap: () => tapped++,
        )),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(IdentityConflictsHeaderBanner));
      await tester.pumpAndSettle();

      expect(tapped, 1);
    });
  });
}
