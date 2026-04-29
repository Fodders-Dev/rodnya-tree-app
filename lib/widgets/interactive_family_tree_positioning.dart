part of 'interactive_family_tree.dart';

extension _InteractiveFamilyTreePositioning on _InteractiveFamilyTreeState {
  Map<String, Offset> _mergeManualNodePositions(
    Map<String, Offset> automaticPositions,
  ) {
    final manualPositions = widget.manualNodePositions;
    if (manualPositions == null || manualPositions.isEmpty) {
      return automaticPositions;
    }

    final merged = Map<String, Offset>.from(automaticPositions);
    for (final entry in manualPositions.entries) {
      if (!merged.containsKey(entry.key)) {
        continue;
      }
      merged[entry.key] = _mergeNodePosition(
        personId: entry.key,
        automaticPosition: automaticPositions[entry.key]!,
        manualPosition: entry.value,
      );
    }
    return merged;
  }

  Offset _mergeNodePosition({
    required String personId,
    required Offset automaticPosition,
    required Offset manualPosition,
  }) {
    final normalizedManual = _normalizeNodePosition(manualPosition);
    final rowHints = _generationRowHints();
    final semanticRow = rowHints[personId];
    final maxVerticalDrift = semanticRow == null
        ? (InteractiveFamilyTree.nodeHeight +
                InteractiveFamilyTree.levelSeparation) *
            0.55
        : (InteractiveFamilyTree.nodeHeight +
                InteractiveFamilyTree.levelSeparation) *
            0.38;
    final mergedDy =
        (normalizedManual.dy - automaticPosition.dy).abs() > maxVerticalDrift
            ? automaticPosition.dy
            : normalizedManual.dy;
    return Offset(normalizedManual.dx, mergedDy);
  }

  Map<String, int> _generationRowHints() {
    final snapshot = widget.graphSnapshot;
    if (snapshot == null || snapshot.generationRows.isEmpty) {
      return const <String, int>{};
    }
    final hints = <String, int>{};
    final rowValues =
        snapshot.generationRows.map((row) => row.row).toList(growable: false);
    if (rowValues.isEmpty) {
      return const <String, int>{};
    }
    final minRow =
        rowValues.reduce((left, right) => left < right ? left : right);
    for (final row in snapshot.generationRows) {
      for (final personId in row.personIds) {
        hints[personId] = row.row - minRow;
      }
    }
    return hints;
  }

  Size _calculateTreeSize(
    Map<String, Offset> positions, {
    double minimumWidth = 300,
    double minimumHeight = 300,
  }) {
    if (positions.isEmpty) {
      return Size(
        max(minimumWidth, 300),
        max(minimumHeight, 300),
      );
    }

    double maxRight = 0;
    double maxBottom = 0;
    for (final position in positions.values) {
      maxRight = max(
        maxRight,
        position.dx +
            InteractiveFamilyTree.nodeWidth / 2 +
            InteractiveFamilyTree.contentInsetHorizontal,
      );
      maxBottom = max(
        maxBottom,
        position.dy +
            InteractiveFamilyTree.nodeHeight / 2 +
            InteractiveFamilyTree.contentInsetBottom,
      );
    }

    return Size(
      max(maxRight, max(minimumWidth, 300)),
      max(maxBottom, max(minimumHeight, 300)),
    );
  }

  Offset _normalizeNodePosition(Offset position) {
    final minDx = InteractiveFamilyTree.contentInsetHorizontal +
        InteractiveFamilyTree.nodeWidth / 2;
    final minDy = InteractiveFamilyTree.contentInsetTop +
        InteractiveFamilyTree.nodeHeight / 2;
    return Offset(
      max(position.dx, minDx),
      max(position.dy, minDy),
    );
  }

  void _handleNodeDragStart(FamilyPerson person) {
    if (!widget.isEditMode) {
      return;
    }
    final currentPosition = nodePositions[person.id];
    if (currentPosition == null) {
      return;
    }
    _selectEditPerson(person);
    _updateTreeState(() {
      _draggingPersonId = person.id;
      _dragStartNodePosition = currentPosition;
    });
  }

