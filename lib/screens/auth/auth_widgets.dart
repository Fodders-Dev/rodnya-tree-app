part of '../auth_screen.dart';

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.feature,
    required this.compact,
  });

  final _AuthFeature feature;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 16,
        vertical: compact ? 12 : 14,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: compact ? 0.1 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(feature.icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(
            feature.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthFeature {
  const _AuthFeature({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}

/// Decorative tree silhouette painted into the auth hero, behind the
/// tagline. Lifted from the reference jsx SVG path: a single trunk that
/// branches in symmetric pairs upward, with small dots marking the
/// branch terminals — reads as a stylized family graph.
class _AuthHeroTreePainter extends CustomPainter {
  const _AuthHeroTreePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Reference uses a 360x380 viewbox aligned to the bottom-center.
    // Project that into our actual canvas.
    final cx = w * 0.5;
    final baseY = h;
    final trunkTop = h * 0.37;

    final stroke = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final dot = Paint()..color = Colors.white;

    // Main trunk.
    canvas.drawLine(Offset(cx, baseY), Offset(cx, trunkTop), stroke);

    // Three pairs of branches, each going further up + outward.
    // pair 1 — wide spread, lowest branch fork
    final l1 = Offset(cx - w * 0.25, h * 0.42);
    final r1 = Offset(cx + w * 0.25, h * 0.42);
    canvas.drawPath(
      Path()
        ..moveTo(cx, h * 0.58)
        ..cubicTo(cx - w * 0.08, h * 0.53, l1.dx + w * 0.04, l1.dy + 12, l1.dx,
            l1.dy),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(cx, h * 0.58)
        ..cubicTo(cx + w * 0.08, h * 0.53, r1.dx - w * 0.04, r1.dy + 12, r1.dx,
            r1.dy),
      stroke,
    );

    // pair 2
    final l2 = Offset(cx - w * 0.17, h * 0.29);
    final r2 = Offset(cx + w * 0.17, h * 0.29);
    canvas.drawPath(
      Path()
        ..moveTo(cx, h * 0.45)
        ..cubicTo(cx - w * 0.06, h * 0.40, l2.dx + w * 0.03, l2.dy + 10, l2.dx,
            l2.dy),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(cx, h * 0.45)
        ..cubicTo(cx + w * 0.06, h * 0.40, r2.dx - w * 0.03, r2.dy + 10, r2.dx,
            r2.dy),
      stroke,
    );

    // pair 3 — top
    final l3 = Offset(cx - w * 0.085, h * 0.24);
    final r3 = Offset(cx + w * 0.085, h * 0.24);
    canvas.drawPath(
      Path()
        ..moveTo(cx, trunkTop)
        ..cubicTo(cx - w * 0.04, h * 0.33, l3.dx + w * 0.015, l3.dy + 8, l3.dx,
            l3.dy),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(cx, trunkTop)
        ..cubicTo(cx + w * 0.04, h * 0.33, r3.dx - w * 0.015, r3.dy + 8, r3.dx,
            r3.dy),
      stroke,
    );

    // Branch terminal dots.
    for (final node in [l1, r1, l2, r2, l3, r3, Offset(cx, trunkTop)]) {
      canvas.drawCircle(node, 5, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _AuthHeroTreePainter oldDelegate) => false;
}

/// Horizontal icon+label pill used on the auth-screen "Быстрый вход"
/// row. Density chunk 18: replaces the old 60dp-circle-with-label-
/// below chip (~86dp tall, its own row) plus a separate "Войти по QR"
/// text button below it — that pair ate ~136dp for what is now one
/// 46dp-tall `Wrap` of these pills (icon + label side by side, single
/// line each, so labels never break into vertical letter columns the
/// way the pre-circle `OutlinedButton.icon` row used to).
class _SocialAuthChip extends StatelessWidget {
  const _SocialAuthChip({
    required this.label,
    required this.icon,
    required this.isLoading,
    required this.onTap,
    this.semanticsLabel,
  });

  final String label;
  final IconData icon;
  final bool isLoading;
  final VoidCallback? onTap;

  /// Override for the a11y announcement when [label] alone doesn't read
  /// naturally after "Войти через …" (e.g. QR-код → "Войти по QR-коду").
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final disabled = onTap == null;
    final ringColor = disabled
        ? scheme.outlineVariant.withValues(alpha: 0.45)
        : scheme.outlineVariant;
    final iconColor = disabled
        ? scheme.onSurfaceVariant.withValues(alpha: 0.5)
        : scheme.onSurface;
    final textColor = disabled
        ? scheme.onSurfaceVariant.withValues(alpha: 0.6)
        : scheme.onSurface;
    return Semantics(
      label: semanticsLabel ?? 'Войти через $label',
      button: true,
      child: Material(
        color: Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: ringColor, width: 1.2)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                isLoading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.primary,
                        ),
                      )
                    : Icon(icon, size: 20, color: iconColor),
                const SizedBox(width: 8),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
