import 'dart:ui';

import 'package:flutter/material.dart';

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.blur = 22,
    this.color,
    this.borderColor,
    this.boxShadow,
    this.clipBehavior = Clip.antiAlias,
    this.showSpecular = true,
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

  @override
  Widget build(BuildContext context) {
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
        blurRadius: 30,
        offset: const Offset(0, 14),
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
              // Base tinted glass fill.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(color: panelColor),
                ),
              ),
              // Subtle vertical sheen — brighter near the top, fades downward.
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
              // Hairline border that fakes the inner edge of glass.
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
