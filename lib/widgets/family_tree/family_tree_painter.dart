part of '../interactive_family_tree.dart';

// Класс для отрисовки линий связей - ВНЕ класса _InteractiveFamilyTreeState
class FamilyTreePainter extends CustomPainter {
  final Map<String, Offset> nodePositions; // Центры узлов
  final List<FamilyConnection> connections;
  final TreeGraphSnapshot? graphSnapshot;
  final List<FamilyRelation> relations;
  final Paint spouseLinePaint;
  final Paint spousePastLinePaint;
  final Paint familyLinePaint;
  final Paint mutedFamilyLinePaint;

  /// Phase 4 chunk 3c: cross-tree paint variants. Cool slate, alpha
  /// equivalent legacy paints. Selected per-edge когда `at least
  /// one endpoint ∈ foreignPersonIds`.
  final Paint foreignFamilyLinePaint;
  final Paint foreignSpouseLinePaint;

  final Paint junctionPaint;
  final Paint mutedJunctionPaint;
  final Color tokenInk;

  /// Phase 4 chunk 3c: set of graphPerson ids считающихся foreign
  /// (not owned by viewer). Painter dumb — when empty Set → always
  /// returns default warm paints (legacy behavior). Source of
  /// truth — `_InteractiveFamilyTreeState._foreignPersonIds` (cached
  /// per slice).
  final Set<String> foreignPersonIds;

  FamilyTreePainter(
    this.nodePositions,
    this.connections, {
    this.graphSnapshot,
    this.relations = const <FamilyRelation>[],
    Color? lineColor,
    Color? mutedLineColor,
    Color? spouseColor,
    Color junctionColor = const Color(0xFF8E9588),
    Color foreignEdgeColor = const Color(0xFF7E8896),
    this.foreignPersonIds = const <String>{},
  })  : tokenInk = lineColor ?? const Color(0xFF6E7766),
        // Reference lines: ink-muted at ~50% opacity, subtle warm undertone
        // for spouse vs family. We pull base colors from design tokens via
        // the section builder; fallbacks keep the painter usable in tests.
        spouseLinePaint = Paint()
          ..color =
              (spouseColor ?? const Color(0xFFB39B5C)).withValues(alpha: 0.55)
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke,
        spousePastLinePaint = Paint()
          ..color =
              (spouseColor ?? const Color(0xFFB39B5C)).withValues(alpha: 0.32)
          ..strokeWidth = 1.1
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke,
        familyLinePaint = Paint()
          ..color =
              (lineColor ?? const Color(0xFF6E7766)).withValues(alpha: 0.55)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke,
        mutedFamilyLinePaint = Paint()
          ..color = (mutedLineColor ?? const Color(0xFF8E9588))
              .withValues(alpha: 0.42)
          ..strokeWidth = 1.3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke,
        // Phase 4 chunk 3c cross-tree paints. Same stroke width
        // как legacy для visual continuity (только color shifted).
        foreignFamilyLinePaint = Paint()
          ..color = foreignEdgeColor.withValues(alpha: 0.45)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke,
        foreignSpouseLinePaint = Paint()
          ..color = foreignEdgeColor.withValues(alpha: 0.45)
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke,
        junctionPaint = Paint()
          ..color = junctionColor.withValues(alpha: 0.55)
          ..isAntiAlias = true
          ..style = PaintingStyle.fill,
        mutedJunctionPaint = Paint()
          ..color = junctionColor.withValues(alpha: 0.32)
          ..isAntiAlias = true
          ..style = PaintingStyle.fill;

