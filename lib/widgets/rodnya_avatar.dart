import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Single source of truth for avatar rendering across the app.
/// Replaces five-or-so ad-hoc CircleAvatar / ClipRRect implementations
/// that each had their own fallback chain (initials vs person icon vs
/// gradient). Now every surface — comments, post cards, story rail,
/// chat list, profile, picker — uses the same widget so the UI feels
/// consistent.
///
/// Fallback order:
/// 1. [photoUrl] via [CachedNetworkImage], silently degrades on 404.
/// 2. [name] first letter rendered in a tinted accentSoft circle.
/// 3. Generic person icon as last resort (very short or empty name).
class RodnyaAvatar extends StatelessWidget {
  const RodnyaAvatar({
    super.key,
    this.photoUrl,
    this.name,
    this.size = 40,
    this.shape = RodnyaAvatarShape.circle,
    this.borderColor,
    this.borderWidth = 0,
    this.backgroundColor,
    this.textColor,
    this.semanticLabel,
    this.excludeSemantics = false,
  });

  final String? photoUrl;
  final String? name;
  final double size;
  final RodnyaAvatarShape shape;
  final Color? borderColor;
  final double borderWidth;
  final Color? backgroundColor;
  final Color? textColor;

  /// Override for the screen-reader label. Defaults to `Аватар: ИМЯ`
  /// or `Аватар без фото` when no name is available. Set to a more
  /// specific string at call sites where the surrounding row already
  /// reads the name (e.g. ListTile.title), to avoid the screen reader
  /// announcing the same name twice.
  final String? semanticLabel;

  /// True when the surrounding widget already provides full semantic
  /// context (e.g. a card with the user's name + role) and we want
  /// the avatar to be invisible to TalkBack/VoiceOver. Defaults to
  /// false so standalone avatars still get a label.
  final bool excludeSemantics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    final url = (photoUrl ?? '').trim();
    final initial = _initialFor(name ?? '');

    final radius = shape == RodnyaAvatarShape.circle
        ? BorderRadius.circular(size)
        : BorderRadius.circular(size * 0.28);

    final fillColor = backgroundColor ?? tokens.accentSoft;
    final fgColor = textColor ?? tokens.accent;

    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: radius,
      ),
      alignment: Alignment.center,
      child: initial.isEmpty
          ? Icon(
              Icons.person_outline,
              size: size * 0.55,
              color: fgColor.withValues(alpha: 0.85),
            )
          : Text(
              initial,
              style: theme.textTheme.titleMedium?.copyWith(
                color: fgColor,
                fontWeight: FontWeight.w800,
                fontSize: size * 0.42,
                height: 1,
              ),
            ),
    );

    Widget body = url.isEmpty
        ? fallback
        : ClipRRect(
            borderRadius: radius,
            child: CachedNetworkImage(
              imageUrl: url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, __) => fallback,
              errorWidget: (_, __, ___) => fallback,
            ),
          );

    if (borderWidth > 0) {
      body = Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: borderColor ?? tokens.surfaceLine,
            width: borderWidth,
          ),
        ),
        child: body,
      );
    }

    if (excludeSemantics) {
      return ExcludeSemantics(child: body);
    }

    final trimmedName = (name ?? '').trim();
    final label = semanticLabel ??
        (trimmedName.isEmpty
            ? 'Аватар без фото'
            : 'Аватар: $trimmedName');

    return Semantics(
      label: label,
      image: true,
      excludeSemantics: true,
      child: body,
    );
  }

  static String _initialFor(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }
}

enum RodnyaAvatarShape {
  /// Round avatar — used in chat / comments / picker rows.
  circle,

  /// Soft rectangle (28% corner radius) — used in profile hero +
  /// some person tiles. Matches the look of person cards in the tree.
  rounded,
}
