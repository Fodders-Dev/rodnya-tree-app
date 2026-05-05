import 'package:flutter/material.dart';

import '../models/reaction_summary.dart';
import '../theme/app_theme.dart';

/// Renders a wrapping row of emoji-count chips for any reactable
/// surface (post, comment). Tap on a chip toggles the current user's
/// reaction with that emoji. Chip the user has already picked is
/// highlighted with the accent color. Tapping the emoji also runs a
/// "ka-bunce" scale animation (1.0 → 1.18 → 1.0) so the chip feels
/// responsive — same satisfying click feel TG / iMessage have.
class ReactionChipStrip extends StatelessWidget {
  const ReactionChipStrip({
    super.key,
    required this.reactions,
    required this.currentUserId,
    required this.onToggle,
    this.alignment = WrapAlignment.start,
  });

  final List<ReactionSummary> reactions;
  final String? currentUserId;
  final ValueChanged<String> onToggle;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    final visible = reactions
        .where((r) => r.emoji.trim().isNotEmpty && r.count > 0)
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return Wrap(
      alignment: alignment,
      spacing: 6,
      runSpacing: 6,
      children: visible.map((r) {
        final mine = r.isMine(currentUserId);
        return _ReactionChip(
          // Key by emoji so chip identity is preserved across rebuilds
          // — that lets the inner AnimationController persist while
          // counts flip up/down on toggles.
          key: ValueKey<String>('rxn-${r.emoji}'),
          emoji: r.emoji,
          count: r.count,
          mine: mine,
          tokens: tokens,
          onTap: () => onToggle(r.emoji),
        );
      }).toList(),
    );
  }
}

class _ReactionChip extends StatefulWidget {
  const _ReactionChip({
    super.key,
    required this.emoji,
    required this.count,
    required this.mine,
    required this.tokens,
    required this.onTap,
  });

  final String emoji;
  final int count;
  final bool mine;
  final RodnyaDesignTokens tokens;
  final VoidCallback onTap;

  @override
  State<_ReactionChip> createState() => _ReactionChipState();
}

class _ReactionChipState extends State<_ReactionChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce;

  @override
  void initState() {
    super.initState();
    _bounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
  }

  @override
  void didUpdateWidget(covariant _ReactionChip old) {
    super.didUpdateWidget(old);
    // Auto-bounce on count change too — the user (or the server-truth
    // reconciliation) flipped this reaction. Bouncing on every count
    // change makes group reactions feel alive without an explicit
    // animation per other-user.
    if (old.count != widget.count) {
      _runBounce();
    }
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  void _runBounce() {
    _bounce.forward(from: 0);
  }

  void _handleTap() {
    _runBounce();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final mine = widget.mine;
    return AnimatedBuilder(
      animation: _bounce,
      builder: (context, child) {
        // 0 → 0.5 → 1.0 maps to 1.0 → 1.18 → 1.0 — TweenSequence
        // gives a peaky scale that feels punchier than a single
        // ease curve.
        final t = _bounce.value;
        final scale = t < 0.5
            ? 1.0 + 0.18 * (t / 0.5)
            : 1.18 - 0.18 * ((t - 0.5) / 0.5);
        return Transform.scale(scale: scale, child: child);
      },
      child: Material(
        color: mine
            ? tokens.accentSoft
            : tokens.surfaceStrong.withValues(alpha: 0.6),
        shape: StadiumBorder(
          side: BorderSide(
            color: mine ? tokens.accent : tokens.surfaceLine,
            width: mine ? 1.2 : 0.6,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: _handleTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 9,
              vertical: 4,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.emoji,
                  style: const TextStyle(fontSize: 14, height: 1.2),
                ),
                const SizedBox(width: 4),
                // AnimatedSwitcher on the count text so number flips
                // (3 → 4 / 4 → 3) cross-fade instead of hard cut.
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, animation) {
                    return ScaleTransition(
                      scale: Tween<double>(begin: 0.7, end: 1.0)
                          .animate(animation),
                      child: FadeTransition(
                        opacity: animation,
                        child: child,
                      ),
                    );
                  },
                  child: Text(
                    '${widget.count}',
                    key: ValueKey<int>(widget.count),
                    style: AppTheme.sans(
                      color: mine ? tokens.accent : tokens.inkSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
