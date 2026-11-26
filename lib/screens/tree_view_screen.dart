import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart'; // Импортируем Provider
import 'package:get_it/get_it.dart';

import '../backend/backend_runtime_config.dart';
import '../backend/interfaces/blood_relation_capable_family_tree_service.dart';
import '../backend/interfaces/bulk_import_capable_family_tree_service.dart';
import '../backend/interfaces/identity_conflicts_capable_family_tree_service.dart';
import '../backend/interfaces/identity_suggestions_capable_family_tree_service.dart';
import '../backend/interfaces/semya_capable_family_tree_service.dart';
import '../backend/interfaces/semya_manage_capable_family_tree_service.dart';
import '../backend/models/blood_relation.dart';
import '../backend/models/semya.dart';
import '../backend/models/identity_field_conflict.dart';
import '../backend/models/identity_suggestion.dart';
import '../models/family_person.dart';
import '../models/family_relation.dart';
import '../models/family_tree.dart';
import '../widgets/identity_conflicts_sheet.dart';
import '../backend/interfaces/extended_network_capable_family_tree_service.dart';
import '../backend/models/extended_network_slice.dart';
import '../providers/extended_network_controller.dart';
import '../widgets/extended_network_empty_state.dart';
import '../widgets/extended_network_filter_sheet.dart';
import '../widgets/extended_network_filter_sidebar.dart';
import '../widgets/extended_network_search_sheet.dart';
import '../widgets/empty_tree_guided_cta.dart';
import '../widgets/relation_picker_sheet.dart';
import '../widgets/extended_network_toggle.dart';
import '../widgets/branch_switcher_chip.dart';
import '../widgets/semya_context_badge.dart';
import '../widgets/foreign_node_sheet.dart';
import '../widgets/interactive_family_tree.dart';
import '../widgets/safe_delete_confirmation_dialog.dart';
import '../widgets/tree_history_sheet.dart';
import '../widgets/tree_person_action_sheet.dart';
import '../widgets/glass_panel.dart';
import 'semya_details_screen.dart';
import '../providers/tree_provider.dart'; // Импортируем TreeProvider
import 'package:go_router/go_router.dart'; // Для навигации
import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/chat_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/tree_graph_capable_family_tree_service.dart';

import '../services/app_status_service.dart';
import '../services/custom_api_diagnostics_service.dart';
import '../services/public_tree_link_service.dart';
import '../services/local_storage_service.dart';
import '../services/tree_mutation_history.dart';
import '../services/tree_refresh_coordinator.dart';
import '../models/tree_graph_snapshot.dart';
import '../theme/app_theme.dart';
import '../utils/user_facing_error.dart';
import '../utils/e2e_state_bridge.dart';
import '../utils/photo_url.dart';
import '../utils/relative_details_route.dart';
import '../utils/russian_plural.dart';
import '../utils/snackbar.dart';
import '../widgets/dont_fear_breaking_banner.dart';

part 'tree/tree_topbar_widgets.dart';
part 'tree/tree_identity_suggestions_sheet.dart';
part 'tree/tree_blood_relation_sheet.dart';
part 'tree/tree_diagnostics_builder.dart';
part 'tree/tree_topbar_section.dart';
part 'tree/tree_context_panels.dart';
part 'tree/tree_canvas_section.dart';
part 'tree/tree_person_sheets.dart';
part 'tree/tree_selection_bulk_section.dart';
part 'tree/tree_mutations_section.dart';
part 'tree/tree_identity_and_search_section.dart';

class TreeViewScreen extends StatefulWidget {
  final String? routeTreeId;
  final String? routeTreeName;

  const TreeViewScreen({
    super.key,
    this.routeTreeId,
    this.routeTreeName,
  });

  /// A-CTA: сброс session-dismiss гида между тестами.
  @visibleForTesting
  static void debugResetGuidedCtaDismissal() {
    _TreeViewScreenState._guidedCtaDismissedThisSession = false;
  }

  @override
  State<TreeViewScreen> createState() => _TreeViewScreenState();
}

