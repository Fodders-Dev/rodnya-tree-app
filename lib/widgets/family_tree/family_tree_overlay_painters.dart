part of '../interactive_family_tree.dart';

class _SelectedTreePathPainter extends CustomPainter {
  const _SelectedTreePathPainter({
    required this.nodePositions,
    required this.relations,
    required this.selectedPersonId,
    required this.accent,
  });

  final Map<String, Offset> nodePositions;
  final List<FamilyRelation> relations;
  final String selectedPersonId;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final selectedPosition = nodePositions[selectedPersonId];
    if (selectedPosition == null) {
      return;
    }

    final paint = Paint()
      ..color = accent.withValues(alpha: 0.62)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    final glowPaint = Paint()
      ..color = accent.withValues(alpha: 0.16)
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    final highlightedPairs = <String>{};
    for (final relation in relations) {
      final isFromSelected = relation.person1Id == selectedPersonId;
      final isToSelected = relation.person2Id == selectedPersonId;
      if (!isFromSelected && !isToSelected) {
        continue;
      }
      final otherId = isFromSelected ? relation.person2Id : relation.person1Id;
      final otherPosition = nodePositions[otherId];
      if (otherPosition == null) {
        continue;
      }
      final pair = <String>[selectedPersonId, otherId]..sort();
      if (!highlightedPairs.add(pair.join('::'))) {
        continue;
      }

      final path = _pathBetweenNodes(selectedPosition, otherPosition);
      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, paint);
    }

    final ringPaint = Paint()
      ..color = accent.withValues(alpha: 0.34)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: selectedPosition,
          width: InteractiveFamilyTree.nodeWidth + 16,
          height: InteractiveFamilyTree.nodeHeight + 16,
        ),
        const Radius.circular(18),
      ),
      ringPaint,
    );
  }

  Path _pathBetweenNodes(Offset start, Offset end) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final path = Path()..moveTo(start.dx, start.dy);
    if (dy.abs() < 24) {
      path.cubicTo(
        start.dx + dx * 0.35,
        start.dy,
        start.dx + dx * 0.65,
        end.dy,
        end.dx,
        end.dy,
      );
      return path;
    }
    final controlYOffset = dy.sign * min(96.0, dy.abs() * 0.42);
    path.cubicTo(
      start.dx,
      start.dy + controlYOffset,
      end.dx,
      end.dy - controlYOffset,
      end.dx,
      end.dy,
    );
    return path;
  }

  @override
  bool shouldRepaint(covariant _SelectedTreePathPainter oldDelegate) {
    return oldDelegate.nodePositions != nodePositions ||
        oldDelegate.relations != relations ||
        oldDelegate.selectedPersonId != selectedPersonId ||
        oldDelegate.accent != accent;
  }
}

/// 4-icon picker for the edge-first connector. The user has just
/// dropped a card onto another and now picks the relation type.
/// Returns the chosen [RelationType] via Navigator.pop, or null
/// when the user dismisses (taps outside or hits back).
///
/// We deliberately keep the choices to FOUR — covers >95% of real
/// family-tree edits and matches the existing quick-add bottom-
/// sheet's vocabulary. "Другая связь" pops the legacy quick-add
/// sheet so power users can still reach the long tail
/// (cousin / nephew / step-* / in-laws / friend / colleague).
/// drag ends (accepted or canceled) the parent removes this from
/// the tree entirely.
class _ConnectorPreviewPainter extends CustomPainter {
  _ConnectorPreviewPainter({
    required this.source,
    required this.target,
    required this.color,
  });

  final Offset source;
  final Offset target;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.78)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Dashed line: 8 px on, 6 px off. Path-based so the cap-rounded
    // segments look continuous at the tip.
    const dashOn = 8.0;
    const dashOff = 6.0;
    final dx = target.dx - source.dx;
    final dy = target.dy - source.dy;
    final totalLength = sqrt(dx * dx + dy * dy);
    if (totalLength <= 0) return;
    final stepX = dx / totalLength;
    final stepY = dy / totalLength;
    var traveled = 0.0;
    while (traveled < totalLength) {
      final segmentEnd = min(traveled + dashOn, totalLength);
      canvas.drawLine(
        Offset(source.dx + stepX * traveled, source.dy + stepY * traveled),
        Offset(source.dx + stepX * segmentEnd, source.dy + stepY * segmentEnd),
        paint,
      );
      traveled = segmentEnd + dashOff;
    }

    // Filled circle on the target end so the line "reads" as
    // attaching to the cursor rather than fading off.
    final dotPaint = Paint()
      ..color = color.withValues(alpha: 0.92)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(target, 5.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _ConnectorPreviewPainter oldDelegate) {
    return oldDelegate.source != source ||
        oldDelegate.target != target ||
        oldDelegate.color != color;
  }
}

/// Lasso-rectangle overlay painted while the user is dragging in
/// selection mode. Translucent accent fill + 1.4px accent border
/// — enough to read the bounds against the canvas without
/// drowning the cards underneath. Coordinates are canvas-space
/// (already through `transformationController.toScene`) so the
/// rectangle stays anchored when the user pans the viewport
/// during the drag (current behaviour: pan disabled in selection
/// mode, but the painter is correct either way).
class _LassoRectPainter extends CustomPainter {
  _LassoRectPainter({
    required this.start,
    required this.end,
    required this.accent,
  });

  final Offset start;
  final Offset end;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(start, end);
    if (rect.isEmpty) return;
    final fill = Paint()
      ..color = accent.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = accent.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final rounded = RRect.fromRectAndRadius(rect, const Radius.circular(6));
    canvas.drawRRect(rounded, fill);
    canvas.drawRRect(rounded, stroke);
  }

  @override
  bool shouldRepaint(covariant _LassoRectPainter oldDelegate) {
    return oldDelegate.start != start ||
        oldDelegate.end != end ||
        oldDelegate.accent != accent;
  }
}
