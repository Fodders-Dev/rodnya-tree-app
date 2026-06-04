// Phase E2c: feed card for a «Встреча» (Gathering). Mirrors PostCard's
// visual language (author header, audience chip, body) but is
// self-contained — no likes / comments / reactions / media. RSVP controls
// are intentionally absent until Phase E3 wires the logic.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/gathering.dart';
import '../models/post.dart' show TreeContentScopeType;
import '../theme/app_theme.dart';

class GatheringCard extends StatelessWidget {
  const GatheringCard({super.key, required this.gathering});

  final Gathering gathering;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return Container(
      key: Key('gathering-card-${gathering.id}'),
      margin: EdgeInsets.only(bottom: tokens.space12),
      padding: EdgeInsets.all(tokens.space16),
      decoration: BoxDecoration(
        color: tokens.surfaceStrong,
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        border: Border.all(color: tokens.surfaceLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(theme, tokens),
          SizedBox(height: tokens.space12),
          _buildBody(theme, tokens),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, RodnyaDesignTokens tokens) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAvatar(theme, tokens),
        SizedBox(width: tokens.space8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                gathering.authorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: tokens.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatPosted(gathering.createdAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.inkMuted,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: tokens.space8),
        _buildTypeBadge(theme, tokens),
      ],
    );
  }

  Widget _buildAvatar(ThemeData theme, RodnyaDesignTokens tokens) {
    final photo = gathering.renderableAuthorPhotoUrl;
    return Container(
      width: 40,
      height: 40,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tokens.accentSoft,
        shape: BoxShape.circle,
        border: Border.all(color: tokens.surfaceLine),
      ),
      child: photo != null && photo.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: photo,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _buildInitials(theme, tokens),
            )
          : _buildInitials(theme, tokens),
    );
  }

  Widget _buildInitials(ThemeData theme, RodnyaDesignTokens tokens) {
    final name = gathering.authorName.trim();
    final initial = name.isEmpty ? 'Р' : String.fromCharCode(name.runes.first);
    return Center(
      child: Text(
        initial.toUpperCase(),
        style: theme.textTheme.titleSmall?.copyWith(
          color: tokens.accent,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildTypeBadge(ThemeData theme, RodnyaDesignTokens tokens) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tokens.accentSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_outlined, size: 14, color: tokens.accent),
          const SizedBox(width: 4),
          Text(
            'Встреча',
            style: theme.textTheme.labelSmall?.copyWith(
              color: tokens.accent,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme, RodnyaDesignTokens tokens) {
    final description = gathering.description?.trim() ?? '';
    final place = gathering.place?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          gathering.title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontFamily: 'Lora',
            fontWeight: FontWeight.w700,
            color: tokens.ink,
            height: 1.2,
          ),
        ),
        SizedBox(height: tokens.space8),
        _buildInfoRow(
          theme,
          tokens,
          Icons.schedule_outlined,
          _formatWhen(),
        ),
        if (place.isNotEmpty) ...[
          SizedBox(height: tokens.space4),
          _buildInfoRow(theme, tokens, Icons.place_outlined, place),
        ],
        // Audience hint chip (mirrors the post card's audience affordance).
        SizedBox(height: tokens.space8),
        _buildAudienceChip(theme, tokens),
        if (description.isNotEmpty) ...[
          SizedBox(height: tokens.space12),
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tokens.ink,
              height: 1.4,
            ),
          ),
        ],
        // RSVP controls intentionally hidden until Phase E3.
      ],
    );
  }

  Widget _buildInfoRow(
    ThemeData theme,
    RodnyaDesignTokens tokens,
    IconData icon,
    String text,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: tokens.accent),
        SizedBox(width: tokens.space8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tokens.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAudienceChip(ThemeData theme, RodnyaDesignTokens tokens) {
    final label = gathering.scopeType == TreeContentScopeType.branches
        ? 'Отдельные ветки'
        : 'Вся семья';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.group_outlined, size: 13, color: tokens.inkMuted),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: tokens.inkMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _formatWhen() {
    final pattern = gathering.isAllDay ? 'd MMMM y' : 'd MMMM y, HH:mm';
    final start = DateFormat(pattern, 'ru').format(gathering.startAt);
    final end = gathering.endAt;
    if (end == null) return start;
    // Same-day end → show just the end time; otherwise the full date.
    final sameDay = end.year == gathering.startAt.year &&
        end.month == gathering.startAt.month &&
        end.day == gathering.startAt.day;
    final endLabel = gathering.isAllDay
        ? DateFormat('d MMMM y', 'ru').format(end)
        : sameDay
            ? DateFormat('HH:mm', 'ru').format(end)
            : DateFormat('d MMMM y, HH:mm', 'ru').format(end);
    return '$start — $endLabel';
  }

  String _formatPosted(DateTime createdAt) {
    return DateFormat('d MMMM', 'ru').format(createdAt);
  }
}
