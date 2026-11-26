import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math'; // <--- Добавляем импорт для функции min
import 'package:vector_math/vector_math_64.dart' as vector_math;
import '../backend/models/extended_network_slice.dart';
import '../models/family_person.dart';
import '../models/family_relation.dart';
import '../models/tree_graph_snapshot.dart';
import '../models/user_profile.dart';
import '../providers/extended_network_controller.dart';
import '../theme/app_theme.dart';
import '../utils/photo_url.dart';
import 'family_tree_node_card.dart';

part 'family_tree/family_tree_layout_models.dart';
part 'family_tree/family_tree_layout_engine.dart';
part 'family_tree/family_tree_painter.dart';
part 'family_tree/family_tree_overlay_painters.dart';
part 'family_tree/family_tree_connector_widgets.dart';
part 'family_tree/family_tree_blank_card_dialog.dart';
part 'family_tree/family_tree_badges.dart';
part 'family_tree/interactive_tree_viewport.dart';
part 'family_tree/interactive_tree_interactions.dart';
part 'family_tree/interactive_tree_nodes.dart';
part 'family_tree/interactive_tree_surface.dart';

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

  /// Horizontal pixels reserved at the left/right edges (e.g. desktop
  /// "Карта рода" sidebar and right zoom dock). Defaults to 0.
  final double viewportReservedLeft;
  final double viewportReservedRight;

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
  // Horizontal canvas inset on both sides. The left side has to
  // host the generation gutter badges ("Поколение 2 / Молчаливое /
  // Зумеры"), which can run up to ~180px wide. With the previous
  // 72px inset the leftmost card ended up sitting on top of its
  // own badge — user reported "карточки перекрывают поколения".
  // 200px gives badges a real strip on the left without crowding
  // the cards. Bump this in lockstep with the labelLeft offset in
  // _buildGenerationGuideWidgets if you change the gutter design.
  static const double contentInsetHorizontal = 200;
  static const double contentInsetTop = 80;
  static const double contentInsetBottom = 40;
  // Reserved width for the generation gutter badges on the left
  // side of the canvas. Keep in sync with contentInsetHorizontal —
  // labels are clamped to (gutter - 12) so they can never visually
  // crash into the leftmost card.
  static const double generationGutterWidth = 188;

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
    this.viewportReservedLeft = 0,
    this.viewportReservedRight = 0,
    this.showInlineEditPanel = true,
    this.selectionMode = false,
    this.selectedPersonIds = const <String>{},
    this.onPersonSelectionToggle,
    this.viewMode = ExtendedNetworkMode.mine,
    this.networkSlice,
    // Phase 4 chunk 4a: foreign node tap callback. Когда extended
    // render active && tapped person is foreign → invoke ПЕРЕД
    // legacy onPersonTap. Host (`tree_view_screen`) attaches
    // showModalBottomSheet с ForeignNodeSheet. Null → fallback на
    // legacy onPersonTap (own person либо mine view).
    this.onForeignNodeTap,
  });

  /// Multi-select mode for bulk operations on canvas (e.g. «выделить
  /// родню по маминой линии и одной кнопкой добавить в ветку
  /// «Мамина линия»»). When true:
  ///   - Tap on a card calls [onPersonSelectionToggle] instead of
  ///     [onPersonTap] — no inspector, no profile open.
  ///   - Long-press connector (relation creation) is disabled —
  ///     selection mode owns the gesture.
  ///   - Cards in [selectedPersonIds] render with an accent ring +
  ///     check overlay so the multi-select state is visible at a
  ///     glance even when the user pans/zooms.
  /// Edit-mode short-circuits this — the two are mutually exclusive
  /// at the host level.
  final bool selectionMode;

  /// Person ids currently selected in selection mode. Cards check
  /// membership at render time; the host owns the source of truth.
  final Set<String> selectedPersonIds;

  /// Callback when the user taps a card while [selectionMode] is on.
  /// The host adds/removes the person from its selection set and
  /// re-renders the widget with the new [selectedPersonIds]. Null
  /// when the host doesn't support selection (read-only viewer, etc.)
  /// — selection mode falls back to no-op tapping.
  final void Function(FamilyPerson)? onPersonSelectionToggle;

  // ── Phase 4 extended-network rendering ──────────────────────────

  /// View mode для extended-network rendering. `mine` отрисовывает
  /// только tree собственника; `extended` (+ non-null [networkSlice])
  /// активирует foreign-aware визуальные элементы (tint, edge color,
  /// foreign-node sheet).
  final ExtendedNetworkMode viewMode;

  /// Extended network slice (Phase 4 chunk 1 endpoint payload).
  /// Pass'ится из tree_view_screen когда viewMode == extended; null
  /// в mine mode. Несёт `ownerMap` для foreign-detection и
  /// `graphPersons.hopDistance` для generation filters.
  final ExtendedNetworkSlice? networkSlice;

  /// Phase 4 chunk 4a: foreign node tap callback. Host owns sheet
  /// lifecycle (`showModalBottomSheet`, navigation на chat / details,
  /// services). Widget просто detects + delegates. Когда `null` либо
  /// extended render inactive → fallback на [onPersonTap].
  final ValueChanged<FamilyPerson>? onForeignNodeTap;

  @override
  State<InteractiveFamilyTree> createState() => _InteractiveFamilyTreeState();
}

