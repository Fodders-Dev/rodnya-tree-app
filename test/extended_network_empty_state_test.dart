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
  });
}
