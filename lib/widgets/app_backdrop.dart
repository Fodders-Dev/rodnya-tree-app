import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.surface.withValues(alpha: 0.96),
                  theme.colorScheme.surfaceContainer.withValues(alpha: 0.88),
                  theme.colorScheme.surface.withValues(alpha: 0.94),
                ],
                stops: const [0, 0.55, 1],
              ),
            ),
          ),
          Opacity(
            opacity: 0.98,
            child: SvgPicture.asset(
              'assets/backgrounds/rodnya_backdrop.svg',
              fit: BoxFit.cover,
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.72, -0.9),
                radius: 1.18,
                colors: [
                  theme.colorScheme.primary.withValues(alpha: 0.07),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.84, 0.92),
                radius: 1.12,
                colors: [
                  theme.colorScheme.tertiary.withValues(alpha: 0.12),
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
