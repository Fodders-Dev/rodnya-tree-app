part of '../tree_view_screen.dart';

enum _TreeToolbarAction {
  refresh,
  openHistory,
  sendDiagnostics,
  openChats,
  createPost,
  // UX-T1.2 FR-c: вторичные контролы (undo/redo/поиск/фильтры) на телефоне
  // переезжают сюда, в overflow «•••», вместо постоянных пилюль топ-бара.
  undo,
  redo,
  openSearch,
  openFilters,
  toggleEditMode,
  toggleSelectionMode,
  openBranchChat,
  openBranchDetails,
  copyPublicLink,
  resetBranchFocus,
  resetLayout,
}

/// Smart-selection options surfaced in the selection toolbar's
/// «Расширить» popup. Each one expands the user's current
/// selection set by walking parent / child edges from the
/// already-picked anchors — turning «one tap on mama» into «mama +
/// all her line».
enum _SelectionExpand {
  ancestors,
  descendants,
  lineage,
}

class SectionTitle extends StatelessWidget {
  final String title;

  const SectionTitle({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _ExtendedSearchButton extends StatelessWidget {
  const _ExtendedSearchButton({required this.tokens, required this.onTap});

  final RodnyaDesignTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: tokens.surfaceStrong,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.surfaceLine),
        ),
        child: Tooltip(
          message: 'Поиск в расширенной сети',
          child: Icon(
            Icons.search_rounded,
            size: 19,
            color: tokens.ink,
          ),
        ),
      ),
    );
  }
}

class _FiltersButton extends StatelessWidget {
  const _FiltersButton({required this.tokens, required this.onTap});

  final RodnyaDesignTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: tokens.surfaceStrong,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.surfaceLine),
        ),
        child: Tooltip(
          message: 'Фильтры расширенной сети',
          child: Icon(
            Icons.tune_rounded,
            size: 19,
            color: tokens.ink,
          ),
        ),
      ),
    );
  }
}

class _TreeTopbarPill extends StatelessWidget {
  const _TreeTopbarPill({
    required this.tokens,
    required this.child,
    required this.tooltip,
    required this.onTap,
  });

  final RodnyaDesignTokens tokens;
  final Widget child;
  final String tooltip;

  /// `null` означает disabled-state — пилюля всё ещё видна
  /// (приглушенный фон, серая рамка), но не реагирует на тап.
  /// Нужно для undo/redo кнопок которые всегда должны быть в
  /// топбаре, чтобы юзер видел что функциональность есть.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: tokens.surfaceStrong.withValues(alpha: isEnabled ? 1.0 : 0.5),
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: tokens.surfaceLine.withValues(alpha: isEnabled ? 1.0 : 0.4),
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet shown when the user taps the 💡 voltage-indicator
/// dot on a card. Lists each suggestion with target person + tree
/// origin + match reasons + confirm/dismiss buttons.