  void _handleNodeDragUpdate(
    FamilyPerson person,
    Offset offsetFromOrigin,
  ) {
    if (!widget.isEditMode) {
      return;
    }

    final dragStartPosition =
        _dragStartNodePosition ?? nodePositions[person.id];
    if (dragStartPosition == null) {
      return;
    }

    final effectiveScale = _currentScale <= 0 ? 1.0 : _currentScale;
    final automaticPosition =
        _automaticNodePositions[person.id] ?? dragStartPosition;
    final rawCandidate =
        dragStartPosition + (offsetFromOrigin / effectiveScale);
    final nextPosition = _snapNodePositionWithinGeneration(
      personId: person.id,
      candidatePosition: rawCandidate,
      automaticPosition: automaticPosition,
    );
    final updatedPositions = Map<String, Offset>.from(nodePositions)
      ..[person.id] = nextPosition;

    _updateTreeState(() {
      nodePositions = updatedPositions;
      treeSize = _calculateTreeSize(updatedPositions);
    });
  }

  void _handleNodeDragEnd() {
    if (_draggingPersonId == null) {
      return;
    }

    final updatedPositions = Map<String, Offset>.from(nodePositions);
    _updateTreeState(() {
      _draggingPersonId = null;
      _dragStartNodePosition = null;
    });
    widget.onNodePositionsChanged?.call(updatedPositions);
  }

  Offset _snapNodePositionWithinGeneration({
    required String personId,
    required Offset candidatePosition,
    required Offset automaticPosition,
  }) {
    final normalized = _normalizeNodePosition(candidatePosition);
    final rowHints = _generationRowHints();
    final semanticRow = rowHints[personId];
    final rowAutomaticPositions = _automaticNodePositions.entries
        .where((entry) => rowHints[entry.key] == semanticRow)
        .map((entry) => entry.value.dx)
        .toList()
      ..sort();

    final rowMinDx = rowAutomaticPositions.isEmpty
        ? automaticPosition.dx - InteractiveFamilyTree.nodeWidth
        : rowAutomaticPositions.first -
            (InteractiveFamilyTree.nodeWidth * 0.85);
    final rowMaxDx = rowAutomaticPositions.isEmpty
        ? automaticPosition.dx + InteractiveFamilyTree.nodeWidth
        : rowAutomaticPositions.last + (InteractiveFamilyTree.nodeWidth * 0.85);
    final clampedDx = normalized.dx.clamp(rowMinDx, rowMaxDx).toDouble();
    final snappedDx = _snapNodeDxToGenerationLanes(
      candidateDx: clampedDx,
      automaticDx: automaticPosition.dx,
      rowAutomaticPositions: rowAutomaticPositions,
    );
    return Offset(snappedDx, automaticPosition.dy);
  }

  double _snapNodeDxToGenerationLanes({
    required double candidateDx,
    required double automaticDx,
    required List<double> rowAutomaticPositions,
  }) {
    final snapTargets = <double>{automaticDx};
    for (final dx in rowAutomaticPositions) {
      snapTargets.add(dx);
    }
    final sortedRowPositions = rowAutomaticPositions.toList()..sort();
    for (var index = 0; index < sortedRowPositions.length - 1; index++) {
      snapTargets.add(
        (sortedRowPositions[index] + sortedRowPositions[index + 1]) / 2,
      );
    }

    if (snapTargets.isNotEmpty) {
      double? nearestTarget;
      var nearestDistance = double.infinity;
      for (final target in snapTargets) {
        final distance = (target - candidateDx).abs();
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearestTarget = target;
        }
      }
      if (nearestTarget != null && nearestDistance <= 36) {
        return nearestTarget;
      }
    }

    const gridStep = 24.0;
    final snappedGridDx = (candidateDx / gridStep).roundToDouble() * gridStep;
    if ((snappedGridDx - candidateDx).abs() <= 12) {
      return snappedGridDx;
    }
    return candidateDx;
  }
}
