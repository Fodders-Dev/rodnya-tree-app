import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_theme.dart';

/// Warm, layered backdrop that gives the Liquid Glass surfaces something to
/// refract. Avoids hardcoded colors so it reads correctly under both themes.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (isDark ? RodnyaDesignTokens.dark : RodnyaDesignTokens.light);

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(decoration: BoxDecoration(color: tokens.bgBase)),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.85, -0.95),
                radius: 1.15,
                colors: [
                  tokens.bgTintWarm.withValues(alpha: isDark ? 0.46 : 0.82),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.96, -0.18),
                radius: 1.08,
                colors: [
                  tokens.bgTintHoney.withValues(alpha: isDark ? 0.30 : 0.52),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.18, 1.0),
                radius: 1.18,
                colors: [
                  tokens.bgTintSage.withValues(alpha: isDark ? 0.44 : 0.64),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          CustomPaint(
            painter: _LinenWeavePainter(isDark: isDark),
            size: Size.infinite,
          ),
          Opacity(
            opacity: isDark ? 0.10 : 0.18,
            child: SvgPicture.asset(
              'assets/backgrounds/rodnya_backdrop.svg',
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(
                tokens.ink.withValues(alpha: 0.72),
                BlendMode.srcIn,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinenWeavePainter extends CustomPainter {
  const _LinenWeavePainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(
        alpha: isDark ? 0.018 : 0.022,
      )
      ..strokeWidth = 1;

    for (var x = 0.0; x < size.width; x += 3) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LinenWeavePainter oldDelegate) {
    return oldDelegate.isDark != isDark;
  }
}