class _InteractiveFamilyTreeState extends State<InteractiveFamilyTree> {
  static const double _doubleTapZoomFactor = 1.5;
  static const double _doubleTapFitFallbackScale = 2.2;

  // Space reserved inside the viewport when fitting/focusing the tree —
  // keeps cards from appearing under floating chrome (toolbar, desktop
  // "Карта рода" sidebar, bottom sheet).
  double get _viewportReservedTop => widget.viewportReservedTop;
  double get _viewportReservedBottom => widget.viewportReservedBottom;
  double get _viewportReservedLeft => widget.viewportReservedLeft;
  double get _viewportReservedRight => widget.viewportReservedRight;

  /// Единственная точка где render path branches на extended-network
  /// mode. Используется card constructor для tint + edge-color +
  /// foreign-node sheet activation.
  bool get _isExtendedRenderActive {
    return widget.viewMode == ExtendedNetworkMode.extended &&
        widget.networkSlice != null;
  }

  /// Phase 4 chunk 4b hotfix: foreign-node Set keyed на **legacy
  /// tree-scoped person.id** (NOT identity id). Painter receives
  /// FamilyConnection.fromId/toId которые tree-scoped; card consumer
  /// получает `person.id`. Set must align с tree-scoped scheme.
  ///
  /// Earlier chunk 3b/3c versions returned `slice.ownerMap.keys.toSet()`
  /// (identity ids) — bug. Card tint never activated в production
  /// (`person.id ∉ identityIds` for most persons). Surface'нулся
  /// при chunk 4b design analysis (DECISIONS.md 2026-05-12 chunk 4b
  /// follow-up — see commit message).
  ///
  /// Algorithm: take slice's foreign identityIds set → map к tree-
  /// scoped person.id values via `_treePeople` lookup. Person'ы
  /// чьё identityId matches foreign set → их legacy person.id в
  /// результат.
  ///
  /// Slice's `ownerMap` остаётся sparse — keys identityIds (viewer-
  /// owned implicit). O(1) lookup preserved для both consumers.
  Set<String> get _foreignPersonIds {
    if (!_isExtendedRenderActive) return const <String>{};
    final slice = widget.networkSlice;
    if (slice == null) return const <String>{};
    final foreignIdentityIds = slice.ownerMap.keys.toSet();
    if (foreignIdentityIds.isEmpty) return const <String>{};
    final result = <String>{};
    for (final entry in widget.peopleData) {
      final person = entry['person'];
      if (person is FamilyPerson) {
        final iid = person.identityId;
        if (iid != null && foreignIdentityIds.contains(iid)) {
          result.add(person.id);
        }
      }
    }
    return result;
  }

  /// Phase 4 chunk 3b: foreign-node detection per-person.
  /// Defensive default-to-own (DECISIONS.md 2026-05-12 Q2):
  ///   • если slice null → all own (mine mode либо not capable).
  ///   • если person.id отсутствует в slice.graphPersons →
  ///     treat as own, debugPrint warning для surface upstream
  ///     inconsistency.
  ///   • иначе O(1) check через cached Set.
  bool _isPersonForeign(String personId) {
    if (!_isExtendedRenderActive) return false;
    final slice = widget.networkSlice;
    if (slice == null) return false;
    final foreignIds = _foreignPersonIds;
    if (foreignIds.contains(personId)) return true;
    // Defensive: validate that person.id is at all in slice (own
    // OR foreign). If not — data inconsistency.
    final personIsInSlice =
        slice.graphPersons.any((entry) => entry.id == personId);
    if (!personIsInSlice) {
      debugPrint(
        '[phase-4 chunk 3b/3c] person $personId rendered but not '
        'in extended slice — possible data inconsistency. Falling '
        'back to "own" tint.',
      );
    }
    return false;
  }

