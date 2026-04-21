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

                return SafeArea(
                  minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final showLabels = constraints.maxWidth >= 480;
                      final itemBorderRadius = showLabels ? 22.0 : 20.0;

                      return ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: showLabels ? 8 : 6,
                              vertical: showLabels ? 8 : 6,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surface.withValues(alpha: 0.84),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.9,
                                ),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: scheme.shadow.withValues(alpha: 0.1),
                                  blurRadius: 28,
                                  offset: const Offset(0, 14),
                                ),
                              ],
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
    final icon = Icon(
      selected ? data.filledIcon : data.outlinedIcon,
      size: 22,
      color: selected ? scheme.primary : scheme.onSurfaceVariant,
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
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: showLabel ? 8 : 4,
              vertical: showLabel ? 8 : 10,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(itemBorderRadius),
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
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
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
