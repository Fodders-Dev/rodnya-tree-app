part of '../interactive_family_tree.dart';

class _GenerationGuideBadge extends StatelessWidget {
  const _GenerationGuideBadge({
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    // Reference `.gs-main`: 11px 700 ink-2; `.gs-sub`: 9.5px 600 ink-3 dimmed.
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 12, 8),
      decoration: BoxDecoration(
        color: tokens.surface.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: tokens.surfaceLine.withValues(alpha: 0.55),
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: AppTheme.sans(
              color: tokens.inkSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              height: 1.0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: AppTheme.sans(
                color: tokens.inkMuted,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

/// wanted: "small bulb that lights up when there's something
/// to look at, doesn't pop modals on you 200 times".
class _IdentitySuggestionsBadge extends StatelessWidget {
  const _IdentitySuggestionsBadge({
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: count == 1
          ? 'Возможный дубликат в другом дереве'
          : 'Возможные дубликаты в других деревьях ($count)',
      child: Tooltip(
        message: count == 1
            ? 'Похоже, эта карточка есть и в другом вашем дереве'
            : '$count похожих карточек в других ваших деревьях',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer.withValues(alpha: 0.95),
                shape: BoxShape.circle,
                border: Border.all(
                  color: scheme.tertiary.withValues(alpha: 0.6),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: scheme.tertiary.withValues(alpha: 0.18),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Icon(
                Icons.lightbulb_outline_rounded,
                size: 15,
                color: scheme.tertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Phase 1.3 ⚠️ badge — appears on the bottom-right of a card
/// when at least one identity-field conflict is unresolved on
/// the linked person on this tree. Visual is more assertive
/// than the 💡 badge (error-tinted vs. tertiary, always visible
/// regardless of hover) because the meaning is also more
/// urgent: data diverged, the user needs to pick a side.
///
/// Tap → host opens the resolve sheet. The sheet is owned by
/// tree_view_screen so it can wire to the service and refresh
/// counts after resolution.
class _IdentityConflictsBadge extends StatelessWidget {
  const _IdentityConflictsBadge({
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: count == 1
          ? 'Конфликт правок: одна карточка'
          : 'Конфликты правок: $count полей',
      child: Tooltip(
        message: count == 1
            ? 'Поле этой карточки расходится с другой веткой — нажмите, чтобы выбрать значение'
            : '$count полей расходятся с другой веткой — нажмите, чтобы разобраться',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.95),
                shape: BoxShape.circle,
                border: Border.all(
                  color: scheme.error.withValues(alpha: 0.6),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: scheme.error.withValues(alpha: 0.18),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 15,
                color: scheme.error,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
