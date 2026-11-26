part of '../interactive_family_tree.dart';

extension _InteractiveTreeViewport on _InteractiveFamilyTreeState {
  void _setControlDockExpanded(bool value) {
    if (_controlDockExpanded == value) return;
    _updateTreeState(() => _controlDockExpanded = value);
  }

  void _handleTransformChanged() {
    if (!mounted) {
      return;
    }
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final scaleChanged = (scale - _currentScale).abs() >= 0.04;

    // K (culling): rebuild the node list when the viewport has moved OUTSIDE
    // the built set's cull rect, so nodes culled while offscreen reappear when
    // panned/zoomed back into view. The ~1-viewport margin baked into
    // _lastCulledRect means panning WITHIN it doesn't rebuild — idle-pan churn
    // stays near zero. (Before culling, pans never rebuilt at all; this is the
    // one behavioral change and is bounded by the margin.)
    var cullRebuild = false;
    final last = _lastCulledRect;
    if (last != null) {
      final vr = _visibleSceneRect();
      if (vr == null ||
          !(last.contains(vr.topLeft) && last.contains(vr.bottomRight))) {
        cullRebuild = true;
      }
    }

    if (!scaleChanged && !cullRebuild) {
      return;
    }
    _updateTreeState(() {
      _currentScale = scale;
    });
    // Pinch + the zoom +/- buttons flow through the transform; surface the live
    // percentage. Only on an actual scale change — a pure pan-driven cull
    // rebuild must not flash the zoom HUD. Fit / center override this with
    // their own label right after they set the transform.
    if (scaleChanged && _zoomHudReady) {
      _showZoomHud('${(scale * 100).round()}%');
    }
  }

  /// L (lost-user recovery): detect the tree drifting fully off the viewport
  /// and toggle the floating «Вернуться к дереву» pill. Runs on EVERY transform
  /// tick (translation-only pans included). Pure geometry off the cached
  /// treeSize + viewport + matrix — no fit math, no layout. Debounced ~220ms
  /// so a quick pan across the edge and back doesn't flash the pill.
  void _evaluateTreeOffscreen() {
    if (!mounted ||
        !_hasAppliedViewportFit ||
        _viewportSize == null ||
        treeSize == Size.zero) {
      return;
    }
    final viewport = _viewportSize!;
    final matrix = _transformationController.value;
    final scale = matrix.getMaxScaleOnAxis();
    final translation = matrix.getTranslation();
    final treeRect = Rect.fromLTWH(
      translation.x,
      translation.y,
      treeSize.width * scale,
      treeSize.height * scale,
    );
    // Require at least a 24px sliver on screen — «barely a corner peeking»
    // still counts as lost.
    final viewportRect = (Offset.zero & viewport).deflate(24);
    final offscreen = !treeRect.overlaps(viewportRect);
    if (offscreen == _treeOffscreen) {
      // Already in the target state — cancel any pending flip the other way.
      _offscreenDebounceTimer?.cancel();
      _offscreenDebounceTimer = null;
      return;
    }
    _offscreenDebounceTimer?.cancel();
    _offscreenDebounceTimer = Timer(const Duration(milliseconds: 220), () {
      if (!mounted || offscreen == _treeOffscreen) return;
      _updateTreeState(() => _treeOffscreen = offscreen);
    });
  }

  /// Dismiss the recovery pill immediately (the tree is back in view). Called
  /// by the recovery action itself so it doesn't linger for another debounce.
  void _clearTreeOffscreen() {
    _offscreenDebounceTimer?.cancel();
    _offscreenDebounceTimer = null;
    if (_treeOffscreen && mounted) {
      _updateTreeState(() => _treeOffscreen = false);
    }
  }

