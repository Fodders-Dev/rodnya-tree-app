import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'dart:math'; // <--- Добавляем импорт для функции min
import 'package:vector_math/vector_math_64.dart' as vector_math;
import '../models/family_person.dart';
import '../models/family_relation.dart';
import '../models/tree_graph_snapshot.dart';
import '../models/user_profile.dart';
import 'family_tree_node_card.dart';

// Структура для хранения информации о связях для отрисовки
class FamilyConnection {
  final String fromId;
  final String toId;
  final RelationType type; // Добавляем тип связи

  FamilyConnection({
    required this.fromId,
    required this.toId,
    required this.type,
  });
}

class InteractiveFamilyTree extends StatefulWidget {
  final List<Map<String, dynamic>>
      peopleData; // Теперь содержит {'person': FamilyPerson, 'userProfile': UserProfile?}
  final List<FamilyRelation> relations;
  final TreeGraphSnapshot? graphSnapshot;
  final Function(FamilyPerson) onPersonTap; // Коллбэк при нажатии на узел
  final bool isEditMode; // Флаг режима редактирования
  final void Function(FamilyPerson person, RelationType type)
      onAddRelativeTapWithType; // Коллбэк для добавления
  final bool
      currentUserIsInTree; // <<< НОВЫЙ ПАРАМЕТР: Флаг, добавлен ли текущий пользователь
  final void Function(FamilyPerson targetPerson, RelationType relationType)
      onAddSelfTapWithType; // <<< НОВЫЙ ПАРАМЕТР: Коллбэк для добавления себя
  final String? currentUserId;
  final String? branchRootPersonId;
  final ValueChanged<FamilyPerson>? onBranchFocusRequested;
  final VoidCallback? onBranchFocusCleared;
  final String? selectedEditPersonId;
  final ValueChanged<FamilyPerson>? onEditPersonSelected;
  final ValueChanged<FamilyPerson>? onOpenPersonHistory;
  final ValueChanged<FamilyPerson>? onShowRelationPath;
  final ValueChanged<FamilyPerson>? onShowOtherParents;
  final ValueChanged<FamilyPerson>? onFixPersonRelations;
  final Map<String, Offset>? manualNodePositions;
  final ValueChanged<Map<String, Offset>>? onNodePositionsChanged;
  final bool showGenerationGuides;
  final String graphLabel;
  final bool hasManualLayout;
  final VoidCallback? onResetLayout;

  // Константы для размеров узлов и отступов - понадобятся для расчета layout
  static const double nodeWidth = 132; // Примерная ширина карточки
  static const double nodeHeight = 112; // Примерная высота карточки
  static const double levelSeparation =
      64; // Вертикальное расстояние между уровнями
  static const double siblingSeparation =
      40; // Горизонтальное расстояние между братьями/сестрами
  static const double spouseSeparation =
      20; // Горизонтальное расстояние между супругами
  static const double contentInsetHorizontal = 72;
  static const double contentInsetTop = 80;
  static const double contentInsetBottom = 40;

  const InteractiveFamilyTree({
    super.key,
    required this.peopleData,
    required this.relations,
    this.graphSnapshot,
    required this.onPersonTap,
    this.isEditMode = false, // По умолчанию выключен
    required this.onAddRelativeTapWithType,
    required this.currentUserIsInTree, // Делаем обязательным
    required this.onAddSelfTapWithType, // Делаем обязательным
    this.currentUserId,
    this.branchRootPersonId,
    this.onBranchFocusRequested,
    this.onBranchFocusCleared,
    this.selectedEditPersonId,
    this.onEditPersonSelected,
    this.onOpenPersonHistory,
    this.onShowRelationPath,
    this.onShowOtherParents,
    this.onFixPersonRelations,
    this.manualNodePositions,
    this.onNodePositionsChanged,
    this.showGenerationGuides = true,
    this.graphLabel = 'дерева',
    this.hasManualLayout = false,
    this.onResetLayout,
  });

  @override
  State<InteractiveFamilyTree> createState() => _InteractiveFamilyTreeState();
}

class _InteractiveFamilyTreeState extends State<InteractiveFamilyTree> {
  static const double _viewportReservedTop = 64;
  static const double _viewportReservedBottom = 28;

  // Данные для CustomPainter
  Map<String, Offset> nodePositions = {}; // ID человека -> его позиция (центр)
  Map<String, Offset> _automaticNodePositions = {};
  List<FamilyConnection> connections = []; // Список связей для отрисовки линий
  Size treeSize = Size.zero; // Общий размер дерева для CustomPaint и Stack
  final TransformationController _transformationController =
      TransformationController();
  Size? _viewportSize;
  bool _hasAppliedViewportFit = false;
  String? _selectedEditPersonId;
  double _currentScale = 1.0;
  String? _draggingPersonId;
  String? _hoveredPersonId;
  Offset? _dragStartNodePosition;

  @override
  void initState() {
    super.initState();
    _selectedEditPersonId = widget.selectedEditPersonId;
    _transformationController.addListener(_handleTransformChanged);
    _calculateLayout(); // Вызываем расчет layout
  }

