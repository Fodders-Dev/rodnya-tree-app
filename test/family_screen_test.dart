// UX-core S1: «Семья» tab scaffold — the Список⇄Дерево toggle swaps bodies
// while keeping the visited tree mounted (lazy + keep-alive). Uses the
// builder seams so the toggle logic is tested without the heavy real screens.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/screens/family_screen.dart';
import 'package:rodnya/theme/app_theme.dart';

Widget _host({FamilyView initialView = FamilyView.list}) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: FamilyScreen(
        initialView: initialView,
        listBuilder: (_) => const Text('LIST-BODY'),
        treeBuilder: (_) => const Text('TREE-BODY'),
      ),
    );

void main() {
  testWidgets('defaults to the Список view; tree body not built yet',
      (tester) async {
    await tester.pumpWidget(_host());

    expect(find.text('LIST-BODY'), findsOneWidget);
    // Tree is deferred until first visited (and would be offstage anyway).
    expect(
      find.text('TREE-BODY', skipOffstage: false),
      findsNothing,
    );
    // Both toggle segments are present.
    expect(find.byKey(const Key('family-view-list')), findsOneWidget);
    expect(find.byKey(const Key('family-view-tree')), findsOneWidget);
    // 2c: сегменты toggle — тап-таргет ≥44dp (мобильная эргономика).
    expect(
      tester.getSize(find.byKey(const Key('family-view-list'))).height,
      greaterThanOrEqualTo(44.0),
    );
    expect(
      tester.getSize(find.byKey(const Key('family-view-tree'))).height,
      greaterThanOrEqualTo(44.0),
    );
  });

  testWidgets('tapping «Дерево» switches to the tree body', (tester) async {
    await tester.pumpWidget(_host());

    await tester.tap(find.byKey(const Key('family-view-tree')));
    await tester.pumpAndSettle();

    expect(find.text('TREE-BODY'), findsOneWidget);
    // List is kept mounted but offstage.
    expect(find.text('LIST-BODY'), findsNothing);
    expect(find.text('LIST-BODY', skipOffstage: false), findsOneWidget);
  });

  testWidgets('initialView: tree opens straight on the canvas', (tester) async {
    await tester.pumpWidget(_host(initialView: FamilyView.tree));

    expect(find.text('TREE-BODY'), findsOneWidget);
    expect(find.text('LIST-BODY'), findsNothing);
  });

  testWidgets('the visited tree stays mounted after toggling back to list',
      (tester) async {
    // UX-T1 FR1: на телефоне в режиме «Дерево» шелл-полоса переключателя
    // скрыта (тумблер переехал в топ-бар дерева). Этот тест про keep-alive
    // IndexedStack (ширинонезависимо) и переключается через шелл-тумблер,
    // поэтому гоним на desktop-ширине (>=1180), где полоса видна всегда.
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.binding.setSurfaceSize(const Size(1280, 1024));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host());

    await tester.tap(find.byKey(const Key('family-view-tree')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('family-view-list')));
    await tester.pumpAndSettle();

    expect(find.text('LIST-BODY'), findsOneWidget);
    // Tree remains in the IndexedStack (offstage) — state preserved.
    expect(find.text('TREE-BODY'), findsNothing);
    expect(find.text('TREE-BODY', skipOffstage: false), findsOneWidget);
  });

  test('viewFromQuery maps the deep-link param', () {
    expect(FamilyScreen.viewFromQuery('tree'), FamilyView.tree);
    expect(FamilyScreen.viewFromQuery('list'), FamilyView.list);
    expect(FamilyScreen.viewFromQuery(null), FamilyView.list);
    expect(FamilyScreen.viewFromQuery('garbage'), FamilyView.list);
  });
}