  /// Phase 4 chunk 3c: edge cross-tree check. At-least-one-endpoint-
  /// foreign per Артёмов definition (DECISIONS.md 2026-05-12 §5.A
  /// Element 2). Empty Set → all edges legacy warm — guarantees
  /// bit-identical rendering при flag=false либо mine mode.
  bool _isCrossTreeEdge(String fromId, String toId) {
    if (foreignPersonIds.isEmpty) return false;
    return foreignPersonIds.contains(fromId) || foreignPersonIds.contains(toId);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final snapshot = graphSnapshot;
    if (snapshot != null && snapshot.familyUnits.isNotEmpty) {
      final didPaintFromSnapshot = _paintSnapshotUnits(canvas, snapshot);
      if (didPaintFromSnapshot) {
        return;
      }
    }

    final familyUnits = <String, _PaintFamilyUnit>{};
    final paintedFamilyKeys = <String>{};

    for (final connection in connections) {
      final startNodePos = nodePositions[connection.fromId];
      final endNodePos = nodePositions[connection.toId];
      if (startNodePos == null || endNodePos == null) {
        continue;
      }

      if (connection.type == RelationType.spouse) {
        // Phase 4 chunk 3c: cross-tree spouse → foreign tint.
        // F2: бывший союз — приглушённый пунктир, читается как «было».
        final isCrossTree =
            _isCrossTreeEdge(connection.fromId, connection.toId);
        final paint = isCrossTree
            ? foreignSpouseLinePaint
            : (connection.isPastUnion ? spousePastLinePaint : spouseLinePaint);
        _drawSpouseLine(
          canvas,
          startNodePos,
          endNodePos,
          paint,
          dashed: connection.isPastUnion && !isCrossTree,
        );
      } else if (connection.type == RelationType.parent) {
        final key = connection.toId;
        final unit = familyUnits.putIfAbsent(
          key,
          () => _PaintFamilyUnit(childId: connection.toId),
        );
        unit.parentIds.add(connection.fromId);
      }
    }

    for (final unit in familyUnits.values) {
      final parentIds = unit.parentIds.toList()
        ..sort((a, b) => nodePositions[a]!.dx.compareTo(nodePositions[b]!.dx));
      final childIds = <String>[unit.childId];
      final groupedKey = parentIds.join('::');
      final siblings = familyUnits.values
          .where((candidate) =>
              candidate.childId != unit.childId &&
              candidate.parentIds.length == unit.parentIds.length &&
              candidate.parentIds.toSet().containsAll(parentIds))
          .map((candidate) => candidate.childId)
          .toList()
        ..sort((a, b) => nodePositions[a]!.dx.compareTo(nodePositions[b]!.dx));
      childIds.addAll(siblings.where((id) => !childIds.contains(id)));

      if (groupedKey.isEmpty) {
        continue;
      }
      if (paintedFamilyKeys.add(groupedKey)) {
        // Phase 4 chunk 3c: family-unit cross-tree if any endpoint
        // foreign (parent либо child). Same rule as spouse.
        final hasForeignEndpoint = parentIds.any(foreignPersonIds.contains) ||
            childIds.any(foreignPersonIds.contains);
        final paint =
            hasForeignEndpoint ? foreignFamilyLinePaint : familyLinePaint;
        _drawFamilyUnit(
          canvas,
          parentIds: parentIds,
          childIds: childIds,
          linePaint: paint,
          pointPaint: junctionPaint,
        );
      }
    }
  }

