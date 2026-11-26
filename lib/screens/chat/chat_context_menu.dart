part of '../chat_screen.dart';

class _DesktopMessageContextMenu<T> extends StatelessWidget {
  const _DesktopMessageContextMenu({
    required this.actions,
    required this.onActionSelected,
    this.reactions = const <String>[],
    this.onReactionSelected,
  });

  final List<_ContextMenuActionItem<T>> actions;
  final List<String> reactions;
  final ValueChanged<T> onActionSelected;
  final ValueChanged<String>? onReactionSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF1F1F22) : Colors.white;
    final reactionBarColor =
        isDark ? const Color(0xFF2A2A2F) : const Color(0xFFF4F5F8);
    final shadowColor = Colors.black.withValues(alpha: isDark ? 0.34 : 0.16);

    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (reactions.isNotEmpty && onReactionSelected != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: reactionBarColor,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: shadowColor,
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: reactions
                      .map(
                        (emoji) => InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => onReactionSelected?.call(emoji),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 26, height: 1),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            if (reactions.isNotEmpty && onReactionSelected != null)
              const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: 30,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var index = 0; index < actions.length; index++) ...[
                      _DesktopMessageContextMenuTile<T>(
                        item: actions[index],
                        onTap: () => onActionSelected(actions[index].value),
                      ),
                      if (index != actions.length - 1)
                        Divider(
                          height: 1,
                          indent: 54,
                          endIndent: 16,
                          color: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.32),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopMessageContextMenuTile<T> extends StatelessWidget {
  const _DesktopMessageContextMenuTile({
    required this.item,
    required this.onTap,
  });

  final _ContextMenuActionItem<T> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foregroundColor = item.isDestructive
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              child: Icon(
                item.icon,
                size: 21,
                color: foregroundColor,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                item.label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<T?> showBlurredActionsSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Закрыть',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (context, animation, secondary) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              elevation: 18,
              shadowColor: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: builder(context),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondary, child) {
      // We control three things: backdrop blur sigma, dim alpha, and
      // the card's slide-up + fade. AnimatedBuilder rebuilds the blur
      // every frame; the card itself nests cheap transitions.
      final eased = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return AnimatedBuilder(
        animation: eased,
        builder: (context, _) {
          final t = eased.value;
          return Stack(
            children: [
              // Backdrop blur grows / shrinks with the route — same
              // pattern Telegram / iMessage use to draw attention to
              // the floating action card.
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: true,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 14 * t,
                      sigmaY: 14 * t,
                    ),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.32 * t),
                    ),
                  ),
                ),
              ),
              FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.20),
                    end: Offset.zero,
                  ).animate(eased),
                  child: child,
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Composer-bar slot with smooth show / hide. Wraps a reply / edit /
/// forward bar in [AnimatedSize] (row-height grow) + [AnimatedSwitcher]
/// (cross-fade + slide-down for the bar itself). When [show] flips on
/// the bar slides down 8dp + fades in over 220ms; when it flips off
/// the bar fades out and the row collapses to 0 height.
///
/// Pass `child: null` when the bar should be hidden so the slot has
/// nothing to render — same shape Flutter's `AnimatedSwitcher` expects
/// for the "empty" branch. The 8dp bottom gap is part of the slot
/// itself so the gap collapses with the bar (no leftover whitespace).
