import 'package:cached_network_image/cached_network_image.dart';
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
import '../theme/app_theme.dart';
import '../utils/photo_url.dart';
import 'family_tree_node_card.dart';

part 'interactive_family_tree_layout_models.dart';
part 'interactive_family_tree_positioning.dart';
part 'interactive_family_tree_sections.dart';

class InteractiveFamilyTree extends StatefulWidget {
  final List<Map<String, dynamic>>
      peopleData; // Теперь содержит {'person': FamilyPerson, 'userProfile': UserProfile?}
  final List<FamilyRelation> relations;
  final TreeGraphSnapshot? graphSnapshot;
  final Function(FamilyPerson) onPersonTap; // Коллбэк при нажатии на узел
  /// Двойной клик/тап по карточке — обычно открывает полную страницу профиля.
  final void Function(FamilyPerson)? onPersonDoubleTap;
  final bool isEditMode; // Флаг режима редактирования
  final void Function(FamilyPerson person, RelationType type)
      onAddRelativeTapWithType; // Коллбэк для добавления
  final bool
      currentUserIsInTree; // <<< НОВЫЙ ПАРАМЕТР: Флаг, добавлен ли текущий пользователь
  final void Function(FamilyPerson targetPerson, RelationType relationType)
      onAddSelfTapWithType; // <<< НОВЫЙ ПАРАМЕТР: Коллбэк для добавления себя

  /// Edge-first connector: long-press a card → drag to another card →
  /// pick a relation type from the inline 4-icon picker → relation
  /// is created. Replaces the old "open form, choose relation in
  /// dropdown, save" flow with direct graphical manipulation.
  ///
  /// When omitted (e.g. on the public read-only viewer), the
  /// connector is fully disabled — long-press falls back to the
  /// legacy quick-add bottom-sheet.
  ///
  /// The callback receives the source and target person ids in the
  /// order the user dragged them (source = where the gesture
  /// started, target = where it was released) plus the chosen
  /// `relation1to2`. The consumer is responsible for invoking
  /// `family_tree_service.createRelation(...)` and reloading.
  final void Function(
    String sourcePersonId,
    String targetPersonId,
    RelationType relation1to2,
  )? onConnectExistingPersons;

  /// Phase 1.2 voltage-indicator matcher: per-person counts of
  /// medium+high confidence cross-tree match suggestions the user
  /// hasn't linked or dismissed. When count > 0, the canvas
  /// renders a small 💡 dot on the card; tapping fires
  /// [onShowIdentitySuggestions] so the host can pop a sheet
  /// with the actual suggestion details + confirm/dismiss controls.
  ///
  /// We pass counts (not the full suggestion list) here because
  /// the visible information at the canvas-level is "yes there's
  /// at least one"; the popover fetches details on demand.
  final Map<String, int>? identitySuggestionCounts;

  /// Tap callback for the 💡 dot. Host fetches the actual list,
  /// shows a sheet, dispatches link/dismiss on the service.
  final void Function(String personId)? onShowIdentitySuggestions;

  /// Phase 1.3 edit-time conflict surfacing: per-person counts of
  /// unresolved identity-field conflicts (propagation declined to
  /// overwrite a locally-edited field). When count > 0, the
  /// canvas renders a ⚠️ dot on the card; tapping fires
  /// [onShowIdentityConflicts] so the host can pop a sheet listing
  /// the diverging fields with `keep` / `overwrite` controls.
  ///
  /// Distinct from [identitySuggestionCounts] because the meaning
  /// is different: 💡 means "maybe these are the same human",
  /// ⚠️ means "this human's data is out of sync between branches
  /// and needs your attention".
  final Map<String, int>? identityConflictCounts;

  /// Tap callback for the ⚠️ dot. Host fetches the conflict list
  /// for the tree (already cached from the canvas refresh) and
  /// shows the resolve sheet for the selected card.
  final void Function(String personId)? onShowIdentityConflicts;

  /// Auto-recenter trigger. When this prop's value CHANGES to a
  /// non-null person id, the tree animates / snaps the viewport to
  /// center that person on the next frame. Used after creating a
  /// new card via [onAddBlankPerson] so the user always sees where
  /// it landed (otherwise a freshly-created orphan can appear off-
  /// viewport when the user is zoomed into another branch).
  ///
  /// Only triggers on change — passing the same id twice does
  /// nothing. The host sets it once after a successful create,
  /// the tree consumes it via didUpdateWidget, and the host can
  /// leave it in place; it won't keep firing.
  final String? recenterOnPersonId;

  /// Blank-card creator: lets the user drop a person on the canvas
  /// without specifying any relation up front. The user fills name
  /// + gender in a small dialog (NOT the legacy form), the host
  /// creates the orphan person via the service, and the user then
  /// uses [onConnectExistingPersons] to attach it to the rest of
  /// the tree. Together these two callbacks replace the form-based
  /// add-relative flow with direct graphical manipulation.
  ///
  /// Receives a `personData` map shaped exactly like the body of
  /// `POST /v1/trees/:treeId/persons` — host can pass it through
  /// to `family_tree_service.addRelative(treeId, personData)` as-is.
  ///
  /// When omitted (e.g. on the public read-only viewer) the FAB
  /// is hidden and the legacy add-relative path is the only entry.
  final Future<void> Function(Map<String, dynamic> personData)?
      onAddBlankPerson;
  final String? currentUserId;
  final String? branchRootPersonId;
  final String? selectedPersonId;
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

  /// Vertical pixels reserved at the top of the viewport for floating
  /// chrome (toolbar / context column on mobile). Defaults to 64.
  final double viewportReservedTop;

  /// Vertical pixels reserved at the bottom for the bottom sheet / dock.
  final double viewportReservedBottom;

  /// When false, suppress the inline edit panel that floats next to the
  /// selected node in edit mode. Use this when the consumer is rendering
  /// edit actions inside its own bottom sheet to avoid two surfaces
  /// fighting for the same screen real-estate.
  final bool showInlineEditPanel;

  // Константы для размеров узлов и отступов - понадобятся для расчета layout.
  // nodeHeight should be a tight upper bound on the rendered
  // FamilyTreeNodeCard height — the card with avatar (40), first +
  // last name (~28), life dates (~15), and the role pill (~18) plus
  // padding (10+9) and border (~2) measures around 128px. Setting
  // nodeHeight below that lets the role pill visually leak into the
  // gap between generations, which the user noticed as "карточки
  // налезают". Bumping to 130 + a 12px boost to levelSeparation
  // gives the pill a clear breathing strip above the connectors.
  static const double nodeWidth = 132; // Примерная ширина карточки
  static const double nodeHeight = 130; // Высота карточки с pill-ом
  static const double levelSeparation =
      76; // Вертикальное расстояние между уровнями
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
    this.onPersonDoubleTap,
    this.isEditMode = false, // По умолчанию выключен
    required this.onAddRelativeTapWithType,
    required this.currentUserIsInTree, // Делаем обязательным
    required this.onAddSelfTapWithType, // Делаем обязательным
    this.onConnectExistingPersons,
    this.onAddBlankPerson,
    this.recenterOnPersonId,
    this.identitySuggestionCounts,
    this.onShowIdentitySuggestions,
    this.identityConflictCounts,
    this.onShowIdentityConflicts,
    this.currentUserId,
    this.branchRootPersonId,
    this.selectedPersonId,
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
    this.viewportReservedTop = 64,
    this.viewportReservedBottom = 28,
    this.showInlineEditPanel = true,
  });

  @override
  State<InteractiveFamilyTree> createState() => _InteractiveFamilyTreeState();
}

