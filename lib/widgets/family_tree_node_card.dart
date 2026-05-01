import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/family_person.dart';
import '../theme/app_theme.dart';
import '../utils/photo_url.dart';

class FamilyTreeNodeCard extends StatelessWidget {
  const FamilyTreeNodeCard({
    super.key,
    required this.displayName,
    required this.lifeDates,
    required this.displayGender,
    this.displayPhotoUrl,
    this.relationChipLabel,
    this.isBloodRelation = false,
    this.isCurrentUserNode = false,
    this.isSelectedInEditMode = false,
    this.isDraggingNode = false,
    this.isHovered = false,
  });

  final String displayName;
  final String lifeDates;
  final Gender displayGender;
  final String? displayPhotoUrl;
  final String? relationChipLabel;
  final bool isBloodRelation;
  final bool isCurrentUserNode;
  final bool isSelectedInEditMode;
  final bool isDraggingNode;
  final bool isHovered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final genderAccent = displayGender == Gender.male
        ? const Color(0xFF5A8E8C)
        : const Color(0xFFC78372);
    final borderColor = isDraggingNode
        ? tokens.accentStrong
        : isSelectedInEditMode
            ? tokens.warm
            : isCurrentUserNode
                ? tokens.accent
                : genderAccent.withValues(alpha: 0.42);
    final surfaceColor = isCurrentUserNode
        ? tokens.accentSoft.withValues(alpha: 0.9)
        : tokens.surfaceStrong.withValues(alpha: 0.9);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        boxShadow: [
          BoxShadow(
            color: isDraggingNode
                ? tokens.accentStrong.withValues(alpha: 0.30)
                : isHovered
                    ? tokens.accent.withValues(alpha: 0.18)
                    : isSelectedInEditMode
                        ? tokens.warm.withValues(alpha: 0.26)
                        : isCurrentUserNode
                            ? tokens.accent.withValues(alpha: 0.20)
                            : Colors.black.withValues(alpha: 0.1),
            blurRadius: isDraggingNode
                ? 16
                : isHovered
                    ? 10
                    : isSelectedInEditMode
                        ? 12
                        : (isCurrentUserNode ? 8 : 4),
            offset: Offset(0, isDraggingNode ? 4 : (isHovered ? 3 : 2)),
          ),
        ],
        border: Border.all(
          color: borderColor,
          width: isDraggingNode
              ? 2.8
              : isSelectedInEditMode
                  ? 2.5
                  : (isCurrentUserNode ? 2 : 1.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FamilyTreeNodeAvatar(
            displayGender: displayGender,
            displayPhotoUrl: displayPhotoUrl,
            accent: genderAccent,
          ),
          const SizedBox(height: 6),
          Text(
            displayName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              height: 1.15,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            lifeDates,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: tokens.inkMuted,
            ),
            textAlign: TextAlign.center,
          ),
          if (isCurrentUserNode) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: tokens.accent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Это вы',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: tokens.accentInk,
                ),
              ),
            ),
          ],
          if (relationChipLabel != null) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isBloodRelation
                    ? tokens.accentSoft.withValues(alpha: 0.92)
                    : tokens.warmSoft.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                relationChipLabel!,
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: tokens.ink,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FamilyTreeNodeAvatar extends StatelessWidget {
  const _FamilyTreeNodeAvatar({
    required this.displayGender,
    required this.accent,
    this.displayPhotoUrl,
  });

  final Gender displayGender;
  final Color accent;
  final String? displayPhotoUrl;

  @override
  Widget build(BuildContext context) {
    final photoUrl = normalizePhotoUrl(displayPhotoUrl);
    final hasPhoto = photoUrl != null;
    final fallbackBackground = accent.withValues(alpha: 0.18);
    final fallbackIconColor = accent;
    final fallbackIcon = Icon(
      displayGender == Gender.male ? Icons.person : Icons.person_outline,
      size: 20,
      color: fallbackIconColor,
    );

    if (!hasPhoto) {
      return CircleAvatar(
        backgroundColor: fallbackBackground,
        radius: 22,
        child: fallbackIcon,
      );
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fallbackBackground,
      ),
      clipBehavior: Clip.antiAlias,
      child: CachedNetworkImage(
        imageUrl: photoUrl,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        placeholder: (_, __) {
          return ColoredBox(
            color: fallbackBackground,
            child: Center(child: fallbackIcon),
          );
        },
        errorWidget: (_, __, ___) {
          return ColoredBox(
            color: fallbackBackground,
            child: Center(child: fallbackIcon),
          );
        },
      ),
    );
  }
}
