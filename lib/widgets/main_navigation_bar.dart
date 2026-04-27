import 'dart:ui';

import 'package:flutter/material.dart';

class MainNavigationBar extends StatelessWidget {
  const MainNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.unreadNotificationsStream,
    required this.unreadChatsStream,
    required this.pendingInvitationsCountStream,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final Stream<int> unreadNotificationsStream;
  final Stream<int> unreadChatsStream;
  final Stream<int> pendingInvitationsCountStream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: unreadNotificationsStream,
      initialData: 0,
      builder: (context, notificationsSnapshot) {
        final unreadNotificationsCount = notificationsSnapshot.data ?? 0;
        return StreamBuilder<int>(
          stream: unreadChatsStream,
          initialData: 0,
          builder: (context, unreadSnapshot) {
            final unreadCount = unreadSnapshot.data ?? 0;
            return StreamBuilder<int>(
              stream: pendingInvitationsCountStream,
              initialData: 0,
              builder: (context, invitationsSnapshot) {
                final pendingInvitationsCount = invitationsSnapshot.data ?? 0;

                final items = <_NavItemData>[
                  _NavItemData(
                    label: 'Главная',
                    outlinedIcon: Icons.home_outlined,
                    filledIcon: Icons.home_rounded,
                    count: unreadNotificationsCount,
                  ),
                  const _NavItemData(
                    label: 'Родные',
                    outlinedIcon: Icons.people_outline_rounded,
                    filledIcon: Icons.people_rounded,
                  ),
                  _NavItemData(
                    label: 'Дерево',
                    outlinedIcon: Icons.account_tree_outlined,
                    filledIcon: Icons.account_tree_rounded,
                    count: pendingInvitationsCount,
                  ),
                  _NavItemData(
                    label: 'Чаты',
                    outlinedIcon: Icons.chat_bubble_outline_rounded,
                    filledIcon: Icons.chat_bubble_rounded,
                    count: unreadCount,
                  ),
                  const _NavItemData(
                    label: 'Профиль',
                    outlinedIcon: Icons.person_outline_rounded,
                    filledIcon: Icons.person_rounded,
                  ),
                ];

                final theme = Theme.of(context);
                final scheme = theme.colorScheme;
                final isDark = theme.brightness == Brightness.dark;

                return SafeArea(
                  minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final showLabels = constraints.maxWidth >= 480;
                      final itemBorderRadius = showLabels ? 22.0 : 20.0;

                      return DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(34),
                          boxShadow: [
                            BoxShadow(
                              color: scheme.shadow.withValues(
                                alpha: isDark ? 0.36 : 0.10,
                              ),
                              blurRadius: 28,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(34),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: scheme.surface.withValues(
                                        alpha: isDark ? 0.62 : 0.7,
                                      ),
                                    ),
                                  ),
                                ),
                                // Specular highlight along the top edge.
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.white.withValues(
                                              alpha: isDark ? 0.08 : 0.36,
                                            ),
                                            Colors.white.withValues(alpha: 0),
                                          ],
                                          stops: const [0, 0.55],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: showLabels ? 8 : 6,
                                    vertical: showLabels ? 8 : 6,
                                  ),
                                  child: Row(
                                    children: [
                                      for (var index = 0;
                                          index < items.length;
                                          index++)
                                        Expanded(
                                          child: _NavItem(
                                            data: items[index],
                                            selected: currentIndex == index,
                                            showLabel: showLabels,
                                            itemBorderRadius: itemBorderRadius,
                                            onTap: () => onTap(index),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                // Hairline border for the glass edge.
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(34),
                                        border: Border.all(
                                          color: isDark
                                              ? Colors.white
                                                  .withValues(alpha: 0.08)
                                              : Colors.white
                                                  .withValues(alpha: 0.6),
                                          width: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _NavItemData {
  const _NavItemData({
    required this.label,
    required this.outlinedIcon,
    required this.filledIcon,
    this.count = 0,
  });

  final String label;
  final IconData outlinedIcon;
  final IconData filledIcon;
  final int count;
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.data,
    required this.selected,
    required this.showLabel,
    required this.itemBorderRadius,
    required this.onTap,
  });

  final _NavItemData data;
  final bool selected;
  final bool showLabel;
  final double itemBorderRadius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final iconColor = selected ? scheme.primary : scheme.onSurfaceVariant;
    final icon = Icon(
      selected ? data.filledIcon : data.outlinedIcon,
      size: 22,
      color: iconColor,
    );

    final iconWithBadge = data.count <= 0
        ? icon
        : Badge(
            label: Text(data.count > 99 ? '99+' : data.count.toString()),
            child: icon,
          );

    return Semantics(
      button: true,
      selected: selected,
      label: data.label,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: showLabel ? 4 : 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(itemBorderRadius),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: showLabel ? 8 : 4,
              vertical: showLabel ? 8 : 10,
            ),
            decoration: BoxDecoration(
              gradient: selected
                  ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        scheme.primary.withValues(alpha: 0.22),
                        scheme.primary.withValues(alpha: 0.10),
                      ],
                    )
                  : null,
              borderRadius: BorderRadius.circular(itemBorderRadius),
              border: selected
                  ? Border.all(
                      color: scheme.primary.withValues(alpha: 0.28),
                      width: 0.8,
                    )
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                iconWithBadge,
                if (showLabel) ...[
                  const SizedBox(height: 4),
                  Text(
                    data.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color:
                          selected ? scheme.primary : scheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