  bool _paintSnapshotUnits(Canvas canvas, TreeGraphSnapshot snapshot) {
    final visiblePersonIds = nodePositions.keys.toSet();
    final paintedFamilyKeys = <String>{};
    final paintedSpousePairs = <String>{};
    var paintedAnything = false;

    for (final unit in snapshot.familyUnits) {
      final parentIds = unit.adultIds
          .where(visiblePersonIds.contains)
          .toList(growable: false)
        ..sort((left, right) =>
            nodePositions[left]!.dx.compareTo(nodePositions[right]!.dx));
      final childIds = unit.childIds
          .where(visiblePersonIds.contains)
          .toList(growable: false)
        ..sort((left, right) =>
            nodePositions[left]!.dx.compareTo(nodePositions[right]!.dx));

      if (parentIds.length > 1) {
        for (var index = 0; index < parentIds.length - 1; index++) {
          final pairIds = [parentIds[index], parentIds[index + 1]]..sort();
          final pairKey = pairIds.join('::');
          if (!paintedSpousePairs.add(pairKey)) {
            continue;
          }
          final firstPosition = nodePositions[pairIds.first];
          final secondPosition = nodePositions[pairIds.last];
          if (firstPosition == null || secondPosition == null) {
            continue;
          }
          // Phase 4 chunk 3c: per-pair cross-tree check. unionStatus
          // past keeps legacy muted variant — cross-tree active edge
          // takes precedence over past styling (semantic priority:
          // ownership > status).
          final isCrossTree = _isCrossTreeEdge(pairIds.first, pairIds.last);
          final isPast = _isInactiveUnionStatus(unit.unionStatus);
          final linePaint = isCrossTree
              ? foreignSpouseLinePaint
              : (isPast ? spousePastLinePaint : spouseLinePaint);
          // F2: бывший союз — пунктир (бледности мало: для 50+ она
          // читается как «дальний», а не «бывший»).
          _drawSpouseLine(
            canvas,
            firstPosition,
            secondPosition,
            linePaint,
            dashed: isPast && !isCrossTree,
          );
          paintedAnything = true;
        }
      }

      if (parentIds.isEmpty || childIds.isEmpty) {
        continue;
      }
      final groupedKey =
          '${unit.id}::${parentIds.join('::')}::${childIds.join('::')}';
      if (!paintedFamilyKeys.add(groupedKey)) {
        continue;
      }

      // Phase 4 chunk 3c: family-unit cross-tree if any parent либо
      // child foreign.
      final hasForeignEndpoint = parentIds.any(foreignPersonIds.contains) ||
          childIds.any(foreignPersonIds.contains);
      final linePaint = hasForeignEndpoint
          ? foreignFamilyLinePaint
          : (_isInactiveUnionStatus(unit.unionStatus)
              ? mutedFamilyLinePaint
              : familyLinePaint);
      final junctionPaintForUnit = _isInactiveUnionStatus(unit.unionStatus)
          ? mutedJunctionPaint
          : junctionPaint;
      final dashed = (unit.parentSetType ?? '').trim().isNotEmpty &&
          unit.parentSetType != 'biological' &&
          unit.parentSetType != 'unknown';
      _drawFamilyUnit(
        canvas,
        parentIds: parentIds,
        childIds: childIds,
        linePaint: linePaint,
        pointPaint: junctionPaintForUnit,
        dashed: dashed,
      );
      paintedAnything = true;
    }

    return paintedAnything;
  }

  // Метод для рисования линии между супругами
  void _drawSpouseLine(
    Canvas canvas,
    Offset pos1,
    Offset pos2,
    Paint linePaint, {
    bool dashed = false,
  }) {
    // Просто рисуем горизонтальную линию между боковыми центрами
    final y = pos1.dy; // Супруги на одном уровне
    final x1 = pos1.dx +
        (pos1.dx < pos2.dx
            ? InteractiveFamilyTree.nodeWidth / 2
            : -InteractiveFamilyTree.nodeWidth / 2);
    final x2 = pos2.dx +
        (pos1.dx < pos2.dx
            ? -InteractiveFamilyTree.nodeWidth / 2
            : InteractiveFamilyTree.nodeWidth / 2);
    if (dashed) {
      // F2: бывший союз — пунктир тем же приёмом, что adoptive-коннекторы.
      _drawDashedSegment(canvas, Offset(x1, y), Offset(x2, y), linePaint);
      return;
    }
    canvas.drawLine(Offset(x1, y), Offset(x2, y), linePaint);
  }