  /// Show a transient zoom HUD label (e.g. «80%», «Вписано»,
  /// «Центрировано») then fade it after ~1s. Additive overlay only —
  /// никакой gesture/layout-математики не трогает.
  void _showZoomHud(String label) {
    if (!mounted) return;
    _updateTreeState(() {
      _zoomHudText = label;
      _zoomHudVisible = true;
    });
    _zoomHudTimer?.cancel();
    _zoomHudTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) _updateTreeState(() => _zoomHudVisible = false);
    });
  }

  String? _findCurrentUserNodeId() {
    final currentUserId = widget.currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      return null;
    }

    for (final entry in widget.peopleData) {
      final person = entry['person'];
      if (person is FamilyPerson && person.userId == currentUserId) {
        return person.id;
      }
    }

    return null;
  }

  void _scheduleViewportFit() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasAppliedViewportFit) {
        return;
      }
      _fitTreeToViewport();
      final branchRootPersonId = widget.branchRootPersonId;
      if (branchRootPersonId != null && branchRootPersonId.isNotEmpty) {
        _focusOnPerson(branchRootPersonId);
      } else {
        // UX-аудит P0: большое дерево при fit-all — море нечитаемых
        // карточек, пользователь вынужден искать себя вручную. Если
        // дерево НЕ умещается в читаемом масштабе (raw fit ниже пола
        // 0.55, т.е. fit-all всё равно показывает лишь часть) —
        // центрируемся на карточке самого пользователя: «я и моя
        // семья вокруг меня». Малые деревья по-прежнему показываются
        // целиком. Явный branchRootPersonId выше приоритетом.
        final selfFocusId = _initialSelfFocusPersonId();
        if (selfFocusId != null) {
          _focusOnPerson(selfFocusId);
        }
      }
      _hasAppliedViewportFit = true;
      // From now on, zoom/fit/center actions are user-initiated → the
      // transient HUD may show (it stayed silent through the auto-fit).
      _zoomHudReady = true;
    });
  }

  /// Узел пользователя для стартового центрирования — только когда
  /// fit-all нечитаем (см. _scheduleViewportFit). Null → оставить fit.
  String? _initialSelfFocusPersonId() {
    final viewport = _viewportSize;
    if (viewport == null ||
        viewport.width <= 0 ||
        viewport.height <= 0 ||
        treeSize == Size.zero) {
      return null;
    }
    if (_rawFitScale(viewport) >= 0.55) {
      return null;
    }
    return _findCurrentUserNodeId();
  }

  /// «Сырой» масштаб вписывания дерева в viewport — ДО клампа полом
  /// 0.55: ниже пола значит «fit-all показал бы нечитаемые карточки
  /// либо обрезал дерево».
  double _rawFitScale(Size viewport) {
    final horizontalInset = viewport.width >= 1180 ? 18.0 : 28.0;
    final usableWidth = max(
      120.0,
      viewport.width -
          _viewportReservedLeft -
          _viewportReservedRight -
          horizontalInset,
    );
    final usableHeight = max(
      120.0,
      viewport.height - _viewportReservedTop - _viewportReservedBottom,
    );
    final horizontalScale = usableWidth / treeSize.width;
    final verticalScale = usableHeight / treeSize.height;
    return min(horizontalScale, verticalScale * 1.14);
  }

  void _fitTreeToViewport() {
    final viewport = _viewportSize;
    if (viewport == null ||
        viewport.width <= 0 ||
        viewport.height <= 0 ||
        treeSize == Size.zero) {
      return;
    }

    final contentWidth = treeSize.width;
    final contentHeight = treeSize.height;
    // User-reported: «дерево у нас так далеко при открытии, можно
    // ближе». The previous 0.2 lower clamp rendered medium-sized
    // trees at ~20% of viewport — readable on desktop, but on a
    // 360 dp phone the names became unreadable squiggles. Bump the
    // floor to 0.55 so even a 30-person tree fills enough of the
    // viewport that the user can read top-row names without zooming.
    final targetScale = _rawFitScale(viewport);
    final safeScale = targetScale.clamp(0.55, _maxViewportFitScale(viewport));

    final availableWidth = max(
      120.0,
      viewport.width - _viewportReservedLeft - _viewportReservedRight,
    );
    final translateX =
        _viewportReservedLeft + (availableWidth - contentWidth * safeScale) / 2;
    final availableHeight =
        viewport.height - _viewportReservedTop - _viewportReservedBottom;
    final translateY = _viewportReservedTop +
        (availableHeight - contentHeight * safeScale) / 2;

    _transformationController.value = vector_math.Matrix4.identity()
      ..translateByDouble(translateX, translateY, 0, 1)
      ..scaleByDouble(safeScale, safeScale, 1, 1);
    _clearTreeOffscreen();
    if (_zoomHudReady) _showZoomHud('Вписано');
  }

  void _focusOnPerson(String personId) {
    final viewport = _viewportSize;
    final targetPosition = nodePositions[personId];
    if (viewport == null ||
        viewport.width <= 0 ||
        viewport.height <= 0 ||
        targetPosition == null) {
      return;
    }

    final focusScale = _focusScaleForViewport(viewport);
    final availableWidth = max(
      120.0,
      viewport.width - _viewportReservedLeft - _viewportReservedRight,
    );
    final usableCenterX = _viewportReservedLeft + availableWidth / 2;
    final translateX = usableCenterX - targetPosition.dx * focusScale;
    final usableCenterY = _viewportReservedTop +
        (viewport.height - _viewportReservedTop - _viewportReservedBottom) / 2;
    final translateY = usableCenterY - targetPosition.dy * focusScale;

    _transformationController.value = vector_math.Matrix4.identity()
      ..translateByDouble(translateX, translateY, 0, 1)
      ..scaleByDouble(focusScale, focusScale, 1, 1);
    if (_zoomHudReady) _showZoomHud('Центрировано');
  }

  double _maxViewportFitScale(Size viewport) {
    final peopleCount = widget.peopleData.length;

    if (viewport.width >= 1500) {
      if (peopleCount <= 3) {
        return 2.04;
      }
      if (peopleCount <= 6) {
        return 1.74;
      }
      if (peopleCount <= 12) {
        return 1.46;
      }
      return 1.34;
    }

    if (viewport.width >= 1180) {
      if (peopleCount <= 3) {
        return 1.82;
      }
      if (peopleCount <= 6) {
        return 1.58;
      }
      if (peopleCount <= 12) {
        return 1.34;
      }
      return 1.26;
    }

    // Mobile (≤ 1180 dp width): allow noticeably bigger initial
    // scale than the previous 1.08-1.20 ceiling so the first frame
    // doesn't drop the user into a faraway aerial view of the tree.
    // The user can always pinch out for a wider overview.
    if (peopleCount <= 6) {
      return 1.6;
    }
    if (peopleCount <= 12) {
      return 1.4;
    }
    return 1.25;
  }

  double _focusScaleForViewport(Size viewport) {
    if (viewport.width >= 1500) {
      return 1.28;
    }
    if (viewport.width >= 1180) {
      return 1.16;
    }
    return 1.0;
  }

  // UX-аудит P1: double-tap раньше делал «вписать всё» — ломал мышечную
  // память карт/Figma. Теперь: зум ×1.5 к точке тапа; на большом
  void _handleCanvasDoubleTap() {
    final tapPoint = _doubleTapLocalPosition;
    _doubleTapLocalPosition = null;
    final currentMatrix = _transformationController.value.clone();
    final currentScale = currentMatrix.getMaxScaleOnAxis();
    if (tapPoint == null ||
        currentScale > _InteractiveFamilyTreeState._doubleTapFitFallbackScale) {
      _fitTreeToViewport();
      return;
    }
    final targetScale =
        (currentScale * _InteractiveFamilyTreeState._doubleTapZoomFactor)
            .clamp(0.08, 3.5);
    final appliedMultiplier = targetScale / currentScale;
    // translate-scale-untranslate вокруг scene-точки — точка тапа
    // остаётся под пальцем (та же математика, что в _zoomBy).
    final sceneFocalPoint = _transformationController.toScene(tapPoint);
    _transformationController.value = currentMatrix
      ..translateByDouble(sceneFocalPoint.dx, sceneFocalPoint.dy, 0, 1)
      ..scaleByDouble(appliedMultiplier, appliedMultiplier, 1, 1)
      ..translateByDouble(-sceneFocalPoint.dx, -sceneFocalPoint.dy, 0, 1);
  }

  void _zoomBy(double multiplier) {
    final viewport = _viewportSize;
    if (viewport == null || viewport.width <= 0 || viewport.height <= 0) {
      return;
    }

    final currentMatrix = _transformationController.value.clone();
    final currentScale = currentMatrix.getMaxScaleOnAxis();
    final targetScale = (currentScale * multiplier).clamp(0.08, 3.5);
    final appliedMultiplier = targetScale / currentScale;
    final availableWidth = max(
      120.0,
      viewport.width - _viewportReservedLeft - _viewportReservedRight,
    );
    final viewportFocalPoint = Offset(
      _viewportReservedLeft + availableWidth / 2,
      _viewportReservedTop +
          (viewport.height - _viewportReservedTop - _viewportReservedBottom) /
              2,
    );
    final sceneFocalPoint =
        _transformationController.toScene(viewportFocalPoint);

    _transformationController.value = currentMatrix
      ..translateByDouble(sceneFocalPoint.dx, sceneFocalPoint.dy, 0, 1)
      ..scaleByDouble(appliedMultiplier, appliedMultiplier, 1, 1)
      ..translateByDouble(-sceneFocalPoint.dx, -sceneFocalPoint.dy, 0, 1);
  }

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
