import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Warm, layered backdrop that gives the Liquid Glass surfaces something to
/// refract. Avoids hardcoded colors so it reads correctly under both themes.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Soft warm canvas wash.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        const Color(0xFF0E1413),
                        const Color(0xFF111A18),
                        const Color(0xFF0B1110),
                      ]
                    : [
                        const Color(0xFFF7F6F1),
                        const Color(0xFFEFF4F0),
                        const Color(0xFFF8F5EE),
                      ],
                stops: const [0, 0.55, 1],
              ),
            ),
          ),
          // Faint linework illustration (kept low opacity so it never fights UI).
          Opacity(
            opacity: isDark ? 0.18 : 0.65,
            child: SvgPicture.asset(
              'assets/backgrounds/rodnya_backdrop.svg',
              fit: BoxFit.cover,
            ),
          ),
          // Top-left teal halo — primary brand light.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.85, -1.0),
                radius: 1.25,
                colors: [
                  scheme.primary.withValues(alpha: isDark ? 0.22 : 0.18),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Bottom-right warm halo for color contrast.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.95, 1.05),
                radius: 1.2,
                colors: [
                  (isDark ? const Color(0xFFE9B98C) : const Color(0xFFF5C9A4))
                      .withValues(alpha: isDark ? 0.18 : 0.22),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Mid-screen accent puddle to lift glass surfaces.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.4, -0.35),
                radius: 0.85,
                colors: [
                  scheme.tertiary.withValues(alpha: isDark ? 0.18 : 0.16),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