  /// F2: пунктирный отрезок (6/4) — союз, который был, но закончился.
  void _drawDashedSegment(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint linePaint,
  ) {
    const dashLength = 6.0;
    const gapLength = 4.0;
    final delta = end - start;
    final distance = delta.distance;
    if (distance <= 0.1) {
      return;
    }
    final direction = Offset(delta.dx / distance, delta.dy / distance);
    double offset = 0;
    while (offset < distance) {
      final segmentStart = start + direction * offset;
      final segmentEnd = start + direction * min(offset + dashLength, distance);
      canvas.drawLine(segmentStart, segmentEnd, linePaint);
      offset += dashLength + gapLength;
    }
  }

  void _drawFamilyUnit(
    Canvas canvas, {
    required List<String> parentIds,
    required List<String> childIds,
    required Paint linePaint,
    required Paint pointPaint,
    bool dashed = false,
  }) {
    final parentAnchors = parentIds
        .map((id) => nodePositions[id])
        .whereType<Offset>()
        .map(
          (offset) => Offset(
            offset.dx,
            offset.dy + InteractiveFamilyTree.nodeHeight / 2,
          ),
        )
        .toList();
    final childAnchors = childIds
        .map((id) => nodePositions[id])
        .whereType<Offset>()
        .map(
          (offset) => Offset(
            offset.dx,
            offset.dy - InteractiveFamilyTree.nodeHeight / 2,
          ),
        )
        .toList();

    if (parentAnchors.isEmpty || childAnchors.isEmpty) {
      return;
    }

    final parentBarY =
        parentAnchors.map((anchor) => anchor.dy).reduce(max) + 18;
    final familyCenterX =
        parentAnchors.map((anchor) => anchor.dx).reduce((a, b) => a + b) /
            parentAnchors.length;

    if (parentAnchors.length > 1) {
      final minParentX = parentAnchors.map((anchor) => anchor.dx).reduce(min);
      final maxParentX = parentAnchors.map((anchor) => anchor.dx).reduce(max);
      for (final anchor in parentAnchors) {
        _drawSegment(
          canvas: canvas,
          start: anchor,
          end: Offset(anchor.dx, parentBarY),
          linePaint: linePaint,
          dashed: dashed,
        );
      }
      _drawSegment(
        canvas: canvas,
        start: Offset(minParentX, parentBarY),
        end: Offset(maxParentX, parentBarY),
        linePaint: linePaint,
        dashed: dashed,
      );
      _drawJunction(canvas, Offset(familyCenterX, parentBarY), pointPaint);
    } else {
      _drawSegment(
        canvas: canvas,
        start: parentAnchors.first,
        end: Offset(familyCenterX, parentBarY),
        linePaint: linePaint,
        dashed: dashed,
      );
      _drawJunction(canvas, Offset(familyCenterX, parentBarY), pointPaint);
    }

    final downwardChildren =
        childAnchors.where((anchor) => anchor.dy >= parentBarY).toList();
    final upwardChildren =
        childAnchors.where((anchor) => anchor.dy < parentBarY).toList();

    if (downwardChildren.isNotEmpty) {
      _drawChildAnchorGroup(
        canvas,
        familyCenterX: familyCenterX,
        parentBarY: parentBarY,
        anchors: downwardChildren,
        linePaint: linePaint,
        pointPaint: pointPaint,
        dashed: dashed,
      );
    }

    if (upwardChildren.isNotEmpty) {
      _drawChildAnchorGroup(
        canvas,
        familyCenterX: familyCenterX,
        parentBarY: parentBarY,
        anchors: upwardChildren,
        linePaint: linePaint,
        pointPaint: pointPaint,
        dashed: dashed,
      );
    }
  }

