import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/family_person.dart';

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
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: isCurrentUserNode
            ? colorScheme.primaryContainer
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDraggingNode
                ? colorScheme.primary.withValues(alpha: 0.32)
                : isHovered
                    ? colorScheme.primary.withValues(alpha: 0.18)
                    : isSelectedInEditMode
                        ? colorScheme.secondary.withValues(alpha: 0.28)
                        : isCurrentUserNode
                            ? colorScheme.primary.withValues(alpha: 0.22)
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
          color: isDraggingNode
              ? colorScheme.primary
              : isSelectedInEditMode
                  ? colorScheme.secondary
                  : isCurrentUserNode
                      ? colorScheme.primary
                      : displayGender == Gender.male
                          ? Colors.blue.shade300
                          : Colors.pink.shade300,
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
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
            textAlign: TextAlign.center,
          ),
          if (isCurrentUserNode) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Это вы',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onPrimary,
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
                    ? colorScheme.secondaryContainer.withValues(alpha: 0.92)
                    : colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                relationChipLabel!,
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
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
    this.displayPhotoUrl,
  });

  final Gender displayGender;
  final String? displayPhotoUrl;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = displayPhotoUrl != null && displayPhotoUrl!.isNotEmpty;
    final fallbackBackground = displayGender == Gender.male
        ? Colors.blue.shade100
        : Colors.pink.shade100;
    final fallbackIconColor = displayGender == Gender.male
        ? Colors.blue.shade800
        : Colors.pink.shade800;
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
      child: Image.network(
        displayPhotoUrl!,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        webHtmlElementStrategy: kIsWeb
            ? WebHtmlElementStrategy.prefer
            : WebHtmlElementStrategy.never,
        errorBuilder: (_, __, ___) {
          return ColoredBox(
            color: fallbackBackground,
            child: Center(child: fallbackIcon),
          );
        },
      ),
    );
  }
}
