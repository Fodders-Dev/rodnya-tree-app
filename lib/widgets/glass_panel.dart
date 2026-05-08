import 'dart:ui';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Frosted-glass panel.
///
/// On **iOS / desktop** this uses [BackdropFilter] + blur so surfaces
/// genuinely refract what's behind them — those GPUs eat the cost
/// without breaking a sweat.
///
/// On **web** (Flutter CanvasKit) [BackdropFilter] is extremely expensive —
/// each instance forces the GPU compositor to create a separate layer and run
/// a pixel-shader blur over everything behind it.  With 10+ panels visible at
/// once the page grinds to a halt and some panels render as gray rectangles
/// (the compositor gives up).
///
/// On **Android** (mid-range Samsung S20 FE / Galaxy A-series in particular)
/// the same problem happens at smaller scale — enough GlassPanels stacked on
/// a feed scroll drop frame rate to single digits. We treat Android the same
/// way as web: skip the blur entirely, compensate with a slightly higher-
/// opacity solid fill that still reads as "glassy".
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.blur = 20,
    this.color,
    this.borderColor,
    this.boxShadow,
    this.clipBehavior = Clip.antiAlias,
    this.showSpecular = true,
    this.plain = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius borderRadius;
  final double blur;
  final Color? color;
  final Color? borderColor;
  final List<BoxShadow>? boxShadow;
  final Clip clipBehavior;
  final bool showSpecular;
  final bool plain;

  @override
  Widget build(BuildContext context) {
    if (plain) {
      return _buildPlainPanel(context);
    }
    // Skip BackdropFilter on web AND Android — the cheap fill path
    // is visually almost identical at the alpha levels we use, and
    // the per-frame cost of stacking many blurred panels is the
    // single biggest hit on mid-range Android. Keep blur on iOS /
    // desktop where it's free.
    final useBlur = !kIsWeb && defaultTargetPlatform != TargetPlatform.android;
    return useBlur ? _buildNativePanel(context) : _buildWebPanel(context);
  }

  Widget _buildPlainPanel(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tokens = _tokensFor(theme);
    final panelColor =
        color ?? tokens.surfaceStrong.withValues(alpha: isDark ? 0.90 : 0.94);
    final outlineColor = borderColor ?? tokens.surfaceLine;
    final defaultShadow = tokens.panelShadow(theme.brightness);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: panelColor,
        border: Border.all(color: outlineColor, width: 1),
        boxShadow: boxShadow ?? defaultShadow,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: clipBehavior,
        child: Padding(padding: padding, child: child),
      ),
    );
  }

  // ── Web: no BackdropFilter, higher-opacity fill ───────────────────────────

  Widget _buildWebPanel(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tokens = _tokensFor(theme);

    // Higher opacity so the panel reads clearly without blur.
    final panelColor =
        color ?? tokens.surfaceStrong.withValues(alpha: isDark ? 0.90 : 0.94);
    final outlineColor = borderColor ?? tokens.surfaceLine;
    final defaultShadow = tokens.panelShadow(theme.brightness);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: panelColor,
        border: Border.all(color: outlineColor, width: 1),
        boxShadow: boxShadow ?? defaultShadow,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: clipBehavior,
        child: Stack(
          children: [
            // Subtle specular sheen — pure CSS-level gradient, zero GPU cost.
            if (showSpecular)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(
                            alpha: isDark ? 0.06 : 0.22,
                          ),
                          Colors.white.withValues(alpha: 0),
                        ],
                        stops: const [0, 0.55],
                      ),
                    ),
                  ),
                ),
              ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }

  // ── Native: full BackdropFilter + blur ────────────────────────────────────

  Widget _buildNativePanel(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tokens = _tokensFor(theme);
    final panelColor =
        color ?? tokens.surface.withValues(alpha: isDark ? 0.58 : 0.64);
    final outlineColor = borderColor ?? tokens.surfaceLine;
    final defaultShadow = tokens.panelShadow(theme.brightness);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: boxShadow ?? defaultShadow,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: clipBehavior,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(color: panelColor),
                ),
              ),
              if (showSpecular)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(
                              alpha: isDark ? 0.08 : 0.32,
                            ),
                            Colors.white.withValues(alpha: 0.0),
                            Colors.white.withValues(
                              alpha: isDark ? 0.0 : 0.04,
                            ),
                          ],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(padding: padding, child: child),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: borderRadius,
                      border: Border.all(color: outlineColor, width: 1),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  RodnyaDesignTokens _tokensFor(ThemeData theme) {
    return theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
  }
}