class _TreeViewScreenState extends State<TreeViewScreen>
    with WidgetsBindingObserver {
  final FamilyTreeServiceInterface _familyService =
      GetIt.I<FamilyTreeServiceInterface>();
  final AuthServiceInterface _authService = GetIt.I<AuthServiceInterface>();
  final ChatServiceInterface _chatService = GetIt.I<ChatServiceInterface>();
  final AppStatusService _appStatusService = GetIt.I<AppStatusService>();
  final LocalStorageService _localStorageService =
      GetIt.I<LocalStorageService>();

  // Map<String, dynamic> _graphData = {'nodes': [], 'edges': []}; // Больше не нужно
  bool _isLoading = true;
  String _errorMessage = '';
  // A-CTA: пользователь закрыл блокирующий гид «добавь близких». Static —
  // переживает пересоздание экрана в рамках сессии, сбрасывается рестартом.
  // Закрыт → показываем канвас с FAB вместо гида.
  static bool _guidedCtaDismissedThisSession = false;
  bool _isEditMode = false; // <<< Добавляем состояние режима редактирования
  // Multi-select mode for bulk operations on the canvas — entered
  // via the toolbar action, exited explicitly by the user (or auto-
  // exits when the user opens edit mode, which owns long-press).
  // The set is the source of truth; it survives until the user
  // closes selection mode or completes a bulk action.
  bool _isSelectionMode = false;
  final Set<String> _selectedPersonIds = <String>{};
  TreeProvider? _treeProviderInstance; // Храним экземпляр
  String? _currentTreeId;
  // Auto-refresh wiring (Phase B): coordinator hands us a callback
  // identity so unregister can identity-check ours vs. another
  // screen's. We hold the function reference for the same reason —
  // bound method tear-off would create a fresh closure each access,
  // breaking identical().
  String? _refreshCoordinatorTreeId;
  late final Future<void> Function() _treeRefreshCallback =
      _handleCoordinatorRefresh;
  String? _branchRootPersonId;
  String? _selectedPersonSheetId;
  String? _selectedEditPersonId;
  // After a successful blank-card creation we set this to the new
  // person's id; the InteractiveFamilyTree picks it up via
  // `recenterOnPersonId` and snaps the viewport to center on the
  // newly-dropped card. Without this the user can lose the card
  // when zoomed into another branch.
  String? _recenterOnPersonIdAfterReload;
  // Phase 1.2 voltage-indicator matcher: per-person count of
  // medium+high confidence cross-tree suggestions. Drives the 💡
  // dot on the canvas. Lazily populated after the tree loads —
  // we don't gate the initial render on this.
  Map<String, int> _identitySuggestionCounts = const <String, int>{};
  // Phase 1.3 edit-time conflict surfacing: per-person count of
  // unresolved identity-field conflicts on this tree. Drives the
  // ⚠️ dot. Same loading model as suggestions — fetch in the
  // background, render when ready, no gate on first paint.
  // Cached full conflict list so the tap handler doesn't refetch
  // (one HTTP roundtrip per tree-load instead of per-tap).
  Map<String, int> _identityConflictCounts = const <String, int>{};
  List<IdentityFieldConflict> _identityConflictsCache =
      const <IdentityFieldConflict>[];
  // Reference design pattern: bottom sheet starts collapsed (peek bar with
  // avatar + name + meta + chevron) and expands on tap to reveal action row
  // and full info. Reset to collapsed whenever selection changes.
  bool _personSheetExpanded = false;
  // Compact (mobile) chrome — info card / quick actions / health panel —
  // is collapsed by default so the canvas takes ~85% of the viewport.
  // Tap on the chevron in the top toolbar toggles it open.
  bool _compactChromeCollapsed = true;
  FamilyTree? _currentTreeMeta;
  Map<String, Offset> _manualNodePositions = <String, Offset>{};
  TreeGraphSnapshot? _graphSnapshot;
  // <<< НОВОЕ СОСТОЯНИЕ: Флаг, добавлен ли текущий пользователь в дерево >>>
  bool _currentUserIsInTree = true; // Изначально true, пока не проверили

  bool get _isFriendsTree => _currentTreeMeta?.isFriendsTree == true;

  // ── Ship FE4 (2026-05-26): семя context state ──
  //
  // Resolved при tree load — if active tree bound к семя (per Ship 5
  // tree.semyaId), we fetch SemyaDetails to learn caller's role.
  // Used to gate edit/add/delete UI affordances per ENTITY-DESIGN §2.1
  // role matrix. Null означает либо unbound tree (legacy / personal) либо
  // не yet loaded / fetch failed → треат как owner-equivalent (legacy
  // compat — don't accidentally hide controls для self-owned trees).
  SemyaDetails? _currentSemyaContext;

  /// Ship FE7 (2026-05-26): caller's personally-hidden person IDs
  /// для current семя. Empty list когда tree unbound либо никто
  /// не скрыт. Server filters tree-routes per этой list — поэтому
  /// frontend не re-filters локально (just re-fetches после toggle).
  /// Used к gate «Скрыть / Показывать снова» tile в action sheet.
  List<String> _hiddenPersonIds = const <String>[];

  /// Convenience: caller's role в active семья (null когда unbound).
  SemyaRole? get _callerSemyaRole => _currentSemyaContext?.callerRole;

  /// True when caller has mutation rights (owner либо editor) — либо
  /// tree unbound (legacy/personal trees default to full access).
  bool get _canEditCurrentTree {
    final role = _callerSemyaRole;
    if (role == null) return true; // unbound либо not loaded → legacy full
    return role == SemyaRole.owner || role == SemyaRole.editor;
  }

  /// Convenience flag для viewer-role gating (inverse of edit access).
  bool get _isViewerOnly => !_canEditCurrentTree;

  // Phase 4 chunk 2: per-tree state для mode toggle + filter panel.
  // Создаётся когда tree selected (см. _syncExtendedNetworkController),
  // dispose'ится в State.dispose(). НЕ менять interactive_family_tree
  // — это chunk 3 work.
  ExtendedNetworkController? _extendedNetworkController;

  TreeGraphCapableFamilyTreeService? get _graphTreeService {
    final service = _familyService;
    if (service is TreeGraphCapableFamilyTreeService) {
      return service as TreeGraphCapableFamilyTreeService;
    }
    return null;
  }

  ExtendedNetworkCapableFamilyTreeService? get _extendedNetworkService {
    final service = _familyService;
    if (service is ExtendedNetworkCapableFamilyTreeService) {
      return service as ExtendedNetworkCapableFamilyTreeService;
    }
    return null;
  }

  void _syncExtendedNetworkController(String? treeId) {
    if (treeId == null || treeId.isEmpty) {
      _extendedNetworkController?.removeListener(_onExtendedNetworkChange);
      _extendedNetworkController?.dispose();
      _extendedNetworkController = null;
      return;
    }
    if (_extendedNetworkController?.treeId == treeId) return;
    _extendedNetworkController?.removeListener(_onExtendedNetworkChange);
    _extendedNetworkController?.dispose();
    _extendedNetworkController = ExtendedNetworkController(
      treeId: treeId,
      service: _extendedNetworkService,
    );
    _extendedNetworkController!.addListener(_onExtendedNetworkChange);
  }

  void _onExtendedNetworkChange() {
    // Phase 4 chunk 3a: controller updates (mode / filter / slice
    // fetch result) → tree_view_screen rebuild чтобы пробросить
    // свежие viewMode / networkSlice в InteractiveFamilyTree.
    // Chunk 3a const flag = false; rebuild по сути no-op для canvas.
    // Chunk 3b/3c активирует actual render branching.
    if (!mounted) return;
    setState(() {});
  }

  String _describeTreeActionError(
    Object error, {
    required String fallbackMessage,
  }) {
    return describeUserFacingError(
      authService: _authService,
      error: error,
      fallbackMessage: fallbackMessage,
    );
  }

  List<FamilyPerson> get _treePeople => _relativesData
      .map((entry) => entry['person'])
      .whereType<FamilyPerson>()
      .toList();

  FamilyPerson? get _selectedEditPerson {
    final selectedId = _selectedEditPersonId;
    if (selectedId == null) {
      return null;
    }
    for (final person in _treePeople) {
      if (person.id == selectedId) {
        return person;
      }
    }
    return null;
  }

  FamilyPerson? get _selectedPersonSheetPerson {
    final selectedId = _selectedPersonSheetId;
    if (selectedId == null) {
      return null;
    }
    for (final person in _treePeople) {
      if (person.id == selectedId) {
        return person;
      }
    }
    return null;
  }

  void _updateSectionState(VoidCallback update) {
    setState(update);
  }

  /// Selection-mode "smart expansion" helpers — used by the toolbar
  /// «Расширить» action. Walking parent/child edges across the
  /// loaded `_relationsData` is enough; we don't need the full
  /// graph snapshot because relations on a single tree are a
  /// closed set. Sibling / spouse / in-law edges are intentionally
  /// IGNORED here — the user's intent in selecting "по маминой
  /// линии" is the blood lineage, and folding spouses in means
  /// the partner's whole family climbs aboard, which is rarely
  /// what they want at this step.

  List<Map<String, dynamic>> _relativesData = [];
  List<FamilyRelation> _relationsData = [];
  static bool _extendedEmptyDismissedThisSession = false;

  @override
  void initState() {
    super.initState();
    // Desktop convention — ESC clears the branch-focus / edit-selection
    // state without forcing the user to reach for the toolbar pill.
    // Same HardwareKeyboard pattern as the home / lightbox shortcuts:
    // Focus.onKeyEvent is unreliable on Flutter web's CanvasKit, so we
    // attach to the global handler instead.
    HardwareKeyboard.instance.addHandler(_handleTreeKeyEvent);
    // App-lifecycle hook — on resume we re-request a refresh для
    // currently viewed tree чтобы catch mutations, missed пока app
    // был backgrounded (push delivered, но silent notification
    // handler не ran потому что process suspended).
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _treeProviderInstance = Provider.of<TreeProvider>(context, listen: false);
      _treeProviderInstance!.addListener(_handleTreeChange); // Подписываемся
      _syncTreeFromRouteOrProvider();
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleTreeKeyEvent);
    WidgetsBinding.instance.removeObserver(this);
    _syncTreeRefreshSubscription(null);
    _treeProviderInstance?.removeListener(_handleTreeChange); // Отписываемся
    _extendedNetworkController?.removeListener(_onExtendedNetworkChange);
    _extendedNetworkController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Phase B auto-refresh: on resume re-trigger refresh для активного
    // tree. Coordinator's debounce coalesces with any concurrent push
    // arrival, so duplicate work не происходит. No-op если tree не
    // выбран либо subscriber unregistered (например screen в фоне
    // другого route).
    if (state != AppLifecycleState.resumed) return;
    final treeId = _refreshCoordinatorTreeId;
    if (treeId == null || treeId.isEmpty) return;
    TreeRefreshCoordinator.instance.requestRefresh(treeId);
  }

  /// Re-load the currently viewed tree. Called by
  /// [TreeRefreshCoordinator] when a `tree_mutated` push/realtime
  /// event arrives для зарегистрированного treeId. Identity-stable
  /// (single field assignment в State init) so coordinator's
  /// identical()-check unregister works.
  Future<void> _handleCoordinatorRefresh() async {
    if (!mounted) return;
    final treeId = _currentTreeId;
    if (treeId == null || treeId.isEmpty) return;
    await _loadData(treeId);
  }

  /// Re-point the [TreeRefreshCoordinator] subscription to [treeId].
  /// Idempotent — calling с тем же treeId no-op'ит. Passing `null`
  /// just unregisters (used on dispose, or когда tree selection
  /// cleared).
  void _syncTreeRefreshSubscription(String? treeId) {
    final previous = _refreshCoordinatorTreeId;
    if (previous == treeId) return;
    if (previous != null) {
      TreeRefreshCoordinator.instance.unregister(
        previous,
        _treeRefreshCallback,
      );
    }
    _refreshCoordinatorTreeId = null;
    if (treeId != null && treeId.isNotEmpty) {
      TreeRefreshCoordinator.instance.register(treeId, _treeRefreshCallback);
      _refreshCoordinatorTreeId = treeId;
    }
  }

  /// Returns true to consume the event so it doesn't bubble. Handles
  /// three desktop shortcuts:
  ///   * Esc — clear branch focus / edit selection
  ///   * Ctrl+Z (or Cmd+Z) — undo last tree mutation
  ///   * Ctrl+Shift+Z (or Cmd+Shift+Z) — redo
  /// Все три consume жест ТОЛЬКО когда есть что отменять / закрывать,
  /// иначе нормальное поведение клавиш (back gesture, browser-zoom)
  /// сохраняется.
  bool _handleTreeKeyEvent(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent) return false;

    final focused = FocusManager.instance.primaryFocus;
    final inEditable = focused?.context?.widget is EditableText ||
        (focused?.context != null &&
            focused!.context!.findAncestorWidgetOfExactType<EditableText>() !=
                null);
    if (inEditable) return false;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      final hadEditSelection = _selectedEditPersonId != null;
      final hadBranchFocus = _branchRootPersonId != null;
      if (!hadEditSelection && !hadBranchFocus) return false;
      setState(() {
        _selectedEditPersonId = null;
        _branchRootPersonId = null;
      });
      return true;
    }

    final keyZ = LogicalKeyboardKey.keyZ;
    if (event.logicalKey != keyZ) return false;
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final hasCmdOrCtrl = keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight) ||
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
    if (!hasCmdOrCtrl) return false;
    final hasShift = keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    if (!GetIt.I.isRegistered<TreeMutationHistory>()) return false;
    if (hasShift) {
      unawaited(_performRedo());
    } else {
      unawaited(_performUndo());
    }
    return true;
  }

  Future<void> _performUndo() async {
    final history = GetIt.I<TreeMutationHistory>();
    if (!history.canUndo) return;
    final desc = await history.undoForUi(_familyService);
    if (!mounted) return;
    if (_currentTreeId != null) {
      await _loadData(_currentTreeId!);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(desc != null ? 'Отменено: $desc' : 'Не удалось отменить'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _performRedo() async {
    final history = GetIt.I<TreeMutationHistory>();
    if (!history.canRedo) return;
    final desc = await history.redoForUi(_familyService);
    if (!mounted) return;
    if (_currentTreeId != null) {
      await _loadData(_currentTreeId!);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(desc != null ? 'Повторено: $desc' : 'Не удалось повторить'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _syncTreeFromRouteOrProvider() async {
    final routeTreeId = widget.routeTreeId;
    final routeTreeName = widget.routeTreeName;
    final provider = _treeProviderInstance;
    if (provider == null) {
      return;
    }

    if (routeTreeId != null && routeTreeId.isNotEmpty) {
      final currentId = provider.selectedTreeId;
      final currentName = provider.selectedTreeName;
      final needsSync = currentId != routeTreeId ||
          ((routeTreeName?.isNotEmpty ?? false) &&
              currentName != routeTreeName);

      if (needsSync) {
        await provider.selectTree(routeTreeId, routeTreeName);
        return;
      }

      _currentTreeId = routeTreeId;
      _syncExtendedNetworkController(routeTreeId);
      _syncTreeRefreshSubscription(routeTreeId);
      await _loadData(routeTreeId);
      return;
    }

    _currentTreeId = provider.selectedTreeId;
    _syncExtendedNetworkController(_currentTreeId);
    _syncTreeRefreshSubscription(_currentTreeId);
    if (_currentTreeId != null) {
      await _loadData(_currentTreeId!);
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Метод-обработчик изменений
  void _handleTreeChange() {
    if (!mounted) return;
    final newTreeId = _treeProviderInstance?.selectedTreeId;
    if (_currentTreeId != newTreeId) {
      debugPrint(
        'TreeView: Обнаружено изменение дерева с $_currentTreeId на $newTreeId',
      );
      _currentTreeId = newTreeId;
      _syncExtendedNetworkController(newTreeId);
      _syncTreeRefreshSubscription(newTreeId);
      if (_currentTreeId != null) {
        _loadData(_currentTreeId!);
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = '';
          _manualNodePositions = <String, Offset>{};
          _selectedPersonSheetId = null;
        });
      }
    }
  }

  // Метод загрузки данных, теперь принимает treeId
  Future<void> _loadData(String treeId) async {
    if (!mounted) return;
    debugPrint('TreeView: Загрузка данных для дерева $treeId');
    final hasCachedTreeData = _currentTreeMeta?.id == treeId &&
        (_relativesData.isNotEmpty || _relationsData.isNotEmpty);
    final graphTreeService = _graphTreeService;
    setState(() {
      _isLoading = !hasCachedTreeData;
      _errorMessage = '';
      _currentUserIsInTree = true;
      if (!hasCachedTreeData) {
        _relativesData = [];
        _relationsData = [];
        _manualNodePositions = <String, Offset>{};
        _graphSnapshot = null;
        _selectedPersonSheetId = null;
      }
    });

    try {
      if (_authService.currentUserId == null) {
        context.go('/login');
        return;
      }
      if (graphTreeService == null) {
        throw StateError(
          'Текущее подключение не поддерживает graph snapshot дерева.',
        );
      }

      late final List<FamilyPerson> relatives;
      late final List<FamilyRelation> relations;
      late final FamilyTree? treeMeta;
      late final SemyaDetails? semyaContext;
      // Ship FE4 (2026-05-26): added семя context fetch к parallel
      // load. Resolves caller's role когда tree bound к семя per
      // tree.semyaId (Ship 5). Result null когда unbound либо
      // capability service incapable — caller defaults к legacy
      // full-access mode.
      final loadResults = await Future.wait<Object?>([
        graphTreeService.getTreeGraphSnapshot(treeId),
        _loadCurrentTreeMeta(treeId),
        _resolveSemyaContextForTree(treeId),
      ]);
      final graphSnapshot = loadResults[0] as TreeGraphSnapshot;
      relatives = graphSnapshot.people;
      relations = graphSnapshot.relations;
      treeMeta = loadResults[1] as FamilyTree?;
      semyaContext = loadResults[2] as SemyaDetails?;
      // Ship FE7 originally fetched caller's hide list before first paint.
      // That made tree reloads feel slow after mutations: the canvas waited
      // for a secondary action-sheet detail. Keep the previous list when the
      // same семя is still active, paint the tree, then refresh hide state in
      // the background.
      final hiddenIds = semyaContext != null &&
              _currentSemyaContext?.semya.id == semyaContext.semya.id
          ? _hiddenPersonIds
          : const <String>[];
      debugPrint(
        'Загружено родственников: ${relatives.length}, связей: ${relations.length}'
        '${semyaContext != null ? '; семя: ${semyaContext.semya.name} '
            '(role: ${semyaContext.callerRole.serverValue})' : '; tree unbound'}',
      );

      if (!mounted) return;

      if (relatives.isEmpty) {
        debugPrint('Дерево $treeId пустое.');
        setState(() {
          _isLoading = false;
          _errorMessage = '';
          _relativesData = [];
          _relationsData = [];
          _currentTreeMeta = treeMeta;
          _currentSemyaContext = semyaContext;
          _hiddenPersonIds = hiddenIds;
          _manualNodePositions = <String, Offset>{};
          _graphSnapshot = graphSnapshot;
          _currentUserIsInTree = graphSnapshot.viewerPersonId != null;
          _selectedPersonSheetId = null;
        });
        unawaited(_refreshHiddenPersonIdsForLoadedSemya(
          treeId: treeId,
          semyaContext: semyaContext,
        ));
        return;
      }

      final List<Map<String, dynamic>> peopleData = [];
      final viewerDescriptors = graphSnapshot.viewerDescriptorByPersonId;
      for (var person in relatives) {
        peopleData.add({
          'person': person,
          'userProfile': null,
          'viewerDescriptor': viewerDescriptors[person.id],
        });
      }

      final savedPositions = await _localStorageService.getTreeNodePositions(
        treeId,
      );
      final visiblePersonIds = relatives.map((person) => person.id).toSet();
      final filteredPositions = <String, Offset>{};
      for (final entry in savedPositions.entries) {
        if (visiblePersonIds.contains(entry.key)) {
          filteredPositions[entry.key] = entry.value;
        }
      }

      // Сохраняем данные в состоянии для передачи в виджет
      if (mounted) {
        final branchRootStillExists = _branchRootPersonId == null ||
            relatives.any((person) => person.id == _branchRootPersonId);
        final selectedEditPersonStillExists = _selectedEditPersonId == null ||
            relatives.any((person) => person.id == _selectedEditPersonId);
        final selectedSheetPersonStillExists = _selectedPersonSheetId == null ||
            relatives.any((person) => person.id == _selectedPersonSheetId);
        setState(() {
          // Сохраняем исходные данные, а не построенный граф
          _relativesData = peopleData;
          _relationsData = relations;
          _currentTreeMeta = treeMeta;
          _currentSemyaContext = semyaContext;
          _hiddenPersonIds = hiddenIds;
          _manualNodePositions = filteredPositions;
          _graphSnapshot = graphSnapshot;
          _isLoading = false;
          _currentUserIsInTree = graphSnapshot.viewerPersonId != null;
          if (!branchRootStillExists) {
            _branchRootPersonId = null;
          }
          if (!selectedEditPersonStillExists) {
            _selectedEditPersonId = null;
          }
          if (!selectedSheetPersonStillExists) {
            _selectedPersonSheetId = null;
          }
        });
        // Phase 1.2 voltage-indicator: kick off cross-tree
        // suggestion fetches in the background. Doesn't block
        // first paint — when responses come in we update the
        // counts state and the canvas re-renders the 💡 dots.
        unawaited(_refreshIdentitySuggestionCounts(treeId, relatives));
        // Phase 1.3 edit-time conflicts: same fire-and-forget
        // pattern. One HTTP call covers every visible card —
        // /v1/trees/:treeId/conflicts is tree-scoped (vs.
        // suggestions, which is per-person — historical).
        unawaited(_refreshIdentityConflictCounts(treeId));
        unawaited(_refreshHiddenPersonIdsForLoadedSemya(
          treeId: treeId,
          semyaContext: semyaContext,
        ));
      }
    } catch (e, s) {
      debugPrint('Ошибка загрузки данных дерева $treeId: $e\\n$s');
      _appStatusService.reportError(
        e,
        fallbackMessage: 'Не удалось загрузить дерево.',
      );
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (!hasCachedTreeData) {
            _errorMessage = e is StateError
                ? 'Этот backend не поддерживает новый graph snapshot дерева.'
                : _appStatusService.isOffline
                    ? 'Нет соединения. Откройте дерево снова, когда интернет вернётся.'
                    : 'Не удалось загрузить данные дерева.';
          }
        });
      }
    }
  }

  // Добавляем переменные состояния для хранения данных

  @override
  Widget build(BuildContext context) {
    final treeProvider = Provider.of<TreeProvider>(context);
    final selectedTreeId = treeProvider.selectedTreeId ?? widget.routeTreeId;
    _publishTreeE2EState(selectedTreeId);

    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    if (selectedTreeId == null) {
      // Дерево — ядро продукта, и это первый экран новичка без дерева:
      // «Выберите дерево / Открыть» отправлял его в селектор искать то,
      // чего ещё нет. Без деревьев зовём создать прямо здесь (create-экран
      // сам выбирает новое дерево и возвращает на вкладку); селектор
      // предлагаем только тем, кому есть из чего выбирать.
      final hasTrees = treeProvider.availableTrees.isNotEmpty;
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(AppTheme.topbarHeight(context)),
          child: _buildTreeTopbar(
            theme: theme,
            tokens: tokens,
            selectedTreeId: null,
          ),
        ),
        body: _buildTreeState(
          icon: Icons.account_tree_outlined,
          title: hasTrees ? 'Выберите дерево' : 'Здесь будет ваше дерево',
          message: hasTrees
              ? 'Откройте одно из ваших деревьев.'
              : 'Добавьте себя и близких — схема семьи вырастет сама.',
          actions: hasTrees
              ? [
                  FilledButton.icon(
                    onPressed: () => context.go('/trees'),
                    icon: const Icon(Icons.list_alt),
                    label: const Text('Выбрать дерево'),
                  ),
                ]
              : [
                  FilledButton.icon(
                    key: const Key('tree-empty-create-family'),
                    onPressed: () => context.push('/trees/create'),
                    icon: const Icon(Icons.add),
                    label: const Text('Создать семью'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('tree-empty-create-friends'),
                    onPressed: () => context.push('/trees/create?kind=friends'),
                    icon: const Icon(Icons.diversity_3_outlined),
                    label: const Text('Круг друзей'),
                  ),
                ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        // Тот же токен, что у пустого состояния выше: хардкод 76 резервировал
        // меньше, чем занимает SafeArea + topbarContentHeight, и на телефонах
        // с высоким статус-баром сжимал заголовок и пилюли.
        preferredSize: Size.fromHeight(AppTheme.topbarHeight(context)),
        child: _buildTreeTopbar(
          theme: theme,
          tokens: tokens,
          selectedTreeId: selectedTreeId,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // The reassurance banner participates in layout instead of
            // covering the canvas toolbar and the first visible generation.
            if (!_isGuidedCtaActive) const DontFearBreakingBanner(),
            Expanded(
              child: _wrapWithExtendedNetworkLayout(
                context,
                _buildTreeBody(selectedTreeId: selectedTreeId),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Phase 4 chunk 2: wrap body в Provider + (optional) sidebar для
  /// wide layout + extended mode. Sidebar показывается ТОЛЬКО когда:
  ///   • controller существует и capable;
  ///   • mode == extended;
  ///   • screen width >= 1500 (== relatives_screen breakpoint).
  ///
  /// Sidebar НЕ менял canvas rendering — это chunk 3. Sidebar
  /// добавляется справа от existing body, занимая 280px.
}
