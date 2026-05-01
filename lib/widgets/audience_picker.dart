import 'package:flutter/material.dart';

import '../models/circle.dart';
import '../theme/app_theme.dart';

class AudiencePicker extends StatelessWidget {
  const AudiencePicker({
    super.key,
    required this.circles,
    required this.selectedCircleId,
    required this.onChanged,
    this.isLoading = false,
    this.isUnavailable = false,
    this.isFriendsTree = false,
    this.onRetry,
  });

  final List<FamilyCircle> circles;
  final String? selectedCircleId;
  final ValueChanged<String?> onChanged;
  final bool isLoading;
  final bool isUnavailable;
  final bool isFriendsTree;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final selectedValue = _resolveSelectedValue();
    final hasChoices = circles.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.surface.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: tokens.surfaceLine),
          ),
          child: Column(
            children: hasChoices
                ? [
                    for (var index = 0; index < circles.length; index++) ...[
                      _AudienceOptionTile(
                        circle: circles[index],
                        selected: circles[index].id == selectedValue,
                        enabled: !isLoading,
                        onTap: () => onChanged(circles[index].id),
                      ),
                      if (index != circles.length - 1)
                        Divider(
                          height: 1,
                          indent: 58,
                          color: tokens.surfaceLine,
                        ),
                    ],
                  ]
                : [
                    _FallbackAudienceTile(
                      isFriendsTree: isFriendsTree,
                      selected: selectedValue == '',
                    ),
                  ],
          ),
        ),
        if (isLoading || isUnavailable) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              if (isLoading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                )
              else
                Icon(
                  Icons.cloud_off_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isLoading ? 'Загружаем круги' : 'Круги недоступны',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (!isLoading && onRetry != null)
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Повторить'),
                ),
            ],
          ),
        ],
      ],
    );
  }

  String? _resolveSelectedValue() {
    if (circles.isEmpty) {
      return '';
    }
    final selected = selectedCircleId;
    if (selected != null && circles.any((circle) => circle.id == selected)) {
      return selected;
    }
    for (final circle in circles) {
      if (circle.isAllTree) {
        return circle.id;
      }
    }
    return circles.first.id;
  }
}

class _AudienceOptionTile extends StatelessWidget {
  const _AudienceOptionTile({
    required this.circle,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final FamilyCircle circle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final accent = _accentFor(circle, tokens);
    final subtitle = _subtitleFor(circle);

    return Material(
      color: selected ? accent.withValues(alpha: 0.08) : Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                ),
                child: Icon(_iconFor(circle), size: 20, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      circle.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: tokens.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.inkSecondary,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: selected ? accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected ? accent : tokens.surfaceLine,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check, size: 15, color: tokens.accentInk)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(FamilyCircle circle) {
    switch (circle.kind) {
      case FamilyCircleKind.allTree:
        return Icons.account_tree_outlined;
      case FamilyCircleKind.favorites:
        return Icons.favorite_border;
      case FamilyCircleKind.descendantsOf:
      case FamilyCircleKind.ancestorsOf:
        return Icons.alt_route_outlined;
      case FamilyCircleKind.pair:
        return Icons.people_outline;
      case FamilyCircleKind.custom:
        return Icons.group_work_outlined;
    }
  }

  Color _accentFor(FamilyCircle circle, RodnyaDesignTokens tokens) {
    switch (circle.kind) {
      case FamilyCircleKind.favorites:
        return tokens.warm;
      case FamilyCircleKind.descendantsOf:
      case FamilyCircleKind.ancestorsOf:
      case FamilyCircleKind.pair:
        return tokens.accentStrong;
      case FamilyCircleKind.allTree:
      case FamilyCircleKind.custom:
        return tokens.accent;
    }
  }

  String _subtitleFor(FamilyCircle circle) {
    final parts = <String>[
      _memberLabel(circle.memberCount),
      if ((circle.description ?? '').trim().isNotEmpty)
        circle.description!.trim()
      else if (circle.isAllTree)
        'все участники выбранного дерева'
      else if (circle.isFavorites)
        'самые близкие родственники'
      else if (circle.isAuto)
        'автоматический круг по ветке'
      else if (circle.isSystem)
        'системный круг',
    ];
    return parts.join(' · ');
  }

  String _memberLabel(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    final suffix = mod10 == 1 && mod100 != 11
        ? 'человек'
        : mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)
            ? 'человека'
            : 'человек';
    return '$count $suffix';
  }
}

class _FallbackAudienceTile extends StatelessWidget {
  const _FallbackAudienceTile({
    required this.isFriendsTree,
    required this.selected,
  });

  final bool isFriendsTree;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tokens.accentSoft,
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
            child: Icon(
              isFriendsTree
                  ? Icons.diversity_3_outlined
                  : Icons.account_tree_outlined,
              size: 20,
              color: tokens.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isFriendsTree ? 'Весь круг' : 'Всё дерево',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: tokens.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Круги пока недоступны, публикация останется внутри выбранного контекста.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.inkSecondary,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          if (selected) ...[
            const SizedBox(width: 10),
            Icon(Icons.check_circle, color: tokens.accent),
          ],
        ],
      ),
    );
  }
}
