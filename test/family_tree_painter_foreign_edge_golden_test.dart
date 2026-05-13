// Phase 4 chunk 3c golden snapshots — Element 2 edge color tint.
//
// Standalone painter goldens — wrap `FamilyTreePainter` в `CustomPaint`
// с fixed node positions + fixed FamilyConnection list. Не через
// full InteractiveFamilyTree (too brittle к layout changes).
//
// Coverage: 6 base + 1 spouse sanity = 7 goldens.
//   3 edge states × 2 themes (family-confirmed):
//     own-own        — both endpoints own → warm primary edge
//     own-foreign    — at-least-one foreign → cool slate edge
//     foreign-foreign — both foreign → cool slate edge (same logic)
//   + 1 spouse sanity (light, own-foreign) — verifies spouse painter
//     also picks cross-tree variant correctly (different stroke width
//     vs family edge).
//
// Pin'нутые vars per DECISIONS.md 2026-05-12 Gate 2 caveat:
//   ThemeMode.light / dark explicit, fixed window size, textScaler
//   = noScaling.
//
// 50% zoom для painter standalone deferred — same caveat as chunk 3b
// (Transform.scale не reflects real InteractiveViewer scroll-out).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/models/family_relation.dart';
import 'package:rodnya/theme/app_theme.dart';
import 'package:rodnya/widgets/interactive_family_tree.dart';

class _EdgeScenario {
  const _EdgeScenario({
    required this.name,
    required this.foreignIds,
    this.connectionType = RelationType.parent,
  });

  final String name;
  final Set<String> foreignIds;
  final RelationType connectionType;

  String filename(String theme) =>
      'goldens/phase4/chunk3c/${name}_$theme.png';
}

const _scenarios = <_EdgeScenario>[
  _EdgeScenario(name: 'family_own_own', foreignIds: <String>{}),
  _EdgeScenario(name: 'family_own_foreign', foreignIds: <String>{'p2'}),
  _EdgeScenario(
    name: 'family_foreign_foreign',
    foreignIds: <String>{'p1', 'p2'},
  ),
];

Widget _wrapForGolden(
  Widget child, {
  required String themeKey,
}) {
  final brightness =
      themeKey == 'dark' ? Brightness.dark : Brightness.light;
  final tokens = brightness == Brightness.dark
      ? RodnyaDesignTokens.dark
      : RodnyaDesignTokens.light;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: brightness,
      extensions: <ThemeExtension<dynamic>>[tokens],
    ),
    themeMode: brightness == Brightness.dark
        ? ThemeMode.dark
        : ThemeMode.light,
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(300, 200),
        textScaler: TextScaler.noScaling,
      ),
      child: Scaffold(
        backgroundColor: tokens.bgBase,
        body: Center(child: child),
      ),
    ),
  );
}

Widget _buildPainterCanvas(_EdgeScenario scenario, RodnyaDesignTokens tokens) {
  // Two nodes 'p1' and 'p2' с fixed positions, one connection между ними.
  final nodePositions = <String, Offset>{
    'p1': const Offset(60, 100),
    'p2': const Offset(220, 100),
  };
  final connections = <FamilyConnection>[
    FamilyConnection(
      fromId: 'p1',
      toId: 'p2',
      type: scenario.connectionType,
    ),
  ];
  return SizedBox(
    width: 280,
    height: 180,
    child: CustomPaint(
      painter: FamilyTreePainter(
        nodePositions,
        connections,
        lineColor: tokens.inkSecondary,
        mutedLineColor: tokens.inkMuted,
        spouseColor: tokens.warm,
        junctionColor: tokens.inkSecondary,
        foreignEdgeColor: tokens.edgeForeignTint,
        foreignPersonIds: scenario.foreignIds,
      ),
    ),
  );
}

void main() {
  // 6 base goldens (3 family-edge states × 2 themes).
  for (final scenario in _scenarios) {
    for (final themeKey in <String>['light', 'dark']) {
      testWidgets(
        'golden: ${scenario.name} @ $themeKey',
        (tester) async {
          tester.view.physicalSize = const Size(300, 200);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.reset();
          });

          final tokens = themeKey == 'dark'
              ? RodnyaDesignTokens.dark
              : RodnyaDesignTokens.light;
          await tester.pumpWidget(
            _wrapForGolden(
              _buildPainterCanvas(scenario, tokens),
              themeKey: themeKey,
            ),
          );
          await tester.pumpAndSettle();

          await expectLater(
            find.byType(CustomPaint).last,
            matchesGoldenFile(scenario.filename(themeKey)),
          );
        },
      );
    }
  }

  // 1 spouse sanity (light theme, own-foreign): verifies that
  // spouse edges (stroke width 1.4 vs family 1.6) also pick
  // cross-tree variant correctly. Optional per Артёмов call,
  // but cheap insurance.
  testWidgets('golden: spouse_own_foreign @ light (sanity)',
      (tester) async {
    tester.view.physicalSize = const Size(300, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.reset();
    });

    const scenario = _EdgeScenario(
      name: 'spouse_own_foreign',
      foreignIds: <String>{'p2'},
      connectionType: RelationType.spouse,
    );
    final tokens = RodnyaDesignTokens.light;
    await tester.pumpWidget(
      _wrapForGolden(
        _buildPainterCanvas(scenario, tokens),
        themeKey: 'light',
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(CustomPaint).last,
      matchesGoldenFile(scenario.filename('light')),
    );
  });
}
