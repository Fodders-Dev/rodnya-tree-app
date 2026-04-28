import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Frosted-glass panel.
///
/// On **native** (Android / iOS) this uses [BackdropFilter] + blur so surfaces
/// genuinely refract what's behind them.
///
/// On **web** (Flutter CanvasKit) [BackdropFilter] is extremely expensive —
/// each instance forces the GPU compositor to create a separate layer and run
/// a pixel-shader blur over everything behind it.  With 10+ panels visible at
/// once the page grinds to a halt and some panels render as gray rectangles
/// (the compositor gives up).  On web we skip the blur entirely and compensate
/// with a slightly higher-opacity solid fill that still reads as "glassy".
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.blur = 14,
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
    return kIsWeb ? _buildWebPanel(context) : _buildNativePanel(context);
  }

  Widget _buildPlainPanel(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final panelColor = color ??
        theme.colorScheme.surface.withValues(alpha: isDark ? 0.84 : 0.94);
    final outlineColor = borderColor ??
        theme.colorScheme.outlineVariant.withValues(alpha: isDark ? 0.38 : 0.7);
    final defaultShadow = <BoxShadow>[
      BoxShadow(
        color: theme.colorScheme.shadow.withValues(alpha: isDark ? 0.16 : 0.04),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ];

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

    // Higher opacity so the panel reads clearly without blur.
    final panelColor = color ??
        theme.colorScheme.surface.withValues(alpha: isDark ? 0.88 : 0.92);
    final outlineColor = borderColor ??
        (isDark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.65));

    final defaultShadow = <BoxShadow>[
      BoxShadow(
        color: theme.colorScheme.shadow.withValues(alpha: isDark ? 0.28 : 0.07),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ];

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
    final panelColor = color ??
        theme.colorScheme.surface.withValues(alpha: isDark ? 0.62 : 0.66);
    final outlineColor = borderColor ??
        (isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.55));

    final defaultShadow = <BoxShadow>[
      BoxShadow(
        color: theme.colorScheme.shadow.withValues(alpha: isDark ? 0.32 : 0.07),
        blurRadius: 22,
        offset: const Offset(0, 10),
      ),
      BoxShadow(
        color: theme.colorScheme.shadow.withValues(alpha: isDark ? 0.18 : 0.04),
        blurRadius: 6,
        offset: const Offset(0, 2),
      ),
    ];

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
}
