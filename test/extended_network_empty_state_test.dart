// Phase 6 chunk 4c: ExtendedNetworkEmptyState widget render +
// CTA dispatch smoke.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/widgets/extended_network_empty_state.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('ExtendedNetworkEmptyState', () {
    testWidgets('renders future-positive copy + both CTAs', (tester) async {
      var shareCalls = 0;
      var findCalls = 0;
      await tester.pumpWidget(
        _wrap(
          ExtendedNetworkEmptyState(
            onShareInvitation: () => shareCalls++,
            onFindRelatives: () => findCalls++,
          ),
        ),
      );
      expect(find.text('Пока никого не нашлось через ваше дерево'),
          findsOneWidget);
      expect(find.text('Поделиться приглашением'), findsOneWidget);
      expect(find.text('Найти родню'), findsOneWidget);
      // Future-positive language — no "У вас нет" sad copy.
      expect(find.textContaining('У вас нет'), findsNothing);
      expect(find.textContaining('появится, когда'), findsOneWidget);
      expect(shareCalls, 0);
      expect(findCalls, 0);
    });

    testWidgets('share CTA tap → onShareInvitation called', (tester) async {
      var shareCalls = 0;
      await tester.pumpWidget(
        _wrap(
          ExtendedNetworkEmptyState(
            onShareInvitation: () => shareCalls++,
            onFindRelatives: () {},
          ),
        ),
      );
      await tester.tap(find.text('Поделиться приглашением'));
      await tester.pumpAndSettle();
      expect(shareCalls, 1);
    });

    testWidgets('find CTA tap → onFindRelatives called', (tester) async {
      var findCalls = 0;
      await tester.pumpWidget(
        _wrap(
          ExtendedNetworkEmptyState(
            onShareInvitation: () {},
            onFindRelatives: () => findCalls++,
          ),
        ),
      );
      await tester.tap(find.text('Найти родню'));
      await tester.pumpAndSettle();
      expect(findCalls, 1);
    });

    // Фикс «карточка запирает дерево»: крестик (сессионный дисмисс) и
    // «Показать моё дерево» (выход из режима «Все»). Оба опциональны —
    // без колбэков карточка остаётся прежней.
    testWidgets('крестик ≥44dp и зовёт onDismiss', (tester) async {
      var dismissed = false;
      await tester.pumpWidget(
        _wrap(
          SingleChildScrollView(
            child: ExtendedNetworkEmptyState(
              onShareInvitation: () {},
              onFindRelatives: () {},
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      );

      final dismiss = find.byKey(const Key('extended-empty-dismiss'));
      expect(dismiss, findsOneWidget);
      final box = tester.getSize(
        find.ancestor(of: dismiss, matching: find.byType(SizedBox)).first,
      );
      expect(box.width, greaterThanOrEqualTo(44));
      expect(box.height, greaterThanOrEqualTo(44));

      await tester.tap(dismiss);
      expect(dismissed, isTrue);
    });

    testWidgets('«Показать моё дерево» зовёт onBackToMine', (tester) async {
      var backToMine = false;
      await tester.pumpWidget(
        _wrap(
          SingleChildScrollView(
            child: ExtendedNetworkEmptyState(
              onShareInvitation: () {},
              onFindRelatives: () {},
              onBackToMine: () => backToMine = true,
            ),
          ),
        ),
      );

      await tester
          .tap(find.byKey(const Key('extended-empty-back-to-mine')));
      expect(backToMine, isTrue);
    });

    testWidgets('без новых колбэков — ни крестика, ни кнопки',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ExtendedNetworkEmptyState(
            onShareInvitation: () {},
            onFindRelatives: () {},
          ),
        ),
      );
      expect(
        find.byKey(const Key('extended-empty-dismiss')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('extended-empty-back-to-mine')),
        findsNothing,
      );
    });
  });
}
