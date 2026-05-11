import 'package:flutter/material.dart';

/// Phase 3.4 chunk 5 (PHASE-3.4-UI-PROPOSAL.md §2.5): reusable
/// «⚠ N» badge для conflict surface на не-canvas screens.
/// Используется в relative_details (header), relatives_screen
/// (list-item trailing icon), потенциально на других screens.
///
/// **Без Material Tooltip** — известный конфликт с long-press
/// gesture'ами (chat_screen voice button). Accessibility описание
/// идёт через [`Semantics`] label — screen reader/announce'ируется
/// то же сообщение что в long-press'е, но без competing gesture'а
/// который проглатывает tap'ы на ребёнке.
///
/// Variants:
///   • `IdentityConflictsBadge` — компактный (для list-item
///     trailing): иконка + опциональный число-чип.
///   • `IdentityConflictsHeaderBanner` — большая полоса для
///     header-summary («N карточек требуют внимания»).
class IdentityConflictsBadge extends StatelessWidget {
  const IdentityConflictsBadge({
    required this.count,
    this.onTap,
    this.compact = false,
    super.key,
  });

  /// Сколько unresolved conflict'ов у этой entity. 0 → widget
  /// рендерит [`SizedBox.shrink`] (caller'у не надо conditionally
  /// строить).
  final int count;

  /// null → значок show-only (не tappable). Не-null → весь
  /// container tappable, переходит на conflict resolution.
  final VoidCallback? onTap;

  /// `true` — single icon без числа (для list-item где badge должен
  /// быть тонкий). `false` — иконка + число-chip.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semanticsLabel = compact
        ? 'У карточки есть $count ${_pluralConflict(count)}'
        : '$count ${_pluralConflict(count)}';

    final content = compact
        ? Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: scheme.error,
            semanticLabel: semanticsLabel,
          )
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 14,
                  color: scheme.error,
                ),
                const SizedBox(width: 4),
                Text(
                  '$count',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.error,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          );

    // Semantics обёртка ставится наружу всегда — даже без onTap.
    // Это «info-badge» seman, не interactive. `container: true` —
    // forces новый semantic node, иначе label не aнnотируется
    // (тестируется find.bySemanticsLabel).
    Widget wrapped = Semantics(
      container: true,
      label: semanticsLabel,
      button: onTap != null,
      excludeSemantics: true, // suppress нижний Icon semanticLabel
      child: content,
    );

    if (onTap != null) {
      wrapped = InkResponse(
        onTap: onTap,
        radius: 24,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: wrapped,
        ),
      );
    }
    return wrapped;
  }

  static String _pluralConflict(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'расхождение';
    if ([2, 3, 4].contains(mod10) && ![12, 13, 14].contains(mod100)) {
      return 'расхождения';
    }
    return 'расхождений';
  }
}

/// Header-summary полоса: «На N карточках есть расхождения.
/// [Посмотреть]» — для relative_details (per person) или
/// relatives_screen (per tree). Tap → caller открывает sheet.
class IdentityConflictsHeaderBanner extends StatelessWidget {
  const IdentityConflictsHeaderBanner({
    required this.count,
    required this.onTap,
    this.scope = ConflictBannerScope.singlePerson,
    super.key,
  });

  final int count;
  final VoidCallback onTap;

  /// `singlePerson` — banner на relative_details, «расхождения у
  /// этого человека». `tree` — banner на relatives_screen, «N
  /// карточек требуют внимания».
  final ConflictBannerScope scope;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final String title;
    switch (scope) {
      case ConflictBannerScope.singlePerson:
        title = count == 1
            ? 'Найдено одно расхождение с другой веткой'
            : 'Найдено $count ${_pluralConflicts(count)} с другими ветками';
        break;
      case ConflictBannerScope.tree:
        title = count == 1
            ? '1 карточка требует внимания'
            : '$count ${_pluralCards(count)} требуют внимания';
        break;
    }
    final actionLabel = scope == ConflictBannerScope.singlePerson
        ? 'Посмотреть и решить'
        : 'Открыть список';

    return Semantics(
      label: title,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.errorContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: scheme.error.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: scheme.error,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      actionLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onErrorContainer,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _pluralConflicts(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'расхождение';
    if ([2, 3, 4].contains(mod10) && ![12, 13, 14].contains(mod100)) {
      return 'расхождения';
    }
    return 'расхождений';
  }

  static String _pluralCards(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'карточка';
    if ([2, 3, 4].contains(mod10) && ![12, 13, 14].contains(mod100)) {
      return 'карточки';
    }
    return 'карточек';
  }
}

enum ConflictBannerScope {
  /// Используется в relative_details — «у этого человека N
  /// расхождений с другими ветками».
  singlePerson,

  /// Используется в relatives_screen — «N карточек в дереве
  /// требуют внимания».
  tree,
}