class _InteractiveFamilyTreeState extends State<InteractiveFamilyTree> {
  // Space reserved at the top/bottom of the viewport when fitting/focusing
  // the tree — keeps cards from appearing under floating chrome (toolbar,
  // sidebar, bottom sheet).
  double get _viewportReservedTop => widget.viewportReservedTop;
  double get _viewportReservedBottom => widget.viewportReservedBottom;

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
  // Floating zoom dock starts collapsed on compact viewports so it
  // doesn't overlap person cards (user feedback "все мешается").
  // Tap on the chevron expands the column.
  bool _controlDockExpanded = false;

  /// Public toggle for the control-dock state, callable from the
  /// extension methods in interactive_family_tree_sections.dart.
  /// Direct `setState` from extensions trips the protected-member
  /// analyzer rule, so we hop through this helper.
  void _setControlDockExpanded(bool value) {
    if (_controlDockExpanded == value) return;
    setState(() => _controlDockExpanded = value);
  }

  // Normalizes a backend role label for the role pill on tree
  // cards. We strip the pronoun («Ваш/Ваша») — every card lives in
  // a tree centered on the current user, so prepending "Ваш(а)" to
  // every label was visually noisy and pushed long roles
  // («Ваша двоюродная сестра») past the pill's max-width into
  // ellipsis. Also folds Soviet-style «Мать»/«Отец» to the warmer
  // «Мама»/«Папа», fixes the missing ё in «тетя»/«теща», and
  // capitalizes the first letter so "свояк" reads as "Свояк".
  String _normalizeRelationLabel(String roleLabel) {
    final lower = roleLabel.toLowerCase().trim();
    if (lower.isEmpty) return roleLabel;
    const friendly = <String, String>{
      'мать': 'Мама',
      'отец': 'Папа',
      'тетя': 'Тётя',
      'теща': 'Тёща',
    };
    final mapped = friendly[lower];
    if (mapped != null) return mapped;
    return lower[0].toUpperCase() + lower.substring(1);
  }

  Offset? _dragStartNodePosition;

  /// Person ids on the active path (selected + parents + children + spouse +
  /// siblings) — used to dim everyone else when something is selected.
  Set<String>? _activePathPersonIds;

  // ── Edge-first connector state ─────────────────────────────────────
  // Active when the user has long-pressed a card and is dragging a
  // connection towards another card. The whole flow:
  //
  //  1. onLongPressStart → _connectingFromPersonId = source.id
  //     (and we hide the existing legacy quick-add sheet path)
  //  2. Pointer move tracked via Listener at canvas root → updates
  //     _connectingPointerCanvasPosition (in canvas-local coords,
  //     i.e. AFTER the InteractiveViewer transform)
  //  3. DragTarget.onMove on a destination card → sets
  //     _connectingHoverTargetId so the card glows
  //  4. DragTarget.onAcceptWithDetails → opens the relation-type
  //     picker; on selection we fire onConnectExistingPersons
  //  5. Drag released over empty canvas / picker dismissed / ESC
  //     pressed → _cancelConnecting() clears all four fields
  //
  // We never store relation creation locally — that's the consumer's
  // job (tree_view_screen wires it to family_tree_service).
  String? _connectingFromPersonId;
  Offset? _connectingPointerCanvasPosition;
  String? _connectingHoverTargetId;
  bool _showingRelationPicker = false;
  // Used for ESC-to-cancel on desktop. We attach a Focus only while
  // a connect is in progress so we don't fight other shortcuts.
  final FocusNode _connectModeFocusNode = FocusNode(debugLabel: 'tree-connect-mode');

  bool get _isConnecting => _connectingFromPersonId != null;

