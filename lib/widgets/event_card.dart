import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/app_event.dart';
import '../theme/app_theme.dart';
import 'glass_panel.dart';

class EventCard extends StatelessWidget {
  final AppEvent event;
  final double? width;
  final bool compact;

  const EventCard({
    required this.event,
    this.width,
    this.compact = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final canOpenProfile = event.isLinkedToPerson;
    final personName = canOpenProfile ? event.personName.trim() : '';

    return SizedBox(
      width: width ?? (compact ? 232 : 220),
      child: GlassPanel(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(compact ? 18 : 20),
        plain: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(compact ? 18 : 20),
          onTap: canOpenProfile
              ? () => context.push('/relative/details/${event.personId}')
              : null,
          child: Padding(
            padding: compact
                ? const EdgeInsets.fromLTRB(10, 9, 10, 9)
                : const EdgeInsets.fromLTRB(12, 11, 12, 12),
            child: compact
                ? _buildCompactBody(context, personName, canOpenProfile)
                : _buildFullBody(context, personName, canOpenProfile),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactBody(
    BuildContext context,
    String personName,
    bool canOpenProfile,
  ) {
    final theme = Theme.of(context);
    final tokens = _tokensFor(theme);
    final accent = _eventAccent(tokens);
    final accentSoft = _eventAccentSoft(tokens);
    final subtitle = [
      if (personName.isNotEmpty) personName,
      event.status,
    ].join(' · ');

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: accentSoft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.16)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                event.date.day.toString(),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  height: 0.98,
                ),
              ),
              Text(
                _shortMonth(event.date),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                  height: 0.98,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                event.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.08,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
        if (canOpenProfile) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ],
    );
  }

  Widget _buildFullBody(
    BuildContext context,
    String personName,
    bool canOpenProfile,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokens = _tokensFor(theme);
    final accent = _eventAccent(tokens);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.85,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    event.categoryLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                event.status,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                event.icon,
                size: 18,
                color: accent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (personName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      personName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (canOpenProfile) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 17,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ],
    );
  }

  RodnyaDesignTokens _tokensFor(ThemeData theme) {
    return theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
  }

  Color _eventAccent(RodnyaDesignTokens tokens) =>
      _isWarmEvent ? tokens.warm : tokens.accent;

  Color _eventAccentSoft(RodnyaDesignTokens tokens) =>
      _isWarmEvent ? tokens.warmSoft : tokens.accentSoft;

  bool get _isWarmEvent =>
      event.type == AppEventType.birthday ||
      event.type == AppEventType.weddingAnniversary ||
      event.type == AppEventType.customFamilyEvent;

  String _shortMonth(DateTime value) {
    const months = <int, String>{
      1: 'янв',
      2: 'фев',
      3: 'мар',
      4: 'апр',
      5: 'мая',
      6: 'июн',
      7: 'июл',
      8: 'авг',
      9: 'сен',
      10: 'окт',
      11: 'ноя',
      12: 'дек',
    };
    return months[value.month] ?? '';
  }
}
