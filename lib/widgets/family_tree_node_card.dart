import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/family_person.dart';
import '../theme/app_theme.dart';
import '../utils/photo_url.dart';

/// Compact tree-node card matching the Claude Design `.tn-card` reference.
///
/// Layout: avatar (40px round, accent/warm gradient) → first name (Lora, big)
/// + last name (Manrope, smaller) → years → role pill. Selected, deceased,
/// pending, current-user, and dimmed variants are styled per `styles.css`
/// `.tn-card.sel/.dimmed/.deceased/.is-me` rules.
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
    this.isDeceased = false,
    this.isPending = false,
    this.isDimmed = false,
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
  final bool isDeceased;
  final bool isPending;
  final bool isDimmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    // Reference uses surface-line as the default border, accent for selected/me,
    // warm for edit-selected. Dropping the gender-tinted border so cards read
    // as a uniform set rather than red/blue couples.
    final borderColor = isDraggingNode
        ? tokens.accentStrong
        : isSelectedInEditMode
            ? tokens.warm
            : isCurrentUserNode
                ? tokens.accent.withValues(alpha: 0.55)
                : tokens.surfaceLine;
    final borderWidth = isDraggingNode
        ? 2.6
        : isSelectedInEditMode
            ? 2.3
            : isCurrentUserNode
                ? 2.0
                : 1.0;

    final surfaceColor = isCurrentUserNode
        ? tokens.accentSoft.withValues(alpha: 0.65)
        : tokens.surfaceStrong.withValues(alpha: 0.92);

    // Reference `.tn-card.sel`: accent border + 2.5px ring + drop shadow.
    final shadows = <BoxShadow>[
      if (isSelectedInEditMode || isCurrentUserNode)
        BoxShadow(
          color: (isSelectedInEditMode ? tokens.warm : tokens.accent)
              .withValues(alpha: 0.22),
          blurRadius: 16,
          spreadRadius: 0,
          offset: const Offset(0, 4),
        ),
      BoxShadow(
        color: Colors.black.withValues(
            alpha: isDraggingNode ? 0.18 : (isHovered ? 0.10 : 0.06)),
        blurRadius: isDraggingNode ? 14 : (isHovered ? 8 : 4),
        offset: Offset(0, isDraggingNode ? 4 : 2),
      ),
    ];

    // Split displayName into first / last so we can render fname (Lora big)
    // and lname (Manrope smaller) per reference.
    final nameParts = displayName.trim().split(RegExp(r'\s+'));
    final fname = nameParts.isNotEmpty ? nameParts.first : displayName;
    final lname =
        nameParts.length > 1 ? nameParts.sublist(1).join(' ') : null;

    final accent = displayGender == Gender.male
        ? tokens.accent
        : tokens.warm;

    final card = Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: shadows,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _NodeAvatar(
            displayPhotoUrl: displayPhotoUrl,
            displayGender: displayGender,
            accent: accent,
            isDeceased: isDeceased,
            isPending: isPending,
            isCurrentUser: isCurrentUserNode,
            tokens: tokens,
          ),
          const SizedBox(height: 7),
          // First name in Lora — bigger, more elegant.
          Text(
            fname,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.serif(
              color: tokens.ink,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.18,
              height: 1.1,
            ),
          ),
          if (lname != null && lname.isNotEmpty) ...[
            const SizedBox(height: 1),
            Text(
              lname,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.sans(
                color: tokens.inkSecondary,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            lifeDates,
            textAlign: TextAlign.center,
            style: AppTheme.sans(
              color: tokens.inkMuted,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
          if (isCurrentUserNode) ...[
            const SizedBox(height: 5),
            _RolePill(
              label: 'Это вы',
              fg: tokens.accentInk,
              bg: tokens.accent,
            ),
          ] else if (relationChipLabel != null &&
              relationChipLabel!.trim().isNotEmpty) ...[
            const SizedBox(height: 5),
            _RolePill(
              label: relationChipLabel!.trim(),
              fg: tokens.accent,
              bg: tokens.accentSoft,
            ),
          ],
        ],
      ),
    );

    // Reference `.tn-card.dimmed { opacity: 0.28 }` — when a node is selected,
    // non-neighbour cards fade to surface the active path.
    final wrapped = AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      opacity: isDimmed ? 0.32 : 1.0,
      child: card,
    );

    // Reference `.tn-card.deceased { filter: saturate(0.35) brightness(0.95) }`.
    if (isDeceased) {
      return ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          // saturate(0.4) approx — keep some warmth so cards don't read as dead grey.
          0.50, 0.39, 0.11, 0, 0,
          0.18, 0.71, 0.11, 0, 0,
          0.18, 0.39, 0.43, 0, 0,
          0,    0,    0,    1, 0,
        ]),
        child: wrapped,
      );
    }
    return wrapped;
  }
}

class _RolePill extends StatelessWidget {
  const _RolePill({required this.label, required this.fg, required this.bg});

  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      constraints: const BoxConstraints(maxWidth: 110),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: AppTheme.sans(
          color: fg,
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _NodeAvatar extends StatelessWidget {
  const _NodeAvatar({
    required this.displayGender,
    required this.accent,
    required this.tokens,
    this.displayPhotoUrl,
    this.isDeceased = false,
    this.isPending = false,
    this.isCurrentUser = false,
  });

  final Gender displayGender;
  final Color accent;
  final RodnyaDesignTokens tokens;
  final String? displayPhotoUrl;
  final bool isDeceased;
  final bool isPending;
  final bool isCurrentUser;

  @override
  Widget build(BuildContext context) {
    final photoUrl = normalizePhotoUrl(displayPhotoUrl);
    final hasPhoto = photoUrl != null;

    final gradient = LinearGradient(
      begin: const Alignment(-0.6, -0.6),
      end: const Alignment(0.6, 0.6),
      colors: [
        accent,
        Color.lerp(accent, Colors.black, 0.18)!,
      ],
    );

    final fallback = Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: gradient,
      ),
      alignment: Alignment.center,
      child: Icon(
        displayGender == Gender.male
            ? Icons.person
            : Icons.person_outline,
        size: 22,
        color: Colors.white.withValues(alpha: 0.94),
      ),
    );

    final image = hasPhoto
        ? ClipOval(
            child: SizedBox(
              width: 40,
              height: 40,
              child: CachedNetworkImage(
                imageUrl: photoUrl,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                placeholder: (_, __) => fallback,
                errorWidget: (_, __, ___) => fallback,
              ),
            ),
          )
        : SizedBox(width: 40, height: 40, child: fallback);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        image,
        // Pending warm dot — bottom-right, ringed by surface for separation.
        if (isPending)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: tokens.warm,
                shape: BoxShape.circle,
                border: Border.all(
                  color: tokens.surfaceStrong,
                  width: 1.5,
                ),
              ),
            ),
          ),
        // Current-user accent dot — only when there's no pending state.
        if (isCurrentUser && !isPending)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: tokens.accent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: tokens.surfaceStrong,
                  width: 1.5,
                ),
              ),
            ),
          ),
        // Deceased mark † top-right.
        if (isDeceased)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
              decoration: BoxDecoration(
                color: tokens.surfaceStrong,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: tokens.surfaceLine,
                  width: 0.6,
                ),
              ),
              child: Text(
                '†',
                style: AppTheme.serif(
                  color: tokens.inkMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