  void _startConnecting(String sourcePersonId) {
    if (widget.onConnectExistingPersons == null) return;
    if (widget.isEditMode) return;
    if (_connectingFromPersonId == sourcePersonId) return;
    HapticFeedback.selectionClick();
    setState(() {
      _connectingFromPersonId = sourcePersonId;
      _connectingPointerCanvasPosition =
          nodePositions[sourcePersonId];
      _connectingHoverTargetId = null;
      _showingRelationPicker = false;
    });
    // Grab focus so ESC works on desktop. Do it after the frame so
    // the FocusNode is mounted into the tree.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isConnecting) {
        _connectModeFocusNode.requestFocus();
      }
    });
  }

  void _cancelConnecting() {
    if (!_isConnecting && !_showingRelationPicker) return;
    setState(() {
      _connectingFromPersonId = null;
      _connectingPointerCanvasPosition = null;
      _connectingHoverTargetId = null;
      _showingRelationPicker = false;
    });
  }

  void _setHoverTargetForConnect(String targetPersonId) {
    if (!_isConnecting) return;
    if (targetPersonId == _connectingFromPersonId) return;
    if (_connectingHoverTargetId == targetPersonId) return;
    setState(() {
      _connectingHoverTargetId = targetPersonId;
    });
  }

  void _clearHoverTargetIfMatches(String targetPersonId) {
    if (_connectingHoverTargetId != targetPersonId) return;
    setState(() {
      _connectingHoverTargetId = null;
    });
  }

  Future<void> _completeConnection(String sourceId, String targetId) async {
    if (!_isConnecting) return;
    if (sourceId == targetId) {
      _cancelConnecting();
      return;
    }
    HapticFeedback.mediumImpact();
    // Resolve persons for nicer copy in the picker.
    final sourcePerson = _findPersonInData(sourceId);
    final targetPerson = _findPersonInData(targetId);
    setState(() {
      _showingRelationPicker = true;
      _connectingHoverTargetId = targetId;
    });
    final picked = await showDialog<RelationType>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (dialogContext) => _ConnectorRelationTypePicker(
        sourceName: sourcePerson?.displayName ?? 'этот человек',
        targetName: targetPerson?.displayName ?? 'этому человеку',
      ),
    );
    if (!mounted) return;
    if (picked == null) {
      // User dismissed the picker (tapped outside / pressed back).
      _cancelConnecting();
      return;
    }
    // Fire-and-forget: the consumer reloads the tree, didUpdateWidget
    // will pick up the new relation and re-render. We clear our local
    // state immediately so the preview line/pill go away.
    widget.onConnectExistingPersons?.call(sourceId, targetId, picked);
    _cancelConnecting();
  }

  FamilyPerson? _findPersonInData(String personId) {
    for (final entry in widget.peopleData) {
      final person = entry['person'];
      if (person is FamilyPerson && person.id == personId) {
        return person;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _selectedEditPersonId = widget.selectedEditPersonId;
    _transformationController.addListener(_handleTransformChanged);
    _calculateLayout(); // Вызываем расчет layout
    _activePathPersonIds = _computeActivePath(widget.selectedPersonId);
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

    // Recompute the highlighted active path whenever selection or graph
    // structure changes.
    if (oldWidget.selectedPersonId != widget.selectedPersonId ||
        oldWidget.relations != widget.relations) {
      _activePathPersonIds = _computeActivePath(widget.selectedPersonId);
    }

    // Auto-recenter trigger from the host. Used after the user
    // creates a fresh blank card via the "+" FAB so they always
    // see where it landed — without this, a freshly-created
    // orphan can end up off-viewport when the user is zoomed
    // into another branch.
    //
    // Only fires on CHANGE: passing the same id twice in a row is
    // a no-op, so the host can leave the prop in place after the
    // first set without causing repeated re-centers on every
    // unrelated rebuild.
    final pendingRecenterId = widget.recenterOnPersonId;
    if (pendingRecenterId != null &&
        pendingRecenterId.isNotEmpty &&
        pendingRecenterId != oldWidget.recenterOnPersonId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // _calculateLayout has already run synchronously by the
        // time this post-frame callback fires (didUpdateWidget
        // recomputes layout above when peopleData changes), so
        // nodePositions is populated for the new card.
        _focusOnPerson(pendingRecenterId);
      });
    }
  }

  /// Returns the set of person ids that are on the active path of [selectedId]:
  /// the selected person, their direct parents, their direct children, their
  /// spouse, and their siblings (children of the same parents). Anyone outside
  /// this set is dimmed in the canvas.
  Set<String>? _computeActivePath(String? selectedId) {
    if (selectedId == null || selectedId.isEmpty) return null;
    final result = <String>{selectedId};
    final parents = <String>{};
    bool isParentRel(RelationType t) => t == RelationType.parent;
    bool isChildRel(RelationType t) =>
        t == RelationType.child ||
        t == RelationType.grandchild ||
        t == RelationType.greatGrandchild;
    bool isSpousal(RelationType t) =>
        t == RelationType.spouse || t == RelationType.partner;

    for (final relation in widget.relations) {
      final r12 = relation.relation1to2;
      final r21 = relation.relation2to1;
      if (relation.person1Id == selectedId) {
        if (isParentRel(r12)) {
          // person2 is selected's child (selected is parent of person2)
          // — wait: r12 says how person1 relates to person2. If r12==parent,
          // person1 is parent of person2.
          result.add(relation.person2Id);
        }
        if (isChildRel(r12)) {
          // person1 is child of person2 → person2 is parent
          parents.add(relation.person2Id);
          result.add(relation.person2Id);
        }
        if (isSpousal(r12)) {
          result.add(relation.person2Id);
        }
      }
      if (relation.person2Id == selectedId) {
        if (isParentRel(r12)) {
          // person1 is parent of person2 (selected) → add person1 as parent
          parents.add(relation.person1Id);
          result.add(relation.person1Id);
        }
        if (isChildRel(r12)) {
          // person1 is child of person2 (selected) → add person1 as child
          result.add(relation.person1Id);
        }
        if (isSpousal(r21)) {
          result.add(relation.person1Id);
        }
      }
    }
    // Siblings: anyone whose parent set intersects mine.
    if (parents.isNotEmpty) {
      for (final relation in widget.relations) {
        if (relation.relation1to2 == RelationType.parent &&
            parents.contains(relation.person1Id) &&
            relation.person2Id != selectedId) {
          result.add(relation.person2Id);
        }
        if (relation.relation1to2 == RelationType.child &&
            parents.contains(relation.person2Id) &&
            relation.person1Id != selectedId) {
          result.add(relation.person1Id);
        }
      }
    }
    return result;
  }

  @override
  void dispose() {
    _transformationController.removeListener(_handleTransformChanged);
    _transformationController.dispose();
    _connectModeFocusNode.dispose();
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
      currentUserId: widget.currentUserId,
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
    return _buildInteractiveTreeSurface(
      context: context,
      stackWidth: stackWidth,
      stackHeight: stackHeight,
      interactionBoundary: interactionBoundary,
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

  void _updateTreeState(VoidCallback update) {
    if (!mounted) {
      return;
    }
    setState(update);
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
                            tooltip: 'Закрыть галерею',
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
                          final normalizedItemUrl = normalizePhotoUrl(itemUrl);
                          return InteractiveViewer(
                            child: normalizedItemUrl == null
                                ? const Center(
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      color: Colors.white,
                                      size: 40,
                                    ),
                                  )
                                : CachedNetworkImage(
                                    imageUrl: normalizedItemUrl,
                                    fit: BoxFit.contain,
                                    placeholder: (context, url) => const Center(
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                      ),
                                    ),
                                    errorWidget: (context, url, error) =>
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
        key: ValueKey<String>('tree-node-position-$personId'),
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
    final isSelectedPerson = widget.selectedPersonId == person.id;
    final isSelectedInEditMode =
        widget.isEditMode && _selectedEditPersonId == person.id;
    final isDraggingNode = _draggingPersonId == person.id;
    final supportsHoverActions = _supportsHoverNodeActions();
    final isHoveredNode = !widget.isEditMode && _hoveredPersonId == person.id;
    // Backend gives us role labels from the viewer's perspective
    // ("Мать"/"Дядя"/"Двоюродная сестра"). We just normalize them
    // for the pill — folding "Мать"→"Мама" and similar — and skip
    // the pill entirely on the current-user node (it already shows
    // a "Это вы" chip). The "Ваш/Ваша" pronoun used to live here
    // but felt redundant on every card and ate horizontal space
    // for long roles; the whole tree is rooted in the viewer so
    // the bare role is unambiguous.
    final relationChipLabel = viewerDescriptor?.primaryRelationLabel == null ||
            viewerDescriptor!.primaryRelationLabel!.trim().isEmpty ||
            isCurrentUserNode
        ? null
        : _normalizeRelationLabel(
              viewerDescriptor.primaryRelationLabel!.trim(),
            ) +
            (viewerDescriptor.alternatePathCount > 0
                ? ' +${viewerDescriptor.alternatePathCount}'
                : '');
    final prefersTouchQuickAdd = !supportsHoverActions && !widget.isEditMode;
    final canUseLongPressQuickAdd = prefersTouchQuickAdd;

    // Reference design states for the card:
    // - deceased = saturate-down + † overlay on avatar
    // - pending  = warm dot on avatar (no userId linked yet)
    // - dimmed   = a different node is selected and this one is not on the
    //              active path → fade to ~32% so the path stands out
    final isDeceasedPerson =
        person.deathDate != null || person.isAlive == false;
    final isPendingPerson =
        (person.userId == null || person.userId!.isEmpty) && !isDeceasedPerson;
    final hasActivePath = widget.selectedPersonId != null;
    final isOnActivePath = hasActivePath &&
        (_activePathPersonIds?.contains(person.id) ?? false);
    final isDimmed = hasActivePath && !isOnActivePath && !isSelectedPerson;

    final cardContent = FamilyTreeNodeCard(
      key: ValueKey<String>('tree-node-${person.id}'),
      displayName: displayName,
      lifeDates: _getLifeDates(person),
      displayGender: displayGender,
      displayPhotoUrl: displayPhotoUrl,
      relationChipLabel: relationChipLabel,
      isBloodRelation: viewerDescriptor?.isBlood == true,
      isCurrentUserNode: isCurrentUserNode,
      isSelectedInEditMode: isSelectedInEditMode || isSelectedPerson,
      isDraggingNode: isDraggingNode,
      isHovered: isHoveredNode,
      isDeceased: isDeceasedPerson,
      isPending: isPendingPerson,
      isDimmed: isDimmed,
    );

    // Edge-first connector is enabled when (a) the host wired the
    // onConnectExistingPersons callback (the public read-only viewer
    // does NOT) AND (b) we're not in edit mode (where long-press is
    // already used to drag cards into manual positions).
    final connectorEnabled =
        widget.onConnectExistingPersons != null && !widget.isEditMode;
    final isConnectHoverTarget =
        connectorEnabled && _connectingHoverTargetId == person.id &&
            _connectingFromPersonId != person.id;
    final isConnectSource =
        connectorEnabled && _connectingFromPersonId == person.id;

    // Card with optional "drop-target glow" for connector hover state.
    final cardWithConnectAffordance = Stack(
      clipBehavior: Clip.none,
      children: [
        cardContent,
        // Glow ring shown when another card is being dragged onto
        // this one during edge-first connection.
        if (isConnectHoverTarget)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.35),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );

    final tapAndDoubleTapDetector = GestureDetector(
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
      onDoubleTap: widget.isEditMode || widget.onPersonDoubleTap == null
          ? null
          : () => widget.onPersonDoubleTap!(person),
      // Legacy long-press → quick-add bottom sheet. Suppressed when
      // the connector is enabled (the LongPressDraggable below
      // takes that gesture for drag-to-connect instead).
      onLongPress: widget.isEditMode ||
              !canUseLongPressQuickAdd ||
              connectorEnabled
          ? null
          : () => _showQuickAddRelativeSheet(context, person),
      child: cardWithConnectAffordance,
    );

    final cardInteractionLayer = connectorEnabled
        ? DragTarget<String>(
            onWillAcceptWithDetails: (details) =>
                // Don't accept self-drops — would create A↔A relations.
                details.data != person.id,
            onMove: (_) => _setHoverTargetForConnect(person.id),
            onLeave: (_) => _clearHoverTargetIfMatches(person.id),
            onAcceptWithDetails: (details) =>
                _completeConnection(details.data, person.id),
            builder: (context, candidates, rejected) {
              return LongPressDraggable<String>(
                data: person.id,
                // Slightly tighter than Flutter's 500 ms default — feels
                // immediate to the user without firing on accidental
                // taps. Matches the Material LongPress recognizer's
                // recommended haptic-confirmation window.
                delay: const Duration(milliseconds: 320),
                onDragStarted: () => _startConnecting(person.id),
                onDragEnd: (details) {
                  // The DragTarget.onAccept path drives _completeConnection
                  // which eventually clears state via _cancelConnecting.
                  // If we reach DragEnd without a drop having been
                  // accepted (released over empty canvas), tear down
                  // here so the preview line doesn't get stuck.
                  if (_isConnecting && !_showingRelationPicker) {
                    _cancelConnecting();
                  }
                },
                feedback: Material(
                  color: Colors.transparent,
                  // We deliberately DO NOT use the full
                  // FamilyTreeNodeCard as feedback — the card has a
                  // flexible internal Column that doesn't survive
                  // the Overlay's unbounded constraints (overflows
                  // vertically). A small named pill is plenty —
                  // the actual source card pulses at its origin
                  // and the dashed preview line connects them.
                  child: _ConnectorDragFeedbackChip(
                    label: displayName,
                    color:
                        Theme.of(context).colorScheme.primary,
                    foreground:
                        Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.35,
                  child: tapAndDoubleTapDetector,
                ),
                child: tapAndDoubleTapDetector,
              );
            },
          )
        : tapAndDoubleTapDetector;

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
          // Subtle source-card pulse so the user remembers WHERE the
          // drag started while their finger is mid-flight elsewhere.
          if (isConnectSource)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                      style: BorderStyle.solid,
                    ),
                  ),
                ),
              ),
            ),
          cardInteractionLayer,
          // Phase 1.2 voltage-indicator: 💡 dot on the top-LEFT of
          // any card the matcher found cross-tree duplicate
          // candidates for. Position deliberately distinct from
          // the "+" badge on top-RIGHT so they don't compete.
          // Visible on hover/select (parity with the existing "+"
          // badge), and ALWAYS visible when the count is high.
          if (!widget.isEditMode &&
              (widget.identitySuggestionCounts?[person.id] ?? 0) > 0)
            Positioned(
              top: 8,
              left: 8,
              child: _IdentitySuggestionsBadge(
                count: widget.identitySuggestionCounts![person.id]!,
                onTap: () =>
                    widget.onShowIdentitySuggestions?.call(person.id),
              ),
            ),
          // Phase 1.3 edit-time conflict surfacing: ⚠️ dot on the
          // bottom-RIGHT (deliberately opposite the 💡 badge so
          // both can coexist on a card without overlapping).
          // Always visible — unlike 💡 this is "your data is
          // diverging, please review" rather than a passive hint,
          // and hiding it would defeat the point.
          if (!widget.isEditMode &&
              (widget.identityConflictCounts?[person.id] ?? 0) > 0)
            Positioned(
              bottom: 8,
              right: 8,
              child: _IdentityConflictsBadge(
                count: widget.identityConflictCounts![person.id]!,
                onTap: () =>
                    widget.onShowIdentityConflicts?.call(person.id),
              ),
            ),
          // Show the "+" quick-add badge on hover (desktop) AND on the
          // currently-selected node (so mobile users with no hover can
          // still trigger the add-relative sheet without going through
          // the bottom sheet's Связь tab).
          if (!widget.isEditMode && (isHoveredNode || isSelectedPerson))
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