  @override
  void didUpdateWidget(InteractiveFamilyTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.peopleData != widget.peopleData ||
        oldWidget.relations != widget.relations ||
        oldWidget.graphSnapshot != widget.graphSnapshot ||
        oldWidget.currentUserId != widget.currentUserId ||
        oldWidget.branchRootPersonId != widget.branchRootPersonId ||
        oldWidget.manualNodePositions != widget.manualNodePositions) {
      _hasAppliedViewportFit = false;
      _calculateLayout(); // Пересчитываем layout при изменении данных
    }
    if (oldWidget.selectedEditPersonId != widget.selectedEditPersonId) {
      _selectedEditPersonId = widget.selectedEditPersonId;
      if (_selectedEditPersonId != null && _selectedEditPersonId!.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _focusOnPerson(_selectedEditPersonId!);
          }
        });
      }
    }
    if (!widget.isEditMode && _selectedEditPersonId != null) {
      _selectedEditPersonId = null;
    }
  }

  @override
  void dispose() {
    _transformationController.removeListener(_handleTransformChanged);
    _transformationController.dispose();
    super.dispose();
  }

  void _handleTransformChanged() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    if ((scale - _currentScale).abs() < 0.04 || !mounted) {
      return;
    }
    setState(() {
      _currentScale = scale;
    });
  }

  // Метод для расчета позиций узлов и связей
  void _calculateLayout() {
    if (widget.peopleData.isEmpty) {
      setState(() {
        nodePositions = {};
        _automaticNodePositions = {};
        connections = [];
        treeSize = Size.zero;
      });
      return;
    }
    final modernLayout = _buildModernLayout();
    final mergedPositions =
        _mergeManualNodePositions(modernLayout.nodePositions);
    setState(() {
      _automaticNodePositions = modernLayout.nodePositions;
      nodePositions = mergedPositions;
      connections = modernLayout.connections;
      treeSize = _calculateTreeSize(
        mergedPositions,
        minimumWidth: modernLayout.treeSize.width,
        minimumHeight: modernLayout.treeSize.height,
      );
    });
    _scheduleViewportFit();
  }

  _TreeLayoutComputation _buildModernLayout() {
    final visiblePeopleData = _buildVisiblePeopleData();
    if (visiblePeopleData.isEmpty) {
      return const _TreeLayoutComputation(
        nodePositions: <String, Offset>{},
        connections: <FamilyConnection>[],
        treeSize: Size.zero,
      );
    }

    final visibleIds = visiblePeopleData
        .map((entry) => (entry['person'] as FamilyPerson).id)
        .toSet();
    final visibleRelations = widget.relations.where((relation) {
      return visibleIds.contains(relation.person1Id) &&
          visibleIds.contains(relation.person2Id);
    }).toList();

    return _TreeLayoutEngine(
      peopleData: visiblePeopleData,
      relations: visibleRelations,
      graphSnapshot: widget.graphSnapshot,
    ).compute();
  }

  List<Map<String, dynamic>> _buildVisiblePeopleData() {
    final branchRootPersonId = widget.branchRootPersonId;
    if (branchRootPersonId == null || branchRootPersonId.isEmpty) {
      return widget.peopleData;
    }

    final visibleIds = _buildBranchVisibleIds(branchRootPersonId);
    return widget.peopleData.where((entry) {
      final person = entry['person'];
      return person is FamilyPerson && visibleIds.contains(person.id);
    }).toList();
  }

  Set<String> _buildBranchVisibleIds(String branchRootPersonId) {
    final personIds = widget.peopleData
        .map((entry) => (entry['person'] as FamilyPerson).id)
        .toSet();
    final graphSnapshot = widget.graphSnapshot;
    if (graphSnapshot != null) {
      final branchBlock =
          graphSnapshot.findBranchBlockForPerson(branchRootPersonId);
      if (branchBlock != null) {
        return branchBlock.memberPersonIds.toSet();
      }
    }
    return personIds;
  }

  @override
  Widget build(BuildContext context) {
    final stackWidth = treeSize.width;
    final stackHeight = treeSize.height;
    final interactionBoundary = max(stackWidth, stackHeight) + 160;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportSize = Size(
            constraints.maxWidth,
            constraints.maxHeight,
          );
          if (_viewportSize != viewportSize) {
            _viewportSize = viewportSize;
            _hasAppliedViewportFit = false;
            _scheduleViewportFit();
          }

          return Stack(
            clipBehavior: Clip.none,
            children: [
              CallbackShortcuts(
                bindings: <ShortcutActivator, VoidCallback>{
                  const SingleActivator(LogicalKeyboardKey.equal): () =>
                      _zoomBy(1.2),
                  const SingleActivator(LogicalKeyboardKey.numpadAdd): () =>
                      _zoomBy(1.2),
                  const SingleActivator(LogicalKeyboardKey.minus): () =>
                      _zoomBy(1 / 1.2),
                  const SingleActivator(LogicalKeyboardKey.numpadSubtract):
                      () => _zoomBy(1 / 1.2),
                  const SingleActivator(LogicalKeyboardKey.digit0): () =>
                      _fitTreeToViewport(),
                },
                child: Focus(
                  autofocus: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onDoubleTap: _fitTreeToViewport,
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      constrained: false,
                      clipBehavior: Clip.none,
                      boundaryMargin: EdgeInsets.all(interactionBoundary),
                      panAxis: PanAxis.free,
                      panEnabled: _draggingPersonId == null,
                      scaleEnabled: true,
                      trackpadScrollCausesScale: true,
                      minScale: 0.08,
                      maxScale: 3.5,
                      child: SizedBox(
                        width: stackWidth,
                        height: stackHeight,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            if (widget.showGenerationGuides)
                              ..._buildGenerationGuideWidgets(
                                stackWidth: stackWidth,
                              ),
                            CustomPaint(
                              size: Size(stackWidth, stackHeight),
                              painter: FamilyTreePainter(
                                nodePositions,
                                connections,
                                graphSnapshot: widget.graphSnapshot,
                                relations: widget.relations,
                              ),
                            ),
                            ..._buildPersonWidgets(),
                            if (widget.isEditMode)
                              _buildInlineEditPanel(
                                stackWidth: stackWidth,
                                stackHeight: stackHeight,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                child: _buildViewportStatusBar(),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: _buildViewportControlDock(),
              ),
            ],
          );
        },
      ),
    );
  }

  void _selectEditPerson(FamilyPerson person) {
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedEditPersonId = person.id;
    });
    widget.onEditPersonSelected?.call(person);
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
    setState(() {
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

    setState(() {
      nodePositions = updatedPositions;
      treeSize = _calculateTreeSize(updatedPositions);
    });
  }

  void _handleNodeDragEnd() {
    if (_draggingPersonId == null) {
      return;
    }

    final updatedPositions = Map<String, Offset>.from(nodePositions);
    setState(() {
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

  List<Widget> _buildGenerationGuideWidgets({
    required double stackWidth,
  }) {
    if (nodePositions.isEmpty) {
      return const <Widget>[];
    }

    final levels = nodePositions.values
        .map((offset) => offset.dy)
        .toSet()
        .toList()
      ..sort();
    final peopleById = {
      for (final entry in widget.peopleData)
        (entry['person'] as FamilyPerson).id: entry['person'] as FamilyPerson,
    };
    final contentLeft = nodePositions.values
        .map((offset) => offset.dx - InteractiveFamilyTree.nodeWidth / 2)
        .reduce(min);
    final labelLeft = max(14.0, contentLeft - 118);
    final dividerLeft = min(labelLeft + 44, stackWidth - 56);
    final dividerWidth = max(0.0, stackWidth - dividerLeft - 32);
    final guides = <Widget>[];

    for (var index = 0; index < levels.length; index++) {
      final levelY = levels[index];
      final labelTop = max(
        8.0,
        levelY - InteractiveFamilyTree.nodeHeight / 2 - 26,
      );
      guides.add(
        Positioned(
          left: labelLeft,
          top: labelTop,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: _GenerationGuideBadge(
                title: _generationLabel(index, levels.length),
                subtitle: _generationCohortLabel(
                  _peopleForGenerationLevel(
                    levelY: levelY,
                    peopleById: peopleById,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      if (index < levels.length - 1) {
        final nextLevelY = levels[index + 1];
        final dividerY = (levelY + nextLevelY) / 2;
        guides.add(
          Positioned(
            left: dividerLeft,
            top: dividerY,
            width: dividerWidth,
            child: IgnorePointer(
              child: Container(
                height: 1,
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.28),
              ),
            ),
          ),
        );
      }
    }

    return guides;
  }

  String _generationLabel(int index, int totalLevels) {
    if (totalLevels == 1) {
      return 'Центр дерева';
    }
    if (index == 0) {
      return 'Старшее поколение';
    }
    if (index == totalLevels - 1) {
      return 'Младшее поколение';
    }
    return 'Поколение ${index + 1}';
  }

  List<FamilyPerson> _peopleForGenerationLevel({
    required double levelY,
    required Map<String, FamilyPerson> peopleById,
  }) {
    return nodePositions.entries
        .where((entry) => (entry.value.dy - levelY).abs() < 0.1)
        .map((entry) => peopleById[entry.key])
        .whereType<FamilyPerson>()
        .toList(growable: false);
  }

  String? _generationCohortLabel(List<FamilyPerson> people) {
    final cohortLabels = people
        .map((person) => person.birthDate?.year)
        .whereType<int>()
        .map(_cohortLabelForBirthYear)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort(_compareCohortLabels);

    if (cohortLabels.isEmpty) {
      return null;
    }
    if (cohortLabels.length <= 2) {
      return cohortLabels.join(' / ');
    }
    return 'Смешанные поколения';
  }

  String? _cohortLabelForBirthYear(int year) {
    if (year <= 1927) {
      return 'Величайшее';
    }
    if (year <= 1945) {
      return 'Молчаливое';
    }
    if (year <= 1964) {
      return 'Бумеры';
    }
    if (year <= 1980) {
      return 'Поколение X';
    }
    if (year <= 1996) {
      return 'Миллениалы';
    }
    if (year <= 2012) {
      return 'Зумеры';
    }
    if (year <= 2028) {
      return 'Альфа';
    }
    return 'Бета';
  }

  int _compareCohortLabels(String left, String right) {
    const order = <String, int>{
      'Величайшее': 0,
      'Молчаливое': 1,
      'Бумеры': 2,
      'Поколение X': 3,
      'Миллениалы': 4,
      'Зумеры': 5,
      'Альфа': 6,
      'Бета': 7,
    };
    return (order[left] ?? 999).compareTo(order[right] ?? 999);
  }

  bool _supportsHoverNodeActions() {
    if (RendererBinding.instance.mouseTracker.mouseIsConnected) {
      return true;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  Widget _buildInlineEditPanel({
    required double stackWidth,
    required double stackHeight,
  }) {
    final selectedId = _selectedEditPersonId;
    if (selectedId == null) {
      return const SizedBox.shrink();
    }

    final position = nodePositions[selectedId];
    if (position == null) {
      return const SizedBox.shrink();
    }

    final person = widget.peopleData
        .map((entry) => entry['person'])
        .whereType<FamilyPerson>()
        .firstWhere(
          (candidate) => candidate.id == selectedId,
          orElse: () => FamilyPerson.empty,
        );
    if (person == FamilyPerson.empty) {
      return const SizedBox.shrink();
    }

    const panelWidth = 310.0;
    const panelHeight = 272.0;
    final preferredRight =
        position.dx + InteractiveFamilyTree.nodeWidth / 2 + 18;
    final preferredLeft =
        position.dx - InteractiveFamilyTree.nodeWidth / 2 - panelWidth - 18;
    final canPlaceRight = preferredRight + panelWidth <= stackWidth - 16;
    final canPlaceLeft = preferredLeft >= 16;

    late final double left;
    late final double top;
    if (canPlaceRight) {
      left = preferredRight;
      top = max(
        16.0,
        min(position.dy - panelHeight / 2, stackHeight - panelHeight - 16),
      );
    } else if (canPlaceLeft) {
      left = preferredLeft;
      top = max(
        16.0,
        min(position.dy - panelHeight / 2, stackHeight - panelHeight - 16),
      );
    } else {
      left = max(
        16.0,
        min(
          position.dx - panelWidth / 2,
          stackWidth - panelWidth - 16,
        ),
      );
      top = min(
        position.dy + InteractiveFamilyTree.nodeHeight / 2 + 14,
        stackHeight - panelHeight - 16,
      );
    }

    return Positioned(
      left: left,
      top: top,
      width: panelWidth,
      child: Material(
        elevation: 8,
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border:
                Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      person.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _selectedEditPersonId = null;
                      });
                    },
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close),
                    tooltip: 'Скрыть быстрые действия',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildInspectorStatusChip(
                    icon: Icons.photo_library_outlined,
                    label: person.photoGallery.isEmpty
                        ? 'Без фото'
                        : '${person.photoGallery.length} фото',
                  ),
                  _buildInspectorStatusChip(
                    icon: person.primaryPhotoUrl != null
                        ? Icons.star_outline
                        : Icons.image_not_supported_outlined,
                    label: person.primaryPhotoUrl != null
                        ? 'Основное фото есть'
                        : 'Основное фото не выбрано',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildInlineActionButton(
                    icon: Icons.north_outlined,
                    label: 'Родитель',
                    onTap: () => widget.onAddRelativeTapWithType(
                      person,
                      RelationType.parent,
                    ),
                  ),
                  _buildInlineActionButton(
                    icon: Icons.favorite_border,
                    label: 'Супруг',
                    onTap: () => widget.onAddRelativeTapWithType(
                      person,
                      RelationType.spouse,
                    ),
                  ),
                  _buildInlineActionButton(
                    icon: Icons.south_outlined,
                    label: 'Ребёнок',
                    onTap: () => widget.onAddRelativeTapWithType(
                      person,
                      RelationType.child,
                    ),
                  ),
                  _buildInlineActionButton(
                    icon: Icons.people_outline,
                    label: 'Сиблинг',
                    onTap: () => widget.onAddRelativeTapWithType(
                      person,
                      RelationType.sibling,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildInspectorQuickActionChip(
                    icon: Icons.open_in_new,
                    label: 'Карточка',
                    semanticsLabel: 'tree-inspector-open-card',
                    onTap: () => widget.onPersonTap(person),
                  ),
                  _buildInspectorQuickActionChip(
                    icon: Icons.photo_library_outlined,
                    label: person.photoGallery.isEmpty
                        ? 'Фото'
                        : 'Фото (${person.photoGallery.length})',
                    semanticsLabel: 'tree-inspector-open-gallery',
                    onTap: person.photoGallery.isEmpty
                        ? null
                        : () => _showPersonGalleryDialog(context, person),
                  ),
                  _buildInspectorQuickActionChip(
                    icon: Icons.history_outlined,
                    label: 'История',
                    semanticsLabel: 'tree-inspector-open-history',
                    onTap: widget.onOpenPersonHistory == null
                        ? null
                        : () => widget.onOpenPersonHistory!(person),
                  ),
                  _buildInspectorQuickActionChip(
                    icon: Icons.more_horiz,
                    label: 'Ещё',
                    semanticsLabel: 'tree-inspector-more-actions',
                    onTap: () => _showEditActionsSheet(context, person),
                  ),
                  if (!widget.currentUserIsInTree)
                    _buildInspectorQuickActionChip(
                      icon: Icons.person_add_alt_1,
                      label: 'Вписать себя',
                      semanticsLabel: 'tree-inspector-add-self',
                      onTap: () =>
                          _showAddSelfRelationTypeDialog(context, person),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInlineActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ActionChip(
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      avatar: Icon(
        icon,
        size: 16,
        color: theme.colorScheme.primary,
      ),
      label: Text(label),
      side: BorderSide(color: theme.colorScheme.outlineVariant),
      backgroundColor:
          theme.colorScheme.secondaryContainer.withValues(alpha: 0.55),
      padding: const EdgeInsets.symmetric(horizontal: 6),
    );
  }

  Widget _buildInspectorQuickActionChip({
    required IconData icon,
    required String label,
    String? semanticsLabel,
    required VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return Semantics(
      label: semanticsLabel,
      button: true,
      enabled: onTap != null,
      child: ActionChip(
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        avatar: Icon(icon, size: 16),
        label: Text(label),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        backgroundColor:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.82),
        padding: const EdgeInsets.symmetric(horizontal: 6),
      ),
    );
  }

  Widget _buildInspectorStatusChip({
    required IconData icon,
    required String label,
  }) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16),
      label: Text(label),
    );
  }

  void _showPersonGalleryDialog(BuildContext context, FamilyPerson person) {
    final gallery = person.photoGallery;
    if (gallery.isEmpty) {
      return;
    }

    final pageController = PageController();
    var currentIndex = 0;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final media = gallery[currentIndex];
            final caption = media['caption']?.toString();

            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              backgroundColor: Colors.black,
              child: SizedBox(
                width: 520,
                height: 520,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              media['isPrimary'] == true
                                  ? 'Основное фото'
                                  : 'Фото родственника',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: pageController,
                        itemCount: gallery.length,
                        onPageChanged: (index) {
                          setDialogState(() {
                            currentIndex = index;
                          });
                        },
                        itemBuilder: (context, index) {
                          final itemUrl =
                              gallery[index]['url']?.toString() ?? '';
                          return InteractiveViewer(
                            child: itemUrl.isEmpty
                                ? const Center(
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      color: Colors.white,
                                      size: 40,
                                    ),
                                  )
                                : Image.network(
                                    itemUrl,
                                    fit: BoxFit.contain,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Center(
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: Colors.white,
                                        size: 40,
                                      ),
                                    ),
                                  ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        children: [
                          Text(
                            '${currentIndex + 1} из ${gallery.length}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          if (caption != null && caption.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              caption,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<TreeGraphWarning> _sortedGraphWarnings(
    Iterable<TreeGraphWarning> warnings,
  ) {
    final items = warnings.toList();
    items.sort((left, right) {
      final severityComparison = _graphWarningPriority(right.severity)
          .compareTo(_graphWarningPriority(left.severity));
      if (severityComparison != 0) {
        return severityComparison;
      }
      return left.message.compareTo(right.message);
    });
    return items;
  }

  int _graphWarningPriority(String? severity) {
    switch ((severity ?? '').trim().toLowerCase()) {
      case 'error':
        return 3;
      case 'warning':
        return 2;
      case 'info':
        return 1;
      default:
        return 0;
    }
  }

  String _graphWarningTitle(TreeGraphWarning warning) {
    switch (warning.code) {
      case 'multiple_primary_parent_sets':
        return 'Несколько основных родителей';
      case 'auto_repaired_parent_link':
        return 'Связь достроена автоматически';
      case 'conflicting_direct_links':
        return 'Конфликт прямых связей';
      default:
        return 'Нужна проверка дерева';
    }
  }

  Color _graphWarningAccent(TreeGraphWarning warning) {
    final colorScheme = Theme.of(context).colorScheme;
    switch ((warning.severity).trim().toLowerCase()) {
      case 'error':
        return colorScheme.error;
      case 'info':
        return colorScheme.primary;
      default:
        return colorScheme.tertiary;
    }
  }

  IconData _graphWarningIcon(TreeGraphWarning warning) {
    switch ((warning.severity).trim().toLowerCase()) {
      case 'error':
        return Icons.error_outline_rounded;
      case 'info':
        return Icons.info_outline_rounded;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  Widget _buildGraphWarningCard(
    TreeGraphWarning warning, {
    bool compact = false,
  }) {
    final accent = _graphWarningAccent(warning);
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(compact ? 14 : 16),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _graphWarningIcon(warning),
            size: compact ? 18 : 20,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _graphWarningTitle(warning),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  warning.message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.3,
                        color: colorScheme.onSurface,
                      ),
                ),
                if (warning.hint != null &&
                    warning.hint!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    warning.hint!.trim(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          height: 1.3,
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _hasAdditionalParentSets(String personId) {
    final snapshot = widget.graphSnapshot;
    if (snapshot == null) {
      return false;
    }
    return snapshot.parentFamilyUnitsForChild(personId).any(
          (unit) => unit.isPrimaryParentSet == false,
        );
  }

  void _showPersonInsightSheet(
    BuildContext context,
    FamilyPerson person, {
    required List<TreeGraphWarning> warnings,
    TreeGraphViewerDescriptor? viewerDescriptor,
  }) {
    final relationPathEnabled = widget.onShowRelationPath != null;
    final otherParentsEnabled = widget.onShowOtherParents != null &&
        _hasAdditionalParentSets(person.id);
    final fixRelationsEnabled = widget.onFixPersonRelations != null;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.86,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    person.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    warnings.isEmpty
                        ? 'Здесь собраны быстрые инструменты по этой ветке.'
                        : 'Проверьте предупреждения и при необходимости откройте нужный инструмент.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (viewerDescriptor?.primaryRelationLabel
                              ?.trim()
                              .isNotEmpty ==
                          true)
                        _buildInspectorStatusChip(
                          icon: viewerDescriptor!.isBlood
                              ? Icons.family_restroom
                              : Icons.handshake_outlined,
                          label: viewerDescriptor.primaryRelationLabel!.trim(),
                        ),
                      _buildInspectorStatusChip(
                        icon: warnings.isEmpty
                            ? Icons.task_alt_outlined
                            : Icons.warning_amber_rounded,
                        label: warnings.isEmpty
                            ? 'Без конфликтов'
                            : warnings.length == 1
                                ? '1 предупреждение'
                                : '${warnings.length} предупреждения',
                      ),
                    ],
                  ),
                  if (warnings.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      'Предупреждения',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    ...warnings.map(
                      (warning) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildGraphWarningCard(warning, compact: true),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Быстрые действия',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  _buildEditActionTile(
                    sheetContext: sheetContext,
                    icon: Icons.person_add_alt_1_outlined,
                    title: 'Добавить родственника',
                    semanticsLabel: 'tree-sheet-open-add-relative',
                    subtitle: 'Сразу привязать нового человека к этой карточке',
                    onTap: () => _showQuickAddRelativeSheet(context, person),
                  ),
                  if (relationPathEnabled)
                    _buildEditActionTile(
                      sheetContext: sheetContext,
                      icon: Icons.route_outlined,
                      title: 'Путь родства',
                      semanticsLabel: 'tree-sheet-open-relation-path',
                      subtitle: 'Показать цепочку людей между вами',
                      onTap: () => widget.onShowRelationPath!(person),
                    ),
                  if (otherParentsEnabled)
                    _buildEditActionTile(
                      sheetContext: sheetContext,
                      icon: Icons.account_tree_outlined,
                      title: 'Другие родители',
                      semanticsLabel: 'tree-sheet-open-other-parents',
                      subtitle: 'Проверить альтернативные наборы родителей',
                      onTap: () => widget.onShowOtherParents!(person),
                    ),
                  if (fixRelationsEnabled)
                    _buildEditActionTile(
                      sheetContext: sheetContext,
                      icon: Icons.hub_outlined,
                      title: 'Исправить связи',
                      semanticsLabel: 'tree-sheet-open-fix-relations',
                      subtitle: 'Открыть редактор прямых связей',
                      onTap: () => widget.onFixPersonRelations!(person),
                    ),
                  _buildEditActionTile(
                    sheetContext: sheetContext,
                    icon: Icons.open_in_new,
                    title: 'Открыть карточку',
                    semanticsLabel: 'tree-sheet-open-card',
                    subtitle: 'Полная карточка, заметки и история',
                    onTap: () => widget.onPersonTap(person),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showQuickAddRelativeSheet(BuildContext context, FamilyPerson person) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Добавить к карточке',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Новый человек будет сразу привязан к ${person.name}.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                ),
                const SizedBox(height: 12),
                _buildEditActionTile(
                  sheetContext: sheetContext,
                  icon: Icons.arrow_upward,
                  title: 'Добавить родителя',
                  semanticsLabel: 'tree-sheet-add-parent',
                  onTap: () => widget.onAddRelativeTapWithType(
                      person, RelationType.parent),
                ),
                _buildEditActionTile(
                  sheetContext: sheetContext,
                  icon: Icons.favorite_border,
                  title: 'Добавить супруга или партнёра',
                  semanticsLabel: 'tree-sheet-add-partner',
                  onTap: () => widget.onAddRelativeTapWithType(
                      person, RelationType.spouse),
                ),
                _buildEditActionTile(
                  sheetContext: sheetContext,
                  icon: Icons.arrow_downward,
                  title: 'Добавить ребёнка',
                  semanticsLabel: 'tree-sheet-add-child',
                  onTap: () => widget.onAddRelativeTapWithType(
                      person, RelationType.child),
                ),
                _buildEditActionTile(
                  sheetContext: sheetContext,
                  icon: Icons.people_outline,
                  title: 'Добавить брата или сестру',
                  semanticsLabel: 'tree-sheet-add-sibling',
                  onTap: () => widget.onAddRelativeTapWithType(
                    person,
                    RelationType.sibling,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildPersonWidgets() {
    final nodeDataByPersonId = <String, Map<String, dynamic>>{
      for (final data in widget.peopleData)
        (data['person'] as FamilyPerson).id: data,
    };
    final warningCache = <String, List<TreeGraphWarning>>{};

    return nodePositions.entries.map((entry) {
      final personId = entry.key;
      final position = entry.value;
      final nodeData = nodeDataByPersonId[personId];

      if (nodeData == null) return const SizedBox.shrink();

      final topLeftX = position.dx - InteractiveFamilyTree.nodeWidth / 2;
      final topLeftY = position.dy - InteractiveFamilyTree.nodeHeight / 2;
      final personWarnings = warningCache.putIfAbsent(
        personId,
        () => _sortedGraphWarnings(
          widget.graphSnapshot?.warningsForPerson(personId) ??
              const <TreeGraphWarning>[],
        ),
      );

      return Positioned(
        left: topLeftX,
        top: topLeftY,
        width: InteractiveFamilyTree.nodeWidth,
        child: _buildPersonNode(
          nodeData,
          personWarnings: personWarnings,
        ),
      );
    }).toList();
  }

  Widget _buildPersonNode(
    Map<String, dynamic> nodeData, {
    required List<TreeGraphWarning> personWarnings,
  }) {
    final FamilyPerson person = nodeData['person'];
    final UserProfile? userProfile = nodeData['userProfile'];
    final TreeGraphViewerDescriptor? viewerDescriptor =
        nodeData['viewerDescriptor'] as TreeGraphViewerDescriptor?;

    final String displayName = userProfile != null
        ? '${userProfile.firstName} ${userProfile.lastName}'.trim()
        : person.name;
    final String? displayPhotoUrl = userProfile?.photoURL ?? person.photoUrl;
    final Gender displayGender = person.gender;
    final isCurrentUserNode =
        widget.currentUserId != null && person.userId == widget.currentUserId;
    final isSelectedInEditMode =
        widget.isEditMode && _selectedEditPersonId == person.id;
    final isDraggingNode = _draggingPersonId == person.id;
    final supportsHoverActions = _supportsHoverNodeActions();
    final isHoveredNode = !widget.isEditMode && _hoveredPersonId == person.id;
    final relationChipLabel = viewerDescriptor?.primaryRelationLabel == null ||
            viewerDescriptor!.primaryRelationLabel!.trim().isEmpty ||
            isCurrentUserNode
        ? null
        : viewerDescriptor.primaryRelationLabel!.trim() +
            (viewerDescriptor.alternatePathCount > 0
                ? ' +${viewerDescriptor.alternatePathCount}'
                : '');
    final prefersTouchQuickAdd = !supportsHoverActions && !widget.isEditMode;
    final canUseLongPressQuickAdd = prefersTouchQuickAdd;

    final cardContent = FamilyTreeNodeCard(
      key: ValueKey<String>('tree-node-${person.id}'),
      displayName: displayName,
      lifeDates: _getLifeDates(person),
      displayGender: displayGender,
      displayPhotoUrl: displayPhotoUrl,
      relationChipLabel: relationChipLabel,
      isBloodRelation: viewerDescriptor?.isBlood == true,
      isCurrentUserNode: isCurrentUserNode,
      isSelectedInEditMode: isSelectedInEditMode,
      isDraggingNode: isDraggingNode,
      isHovered: isHoveredNode,
    );

    return MouseRegion(
      onEnter: widget.isEditMode
          ? null
          : (_) => setState(() => _hoveredPersonId = person.id),
      onExit: widget.isEditMode
          ? null
          : (_) {
              if (_hoveredPersonId == person.id) {
                setState(() => _hoveredPersonId = null);
              }
            },
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPressStart: widget.isEditMode
                ? (_) {
                    HapticFeedback.mediumImpact();
                    _handleNodeDragStart(person);
                  }
                : null,
            onLongPressMoveUpdate: widget.isEditMode
                ? (details) => _handleNodeDragUpdate(
                      person,
                      details.offsetFromOrigin,
                    )
                : null,
            onLongPressEnd:
                widget.isEditMode ? (_) => _handleNodeDragEnd() : null,
            onTap: () {
              if (widget.isEditMode) {
                _selectEditPerson(person);
                return;
              }
              widget.onPersonTap(person);
            },
            onLongPress: widget.isEditMode || !canUseLongPressQuickAdd
                ? null
                : () => _showQuickAddRelativeSheet(context, person),
            child: cardContent,
          ),
          if (!widget.isEditMode && isHoveredNode)
            Positioned(
              top: 8,
              right: 8,
              child: Tooltip(
                message: 'Добавить родственника',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key:
                        ValueKey<String>('tree-node-add-relative-${person.id}'),
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => _showQuickAddRelativeSheet(context, person),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOut,
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surface
                            .withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context)
                                .colorScheme
                                .shadow
                                .withValues(alpha: 0.12),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.add,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (widget.isEditMode)
            Positioned(
              top: -8,
              right: -8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelectedInEditMode
                      ? Theme.of(context).colorScheme.secondary
                      : Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: (isSelectedInEditMode
                              ? Theme.of(context).colorScheme.secondary
                              : Theme.of(context).colorScheme.primary)
                          .withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isDraggingNode
                          ? Icons.open_with
                          : isSelectedInEditMode
                              ? Icons.check
                              : Icons.touch_app_outlined,
                      size: 12,
                      color: isDraggingNode
                          ? Theme.of(context).colorScheme.onPrimary
                          : isSelectedInEditMode
                              ? Theme.of(context).colorScheme.onSecondary
                              : Theme.of(context).colorScheme.onPrimary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isDraggingNode
                          ? 'Тяните'
                          : isSelectedInEditMode
                              ? 'Выбрано'
                              : 'Зажмите',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: isDraggingNode
                            ? Theme.of(context).colorScheme.onPrimary
                            : isSelectedInEditMode
                                ? Theme.of(context).colorScheme.onSecondary
                                : Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!widget.isEditMode && personWarnings.isNotEmpty)
            Positioned(
              top: -10,
              right: -10,
              child: Tooltip(
                message: personWarnings.length == 1
                    ? 'Есть предупреждение'
                    : 'Есть предупреждения',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: ValueKey<String>('tree-warning-badge-${person.id}'),
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => _showPersonInsightSheet(
                      context,
                      person,
                      warnings: personWarnings,
                      viewerDescriptor: viewerDescriptor,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: _graphWarningAccent(personWarnings.first),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: _graphWarningAccent(personWarnings.first)
                                .withValues(alpha: 0.22),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _graphWarningIcon(personWarnings.first),
                            size: 14,
                            color: Colors.white,
                          ),
                          if (personWarnings.length > 1) ...[
                            const SizedBox(width: 4),
                            Text(
                              '${personWarnings.length}',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showEditActionsSheet(BuildContext context, FamilyPerson person) {
    final hasGallery = person.photoGallery.isNotEmpty;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.8,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Выберите действие для этого человека.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildInspectorStatusChip(
                        icon: Icons.photo_library_outlined,
                        label: hasGallery
                            ? '${person.photoGallery.length} фото'
                            : 'Без фото',
                      ),
                      _buildInspectorStatusChip(
                        icon: person.primaryPhotoUrl != null
                            ? Icons.star_outline
                            : Icons.image_not_supported_outlined,
                        label: person.primaryPhotoUrl != null
                            ? 'Основное фото есть'
                            : 'Основное фото не выбрано',
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Быстрые переходы',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  _buildEditActionTile(
                    sheetContext: sheetContext,
                    icon: Icons.open_in_new,
                    title: 'Открыть профиль',
                    semanticsLabel: 'tree-sheet-open-card',
                    subtitle: 'Полная карточка, связи и заметки',
                    onTap: () => widget.onPersonTap(person),
                  ),
                  _buildEditActionTile(
                    sheetContext: sheetContext,
                    icon: Icons.photo_library_outlined,
                    title: hasGallery ? 'Открыть фото' : 'Перейти к фото',
                    semanticsLabel: 'tree-sheet-open-gallery',
                    subtitle: hasGallery
                        ? 'В галерее ${person.photoGallery.length} фото'
                        : 'Откройте карточку и добавьте фото',
                    onTap: hasGallery
                        ? () => _showPersonGalleryDialog(context, person)
                        : () => widget.onPersonTap(person),
                  ),
                  if (widget.onOpenPersonHistory != null)
                    _buildEditActionTile(
                      sheetContext: sheetContext,
                      icon: Icons.history_outlined,
                      title: 'История изменений',
                      semanticsLabel: 'tree-sheet-open-history',
                      subtitle: 'Журнал правок этой карточки',
                      onTap: () => widget.onOpenPersonHistory!(person),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'Добавить связь',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  _buildEditActionTile(
                    sheetContext: sheetContext,
                    icon: Icons.arrow_upward,
                    title: 'Добавить родителя',
                    onTap: () => widget.onAddRelativeTapWithType(
                        person, RelationType.parent),
                  ),
                  _buildEditActionTile(
                    sheetContext: sheetContext,
                    icon: Icons.favorite_border,
                    title: 'Добавить супруга или партнёра',
                    onTap: () => widget.onAddRelativeTapWithType(
                        person, RelationType.spouse),
                  ),
                  _buildEditActionTile(
                    sheetContext: sheetContext,
                    icon: Icons.arrow_downward,
                    title: 'Добавить ребёнка',
                    onTap: () => widget.onAddRelativeTapWithType(
                        person, RelationType.child),
                  ),
                  _buildEditActionTile(
                    sheetContext: sheetContext,
                    icon: Icons.people_outline,
                    title: 'Добавить брата или сестру',
                    onTap: () => widget.onAddRelativeTapWithType(
                      person,
                      RelationType.sibling,
                    ),
                  ),
                  if (!widget.currentUserIsInTree)
                    _buildEditActionTile(
                      sheetContext: sheetContext,
                      icon: Icons.person_add_alt_1,
                      title: 'Добавить себя в это дерево',
                      onTap: () =>
                          _showAddSelfRelationTypeDialog(context, person),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditActionTile({
    required BuildContext sheetContext,
    required IconData icon,
    required String title,
    String? semanticsLabel,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return Semantics(
      label: semanticsLabel,
      button: true,
      enabled: onTap != null,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        enabled: onTap != null,
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        onTap: onTap == null
            ? null
            : () {
                Navigator.of(sheetContext).pop();
                onTap();
              },
      ),
    );
  }

  void _showAddSelfRelationTypeDialog(
    BuildContext context,
    FamilyPerson targetPerson,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Добавить себя как...'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: RelationType.values
                  .where(
                (type) =>
                    /* type != RelationType.unknown && */ type !=
                        RelationType.other &&
                    // <<< Дополнительный фильтр: Убираем слишком далекие/сложные связи для этого диалога >>>
                    ![
                      RelationType.greatGrandparent,
                      RelationType.greatGrandchild,
                      RelationType.cousin,
                      RelationType.parentInLaw,
                      RelationType.childInLaw,
                      RelationType.siblingInLaw,
                      RelationType.stepparent,
                      RelationType.stepchild,
                      RelationType.inlaw,
                      RelationType.ex_spouse,
                      RelationType.ex_partner,
                      RelationType.friend,
                      RelationType.colleague,
                    ].contains(type),
              ) // Фильтруем ненужные и сложные
                  .map((type) {
                // Определяем текст кнопки на основе типа связи
                String buttonText =
                    'Как ${FamilyRelation.getGenericRelationTypeStringRu(type).toLowerCase()}';
                IconData iconData = Icons.person; // Иконка по умолчанию
                switch (type) {
                  case RelationType.parent:
                    iconData = Icons.arrow_upward;
                    break;
                  case RelationType.child:
                    iconData = Icons.arrow_downward;
                    break;
                  case RelationType.spouse:
                    iconData = Icons.favorite;
                    break;
                  case RelationType.sibling:
                    iconData = Icons.people;
                    break;
                  default:
                    break;
                }

                return ListTile(
                  leading: Icon(iconData),
                  title: Text(buttonText),
                  onTap: () {
                    Navigator.of(dialogContext).pop(); // Закрываем диалог
                    // <<< ИСПРАВЛЕНИЕ: Вызываем коллбэк с ЗЕРКАЛЬНЫМ типом связи >>>
                    // Передаем отношение ОТ targetPerson К новому пользователю
                    widget.onAddSelfTapWithType(
                      targetPerson,
                      FamilyRelation.getMirrorRelation(type),
                    );
                  },
                );
              }).toList(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Отмена'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }

  String _getLifeDates(FamilyPerson person) {
    final birthYear = person.birthDate?.year;
    final deathYear = person.deathDate?.year;

    if (birthYear == null && person.isAlive) {
      return 'Годы не указаны';
    }
    if (birthYear == null && deathYear != null) {
      return 'ум. $deathYear';
    }
    if (birthYear != null && person.isAlive) {
      return '$birthYear - н.в.';
    }
    if (birthYear != null && deathYear == null) {
      return '$birthYear - ?';
    }
    return '${birthYear ?? '?'} - ${deathYear ?? '?'}';
  }

  Widget _buildViewportStatusBar() {
    final zoomPercent = (_currentScale * 100).round();
    final chips = <Widget>[
      _buildOverlayChip(
        icon: widget.showGenerationGuides
            ? Icons.account_tree_outlined
            : Icons.diversity_3_outlined,
        label: widget.showGenerationGuides ? 'Семья' : 'Друзья',
        highlighted: true,
      ),
      _buildOverlayChip(
        icon: Icons.people_alt_outlined,
        label: '${widget.peopleData.length}',
      ),
      _buildOverlayChip(
        icon: Icons.hub_outlined,
        label: '${widget.relations.length}',
      ),
      _buildOverlayChip(
        icon: Icons.zoom_in_map_outlined,
        label: '$zoomPercent%',
      ),
    ];

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: min((_viewportSize?.width ?? 640) - 24, 640),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color:
                Theme.of(context).colorScheme.surface.withValues(alpha: 0.84),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.88),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                chips[i],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildViewportControlDock() {
    final currentUserNodeId = _findCurrentUserNodeId();
    final branchRootPersonId = widget.branchRootPersonId;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.88),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDockButton(
            icon: Icons.add,
            tooltip: 'Увеличить',
            onPressed: () => _zoomBy(1.2),
          ),
          const SizedBox(height: 6),
          _buildDockButton(
            icon: Icons.remove,
            tooltip: 'Уменьшить',
            onPressed: () => _zoomBy(1 / 1.2),
          ),
          const SizedBox(height: 6),
          _buildDockButton(
            icon: Icons.fit_screen_outlined,
            tooltip: 'Вписать дерево',
            onPressed: _fitTreeToViewport,
          ),
          if (currentUserNodeId != null) ...[
            const SizedBox(height: 6),
            _buildDockButton(
              icon: Icons.my_location_outlined,
              tooltip: 'Ко мне',
              onPressed: () => _focusOnPerson(currentUserNodeId),
            ),
          ],
          if (branchRootPersonId != null && branchRootPersonId.isNotEmpty) ...[
            const SizedBox(height: 6),
            _buildDockButton(
              icon: Icons.alt_route_outlined,
              tooltip: widget.showGenerationGuides ? 'К ветке' : 'К кругу',
              onPressed: () => _focusOnPerson(branchRootPersonId),
            ),
            if (widget.onBranchFocusCleared != null) ...[
              const SizedBox(height: 6),
              _buildDockButton(
                icon: Icons.clear_all,
                tooltip: widget.showGenerationGuides
                    ? 'Сбросить ветку'
                    : 'Сбросить круг',
                onPressed: widget.onBranchFocusCleared!,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildDockButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.96),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: colorScheme.primary),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayChip({
    required IconData icon,
    required String label,
    bool highlighted = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlighted ? colorScheme.primaryContainer : colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: highlighted ? colorScheme.primary : colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
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
      }
      _hasAppliedViewportFit = true;
    });
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
    final horizontalInset = viewport.width >= 1180 ? 18.0 : 28.0;
    final horizontalScale = (viewport.width - horizontalInset) / contentWidth;
    final verticalScale =
        (viewport.height - _viewportReservedTop - _viewportReservedBottom) /
            contentHeight;
    final targetScale = min(horizontalScale, verticalScale * 1.14);
    final safeScale = targetScale.clamp(0.2, _maxViewportFitScale(viewport));

    final translateX = (viewport.width - contentWidth * safeScale) / 2;
    final availableHeight =
        viewport.height - _viewportReservedTop - _viewportReservedBottom;
    final translateY = _viewportReservedTop +
        (availableHeight - contentHeight * safeScale) / 2;

    _transformationController.value = vector_math.Matrix4.identity()
      ..translateByDouble(translateX, translateY, 0, 1)
      ..scaleByDouble(safeScale, safeScale, 1, 1);
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
    final translateX = viewport.width / 2 - targetPosition.dx * focusScale;
    final usableCenterY = _viewportReservedTop +
        (viewport.height - _viewportReservedTop - _viewportReservedBottom) / 2;
    final translateY = usableCenterY - targetPosition.dy * focusScale;

    _transformationController.value = vector_math.Matrix4.identity()
      ..translateByDouble(translateX, translateY, 0, 1)
      ..scaleByDouble(focusScale, focusScale, 1, 1);
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

    if (peopleCount <= 6) {
      return 1.2;
    }
    if (peopleCount <= 12) {
      return 1.12;
    }
    return 1.08;
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

  void _zoomBy(double multiplier) {
    final viewport = _viewportSize;
    if (viewport == null || viewport.width <= 0 || viewport.height <= 0) {
      return;
    }

    final currentMatrix = _transformationController.value.clone();
    final currentScale = currentMatrix.getMaxScaleOnAxis();
    final targetScale = (currentScale * multiplier).clamp(0.08, 3.5);
    final appliedMultiplier = targetScale / currentScale;
    final viewportFocalPoint = Offset(
      viewport.width / 2,
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
} // <- Закрывающая скобка для класса _InteractiveFamilyTreeState

class _TreeLayoutComputation {
  const _TreeLayoutComputation({
    required this.nodePositions,
    required this.connections,
    required this.treeSize,
  });

  final Map<String, Offset> nodePositions;
  final List<FamilyConnection> connections;
  final Size treeSize;
}

class _SpouseGroup {
  const _SpouseGroup({required this.memberIds});

  final List<String> memberIds;
}

class _TreeLayoutEngine {
  _TreeLayoutEngine({
    required this.peopleData,
    required this.relations,
    this.graphSnapshot,
  });

  final List<Map<String, dynamic>> peopleData;
  final List<FamilyRelation> relations;
  final TreeGraphSnapshot? graphSnapshot;

  _TreeLayoutComputation compute() {
    final peopleById = <String, FamilyPerson>{
      for (final entry in peopleData)
        (entry['person'] as FamilyPerson).id: entry['person'] as FamilyPerson,
    };
    if (peopleById.isEmpty) {
      return const _TreeLayoutComputation(
        nodePositions: <String, Offset>{},
        connections: <FamilyConnection>[],
        treeSize: Size.zero,
      );
    }

    final parentToChildren = <String, Set<String>>{};
    final childToParents = <String, Set<String>>{};
    final spousesByPerson = <String, Set<String>>{};
    final siblingsByPerson = <String, Set<String>>{};
    final adjacency = <String, Set<String>>{
      for (final id in peopleById.keys) id: <String>{},
    };

    for (final relation in relations) {
      final parentId = _parentIdFromRelation(relation);
      final childId = _childIdFromRelation(relation);
      if (parentId != null && childId != null) {
        parentToChildren.putIfAbsent(parentId, () => <String>{}).add(childId);
        childToParents.putIfAbsent(childId, () => <String>{}).add(parentId);
        adjacency[parentId]!.add(childId);
        adjacency[childId]!.add(parentId);
      } else if (_isSpouseRelation(relation)) {
        spousesByPerson
            .putIfAbsent(relation.person1Id, () => <String>{})
            .add(relation.person2Id);
        spousesByPerson
            .putIfAbsent(relation.person2Id, () => <String>{})
            .add(relation.person1Id);
        adjacency[relation.person1Id]!.add(relation.person2Id);
        adjacency[relation.person2Id]!.add(relation.person1Id);
      } else if (_isSiblingRelation(relation)) {
        siblingsByPerson
            .putIfAbsent(relation.person1Id, () => <String>{})
            .add(relation.person2Id);
        siblingsByPerson
            .putIfAbsent(relation.person2Id, () => <String>{})
            .add(relation.person1Id);
        adjacency[relation.person1Id]!.add(relation.person2Id);
        adjacency[relation.person2Id]!.add(relation.person1Id);
      }
    }

    final components = _buildComponents(adjacency, peopleById);
    final nodePositions = <String, Offset>{};
    var offsetX = InteractiveFamilyTree.contentInsetHorizontal +
        InteractiveFamilyTree.nodeWidth / 2 +
        InteractiveFamilyTree.siblingSeparation;
    var maxBottomY = 0.0;

    for (final component in components) {
      final levels = _assignLevels(
        component: component,
        peopleById: peopleById,
        childToParents: childToParents,
        parentToChildren: parentToChildren,
        spousesByPerson: spousesByPerson,
        siblingsByPerson: siblingsByPerson,
      );
      final groupsByLevel = _buildGroupsByLevel(
        component: component,
        levels: levels,
        spousesByPerson: spousesByPerson,
        siblingsByPerson: siblingsByPerson,
        parentToChildren: parentToChildren,
        peopleById: peopleById,
      );

      final componentPositions = <String, Offset>{};
      final levelOrder = groupsByLevel.keys.toList()..sort();
      for (final level in levelOrder) {
        final groups = [...(groupsByLevel[level] ?? const <_SpouseGroup>[])]
          ..sort((left, right) {
            final leftDesired = _desiredCenterForGroup(
              group: left,
              positions: componentPositions,
              childToParents: childToParents,
              parentToChildren: parentToChildren,
              siblingsByPerson: siblingsByPerson,
            );
            final rightDesired = _desiredCenterForGroup(
              group: right,
              positions: componentPositions,
              childToParents: childToParents,
              parentToChildren: parentToChildren,
              siblingsByPerson: siblingsByPerson,
            );
            if (leftDesired != null && rightDesired != null) {
              final centerCompare = leftDesired.compareTo(rightDesired);
              if (centerCompare != 0) {
                return centerCompare;
              }
            } else if (leftDesired != null) {
              return -1;
            } else if (rightDesired != null) {
              return 1;
            }

            final leftWeight = _groupDescendantWeight(
              left.memberIds,
              parentToChildren,
            );
            final rightWeight = _groupDescendantWeight(
              right.memberIds,
              parentToChildren,
            );
            if (leftWeight != rightWeight) {
              return rightWeight.compareTo(leftWeight);
            }

            return _comparePersons(
              peopleById[left.memberIds.first]!,
              peopleById[right.memberIds.first]!,
            );
          });
        groupsByLevel[level] = groups;
        var currentLeft = offsetX;
        for (final group in groups) {
          final requestedCenter = _desiredCenterForGroup(
            group: group,
            positions: componentPositions,
            childToParents: childToParents,
            parentToChildren: parentToChildren,
            siblingsByPerson: siblingsByPerson,
          );
          final groupWidth = _groupWidth(group.memberIds.length);
          final requestedLeft = requestedCenter == null
              ? currentLeft
              : requestedCenter - groupWidth / 2;
          final left = max(currentLeft, requestedLeft);
          final y = InteractiveFamilyTree.contentInsetTop +
              InteractiveFamilyTree.nodeHeight / 2 +
              level *
                  (InteractiveFamilyTree.nodeHeight +
                      InteractiveFamilyTree.levelSeparation);
          for (var index = 0; index < group.memberIds.length; index++) {
            final personId = group.memberIds[index];
            final x = left +
                InteractiveFamilyTree.nodeWidth / 2 +
                index *
                    (InteractiveFamilyTree.nodeWidth +
                        InteractiveFamilyTree.spouseSeparation);
            componentPositions[personId] = Offset(x, y);
            maxBottomY = max(
              maxBottomY,
              y + InteractiveFamilyTree.nodeHeight / 2,
            );
          }
          currentLeft =
              left + groupWidth + InteractiveFamilyTree.siblingSeparation;
        }
      }

      _normalizeGroups(
        componentPositions,
        groupsByLevel,
        levels: levels,
        childToParents: childToParents,
        parentToChildren: parentToChildren,
        siblingsByPerson: siblingsByPerson,
        peopleById: peopleById,
        componentStartX: offsetX,
      );
      _centerParents(componentPositions, groupsByLevel, parentToChildren);
      _normalizeGroups(
        componentPositions,
        groupsByLevel,
        levels: levels,
        childToParents: childToParents,
        parentToChildren: parentToChildren,
        siblingsByPerson: siblingsByPerson,
        peopleById: peopleById,
        componentStartX: offsetX,
      );
      _anchorComponentToStart(
        componentPositions,
        componentStartX: offsetX,
      );
      nodePositions.addAll(componentPositions);

      var rightEdge = offsetX;
      for (final position in componentPositions.values) {
        rightEdge = max(
          rightEdge,
          position.dx + InteractiveFamilyTree.nodeWidth / 2,
        );
      }
      offsetX = rightEdge + InteractiveFamilyTree.siblingSeparation * 3;
    }

    final connections = _buildConnections(relations, nodePositions);
    final maxRight = nodePositions.values.fold<double>(
      InteractiveFamilyTree.nodeWidth,
      (value, position) =>
          max(value, position.dx + InteractiveFamilyTree.nodeWidth / 2),
    );

    return _TreeLayoutComputation(
      nodePositions: nodePositions,
      connections: connections,
      treeSize: Size(
        max(
          maxRight + InteractiveFamilyTree.contentInsetHorizontal,
          300,
        ),
        max(
          maxBottomY + InteractiveFamilyTree.contentInsetBottom,
          300,
        ),
      ),
    );
  }

  List<Set<String>> _buildComponents(
    Map<String, Set<String>> adjacency,
    Map<String, FamilyPerson> peopleById,
  ) {
    final components = <Set<String>>[];
    final visited = <String>{};
    final ids = peopleById.keys.toList()
      ..sort((a, b) => _comparePersons(peopleById[a]!, peopleById[b]!));
    for (final id in ids) {
      if (!visited.add(id)) {
        continue;
      }
      final component = <String>{id};
      final queue = <String>[id];
      while (queue.isNotEmpty) {
        final currentId = queue.removeAt(0);
        for (final neighbour in adjacency[currentId] ?? const <String>{}) {
          if (visited.add(neighbour)) {
            component.add(neighbour);
            queue.add(neighbour);
          }
        }
      }
      components.add(component);
    }
    return components;
  }

  Map<String, int> _assignLevels({
    required Set<String> component,
    required Map<String, FamilyPerson> peopleById,
    required Map<String, Set<String>> childToParents,
    required Map<String, Set<String>> parentToChildren,
    required Map<String, Set<String>> spousesByPerson,
    required Map<String, Set<String>> siblingsByPerson,
  }) {
    final levels = <String, int>{};
    final roots = component
        .where(
          (id) => (childToParents[id] ?? const <String>{})
              .where(component.contains)
              .isEmpty,
        )
        .toList()
      ..sort((a, b) => _comparePersons(peopleById[a]!, peopleById[b]!));
    final queue = <String>[...(roots.isNotEmpty ? roots : component)];

    while (queue.isNotEmpty) {
      final currentId = queue.removeAt(0);
      final currentLevel = levels[currentId] ?? 0;
      levels[currentId] = currentLevel;

      for (final spouseId in spousesByPerson[currentId] ?? const <String>{}) {
        if (!component.contains(spouseId)) {
          continue;
        }
        final existing = levels[spouseId];
        if (existing == null || existing != currentLevel) {
          levels[spouseId] = currentLevel;
          queue.add(spouseId);
        }
      }

      for (final childId in parentToChildren[currentId] ?? const <String>{}) {
        if (!component.contains(childId)) {
          continue;
        }
        final childLevel = currentLevel + 1;
        final existing = levels[childId];
        if (existing == null || childLevel > existing) {
          levels[childId] = childLevel;
          queue.add(childId);
        }
      }

      for (final siblingId in siblingsByPerson[currentId] ?? const <String>{}) {
        if (!component.contains(siblingId)) {
          continue;
        }
        final existing = levels[siblingId];
        if (existing == null || existing != currentLevel) {
          levels[siblingId] = currentLevel;
          queue.add(siblingId);
        }
      }
    }

    for (final id in component) {
      levels.putIfAbsent(id, () {
        final parentLevels = (childToParents[id] ?? const <String>{})
            .where(component.contains)
            .map((parentId) => levels[parentId])
            .whereType<int>()
            .toList();
        return parentLevels.isEmpty ? 0 : parentLevels.reduce(max) + 1;
      });
    }

    final snapshot = graphSnapshot;
    if (snapshot != null && snapshot.generationRows.isNotEmpty) {
      final snapshotLevels = <String, int>{};
      for (final row in snapshot.generationRows) {
        for (final personId in row.personIds) {
          if (component.contains(personId)) {
            snapshotLevels[personId] = row.row;
          }
        }
      }
      if (snapshotLevels.isNotEmpty) {
        final snapshotMinLevel = snapshotLevels.values.reduce(min);
        for (final entry in snapshotLevels.entries) {
          levels[entry.key] = entry.value - snapshotMinLevel;
        }

        final relevantUnits = snapshot.familyUnits.where((unit) {
          return unit.adultIds.any(component.contains) ||
              unit.childIds.any(component.contains);
        }).toList(growable: false);
        final maxIterations = component.length + relevantUnits.length + 4;
        var changed = true;
        var iteration = 0;
        while (changed && iteration < maxIterations) {
          changed = false;
          iteration += 1;

          for (final personId in component) {
            final spouseIds = (spousesByPerson[personId] ?? const <String>{})
                .where(component.contains)
                .toList(growable: false);
            if (spouseIds.isEmpty) {
              continue;
            }
            final targetLevel = [
              levels[personId] ?? 0,
              ...spouseIds.map((spouseId) => levels[spouseId] ?? 0),
            ].reduce(max);
            if ((levels[personId] ?? 0) != targetLevel) {
              levels[personId] = targetLevel;
              changed = true;
            }
            for (final spouseId in spouseIds) {
              if ((levels[spouseId] ?? 0) != targetLevel) {
                levels[spouseId] = targetLevel;
                changed = true;
              }
            }
          }

          for (final unit in relevantUnits) {
            final adultIds =
                unit.adultIds.where(component.contains).toList(growable: false);
            final childIds =
                unit.childIds.where(component.contains).toList(growable: false);
            if (adultIds.isEmpty && childIds.isEmpty) {
              continue;
            }

            int? desiredAdultLevel;
            if (childIds.isNotEmpty) {
              desiredAdultLevel = max(
                0,
                childIds.map((personId) => levels[personId] ?? 0).reduce(min) -
                    1,
              );
            } else if (adultIds.isNotEmpty) {
              desiredAdultLevel =
                  adultIds.map((personId) => levels[personId] ?? 0).reduce(max);
            }

            if (desiredAdultLevel != null) {
              for (final adultId in adultIds) {
                if ((levels[adultId] ?? 0) != desiredAdultLevel) {
                  levels[adultId] = desiredAdultLevel;
                  changed = true;
                }
              }
            }

            if (desiredAdultLevel != null && childIds.isNotEmpty) {
              final desiredChildLevel = desiredAdultLevel + 1;
              for (final childId in childIds) {
                if ((levels[childId] ?? 0) != desiredChildLevel) {
                  levels[childId] = desiredChildLevel;
                  changed = true;
                }
              }
            }
          }

          for (final personId in component) {
            final siblingIds = (siblingsByPerson[personId] ?? const <String>{})
                .where(component.contains)
                .toList(growable: false);
            if (siblingIds.isEmpty) {
              continue;
            }
            final targetLevel = [
              levels[personId] ?? 0,
              ...siblingIds.map((siblingId) => levels[siblingId] ?? 0),
            ].reduce(max);
            if ((levels[personId] ?? 0) != targetLevel) {
              levels[personId] = targetLevel;
              changed = true;
            }
            for (final siblingId in siblingIds) {
              if ((levels[siblingId] ?? 0) != targetLevel) {
                levels[siblingId] = targetLevel;
                changed = true;
              }
            }
          }
        }
      }
    }

    final minLevel = levels.values.reduce(min);
    if (minLevel != 0) {
      for (final entry in levels.entries.toList()) {
        levels[entry.key] = entry.value - minLevel;
      }
    }
    return levels;
  }

  Map<int, List<_SpouseGroup>> _buildGroupsByLevel({
    required Set<String> component,
    required Map<String, int> levels,
    required Map<String, Set<String>> spousesByPerson,
    required Map<String, Set<String>> siblingsByPerson,
    required Map<String, Set<String>> parentToChildren,
    required Map<String, FamilyPerson> peopleById,
  }) {
    final groupsByLevel = <int, List<_SpouseGroup>>{};
    final grouped = <String>{};
    final ids = component.toList()
      ..sort((a, b) {
        final levelCompare = (levels[a] ?? 0).compareTo(levels[b] ?? 0);
        if (levelCompare != 0) {
          return levelCompare;
        }
        return _comparePersons(peopleById[a]!, peopleById[b]!);
      });

    for (final id in ids) {
      if (grouped.contains(id)) {
        continue;
      }
      final level = levels[id] ?? 0;
      final memberIds = <String>{id};
      final queue = <String>[id];
      while (queue.isNotEmpty) {
        final currentId = queue.removeAt(0);
        for (final spouseId in spousesByPerson[currentId] ?? const <String>{}) {
          if (!component.contains(spouseId) ||
              grouped.contains(spouseId) ||
              (levels[spouseId] ?? 0) != level) {
            continue;
          }
          if (memberIds.add(spouseId)) {
            queue.add(spouseId);
          }
        }
      }
      grouped.addAll(memberIds);
      final orderedIds = _orderedPartnerMemberIds(
        memberIds.toList(),
        peopleById,
      );
      groupsByLevel.putIfAbsent(level, () => <_SpouseGroup>[]).add(
            _SpouseGroup(memberIds: orderedIds),
          );
    }

    for (final groups in groupsByLevel.values) {
      groups.sort((a, b) {
        final aWeight = _groupDescendantWeight(a.memberIds, parentToChildren);
        final bWeight = _groupDescendantWeight(b.memberIds, parentToChildren);
        if (aWeight != bWeight) {
          return bWeight.compareTo(aWeight);
        }
        return _comparePersons(
          peopleById[a.memberIds.first]!,
          peopleById[b.memberIds.first]!,
        );
      });
    }
    return groupsByLevel;
  }

  double? _desiredCenterForGroup({
    required _SpouseGroup group,
    required Map<String, Offset> positions,
    required Map<String, Set<String>> childToParents,
    required Map<String, Set<String>> parentToChildren,
    required Map<String, Set<String>> siblingsByPerson,
  }) {
    final referenceCenters = <double>[];
    for (final memberId in group.memberIds) {
      for (final parentId in childToParents[memberId] ?? const <String>{}) {
        final parentPosition = positions[parentId];
        if (parentPosition != null) {
          referenceCenters.add(parentPosition.dx);
        }
      }
      for (final siblingId in siblingsByPerson[memberId] ?? const <String>{}) {
        final siblingPosition = positions[siblingId];
        if (siblingPosition != null) {
          referenceCenters.add(siblingPosition.dx);
        }
      }
      for (final childId in parentToChildren[memberId] ?? const <String>{}) {
        final childPosition = positions[childId];
        if (childPosition != null) {
          referenceCenters.add(childPosition.dx);
        }
      }
    }
    if (referenceCenters.isEmpty) {
      return null;
    }
    return referenceCenters.reduce((a, b) => a + b) / referenceCenters.length;
  }

  void _centerParents(
    Map<String, Offset> positions,
    Map<int, List<_SpouseGroup>> groupsByLevel,
    Map<String, Set<String>> parentToChildren,
  ) {
    final levelOrder = groupsByLevel.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    for (final level in levelOrder) {
      for (final group in groupsByLevel[level] ?? const <_SpouseGroup>[]) {
        final childCenters = <double>[];
        for (final memberId in group.memberIds) {
          for (final childId
              in parentToChildren[memberId] ?? const <String>{}) {
            final childPosition = positions[childId];
            if (childPosition != null) {
              childCenters.add(childPosition.dx);
            }
          }
        }
        if (childCenters.isEmpty) {
          continue;
        }
        final currentCenter = group.memberIds
                .map((memberId) => positions[memberId]!.dx)
                .reduce((a, b) => a + b) /
            group.memberIds.length;
        final childCenter =
            childCenters.reduce((a, b) => a + b) / childCenters.length;
        final shift = childCenter - currentCenter;
        for (final memberId in group.memberIds) {
          final current = positions[memberId]!;
          positions[memberId] = Offset(current.dx + shift, current.dy);
        }
      }
    }
  }

  void _normalizeGroups(
    Map<String, Offset> positions,
    Map<int, List<_SpouseGroup>> groupsByLevel, {
    required Map<String, int> levels,
    required Map<String, Set<String>> childToParents,
    required Map<String, Set<String>> parentToChildren,
    required Map<String, Set<String>> siblingsByPerson,
    required Map<String, FamilyPerson> peopleById,
    required double componentStartX,
  }) {
    for (final entry in groupsByLevel.entries) {
      final level = entry.key;
      final groups = entry.value
        ..sort((a, b) {
          final aCenter = a.memberIds
                  .map((memberId) => positions[memberId]!.dx)
                  .reduce((x, y) => x + y) /
              a.memberIds.length;
          final bCenter = b.memberIds
                  .map((memberId) => positions[memberId]!.dx)
                  .reduce((x, y) => x + y) /
              b.memberIds.length;
          return aCenter.compareTo(bCenter);
        });

      double currentLeft = componentStartX;
      for (final group in groups) {
        final orderedMemberIds = _orientedMemberIds(
          memberIds: group.memberIds,
          level: level,
          positions: positions,
          levels: levels,
          childToParents: childToParents,
          parentToChildren: parentToChildren,
          siblingsByPerson: siblingsByPerson,
          peopleById: peopleById,
        );
        final groupWidth = _groupWidth(orderedMemberIds.length);
        final currentCenter = orderedMemberIds
                .map((memberId) => positions[memberId]!.dx)
                .reduce((x, y) => x + y) /
            orderedMemberIds.length;
        final left = max(currentLeft, currentCenter - groupWidth / 2);
        for (var index = 0; index < orderedMemberIds.length; index++) {
          final memberId = orderedMemberIds[index];
          final current = positions[memberId]!;
          final x = left +
              InteractiveFamilyTree.nodeWidth / 2 +
              index *
                  (InteractiveFamilyTree.nodeWidth +
                      InteractiveFamilyTree.spouseSeparation);
          positions[memberId] = Offset(x, current.dy);
        }
        currentLeft =
            left + groupWidth + InteractiveFamilyTree.siblingSeparation;
      }
    }
  }

  void _anchorComponentToStart(
    Map<String, Offset> positions, {
    required double componentStartX,
  }) {
    if (positions.isEmpty) {
      return;
    }
    final currentLeft = positions.values
        .map((position) => position.dx - InteractiveFamilyTree.nodeWidth / 2)
        .reduce(min);
    final shift = componentStartX - currentLeft;
    if (shift.abs() < 0.1) {
      return;
    }
    for (final entry in positions.entries.toList(growable: false)) {
      positions[entry.key] = Offset(entry.value.dx + shift, entry.value.dy);
    }
  }

  List<String> _orientedMemberIds({
    required List<String> memberIds,
    required int level,
    required Map<String, Offset> positions,
    required Map<String, int> levels,
    required Map<String, Set<String>> childToParents,
    required Map<String, Set<String>> parentToChildren,
    required Map<String, Set<String>> siblingsByPerson,
    required Map<String, FamilyPerson> peopleById,
  }) {
    final baseOrderedMemberIds = _orderedPartnerMemberIds(
      memberIds,
      peopleById,
    );
    if (baseOrderedMemberIds.length <= 1) {
      return baseOrderedMemberIds;
    }

    int lineageScore(String memberId) {
      final previousLevelParents =
          (childToParents[memberId] ?? const <String>{})
              .where((parentId) => levels[parentId] == level - 1)
              .length;
      final nextLevelChildren = (parentToChildren[memberId] ?? const <String>{})
          .where((childId) => levels[childId] == level + 1)
          .length;
      final allChildren =
          (parentToChildren[memberId] ?? const <String>{}).length;
      return previousLevelParents * 100 + nextLevelChildren * 10 + allChildren;
    }

    final scores = <String, int>{
      for (final memberId in baseOrderedMemberIds)
        memberId: lineageScore(memberId),
    };
    final highestScore = scores.values.reduce(max);
    final primaryMembers = baseOrderedMemberIds
        .where((memberId) => scores[memberId] == highestScore)
        .toList();
    final familyReferenceCenters = <String, double?>{
      for (final memberId in baseOrderedMemberIds)
        memberId: _memberPreferredReferenceCenter(
          memberId: memberId,
          level: level,
          positions: positions,
          levels: levels,
          childToParents: childToParents,
          parentToChildren: parentToChildren,
          siblingsByPerson: siblingsByPerson,
        ),
    };
    final anchoredMembers = baseOrderedMemberIds
        .where((memberId) => familyReferenceCenters[memberId] != null)
        .toList();

    if (anchoredMembers.length > 1) {
      final baseIndexes = <String, int>{
        for (var index = 0; index < baseOrderedMemberIds.length; index++)
          baseOrderedMemberIds[index]: index,
      };
      final hasDistinctReferenceCenters = anchoredMembers
              .map((memberId) => familyReferenceCenters[memberId]!)
              .toSet()
              .length >
          1;
      if (hasDistinctReferenceCenters) {
        final orientedIds = [...baseOrderedMemberIds];
        orientedIds.sort((left, right) {
          final leftCenter = familyReferenceCenters[left];
          final rightCenter = familyReferenceCenters[right];
          if (leftCenter != null &&
              rightCenter != null &&
              (leftCenter - rightCenter).abs() > 0.1) {
            return leftCenter.compareTo(rightCenter);
          }
          return (baseIndexes[left] ?? 0).compareTo(baseIndexes[right] ?? 0);
        });
        return orientedIds;
      }
    }

    if (highestScore <= 0 || primaryMembers.length != 1) {
      return baseOrderedMemberIds;
    }

    final primaryMemberId = primaryMembers.single;
    final primaryReferenceCenter = familyReferenceCenters[primaryMemberId];
    if (primaryReferenceCenter == null) {
      return baseOrderedMemberIds;
    }
    final groupCenter = baseOrderedMemberIds
            .map((memberId) => positions[memberId]?.dx)
            .whereType<double>()
            .fold<double>(0, (sum, value) => sum + value) /
        baseOrderedMemberIds.length;
    if ((primaryReferenceCenter - groupCenter).abs() <= 0.1) {
      return baseOrderedMemberIds;
    }
    final otherMemberIds = baseOrderedMemberIds
        .where((memberId) => memberId != primaryMemberId)
        .toList();

    if (primaryReferenceCenter < groupCenter) {
      return <String>[primaryMemberId, ...otherMemberIds];
    }
    return <String>[...otherMemberIds, primaryMemberId];
  }

  double? _memberPreferredReferenceCenter({
    required String memberId,
    required int level,
    required Map<String, Offset> positions,
    required Map<String, int> levels,
    required Map<String, Set<String>> childToParents,
    required Map<String, Set<String>> parentToChildren,
    required Map<String, Set<String>> siblingsByPerson,
  }) {
    final siblingCenter = _memberSiblingReferenceCenter(
      memberId: memberId,
      level: level,
      positions: positions,
      levels: levels,
      siblingsByPerson: siblingsByPerson,
    );
    if (siblingCenter != null) {
      return siblingCenter;
    }
    final parentCenter = _memberParentReferenceCenter(
      memberId: memberId,
      level: level,
      positions: positions,
      levels: levels,
      childToParents: childToParents,
    );
    if (parentCenter != null) {
      return parentCenter;
    }
    return _memberChildReferenceCenter(
      memberId: memberId,
      level: level,
      positions: positions,
      levels: levels,
      parentToChildren: parentToChildren,
    );
  }

  double? _memberParentReferenceCenter({
    required String memberId,
    required int level,
    required Map<String, Offset> positions,
    required Map<String, int> levels,
    required Map<String, Set<String>> childToParents,
  }) {
    final referenceCenters = <double>[];
    for (final parentId in childToParents[memberId] ?? const <String>{}) {
      if (levels[parentId] != level - 1) {
        continue;
      }
      final parentPosition = positions[parentId];
      if (parentPosition != null) {
        referenceCenters.add(parentPosition.dx);
      }
    }
    if (referenceCenters.isEmpty) {
      return null;
    }
    return referenceCenters.reduce((a, b) => a + b) / referenceCenters.length;
  }

  double? _memberSiblingReferenceCenter({
    required String memberId,
    required int level,
    required Map<String, Offset> positions,
    required Map<String, int> levels,
    required Map<String, Set<String>> siblingsByPerson,
  }) {
    final referenceCenters = <double>[];
    for (final siblingId in siblingsByPerson[memberId] ?? const <String>{}) {
      if (levels[siblingId] != level) {
        continue;
      }
      final siblingPosition = positions[siblingId];
      if (siblingPosition != null) {
        referenceCenters.add(siblingPosition.dx);
      }
    }
    if (referenceCenters.isEmpty) {
      return null;
    }
    return referenceCenters.reduce((a, b) => a + b) / referenceCenters.length;
  }

  double? _memberChildReferenceCenter({
    required String memberId,
    required int level,
    required Map<String, Offset> positions,
    required Map<String, int> levels,
    required Map<String, Set<String>> parentToChildren,
  }) {
    final referenceCenters = <double>[];
    for (final childId in parentToChildren[memberId] ?? const <String>{}) {
      if (levels[childId] != level + 1) {
        continue;
      }
      final childPosition = positions[childId];
      if (childPosition != null) {
        referenceCenters.add(childPosition.dx);
      }
    }
    if (referenceCenters.isEmpty) {
      return null;
    }
    return referenceCenters.reduce((a, b) => a + b) / referenceCenters.length;
  }

  List<String> _orderedPartnerMemberIds(
    List<String> memberIds,
    Map<String, FamilyPerson> peopleById,
  ) {
    final orderedIds = [...memberIds];
    orderedIds.sort((left, right) {
      final leftRank = _partnerGenderSortWeight(peopleById[left]?.gender);
      final rightRank = _partnerGenderSortWeight(peopleById[right]?.gender);
      if (leftRank != rightRank) {
        return leftRank.compareTo(rightRank);
      }
      return _comparePersons(peopleById[left]!, peopleById[right]!);
    });
    return orderedIds;
  }

  int _partnerGenderSortWeight(Gender? gender) {
    switch (gender) {
      case Gender.male:
        return 0;
      case Gender.female:
        return 1;
      case Gender.other:
        return 2;
      case Gender.unknown:
      case null:
        return 3;
    }
  }

  List<FamilyConnection> _buildConnections(
    List<FamilyRelation> relations,
    Map<String, Offset> positions,
  ) {
    final connections = <FamilyConnection>[];
    final spousePairs = <String>{};

    for (final relation in relations) {
      final parentId = _parentIdFromRelation(relation);
      final childId = _childIdFromRelation(relation);
      if (parentId != null &&
          childId != null &&
          positions.containsKey(parentId) &&
          positions.containsKey(childId)) {
        connections.add(
          FamilyConnection(
            fromId: parentId,
            toId: childId,
            type: RelationType.parent,
          ),
        );
        continue;
      }
      if (_isSpouseRelation(relation) &&
          positions.containsKey(relation.person1Id) &&
          positions.containsKey(relation.person2Id)) {
        final pair = [relation.person1Id, relation.person2Id]..sort();
        final pairKey = pair.join('::');
        if (spousePairs.add(pairKey)) {
          connections.add(
            FamilyConnection(
              fromId: pair.first,
              toId: pair.last,
              type: RelationType.spouse,
            ),
          );
        }
      }
    }
    return connections;
  }

  bool _isSpouseRelation(FamilyRelation relation) {
    return relation.relation1to2 == RelationType.spouse ||
        relation.relation2to1 == RelationType.spouse ||
        relation.relation1to2 == RelationType.partner ||
        relation.relation2to1 == RelationType.partner;
  }

  bool _isSiblingRelation(FamilyRelation relation) {
    return relation.relation1to2 == RelationType.sibling ||
        relation.relation2to1 == RelationType.sibling;
  }

  String? _parentIdFromRelation(FamilyRelation relation) {
    if (relation.relation1to2 == RelationType.parent ||
        relation.relation2to1 == RelationType.child) {
      return relation.person1Id;
    }
    if (relation.relation2to1 == RelationType.parent ||
        relation.relation1to2 == RelationType.child) {
      return relation.person2Id;
    }
    return null;
  }

  String? _childIdFromRelation(FamilyRelation relation) {
    if (relation.relation1to2 == RelationType.parent ||
        relation.relation2to1 == RelationType.child) {
      return relation.person2Id;
    }
    if (relation.relation2to1 == RelationType.parent ||
        relation.relation1to2 == RelationType.child) {
      return relation.person1Id;
    }
    return null;
  }

  int _comparePersons(FamilyPerson a, FamilyPerson b) {
    final nameCompare = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    if (nameCompare != 0) {
      return nameCompare;
    }
    return a.id.compareTo(b.id);
  }

  double _groupWidth(int membersCount) {
    return membersCount * InteractiveFamilyTree.nodeWidth +
        (membersCount - 1) * InteractiveFamilyTree.spouseSeparation;
  }

  int _groupDescendantWeight(
    List<String> memberIds,
    Map<String, Set<String>> parentToChildren,
  ) {
    final visited = <String>{};
    final queue = <String>[...memberIds];
    while (queue.isNotEmpty) {
      final currentId = queue.removeLast();
      for (final childId in parentToChildren[currentId] ?? const <String>{}) {
        if (visited.add(childId)) {
          queue.add(childId);
        }
      }
    }
    return visited.length;
  }
}

class _GenerationGuideBadge extends StatelessWidget {
  const _GenerationGuideBadge({
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
        );
    final subtitleStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 10,
          height: 1.15,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: titleStyle),
        if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: subtitleStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

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
  final Paint junctionPaint;
  final Paint mutedJunctionPaint;

  FamilyTreePainter(
    this.nodePositions,
    this.connections, {
    this.graphSnapshot,
    this.relations = const <FamilyRelation>[],
  })  : spouseLinePaint = Paint()
          ..color = Colors.grey.shade500
          ..strokeWidth = 1.5
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke,
        spousePastLinePaint = Paint()
          ..color = Colors.grey.shade400
          ..strokeWidth = 1.2
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke,
        familyLinePaint = Paint()
          ..color = Colors.grey.shade700
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke,
        mutedFamilyLinePaint = Paint()
          ..color = Colors.grey.shade500
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke,
        junctionPaint = Paint()
          ..color = Colors.grey.shade500
          ..isAntiAlias = true
          ..style = PaintingStyle.fill,
        mutedJunctionPaint = Paint()
          ..color = Colors.grey.shade400
          ..isAntiAlias = true
          ..style = PaintingStyle.fill;

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
        _drawSpouseLine(canvas, startNodePos, endNodePos, spouseLinePaint);
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
        _drawFamilyUnit(
          canvas,
          parentIds: parentIds,
          childIds: childIds,
          linePaint: familyLinePaint,
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
        final linePaint =
            unit.unionStatus == 'past' ? spousePastLinePaint : spouseLinePaint;
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
          _drawSpouseLine(canvas, firstPosition, secondPosition, linePaint);
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

      final linePaint =
          unit.unionStatus == 'past' ? mutedFamilyLinePaint : familyLinePaint;
      final junctionPaintForUnit =
          unit.unionStatus == 'past' ? mutedJunctionPaint : junctionPaint;
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
    Paint linePaint,
  ) {
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
    canvas.drawLine(Offset(x1, y), Offset(x2, y), linePaint);
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
        branchY: downwardChildren.map((anchor) => anchor.dy).reduce(min) - 18,
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
        branchY: upwardChildren.map((anchor) => anchor.dy).reduce(max) + 18,
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
    required double branchY,
    required Paint linePaint,
    required Paint pointPaint,
    required bool dashed,
  }) {
    if (anchors.isEmpty) {
      return;
    }

    if ((branchY - parentBarY).abs() > 0.1) {
      _drawSegment(
        canvas: canvas,
        start: Offset(familyCenterX, parentBarY),
        end: Offset(familyCenterX, branchY),
        linePaint: linePaint,
        dashed: dashed,
      );
    }

    final minChildX = anchors.map((anchor) => anchor.dx).reduce(min);
    final maxChildX = anchors.map((anchor) => anchor.dx).reduce(max);
    final branchStartX = min(minChildX, familyCenterX);
    final branchEndX = max(maxChildX, familyCenterX);
    if ((branchEndX - branchStartX).abs() > 0.1) {
      _drawSegment(
        canvas: canvas,
        start: Offset(branchStartX, branchY),
        end: Offset(branchEndX, branchY),
        linePaint: linePaint,
        dashed: dashed,
      );
    }
    _drawJunction(canvas, Offset(familyCenterX, branchY), pointPaint);

    for (final anchor in anchors) {
      if ((anchor.dx - familyCenterX).abs() > 0.1) {
        _drawSegment(
          canvas: canvas,
          start: Offset(anchor.dx, branchY),
          end: anchor,
          linePaint: linePaint,
          dashed: dashed,
        );
      } else {
        _drawSegment(
          canvas: canvas,
          start: Offset(familyCenterX, branchY),
          end: anchor,
          linePaint: linePaint,
          dashed: dashed,
        );
      }
      _drawJunction(canvas, Offset(anchor.dx, branchY), pointPaint);
    }
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
    canvas.drawCircle(center, 4.0, pointPaint);
  }

  @override
  bool shouldRepaint(covariant FamilyTreePainter oldDelegate) {
    // Перерисовываем, если изменились позиции узлов или сами связи
    return oldDelegate.nodePositions != nodePositions ||
        oldDelegate.connections != connections ||
        oldDelegate.graphSnapshot != graphSnapshot ||
        oldDelegate.relations != relations;
  }
} // <- Скобка закрывает класс FamilyTreePainter

class _PaintFamilyUnit {
  _PaintFamilyUnit({required this.childId});

  final String childId;
  final Set<String> parentIds = <String>{};
}
