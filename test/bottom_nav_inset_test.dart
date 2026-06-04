// Chunk A: AppTheme.bottomNavInset — the global bottom-edge clearance for
// the floating nav pill, mirror of topbarHeight. Screens under
// extendBody:true reserve this so content clears the pill.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/theme/app_theme.dart';

void main() {
  Future<double> insetFor(WidgetTester tester, double safeBottom) async {
    late double inset;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(padding: EdgeInsets.only(bottom: safeBottom)),
        child: Builder(
          builder: (context) {
            inset = AppTheme.bottomNavInset(context);
            return const SizedBox();
          },
        ),
      ),
    );
    return inset;
  }

  testWidgets('bottomNavInset = bar height + max(safe-bottom, 14) + gap',
      (tester) async {
    // Device inset below the 14dp SafeArea floor → the floor wins.
    final small = await insetFor(tester, 6);
    expect(small, AppTheme.bottomNavContentHeight + 14.0 + 8.0);

    // Gesture-nav device inset above the floor → the device inset wins.
    final large = await insetFor(tester, 48);
    expect(large, AppTheme.bottomNavContentHeight + 48.0 + 8.0);

    // Inset grows with the device safe-area.
    expect(large, greaterThan(small));
  });
}