// Maps the viewer-relative relation label the backend computes
// (e.g., "Дядя", "Двоюродная сестра", "Бабушка") to a generation
// offset in the layout's row index space:
//   negative → older generation (above the viewer row)
//   zero     → same generation as the viewer
//   positive → younger generation (below the viewer row)
//
// Returns null when the label doesn't map cleanly to a single
// offset (e.g., "В законе" / "Друг" / unknown). The caller should
// then fall back to whatever the structural BFS came up with.
//
// The matcher is intentionally lowercase substring — backend
// labels can carry suffixes ("+2", "по жене", colloquial forms)
// which we strip before testing.
int? _generationOffsetFromRelationLabel(String? rawLabel) {
  if (rawLabel == null) return null;
  final label = rawLabel.toLowerCase().trim();
  if (label.isEmpty) return null;

  // Order matters: more specific patterns first so "прабабушка"
  // doesn't accidentally match the "бабушка" rule.
  if (label.contains('прапрадед') ||
      label.contains('прапрабабушк') ||
      label.contains('прапрадеду')) {
    return -4;
  }
  if (label.contains('прадед') ||
      label.contains('прабаб') ||
      label.contains('прадеду')) {
    return -3;
  }
  if (label.contains('двоюродн')) {
    // Двоюродный/-ая брат/сестра/племянник/дядя/тётя — the
    // generation offset depends on the second half.
    if (label.contains('брат') || label.contains('сестр')) return 0;
    if (label.contains('племянн')) return 1;
    if (label.contains('дядя') ||
        label.contains('тёт') ||
        label.contains('тет')) {
      return -1;
    }
    if (label.contains('бабуш') || label.contains('дед')) return -2;
    if (label.contains('внук') || label.contains('внучк')) return 2;
    return null;
  }
  if (label.contains('дед') ||
      label.contains('бабуш') ||
      label.contains('бабк')) {
    return -2;
  }
  if (label.contains('внук') || label.contains('внучк')) return 2;
  if (label.contains('племянн') || label.contains('племяшк')) return 1;
  if (label.contains('дядя') ||
      label.contains('тёт') ||
      label.contains('тет')) {
    return -1;
  }
  if (label.contains('мать') ||
      label.contains('мам') ||
      label.contains('отец') ||
      label.contains('папа') ||
      label.contains('родитель') ||
      label.contains('мачех') ||
      label.contains('отчим')) {
    return -1;
  }
  if (label.contains('сын') ||
      label.contains('дочь') ||
      label.contains('дочк') ||
      label.contains('пасынк') ||
      label.contains('падчериц')) {
    return 1;
  }
  if (label.contains('брат') || label.contains('сестр')) return 0;
  if (label.contains('супруг') ||
      label.contains('партнёр') ||
      label.contains('партнер') ||
      label.contains('жен') ||
      label.contains('муж')) {
    return 0;
  }
  return null;
}

class _TreeLayoutEngine {
  _TreeLayoutEngine({
    required this.peopleData,
    required this.relations,
    this.graphSnapshot,
    this.currentUserId,
  });

  final List<Map<String, dynamic>> peopleData;
  final List<FamilyRelation> relations;
  final TreeGraphSnapshot? graphSnapshot;
  final String? currentUserId;

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

