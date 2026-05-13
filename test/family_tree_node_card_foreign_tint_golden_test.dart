// Phase 4 chunk 3b golden snapshots — Element 1 foreign tint.
//
// Goldens cover 4 states × 2 themes × 2 zoom levels = 16 strict
// snapshots. Pin'нутые variables per DECISIONS.md 2026-05-12
// Gate 2 caveat (ThemeMode.light/dark explicit, fixed window
// size, textScaler = noScaling).
//
// 25% zoom snapshots deferred (DECISIONS.md 2026-05-12 chunk 3b
// follow-up): capture'ть native 25% требует full InteractiveViewer
// canvas context, не trivial standalone widget setup. Tint
// distinguishability на 25% — visual review item, не strict
// regression target.
//
// Goldens regen: `flutter test --update-goldens
//   test/family_tree_node_card_foreign_tint_golden_test.dart`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/models/family_person.dart' show Gender;
import 'package:rodnya/theme/app_theme.dart';
import 'package:rodnya/widgets/family_tree_node_card.dart';
import 'package:rodnya/widgets/identity_conflicts_badge.dart';

class _ConfigKey {
  const _ConfigKey({
    required this.state,
    required this.theme,
    required this.zoom,
  });

  final String state;
  final String theme; // 'light' | 'dark'
  final double zoom;

  String get filename =>
      'goldens/phase4/chunk3b/${state}_${theme}_z'
      '${(zoom * 100).round()}.png';
}

const _states = <String>[
  'own_non_self', // mine mode либо extended mode own; default warm tint
  'extended_own', // explicitly extended mode + own (= same render как own_non_self)
  'extended_foreign', // extended mode foreign; cool tint
  'extended_foreign_with_conflict', // foreign + IdentityConflictsBadge composed
];

const _themes = <String>['light', 'dark'];
const _zoomLevels = <double>[1.0, 0.5];

Widget _wrapForGolden(
  Widget child, {
  required String themeKey,
  required double zoom,
}) {
  final brightness =
      themeKey == 'dark' ? Brightness.dark : Brightness.light;
  final tokens = brightness == Brightness.dark
      ? RodnyaDesignTokens.dark
      : RodnyaDesignTokens.light;
  final themeData = ThemeData(
    brightness: brightness,
    extensions: <ThemeExtension<dynamic>>[tokens],
  );
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: brightness == Brightness.light ? themeData : null,
    darkTheme: brightness == Brightness.dark ? themeData : null,
    themeMode: brightness == Brightness.dark
        ? ThemeMode.dark
        : ThemeMode.light,
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(390, 844),
        textScaler: TextScaler.noScaling,
      ),
      child: Scaffold(
        backgroundColor: tokens.bgBase,
        body: Center(
          child: Transform.scale(scale: zoom, child: child),
        ),
      ),
    ),
  );
}

Widget _buildCardForState(String state) {
  final card = FamilyTreeNodeCard(
    displayName: 'Иван Петров',
    lifeDates: '1990 — 2024',
    displayGender: Gender.male,
    isForeignNode: state == 'extended_foreign' ||
        state == 'extended_foreign_with_conflict',
  );
  if (state == 'extended_foreign_with_conflict') {
    return SizedBox(
      width: 140,
      height: 160,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: card),
          const Positioned(
            top: 2,
            right: 2,
            child: IdentityConflictsBadge(count: 2, compact: true),
          ),
        ],
      ),
    );
  }
  return SizedBox(width: 140, child: card);
}

void main() {
  for (final state in _states) {
    for (final themeKey in _themes) {
      for (final zoom in _zoomLevels) {
        final config = _ConfigKey(
          state: state,
          theme: themeKey,
          zoom: zoom,
        );
        testWidgets(
          'golden: $state @ $themeKey, ${(zoom * 100).round()}%',
          (tester) async {
            tester.view.physicalSize = const Size(390, 844);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(() {
              tester.view.reset();
            });

            await tester.pumpWidget(
              _wrapForGolden(
                _buildCardForState(state),
                themeKey: themeKey,
                zoom: zoom,
              ),
            );
            await tester.pumpAndSettle();

            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(config.filename),
            );
          },
        );
      }
    }
  }
}