  void _drawChildAnchorGroup(
    Canvas canvas, {
    required double familyCenterX,
    required double parentBarY,
    required List<Offset> anchors,
    required Paint linePaint,
    required Paint pointPaint,
    required bool dashed,
  }) {
    if (anchors.isEmpty) {
      return;
    }

    final junction = Offset(familyCenterX, parentBarY);
    final averageChildY =
        anchors.map((anchor) => anchor.dy).reduce((a, b) => a + b) /
            anchors.length;
    final direction = averageChildY >= parentBarY ? 1.0 : -1.0;
    final verticalGap = (averageChildY - parentBarY).abs();
    // Anchor the shared bus to the CHILDREN, not the parent. Previously the
    // bus sat at parentBarY + clamp(verticalGap, 26, 58), so at a typical
    // ~50-70px generation gap the per-child stub (verticalGap - clamp)
    // collapsed to 0-12px: children sat flush against the bus and were
    // indistinguishable from a child's spouse. Anchoring to the children
    // guarantees a visible vertical stub (≈20-40px) dropping onto every
    // child; the parent→bus segment takes the remaining gap.
    final targetStub = (verticalGap * 0.45).clamp(20.0, 40.0).toDouble();
    // Overshoot guard: in unusually tight layouts (verticalGap < targetStub)
    // never let the bus cross above the parent bar — keep at least a small
    // parent→bus segment so the connector still reads top-down.
    final childStub = min(targetStub, max(verticalGap - 12.0, 0.0));
    final busY = averageChildY - childStub * direction;
    final sortedAnchors = [...anchors]..sort((a, b) => a.dx.compareTo(b.dx));
    final minChildX = min(
      familyCenterX,
      sortedAnchors.map((anchor) => anchor.dx).reduce(min),
    );
    final maxChildX = max(
      familyCenterX,
      sortedAnchors.map((anchor) => anchor.dx).reduce(max),
    );

    _drawSegment(
      canvas: canvas,
      start: junction,
      end: Offset(familyCenterX, busY),
      linePaint: linePaint,
      dashed: dashed,
    );
    _drawSegment(
      canvas: canvas,
      start: Offset(minChildX, busY),
      end: Offset(maxChildX, busY),
      linePaint: linePaint,
      dashed: dashed,
    );
    for (final anchor in sortedAnchors) {
      _drawSegment(
        canvas: canvas,
        start: Offset(anchor.dx, busY),
        end: anchor,
        linePaint: linePaint,
        dashed: dashed,
      );
    }
    _drawJunction(canvas, junction, pointPaint);
  }

  void _drawSegment({
    required Canvas canvas,
    required Offset start,
    required Offset end,
    required Paint linePaint,
    required bool dashed,
  }) {
    if (!dashed) {
      canvas.drawLine(start, end, linePaint);
      return;
    }

    const dashLength = 6.0;
    const gapLength = 4.0;
    final delta = end - start;
    final distance = delta.distance;
    if (distance <= 0.1) {
      return;
    }
    final direction = Offset(delta.dx / distance, delta.dy / distance);
    double offset = 0;
    while (offset < distance) {
      final segmentStart = start + direction * offset;
      final segmentEnd = start + direction * min(offset + dashLength, distance);
      canvas.drawLine(segmentStart, segmentEnd, linePaint);
      offset += dashLength + gapLength;
    }
  }

  void _drawJunction(Canvas canvas, Offset center, Paint pointPaint) {
    // Smaller, softer junction circles — reference uses tiny dots so the
    // structure reads as connectors, not bullet points.
    canvas.drawCircle(center, 2.6, pointPaint);
  }

  @override
  bool shouldRepaint(covariant FamilyTreePainter oldDelegate) {
    // Перерисовываем, если изменились позиции узлов или сами связи.
    // Phase 4 chunk 3c: foreignPersonIds change → repaint (mode toggle
    // либо slice update меняет которые edges cross-tree).
    return oldDelegate.nodePositions != nodePositions ||
        oldDelegate.connections != connections ||
        oldDelegate.graphSnapshot != graphSnapshot ||
        oldDelegate.relations != relations ||
        oldDelegate.foreignPersonIds != foreignPersonIds;
  }
} // <- Скобка закрывает класс FamilyTreePainter

class _PaintFamilyUnit {
  _PaintFamilyUnit({required this.childId});

  final String childId;
  final Set<String> parentIds = <String>{};
}
