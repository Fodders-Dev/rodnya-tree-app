import 'package:flutter/material.dart';

import '../models/reaction_summary.dart';
import '../theme/app_theme.dart';

/// Renders a wrapping row of emoji-count chips for any reactable
/// surface (post, comment). Tap on a chip toggles the current user's
/// reaction with that emoji. Chip the user has already picked is
/// highlighted with the accent color.
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
        return Material(
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
            onTap: () => onToggle(r.emoji),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 9,
                vertical: 4,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    r.emoji,
                    style: const TextStyle(fontSize: 14, height: 1.2),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${r.count}',
                    style: AppTheme.sans(
                      color: mine ? tokens.accent : tokens.inkSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