  // Данные для CustomPainter
  Map<String, Offset> nodePositions = {}; // ID человека -> его позиция (центр)
  Map<String, Offset> _automaticNodePositions = {};
  List<FamilyConnection> connections = []; // Список связей для отрисовки линий
  Size treeSize = Size.zero; // Общий размер дерева для CustomPaint и Stack
  final TransformationController _transformationController =
      TransformationController();
  Size? _viewportSize;
  bool _hasAppliedViewportFit = false;
  // K (culling): the inflated scene rect whose nodes were built on the last
  // frame. Read by the transform listener to decide when a pan/zoom has moved
  // outside the built set and a rebuild is needed. Null = culling disabled
  // (no viewport yet) → build all.
  Rect? _lastCulledRect;
  String? _selectedEditPersonId;
  double _currentScale = 1.0;
  // Transient zoom HUD (audit #16/#20): a brief bottom-center pill that
  // confirms a zoom/fit/center action then fades, instead of a pill that
  // sat there persistently. `_zoomHudReady` gates it off during the
  // initial auto-fit so it doesn't flash on every screen open.
  String _zoomHudText = '';
  bool _zoomHudVisible = false;
  bool _zoomHudReady = false;
  Timer? _zoomHudTimer;
  // L (lost-user recovery): with constrained:false + a huge boundaryMargin, a
  // tiny minScale blob can be dragged fully off every viewport edge into blank
  // canvas with no landmark. When that happens, show a floating «Вернуться к
  // дереву» pill → _fitTreeToViewport(). Additive overlay only — no pan/zoom/
  // layout config is touched. Debounced so a quick pan past the edge and back
  // doesn't flash it.
  bool _treeOffscreen = false;
  Timer? _offscreenDebounceTimer;
  String? _draggingPersonId;
  String? _hoveredPersonId;
  // Floating zoom dock starts collapsed on compact viewports so it
  // doesn't overlap person cards (user feedback "все мешается").
  // Tap on the chevron expands the column.
  bool _controlDockExpanded = false;

  // Lasso (Step 4 of the audience-model RFC). Active only while
  // the host is in `selectionMode`. Drag-on-empty inside the
  // canvas paints a translucent rectangle and live-previews which
  // cards intersect it. On release we add every previewed person
  // to the host's selection set via `onPersonSelectionToggle` —
  // strictly additive: lasso never UN-picks something the user
  // had already tapped, the gesture is for inflating selection,
  // not toggling it.
  Offset? _lassoStartCanvas;
  Offset? _lassoCurrentCanvas;
  Set<String> _lassoPreviewIds = const <String>{};

  // Double-tap зум: позиция второго тапа (onDoubleTapDown приходит до
  // onDoubleTap). Живёт здесь — sections.dart это extension, полей
  // объявлять не может.
  Offset? _doubleTapLocalPosition;

  /// Public toggle for the control-dock state, callable from the
  /// extension methods in interactive_family_tree_sections.dart.
  /// Direct `setState` from extensions trips the protected-member
  /// analyzer rule, so we hop through this helper.

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
  final FocusNode _connectModeFocusNode =
      FocusNode(debugLabel: 'tree-connect-mode');

  @override
  void initState() {
    super.initState();
    _selectedEditPersonId = widget.selectedEditPersonId;
    _transformationController.addListener(_handleTransformChanged);
    // Separate listener (not gated by the scale-delta guard) so translation-
    // only pans are seen for the off-screen recovery pill.
    _transformationController.addListener(_evaluateTreeOffscreen);
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
  @override
  void dispose() {
    _zoomHudTimer?.cancel();
    _offscreenDebounceTimer?.cancel();
    _transformationController.removeListener(_handleTransformChanged);
    _transformationController.removeListener(_evaluateTreeOffscreen);
    _transformationController.dispose();
    _connectModeFocusNode.dispose();
    super.dispose();
  }

  // Метод для расчета позиций узлов и связей
  void _calculateLayout() {
    if (widget.peopleData.isEmpty) {
      // Дерево опустело: сбрасываем pill «Вернуться к дереву» и гасим
      // in-flight debounce, иначе он останется висеть над пустым канвасом —
      // _evaluateTreeOffscreen после этого рано выходит на treeSize==zero и
      // уже не может снять флаг (единственный сброс — в _fitTreeToViewport,
      // который тут не вызывается).
      _offscreenDebounceTimer?.cancel();
      _offscreenDebounceTimer = null;
      setState(() {
        nodePositions = {};
        _automaticNodePositions = {};
        connections = [];
        treeSize = Size.zero;
        _treeOffscreen = false;
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

  void _updateTreeState(VoidCallback update) {
    if (!mounted) {
      return;
    }
    setState(update);
  }
}
