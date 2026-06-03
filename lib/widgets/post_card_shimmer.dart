import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_theme.dart';
import 'glass_panel.dart';

/// Loading placeholder that mirrors [PostCard]'s real geometry — same
/// GlassPanel shell, 40dp author avatar, two header lines, a few body
/// lines, a 16:9 media block, then the divider + 3-button action bar.
/// Because the skeleton matches where content will land, the swap to
/// real posts reads as a settle rather than a reflow. Shimmer tones are
/// pulled from the warm palette (surface containers) so it stays
/// on-brand instead of the old neutral grey card.
class PostCardShimmer extends StatelessWidget {
  const PostCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final isDark = theme.brightness == Brightness.dark;
    // Resting tone + brighter sweep, both warm-palette derived.
    final baseColor = isDark
        ? theme.colorScheme.surfaceContainerHigh
        : theme.colorScheme.surfaceContainerHighest;
    final highlightColor = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surfaceContainerLowest;

    return GlassPanel(
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
      borderRadius: BorderRadius.circular(tokens.radiusMd + 2),
      plain: true,
      child: Shimmer.fromColors(
        baseColor: baseColor,
        highlightColor: highlightColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header — avatar + name/meta lines (mirrors _buildPostHeader).
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
              child: Row(
                children: [
                  _block(width: 40, height: 40, shape: BoxShape.circle),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      _ShimmerBar(width: 120, height: 13),
                      SizedBox(height: 6),
                      _ShimmerBar(width: 80, height: 10),
                    ],
                  ),
                ],
              ),
            ),
            // Body text lines (mirrors content padding).
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ShimmerBar(width: double.infinity, height: 12),
                  SizedBox(height: 8),
                  _ShimmerBar(width: double.infinity, height: 12),
                  SizedBox(height: 8),
                  _ShimmerBar(width: 160, height: 12),
                ],
              ),
            ),
            // 16:9 media block (mirrors single-image padding + radius18).
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
            // Divider + 3-button action bar (mirrors _buildPostActions).
            Container(
              height: 0.7,
              margin: const EdgeInsets.symmetric(horizontal: 14),
              color: Colors.white,
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(6, 10, 6, 12),
              child: Row(
                children: [
                  Expanded(child: Center(child: _ShimmerBar(width: 56, height: 14))),
                  Expanded(child: Center(child: _ShimmerBar(width: 56, height: 14))),
                  Expanded(child: Center(child: _ShimmerBar(width: 56, height: 14))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _block({
    required double width,
    required double height,
    BoxShape shape = BoxShape.rectangle,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: shape,
      ),
    );
  }
}

/// A single rounded shimmer bar. The fill colour is irrelevant (Shimmer
/// paints its gradient over the opaque area) — only the shape matters.
class _ShimmerBar extends StatelessWidget {
  const _ShimmerBar({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }
}