    // Enrich parent/child + spouse adjacency from the backend's family
    // unit snapshot. Without this, distant relatives the user adds via
    // their relation type ("cousin", "aunt", "uncle", "niece" ...)
    // never get parent/child edges in this layout — only the literal
    // RelationType.parent/child/spouse/partner/sibling kinds are
    // extracted above. The backend's graph builder already resolves
    // those distant types into proper family units (adultIds + childIds
    // = parent edge, two adultIds = couple), so we just have to
    // re-project them back into adjacency. This is what was breaking
    // the user's tree the moment a cousin was added: she landed in the
    // graph but the layout had no idea who her parents were, so her
    // group's `_desiredCenterForGroup` returned null and she drifted
    // to the far right of the row.
    final snapshot = graphSnapshot;
    if (snapshot != null) {
      for (final unit in snapshot.familyUnits) {
        final adultIds = unit.adultIds
            .where(peopleById.containsKey)
            .toList(growable: false);
        final childIds = unit.childIds
            .where(peopleById.containsKey)
            .toList(growable: false);

        // Adults of the same family unit form an implicit couple even
        // when no explicit spouse/partner relation exists (e.g. an
        // unmarried mother + father the user added independently).
        for (var i = 0; i < adultIds.length; i++) {
          for (var j = i + 1; j < adultIds.length; j++) {
            final a = adultIds[i];
            final b = adultIds[j];
            spousesByPerson.putIfAbsent(a, () => <String>{}).add(b);
            spousesByPerson.putIfAbsent(b, () => <String>{}).add(a);
            adjacency[a]!.add(b);
            adjacency[b]!.add(a);
          }
        }

        // Each adult is a parent of every child in the unit.
        for (final adultId in adultIds) {
          for (final childId in childIds) {
            parentToChildren
                .putIfAbsent(adultId, () => <String>{})
                .add(childId);
            childToParents
                .putIfAbsent(childId, () => <String>{})
                .add(adultId);
            adjacency[adultId]!.add(childId);
            adjacency[childId]!.add(adultId);
          }
        }

        // Children of the same family unit are siblings of each other.
        for (var i = 0; i < childIds.length; i++) {
          for (var j = i + 1; j < childIds.length; j++) {
            final a = childIds[i];
            final b = childIds[j];
            siblingsByPerson.putIfAbsent(a, () => <String>{}).add(b);
            siblingsByPerson.putIfAbsent(b, () => <String>{}).add(a);
            adjacency[a]!.add(b);
            adjacency[b]!.add(a);
          }
        }
      }
    }

    final components = _buildComponents(adjacency, peopleById);

    // ── Find viewer + their global level BEFORE the components loop.
    // We process the viewer's component first, capture its levels,
    // and use the viewer's level as the global anchor for any
    // OTHER component that has a viewer-relative descriptor (e.g.,
    // an uncle-by-marriage who has no structural connection to the
    // viewer's blood ancestors). Without this, separate components
    // each min-shift to row 0 and float independently — placing an
    // uncle's branch at the canvas top instead of the parents' row.
    FamilyPerson? viewerPerson;
    if (currentUserId != null && currentUserId!.isNotEmpty) {
      for (final person in peopleById.values) {
        if (person.userId == currentUserId) {
          viewerPerson = person;
          break;
        }
      }
    }
    int? viewerGlobalLevel;
    final componentLevels = <Set<String>, Map<String, int>>{};

    // Pre-pass: assign levels for every component AND find the
    // viewer's level. We can't do this lazily inside the position
    // loop because uncle's component might be processed before
    // viewer's component, and uncle needs viewer's level to anchor.
    for (final component in components) {
      final levels = _assignLevels(
        component: component,
        peopleById: peopleById,
        childToParents: childToParents,
        parentToChildren: parentToChildren,
        spousesByPerson: spousesByPerson,
        siblingsByPerson: siblingsByPerson,
      );
      componentLevels[component] = levels;
      if (viewerPerson != null && component.contains(viewerPerson.id)) {
        viewerGlobalLevel = levels[viewerPerson.id];
      }
    }

    // Viewer-relation anchor pass: for each NON-viewer component,
    // override its levels using descriptors so people land on the
    // right global row even when they're structurally disconnected
    // from the viewer. Specifically for the uncle-by-marriage case,
    // his "Дядя" descriptor → -1 from viewer → moved to viewer-1.
    final descriptors = graphSnapshot?.viewerDescriptorByPersonId;
    if (viewerGlobalLevel != null &&
        descriptors != null &&
        descriptors.isNotEmpty) {
      for (final component in components) {
        if (viewerPerson != null && component.contains(viewerPerson.id)) {
          // The viewer's own component already has the right
          // structural levels — don't second-guess them.
          continue;
        }
        final levels = componentLevels[component];
        if (levels == null) continue;

        // Find anchor candidates in this component. Each anchor's
        // desired global level (viewerGlobalLevel + offset) maps
        // to a current level in the component; the difference is
        // the shift to apply to ALL members of this component to
        // align them to the viewer's coordinate space.
        final shifts = <int>[];
        for (final personId in component) {
          final descriptor = descriptors[personId];
          if (descriptor == null) continue;
          final offset = _generationOffsetFromRelationLabel(
            descriptor.primaryRelationLabel,
          );
          if (offset == null) continue;
          final currentLevel = levels[personId];
          if (currentLevel == null) continue;
          shifts.add((viewerGlobalLevel + offset) - currentLevel);
        }
        if (shifts.isEmpty) continue;

        // Use the median shift — robust against one weird
        // descriptor pulling everyone the wrong way.
        shifts.sort();
        final medianShift = shifts[shifts.length ~/ 2];
        if (medianShift == 0) continue;

        for (final entry in levels.entries.toList()) {
          levels[entry.key] = entry.value + medianShift;
        }
      }

      // Within-component anchor pass — for the viewer's OWN
      // component. Same idea as the cross-component median shift
      // above, but applied per-person: when an in-law (e.g.
      // "Дядя" by marriage) is connected to the viewer's main
      // family graph via a child edge but has no explicit spouse
      // edge to anchor him to his wife's row, his BFS-derived
      // level is wrong by exactly one. The descriptor knows
      // better, so we override.
      //
      // Critical safety: only override when the move respects
      // parent>child constraints in BOTH directions:
      //   * Person's level must end up > each in-component parent.
      //   * Person's level must end up < each in-component child.
      // If the move would violate either, the structural data is
      // tighter than the descriptor and we leave it alone.
      //
      // We loop until stable so that overriding a parent (e.g.
      // Vitya) ALSO pulls his children (e.g. Nastya) along —
      // the spouse-parity loop in _assignLevels will handle the
      // re-balance after each override.
      if (viewerPerson != null) {
        final viewerOwnComponent = components.firstWhere(
          (component) => component.contains(viewerPerson!.id),
          orElse: () => <String>{},
        );
        final levels = componentLevels[viewerOwnComponent];
        if (levels != null && viewerOwnComponent.isNotEmpty) {
          final maxIterations = viewerOwnComponent.length * 2 + 4;
          var changed = true;
          var iteration = 0;
          while (changed && iteration < maxIterations) {
            changed = false;
            iteration += 1;
            for (final personId in viewerOwnComponent) {
              if (personId == viewerPerson.id) continue;
              final descriptor = descriptors[personId];
              if (descriptor == null) continue;
              final offset = _generationOffsetFromRelationLabel(
                descriptor.primaryRelationLabel,
              );
              if (offset == null) continue;
              final desiredLevel = viewerGlobalLevel + offset;
              final currentLevel = levels[personId];
              if (currentLevel == null) continue;
              if (currentLevel == desiredLevel) continue;
              // Parent-child safety: don't pull a person below
              // their own children, don't push them above their
              // own parents, EVEN if the descriptor disagrees
              // with the BFS. Structural data wins on direction.
              final parents = childToParents[personId] ?? const <String>{};
              final children = parentToChildren[personId] ?? const <String>{};
              var safe = true;
              for (final parentId in parents) {
                if (!viewerOwnComponent.contains(parentId)) continue;
                final parentLevel = levels[parentId];
                if (parentLevel == null) continue;
                if (desiredLevel <= parentLevel) {
                  safe = false;
                  break;
                }
              }
              if (!safe) continue;
              for (final childId in children) {
                if (!viewerOwnComponent.contains(childId)) continue;
                final childLevel = levels[childId];
                if (childLevel == null) continue;
                if (desiredLevel >= childLevel) {
                  safe = false;
                  break;
                }
              }
              if (!safe) continue;
              // Spouse parity: if person has spouse(s) at OTHER
              // levels, snap them along.
              levels[personId] = desiredLevel;
              for (final spouseId
                  in spousesByPerson[personId] ?? const <String>{}) {
                if (viewerOwnComponent.contains(spouseId) &&
                    levels[spouseId] != desiredLevel) {
                  levels[spouseId] = desiredLevel;
                }
              }
              // Children of the moved person should be ONE row
              // below — set them now so the next iteration sees
              // the correct constraint when checking their own
              // descriptors.
              for (final childId in children) {
                if (viewerOwnComponent.contains(childId)) {
                  final newChildLevel = desiredLevel + 1;
                  if ((levels[childId] ?? 0) < newChildLevel) {
                    levels[childId] = newChildLevel;
                  }
                }
              }
              changed = true;
            }
          }
        }
      }
    }

