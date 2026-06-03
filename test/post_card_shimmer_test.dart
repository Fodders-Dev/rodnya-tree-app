// P2: the feed loading skeleton (PostCardShimmer) is on-brand — it
// renders inside a GlassPanel with a Shimmer sweep in both themes,
// mirroring PostCard's geometry rather than the old grey Material card.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shimmer/shimmer.dart';
import 'package:rodnya/theme/app_theme.dart';
import 'package:rodnya/widgets/glass_panel.dart';
import 'package:rodnya/widgets/post_card_shimmer.dart';

void main() {
  testWidgets('PostCardShimmer renders on-brand skeleton in light + dark',
      (tester) async {
    for (final theme in <ThemeData>[AppTheme.lightTheme, AppTheme.darkTheme]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: SingleChildScrollView(child: PostCardShimmer()),
          ),
        ),
      );
      // Shimmer animates indefinitely — pump a couple of frames, never
      // pumpAndSettle (that would spin forever on the repeating sweep).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.byType(PostCardShimmer), findsOneWidget);
      expect(
        find.byType(GlassPanel),
        findsOneWidget,
        reason: 'skeleton shares the GlassPanel shell with PostCard',
      );
      expect(
        find.byType(Shimmer),
        findsOneWidget,
        reason: 'warm shimmer sweep, not a static grey card',
      );
      expect(tester.takeException(), isNull);
    }
  });
}
