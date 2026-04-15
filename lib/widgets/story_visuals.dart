import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/story.dart';

@immutable
class StoryVisualPalette {
  const StoryVisualPalette({
    required this.start,
    required this.end,
    required this.accent,
    required this.soft,
  });

  final Color start;
  final Color end;
  final Color accent;
  final Color soft;
}

StoryVisualPalette storyPaletteForSeed(String seed) {
  const palettes = <StoryVisualPalette>[
    StoryVisualPalette(
      start: Color(0xFF0F766E),
      end: Color(0xFF5EEAD4),
      accent: Color(0xFFFDE68A),
      soft: Color(0x990F766E),
    ),
    StoryVisualPalette(
      start: Color(0xFF5B21B6),
      end: Color(0xFF9333EA),
      accent: Color(0xFFF9A8D4),
      soft: Color(0x995B21B6),
    ),
    StoryVisualPalette(
      start: Color(0xFF1D4ED8),
      end: Color(0xFF60A5FA),
      accent: Color(0xFFBFDBFE),
      soft: Color(0x991D4ED8),
    ),
    StoryVisualPalette(
      start: Color(0xFFB45309),
      end: Color(0xFFF59E0B),
      accent: Color(0xFFFDE68A),
      soft: Color(0x99B45309),
    ),
    StoryVisualPalette(
      start: Color(0xFFBE123C),
      end: Color(0xFFFB7185),
      accent: Color(0xFFFBCFE8),
      soft: Color(0x99BE123C),
    ),
    StoryVisualPalette(
      start: Color(0xFF065F46),
      end: Color(0xFF34D399),
      accent: Color(0xFFDCFCE7),
      soft: Color(0x99065F46),
    ),
  ];

  final hash = seed.runes.fold<int>(0, (value, rune) => value + rune);
  return palettes[hash % palettes.length];
}

String storyInitialsFor(String value) {
  final parts = value
      .trim()
      .split(' ')
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return 'И';
  }
  if (parts.length == 1) {
    return parts.first.substring(0, 1).toUpperCase();
  }
  return '${parts.first.substring(0, 1)}${parts[1].substring(0, 1)}'
      .toUpperCase();
}

String? storyCoverUrl(Story? story) {
  if (story == null) {
    return null;
  }
  if ((story.thumbnailUrl ?? '').trim().isNotEmpty) {
    return story.thumbnailUrl;
  }
  if ((story.mediaUrl ?? '').trim().isNotEmpty) {
    return story.mediaUrl;
  }
  if ((story.authorPhotoUrl ?? '').trim().isNotEmpty) {
    return story.authorPhotoUrl;
  }
  return null;
}

class StoryPosterBackground extends StatelessWidget {
  const StoryPosterBackground({
    super.key,
    required this.palette,
    this.imageUrl,
    this.dimmed = false,
  });

  final StoryVisualPalette palette;
  final String? imageUrl;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final overlayOpacity = dimmed ? 0.56 : 0.28;

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                palette.start,
                palette.end,
              ],
            ),
          ),
        ),
        Positioned(
          top: -36,
          right: -24,
          child: _StoryGlow(
            size: 180,
            color: palette.accent.withValues(alpha: 0.22),
          ),
        ),
        Positioned(
          left: -22,
          bottom: -48,
          child: _StoryGlow(
            size: 210,
            color: Colors.white.withValues(alpha: 0.12),
          ),
        ),
        if (imageUrl != null && imageUrl!.isNotEmpty)
          _StoryPosterImage(
            imageUrl: imageUrl!,
            overlayOpacity: overlayOpacity,
          )
        else
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.08),
                  Colors.black.withValues(alpha: overlayOpacity),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class StoryPosterText extends StatelessWidget {
  const StoryPosterText({
    super.key,
    required this.primaryText,
    this.secondaryText,
    this.centered = false,
    this.textAlign,
    this.maxLines,
  });

  final String primaryText;
  final String? secondaryText;
  final bool centered;
  final TextAlign? textAlign;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final align =
        centered ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final effectiveTextAlign =
        textAlign ?? (centered ? TextAlign.center : TextAlign.left);

    return Column(
      mainAxisAlignment:
          centered ? MainAxisAlignment.center : MainAxisAlignment.end,
      crossAxisAlignment: align,
      children: [
        Text(
          primaryText,
          maxLines: maxLines,
          overflow:
              maxLines == null ? TextOverflow.visible : TextOverflow.ellipsis,
          textAlign: effectiveTextAlign,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                height: 1.08,
              ),
        ),
        if (secondaryText != null && secondaryText!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            secondaryText!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: effectiveTextAlign,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.86),
                  height: 1.35,
                ),
          ),
        ],
      ],
    );
  }
}

class StoryMediaBadge extends StatelessWidget {
  const StoryMediaBadge({
    super.key,
    required this.icon,
    required this.label,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: emphasized
            ? Colors.white.withValues(alpha: 0.22)
            : Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class StoryPosterCardFrame extends StatelessWidget {
  const StoryPosterCardFrame({
    super.key,
    required this.palette,
    required this.child,
    this.imageUrl,
    this.aspectRatio = 9 / 16,
    this.borderRadius = 28,
    this.padding = const EdgeInsets.all(18),
    this.showShine = true,
  });

  final StoryVisualPalette palette;
  final Widget child;
  final String? imageUrl;
  final double aspectRatio;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final bool showShine;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            StoryPosterBackground(
              palette: palette,
              imageUrl: imageUrl,
              dimmed: imageUrl != null && imageUrl!.isNotEmpty,
            ),
            if (showShine)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.14),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.12),
                    ],
                    stops: const [0, 0.35, 1],
                  ),
                ),
              ),
            Padding(
              padding: padding,
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryGlow extends StatelessWidget {
  const _StoryGlow({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color,
              blurRadius: size / 2,
              spreadRadius: math.max(12, size / 8),
            ),
          ],
        ),
        child: SizedBox(width: size, height: size),
      ),
    );
  }
}

class _StoryPosterImage extends StatelessWidget {
  const _StoryPosterImage({
    required this.imageUrl,
    required this.overlayOpacity,
  });

  final String imageUrl;
  final double overlayOpacity;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.08),
                Colors.black.withValues(alpha: overlayOpacity),
              ],
              stops: const [0, 1],
            ),
          ),
        ),
      ],
    );
  }
}