    final nodePositions = <String, Offset>{};
    var offsetX = InteractiveFamilyTree.contentInsetHorizontal +
        InteractiveFamilyTree.nodeWidth / 2 +
        InteractiveFamilyTree.siblingSeparation;
    var maxBottomY = 0.0;

    for (final component in components) {
      final levels = componentLevels[component]!;
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

    // Cycle / runaway-loop guard. The BFS re-enqueues whenever a
    // spouse / sibling / child level disagrees, so a malformed graph
    // (e.g. user accidentally added "X is parent of Y" AND "Y is
    // parent of X") can loop forever. Worst-case stable BFS visits
    // each node O(component.size) times — anything beyond that is a
    // cycle, so we just bail with the levels we have.
    final maxBfsSteps = component.length * 16 + 16;
    var bfsSteps = 0;
    while (queue.isNotEmpty) {
      bfsSteps += 1;
      if (bfsSteps > maxBfsSteps) {
        debugPrint(
          'InteractiveFamilyTree._assignLevels: BFS exceeded '
          'safety cap ($maxBfsSteps) — likely cyclic relations. '
          'Falling back to current level assignments.',
        );
        break;
      }

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

    // Derive implicit couples from shared children: any two adults who
    // share at least one biological child should be treated as a couple
    // for layout purposes, even when no explicit spouse/partner relation
    // exists. Without this, a mother and a father that the user added
    // independently (only as "parent of me") end up on different rows.
    final impliedCouples = <String, Set<String>>{};
    for (final entry in parentToChildren.entries) {
      final parentA = entry.key;
      if (!component.contains(parentA)) continue;
      final children = entry.value.where(component.contains).toList();
      for (final childId in children) {
        for (final parentB in childToParents[childId] ?? const <String>{}) {
          if (parentB == parentA || !component.contains(parentB)) continue;
          impliedCouples
              .putIfAbsent(parentA, () => <String>{})
              .add(parentB);
        }
      }
    }

    // Final spouse-parity pass — runs even when there's no snapshot. The
    // earlier loops can leave a spouse pair on different rows when one
    // partner has parents in-tree and the other doesn't, or when adding a
    // sibling-in-law (e.g. an aunt) re-anchors one partner via a different
    // family unit.
    //
    // Iterate until stable: for each spouse pair, snap both to the row of
    // their lowest-level child minus one (the row that satisfies the
    // parent→child constraint), or to the max of their current levels if
    // they have no children. Sibling pairs follow the same max-rule.
    var changed = true;
    var safetyIterations = 0;
    final maxIterations = component.length * 2 + 8;
    while (changed && safetyIterations < maxIterations) {
      changed = false;
      safetyIterations += 1;

      // Spouses ↔ shared row. Anchored by their kids' row when possible.
      // Use both explicit spouse/partner relations AND implicit "shared-
      // child" pairings so a mother and father that the user added
      // independently still end up on the same row.
      for (final personId in component) {
        final spouseIds = <String>{
          ...(spousesByPerson[personId] ?? const <String>{}),
          ...(impliedCouples[personId] ?? const <String>{}),
        }.where(component.contains).toList(growable: false);
        if (spouseIds.isEmpty) continue;

        final pair = <String>{personId, ...spouseIds};
        final sharedChildren = <String>{};
        for (final memberId in pair) {
          for (final childId
              in parentToChildren[memberId] ?? const <String>{}) {
            if (component.contains(childId)) {
              sharedChildren.add(childId);
            }
          }
        }

        int targetLevel;
        if (sharedChildren.isNotEmpty) {
          // Parents go to one above the lowest-level child — that puts
          // them at the same generation as their kids' other parent set.
          targetLevel = max(
            0,
            sharedChildren
                    .map((childId) => levels[childId] ?? 0)
                    .reduce(min) -
                1,
          );
        } else {
          // No children — fall back to the highest current level among
          // the spouses (matches reference: spouses must share a row).
          targetLevel = pair
              .map((memberId) => levels[memberId] ?? 0)
              .reduce(max);
        }

        for (final memberId in pair) {
          if ((levels[memberId] ?? 0) != targetLevel) {
            levels[memberId] = targetLevel;
            changed = true;
          }
        }
      }

      // Siblings ↔ shared row. Anchored by their parents' row when known,
      // but bounded BELOW by each sibling's own children — otherwise the
      // sibling rule can pull a parent up out of their kids' row (e.g.
      // father is sibling-of-aunt at parent+1=1, but his own son is at
      // level 3 forcing parent at 2 to stay aligned with the mother).
      for (final personId in component) {
        final siblingIds = (siblingsByPerson[personId] ?? const <String>{})
            .where(component.contains)
            .toList(growable: false);
        if (siblingIds.isEmpty) continue;

        final pair = <String>{personId, ...siblingIds};
        final sharedParents = <String>{};
        for (final memberId in pair) {
          for (final parentId
              in childToParents[memberId] ?? const <String>{}) {
            if (component.contains(parentId)) {
              sharedParents.add(parentId);
            }
          }
        }

        // Floor — directly below the highest-level parent.
        final parentFloor = sharedParents.isNotEmpty
            ? sharedParents
                    .map((parentId) => levels[parentId] ?? 0)
                    .reduce(max) +
                1
            : pair.map((memberId) => levels[memberId] ?? 0).reduce(max);

        // Per-sibling floor from their own children, then take the
        // strongest constraint across the group so spouses with kids
        // don't drag back to parent+1.
        int targetLevel = parentFloor;
        for (final memberId in pair) {
          final ownChildren = (parentToChildren[memberId] ?? const <String>{})
              .where(component.contains)
              .toList(growable: false);
          if (ownChildren.isNotEmpty) {
            final childFloor = ownChildren
                    .map((childId) => levels[childId] ?? 0)
                    .reduce(min) -
                1;
            if (childFloor > targetLevel) {
              targetLevel = childFloor;
            }
          }
        }

        for (final memberId in pair) {
          if ((levels[memberId] ?? 0) != targetLevel) {
            levels[memberId] = targetLevel;
            changed = true;
          }
        }
      }
    }

    // ── Viewer-relation anchor pass ───────────────────────────────────
    // The structural BFS gets confused when one half of a couple has
    // strong anchors in-tree (e.g., wife is daughter of grandparents,
    // child of viewer's grandparent → anchored at parents' row) and
    // the other half has only a weak anchor (e.g., husband-by-marriage
    // with only one parent-of-cousin edge — gets dropped a generation
    // because his only kid floats up). In that case the BFS puts the
    // weakly-anchored spouse one row higher than they should be, and
    // their kid follows.
    //
    // The backend already computes a label for everyone relative to
    // the viewer (Дядя / Тётя / Двоюродная сестра / etc), and that
    // label encodes a clear generation offset. When the structural
    // level disagrees by exactly 1 row with what the relation label
    // demands, the label wins — same with the spouse-pairing rules,
    // we treat it as the "ground truth" the BFS should match.
    //
    // We're conservative: only override by ±1 (not ±2+), so a
    // genuinely-broken graph doesn't get yanked across the canvas
    // by a stale label. And the override re-runs the spouse-/kid-
    // anchor passes implicitly via _propagateLevelChange below.
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

    // Snapshot-based anchor: when none of the explicit parent/child/sibling
    // edges resolve to a placed position (orphan in the graph — e.g. a
    // cousin added before her parents were even claimed), fall back to
    // any already-placed person in the SAME family unit. The backend
    // groups co-resident family members into a unit so we treat them
    // as anchors of last resort. This keeps a freshly-added cousin
    // from drifting to the far right of her row.
    if (referenceCenters.isEmpty && graphSnapshot != null) {
      for (final memberId in group.memberIds) {
        for (final unit in graphSnapshot!.familyUnits) {
          final inUnit = unit.adultIds.contains(memberId) ||
              unit.childIds.contains(memberId);
          if (!inUnit) continue;
          for (final relativeId in [...unit.adultIds, ...unit.childIds]) {
            if (relativeId == memberId) continue;
            final placed = positions[relativeId];
            if (placed != null) {
              referenceCenters.add(placed.dx);
            }
          }
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
    final parentChildPairs = <String>{};

    String parentChildKey(String parentId, String childId) =>
        '$parentId::$childId';
    String spousePairKey(String a, String b) {
      final pair = [a, b]..sort();
      return pair.join('::');
    }

    for (final relation in relations) {
      final parentId = _parentIdFromRelation(relation);
      final childId = _childIdFromRelation(relation);
      if (parentId != null &&
          childId != null &&
          positions.containsKey(parentId) &&
          positions.containsKey(childId)) {
        if (parentChildPairs.add(parentChildKey(parentId, childId))) {
          connections.add(
            FamilyConnection(
              fromId: parentId,
              toId: childId,
              type: RelationType.parent,
            ),
          );
        }
        continue;
      }
      if (_isSpouseRelation(relation) &&
          positions.containsKey(relation.person1Id) &&
          positions.containsKey(relation.person2Id)) {
        final pairKey =
            spousePairKey(relation.person1Id, relation.person2Id);
        if (spousePairs.add(pairKey)) {
          final pair = [relation.person1Id, relation.person2Id]..sort();
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

    // Enrich connection lines from snapshot family units. Without this,
    // distant relatives the user adds via "cousin" / "aunt" / "niece"
    // relation types end up positioned correctly (because we already
    // enrich the layout adjacency from the same source) but with no
    // visible line connecting them to their parents — they appear as
    // floating cards. Drawing the parent → child line from the family
    // unit closes the loop.
    final snapshot = graphSnapshot;
    if (snapshot != null) {
      for (final unit in snapshot.familyUnits) {
        final adultIds = unit.adultIds
            .where(positions.containsKey)
            .toList(growable: false);
        final childIds = unit.childIds
            .where(positions.containsKey)
            .toList(growable: false);

        for (var i = 0; i < adultIds.length; i++) {
          for (var j = i + 1; j < adultIds.length; j++) {
            final a = adultIds[i];
            final b = adultIds[j];
            final key = spousePairKey(a, b);
            if (spousePairs.add(key)) {
              final pair = [a, b]..sort();
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

        for (final adultId in adultIds) {
          for (final childId in childIds) {
            if (parentChildPairs.add(parentChildKey(adultId, childId))) {
              connections.add(
                FamilyConnection(
                  fromId: adultId,
                  toId: childId,
                  type: RelationType.parent,
                ),
              );
            }
          }
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
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    // Reference `.gs-main`: 11px 700 ink-2; `.gs-sub`: 9.5px 600 ink-3 dimmed.
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 12, 8),
      decoration: BoxDecoration(
        color: tokens.surface.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: tokens.surfaceLine.withValues(alpha: 0.55),
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: AppTheme.sans(
              color: tokens.inkSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              height: 1.0,
            ),
          ),
          if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: AppTheme.sans(
                color: tokens.inkMuted,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
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
  final Color tokenInk;

  FamilyTreePainter(
    this.nodePositions,
    this.connections, {
    this.graphSnapshot,
    this.relations = const <FamilyRelation>[],
    Color? lineColor,
    Color? mutedLineColor,
    Color? spouseColor,
    Color junctionColor = const Color(0xFF8E9588),
  })  : tokenInk = lineColor ?? const Color(0xFF6E7766),
        // Reference lines: ink-muted at ~50% opacity, subtle warm undertone
        // for spouse vs family. We pull base colors from design tokens via
        // the section builder; fallbacks keep the painter usable in tests.
        spouseLinePaint = Paint()
          ..color = (spouseColor ?? const Color(0xFFB39B5C)).withValues(alpha: 0.55)
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke,
        spousePastLinePaint = Paint()
          ..color = (spouseColor ?? const Color(0xFFB39B5C)).withValues(alpha: 0.32)
          ..strokeWidth = 1.1
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke,
        familyLinePaint = Paint()
          ..color = (lineColor ?? const Color(0xFF6E7766)).withValues(alpha: 0.55)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke,
        mutedFamilyLinePaint = Paint()
          ..color = (mutedLineColor ?? const Color(0xFF8E9588)).withValues(alpha: 0.42)
          ..strokeWidth = 1.3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
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

    // Reference style: each parent→child connection is a single smooth cubic
    // bezier from the family junction (familyCenterX, parentBarY) to the
    // child top anchor, with control points at the vertical mid-line — gives
    // the connectors a soft S-curve instead of H-bus right angles.
    //
    // Reference SVG path:
    //   M${px},${py} C${px},${my} ${cx},${my} ${cx},${cy}
    final junction = Offset(familyCenterX, parentBarY);
    for (final anchor in anchors) {
      final my = (parentBarY + anchor.dy) / 2;
      final path = Path()
        ..moveTo(junction.dx, junction.dy)
        ..cubicTo(
          junction.dx, my,
          anchor.dx, my,
          anchor.dx, anchor.dy,
        );
      if (dashed) {
        _drawDashedPath(canvas, path, linePaint);
      } else {
        canvas.drawPath(path, linePaint);
      }
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

  /// Draws [path] with a dashed stroke by sampling along its [PathMetric] and
  /// extracting alternating sub-paths. Used for adoptive / non-biological
  /// parent-child connectors so they read as a softer attachment.
  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    const dashLength = 6.0;
    const gapLength = 4.0;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dashLength;
        final extracted = metric.extractPath(distance, next);
        canvas.drawPath(extracted, paint);
        distance = next + gapLength;
      }
    }
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
class _ConnectorRelationTypePicker extends StatelessWidget {
  const _ConnectorRelationTypePicker({
    required this.sourceName,
    required this.targetName,
  });

  final String sourceName;
  final String targetName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Кто такие друг другу?',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Выберите связь между «$sourceName» и «$targetName»',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _ConnectorRelationButton(
                  icon: Icons.escalator_warning_outlined,
                  label: 'Родитель → ребёнок',
                  // Source is the PARENT of the target — that's the
                  // direction the user dragged. If they meant
                  // "child of" they should drag the other way.
                  relationType: RelationType.parent,
                ),
                const SizedBox(width: 10),
                _ConnectorRelationButton(
                  icon: Icons.favorite_outline,
                  label: 'Супруги',
                  relationType: RelationType.spouse,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _ConnectorRelationButton(
                  icon: Icons.family_restroom_outlined,
                  label: 'Брат/сестра',
                  relationType: RelationType.sibling,
                ),
                const SizedBox(width: 10),
                _ConnectorRelationButton(
                  icon: Icons.more_horiz_rounded,
                  label: 'Другая связь',
                  relationType: RelationType.other,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Отмена'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact chip used as the LongPressDraggable.feedback during an
/// edge-first connect drag. Shows the source person's name on a
/// small accent pill so the user always sees what they're carrying.
/// We avoid using the full card as feedback because the card's
/// internal Column overflows when wrapped in the Overlay's
/// unbounded constraints.
class _ConnectorDragFeedbackChip extends StatelessWidget {
  const _ConnectorDragFeedbackChip({
    required this.label,
    required this.color,
    required this.foreground,
  });

  final String label;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cable_rounded, size: 16, color: foreground),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              label.isEmpty ? '...' : label,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Live preview line drawn from the long-pressed source card to
/// wherever the user's pointer currently is. Dashed + accent color
/// so the user reads it as "in progress, not yet a real edge".
/// Repainted only while the user is actively dragging — when the
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

class _ConnectorRelationButton extends StatelessWidget {
  const _ConnectorRelationButton({
    required this.icon,
    required this.label,
    required this.relationType,
  });

  final IconData icon;
  final String label;
  final RelationType relationType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).pop(relationType),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer
                  .withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(
                  alpha: 0.6,
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: theme.colorScheme.primary, size: 28),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
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

/// Compact "Новый человек" dialog used by the canvas-level
/// blank-card creator. Asks for the bare minimum to seed a person
/// node — name parts + gender — and pops with a `personData` map
/// the host pipes to family_tree_service.addRelative(...) WITHOUT
/// a follow-up createRelation call. Relations get added later by
/// the user via the edge-first connector.
///
/// Deliberately simpler than AddRelativeScreen — no birth/death
/// dates, no photo upload, no relationship-type picker. The user
/// is in flow ("I want to throw down a card and connect it"); we
/// keep the friction low. They can fill in details by tapping the
/// new card after it lands on the canvas.
class _BlankCardDialog extends StatefulWidget {
  const _BlankCardDialog();

  @override
  State<_BlankCardDialog> createState() => _BlankCardDialogState();
}

class _BlankCardDialogState extends State<_BlankCardDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  Gender _selectedGender = Gender.unknown;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  String _genderToWireString(Gender gender) {
    switch (gender) {
      case Gender.male:
        return 'male';
      case Gender.female:
        return 'female';
      default:
        return 'unknown';
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    Navigator.of(context).pop(<String, dynamic>{
      'firstName': firstName,
      if (lastName.isNotEmpty) 'lastName': lastName,
      'gender': _genderToWireString(_selectedGender),
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.person_add_alt_1_rounded,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Новый человек',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Сначала добавьте карточку, потом соедините её с другими длинным нажатием.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _firstNameController,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Имя',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Введите имя';
                    }
                    if (value.trim().length > 120) {
                      return 'Имя слишком длинное';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _lastNameController,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _save(),
                  decoration: const InputDecoration(
                    labelText: 'Фамилия (необязательно)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value != null && value.trim().length > 120) {
                      return 'Фамилия слишком длинная';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Пол',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                _BlankCardGenderRow(
                  selected: _selectedGender,
                  onChanged: (gender) =>
                      setState(() => _selectedGender = gender),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Отмена'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Добавить'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BlankCardGenderRow extends StatelessWidget {
  const _BlankCardGenderRow({
    required this.selected,
    required this.onChanged,
  });

  final Gender selected;
  final ValueChanged<Gender> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        _option(theme, Gender.male, 'Мужской', Icons.male_rounded),
        const SizedBox(width: 8),
        _option(theme, Gender.female, 'Женский', Icons.female_rounded),
        const SizedBox(width: 8),
        _option(theme, Gender.unknown, 'Не указан', Icons.help_outline_rounded),
      ],
    );
  }

  Widget _option(ThemeData theme, Gender gender, String label, IconData icon) {
    final isActive = selected == gender;
    final scheme = theme.colorScheme;
    return Expanded(
      child: Semantics(
        button: true,
        label: '$label, ${isActive ? "выбран" : "не выбран"}',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onChanged(gender),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              color: isActive
                  ? scheme.primaryContainer.withValues(alpha: 0.85)
                  : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive
                    ? scheme.primary
                    : scheme.outlineVariant.withValues(alpha: 0.5),
                width: isActive ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: isActive ? scheme.primary : scheme.onSurfaceVariant,
                  size: 22,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
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

/// Voltage-indicator dot — small accent-colored 💡 chip on cards
/// where the cross-tree matcher found candidates the user hasn't
/// linked or dismissed yet. Visual is intentionally subtle:
/// passive nudge, not an alert. Tap → popover with suggestion
/// list (host responsibility).
///
/// Why "voltage indicator" — the user described the feel they
/// wanted: "small bulb that lights up when there's something
/// to look at, doesn't pop modals on you 200 times".
class _IdentitySuggestionsBadge extends StatelessWidget {
  const _IdentitySuggestionsBadge({
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: count == 1
          ? 'Возможный дубликат в другом дереве'
          : 'Возможные дубликаты в других деревьях ($count)',
      child: Tooltip(
        message: count == 1
            ? 'Похоже, эта карточка есть и в другом вашем дереве'
            : '$count похожих карточек в других ваших деревьях',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer.withValues(alpha: 0.95),
                shape: BoxShape.circle,
                border: Border.all(
                  color: scheme.tertiary.withValues(alpha: 0.6),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: scheme.tertiary.withValues(alpha: 0.18),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Icon(
                Icons.lightbulb_outline_rounded,
                size: 15,
                color: scheme.tertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Phase 1.3 ⚠️ badge — appears on the bottom-right of a card
/// when at least one identity-field conflict is unresolved on
/// the linked person on this tree. Visual is more assertive
/// than the 💡 badge (error-tinted vs. tertiary, always visible
/// regardless of hover) because the meaning is also more
/// urgent: data diverged, the user needs to pick a side.
///
/// Tap → host opens the resolve sheet. The sheet is owned by
/// tree_view_screen so it can wire to the service and refresh
/// counts after resolution.
class _IdentityConflictsBadge extends StatelessWidget {
  const _IdentityConflictsBadge({
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: count == 1
          ? 'Конфликт правок: одна карточка'
          : 'Конфликты правок: $count полей',
      child: Tooltip(
        message: count == 1
            ? 'Поле этой карточки расходится с другой веткой — нажмите, чтобы выбрать значение'
            : '$count полей расходятся с другой веткой — нажмите, чтобы разобраться',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.95),
                shape: BoxShape.circle,
                border: Border.all(
                  color: scheme.error.withValues(alpha: 0.6),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: scheme.error.withValues(alpha: 0.18),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 15,
                color: scheme.error,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
