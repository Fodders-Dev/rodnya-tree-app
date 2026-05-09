import 'dart:async';
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
import '../backend/models/blood_relation.dart';
import '../backend/models/identity_field_conflict.dart';
import '../backend/models/identity_suggestion.dart';
import '../models/family_person.dart';
import '../models/family_relation.dart';
import '../models/family_tree.dart';
import '../widgets/interactive_family_tree.dart';
import '../widgets/tree_history_sheet.dart';
import '../widgets/glass_panel.dart';
import '../providers/tree_provider.dart'; // Импортируем TreeProvider
import 'package:go_router/go_router.dart'; // Для навигации
import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/chat_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/tree_graph_capable_family_tree_service.dart';

import '../services/app_status_service.dart';
import '../services/public_tree_link_service.dart';
import '../services/local_storage_service.dart';
import '../services/tree_mutation_history.dart';
import '../models/tree_graph_snapshot.dart';
import '../theme/app_theme.dart';
import '../utils/user_facing_error.dart';
import '../utils/e2e_state_bridge.dart';
import '../utils/photo_url.dart';

part 'tree_view_screen_sections.dart';

enum _TreeToolbarAction {
  refresh,
  openHistory,
  openRelatives,
  openChats,
  createPost,
  toggleEditMode,
  toggleSelectionMode,
  openBranchChat,
  openBranchDetails,
  copyPublicLink,
  resetBranchFocus,
  resetLayout,
}

/// Smart-selection options surfaced in the selection toolbar's
/// «Расширить» popup. Each one expands the user's current
/// selection set by walking parent / child edges from the
/// already-picked anchors — turning «one tap on mama» into «mama +
/// all her line».
enum _SelectionExpand {
  ancestors,
  descendants,
  lineage,
}

class SectionTitle extends StatelessWidget {
  final String title;

  const SectionTitle({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class TreeViewScreen extends StatefulWidget {
  final String? routeTreeId;
  final String? routeTreeName;

  const TreeViewScreen({
    super.key,
    this.routeTreeId,
    this.routeTreeName,
  });

  @override
  State<TreeViewScreen> createState() => _TreeViewScreenState();
}

class _TreeViewScreenState extends State<TreeViewScreen> {
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

  TreeGraphCapableFamilyTreeService? get _graphTreeService {
    final service = _familyService;
    if (service is TreeGraphCapableFamilyTreeService) {
      return service as TreeGraphCapableFamilyTreeService;
    }
    return null;
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
  Set<String> _expandSelectionWithAncestors(Iterable<String> seedIds) {
    final parentsOf = _buildParentEdges();
    final result = <String>{...seedIds};
    final queue = <String>[...seedIds];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final parents = parentsOf[current];
      if (parents == null) continue;
      for (final parent in parents) {
        if (result.add(parent)) {
          queue.add(parent);
        }
      }
    }
    return result;
  }

  Set<String> _expandSelectionWithDescendants(Iterable<String> seedIds) {
    final childrenOf = _buildChildEdges();
    final result = <String>{...seedIds};
    final queue = <String>[...seedIds];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final children = childrenOf[current];
      if (children == null) continue;
      for (final child in children) {
        if (result.add(child)) {
          queue.add(child);
        }
      }
    }
    return result;
  }

  Set<String> _expandSelectionWithLineage(Iterable<String> seedIds) {
    final withAncestors = _expandSelectionWithAncestors(seedIds);
    return _expandSelectionWithDescendants(withAncestors);
  }

  Map<String, Set<String>> _buildParentEdges() {
    final edges = <String, Set<String>>{};
    void link(String childId, String parentId) {
      edges.putIfAbsent(childId, () => <String>{}).add(parentId);
    }
    for (final relation in _relationsData) {
      if (relation.relation1to2 == RelationType.parent) {
        link(relation.person2Id, relation.person1Id);
      } else if (relation.relation1to2 == RelationType.child) {
        link(relation.person1Id, relation.person2Id);
      }
    }
    return edges;
  }

  Map<String, Set<String>> _buildChildEdges() {
    final edges = <String, Set<String>>{};
    void link(String parentId, String childId) {
      edges.putIfAbsent(parentId, () => <String>{}).add(childId);
    }
    for (final relation in _relationsData) {
      if (relation.relation1to2 == RelationType.parent) {
        link(relation.person1Id, relation.person2Id);
      } else if (relation.relation1to2 == RelationType.child) {
        link(relation.person2Id, relation.person1Id);
      }
    }
    return edges;
  }

  void _handleSelectionExpand(_SelectionExpand option) {
    if (_selectedPersonIds.isEmpty) return;
    final beforeCount = _selectedPersonIds.length;
    Set<String> expanded;
    String descriptor;
    switch (option) {
      case _SelectionExpand.ancestors:
        expanded = _expandSelectionWithAncestors(_selectedPersonIds);
        descriptor = 'предки';
        break;
      case _SelectionExpand.descendants:
        expanded = _expandSelectionWithDescendants(_selectedPersonIds);
        descriptor = 'потомки';
        break;
      case _SelectionExpand.lineage:
        expanded = _expandSelectionWithLineage(_selectedPersonIds);
        descriptor = 'вся линия';
        break;
    }
    final added = expanded.length - beforeCount;
    setState(() {
      _selectedPersonIds
        ..clear()
        ..addAll(expanded);
    });
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(
          added > 0
              ? 'Добавлено в выбор ($descriptor): $added'
              : 'Никого нового не нашлось — связи уже выбраны.',
        ),
      ),
    );
  }

  void _selectTreePerson(FamilyPerson person) {
    setState(() {
      if (_selectedPersonSheetId == person.id) {
        // Same node tapped twice — close sheet entirely.
        _selectedPersonSheetId = null;
        _personSheetExpanded = false;
      } else {
        _selectedPersonSheetId = person.id;
        _personSheetExpanded = false; // Always start collapsed.
      }
    });
  }

  void _clearSelectedTreePerson() {
    setState(() {
      _selectedPersonSheetId = null;
      _personSheetExpanded = false;
    });
  }

  void _togglePersonSheetExpansion() {
    setState(() {
      _personSheetExpanded = !_personSheetExpanded;
    });
  }

  void _publishTreeE2EState(String? selectedTreeId) {
    if (!E2EStateBridge.isEnabled) {
      return;
    }

    final people = _treePeople;
    final selectedPerson = _selectedEditPerson;
    final selectedSheetPerson = _selectedPersonSheetPerson;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      E2EStateBridge.publish(
        screen: 'tree',
        state: <String, dynamic>{
          'selectedTreeId': selectedTreeId,
          'currentTreeId': _currentTreeId,
          'treeName': _currentTreeMeta?.name ?? widget.routeTreeName,
          'isLoading': _isLoading,
          'isEditMode': _isEditMode,
          'branchRootPersonId': _branchRootPersonId,
          'selectedPersonSheetId': _selectedPersonSheetId,
          'selectedEditPersonId': _selectedEditPersonId,
          'selectedPersonSheet': selectedSheetPerson == null
              ? null
              : <String, dynamic>{
                  'id': selectedSheetPerson.id,
                  'name': selectedSheetPerson.name,
                  'photoCount': selectedSheetPerson.photoGallery.length,
                  'hasPrimaryPhoto':
                      selectedSheetPerson.primaryPhotoUrl != null,
                },
          'selectedEditPerson': selectedPerson == null
              ? null
              : <String, dynamic>{
                  'id': selectedPerson.id,
                  'name': selectedPerson.name,
                  'photoCount': selectedPerson.photoGallery.length,
                  'hasPrimaryPhoto': selectedPerson.primaryPhotoUrl != null,
                },
          'people': people
              .map(
                (person) => <String, dynamic>{
                  'id': person.id,
                  'name': person.name,
                  'photoCount': person.photoGallery.length,
                  'hasPrimaryPhoto': person.primaryPhotoUrl != null,
                },
              )
              .toList(),
        },
      );
    });
  }

  @override
  void initState() {
    super.initState();
    // Desktop convention — ESC clears the branch-focus / edit-selection
    // state without forcing the user to reach for the toolbar pill.
    // Same HardwareKeyboard pattern as the home / lightbox shortcuts:
    // Focus.onKeyEvent is unreliable on Flutter web's CanvasKit, so we
    // attach to the global handler instead.
    HardwareKeyboard.instance.addHandler(_handleTreeKeyEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _treeProviderInstance = Provider.of<TreeProvider>(context, listen: false);
      _treeProviderInstance!.addListener(_handleTreeChange); // Подписываемся
      _syncTreeFromRouteOrProvider();
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleTreeKeyEvent);
    _treeProviderInstance?.removeListener(_handleTreeChange); // Отписываемся
    super.dispose();
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
            focused!.context!
                    .findAncestorWidgetOfExactType<EditableText>() !=
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
        content: Text(desc != null ? 'Повторено: $desc' : 'Не удалось повторить'),
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
      await _loadData(routeTreeId);
      return;
    }

    _currentTreeId = provider.selectedTreeId;
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
      final loadResults = await Future.wait<Object?>([
        graphTreeService.getTreeGraphSnapshot(treeId),
        _loadCurrentTreeMeta(treeId),
      ]);
      final graphSnapshot = loadResults[0] as TreeGraphSnapshot;
      relatives = graphSnapshot.people;
      relations = graphSnapshot.relations;
      treeMeta = loadResults[1] as FamilyTree?;
      debugPrint(
        'Загружено родственников: ${relatives.length}, связей: ${relations.length}',
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
          _manualNodePositions = <String, Offset>{};
          _graphSnapshot = graphSnapshot;
          _currentUserIsInTree = graphSnapshot.viewerPersonId != null;
          _selectedPersonSheetId = null;
        });
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
  List<Map<String, dynamic>> _relativesData = [];
  List<FamilyRelation> _relationsData = [];

  @override
  Widget build(BuildContext context) {
    final treeProvider = Provider.of<TreeProvider>(context);
    final selectedTreeId = treeProvider.selectedTreeId ?? widget.routeTreeId;
    _publishTreeE2EState(selectedTreeId);
    final selectedTreeName = treeProvider.selectedTreeName ??
        widget.routeTreeName ??
        'Семейное дерево';

    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    if (selectedTreeId == null) {
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
          title: 'Выберите дерево',
          message: 'Здесь появится схема семьи.',
          actions: [
            FilledButton.icon(
              onPressed: () => context.go('/tree?selector=1'),
              icon: const Icon(Icons.list_alt),
              label: const Text('Открыть'),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(76),
        child: _buildTreeTopbar(
          theme: theme,
          tokens: tokens,
          selectedTreeId: selectedTreeId,
          treeName: selectedTreeName,
        ),
      ),
      body: SafeArea(
        child: _buildTreeBody(selectedTreeId: selectedTreeId),
      ),
    );
  }

  Widget _buildTreeTopbar({
    required ThemeData theme,
    required RodnyaDesignTokens tokens,
    required String? selectedTreeId,
    String? treeName,
  }) {
    // Same Android perf bypass as the other topbars — TreeView is
    // the most expensive screen anyway (canvas physics + many node
    // renders), so dropping the topbar's per-frame blur matters
    // even more here than on lighter screens.
    final useBlur = defaultTargetPlatform != TargetPlatform.android;
    final body = Container(
      decoration: BoxDecoration(
        color: tokens.surface.withValues(
          alpha: theme.brightness == Brightness.dark
              ? (useBlur ? 0.74 : 0.96)
              : (useBlur ? 0.78 : 0.97),
        ),
        border: Border(
          bottom: BorderSide(
            color: tokens.surfaceLine.withValues(alpha: 0.5),
            width: 0.6,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: AppTheme.topbarContentHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back_rounded, color: tokens.ink),
                  tooltip: 'К списку деревьев',
                  onPressed: () => context.go('/tree?selector=1'),
                ),
                Text(
                  _isFriendsTree ? 'Круг' : 'Дерево',
                  style: AppTheme.serif(
                    color: tokens.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.22,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (treeName != null && treeName.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: tokens.accentSoft,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        treeName,
                        style: AppTheme.sans(
                          color: tokens.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),
                _TreeTopbarPill(
                  tokens: tokens,
                  tooltip: 'Выбрать дерево',
                  onTap: () => context.go('/tree?selector=1'),
                  child: Icon(
                    Icons.account_tree_outlined,
                    size: 19,
                    color: tokens.ink,
                  ),
                ),
                // Undo / redo пилюли — появляются только когда есть
                // что отменять / повторять, чтобы не съедать место в
                // топбаре на узких экранах. ListenableBuilder
                // подписан на TreeMutationHistory, перерисовывается
                // на push/pop стека.
                if (selectedTreeId != null &&
                    GetIt.I.isRegistered<TreeMutationHistory>())
                  ListenableBuilder(
                    listenable: GetIt.I<TreeMutationHistory>(),
                    builder: (context, _) {
                      final history = GetIt.I<TreeMutationHistory>();
                      if (!history.canUndo && !history.canRedo) {
                        return const SizedBox.shrink();
                      }
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (history.canUndo) ...[
                            const SizedBox(width: 8),
                            _TreeTopbarPill(
                              tokens: tokens,
                              tooltip: 'Отменить · Ctrl+Z',
                              onTap: () => unawaited(_performUndo()),
                              child: Icon(
                                Icons.undo_rounded,
                                size: 19,
                                color: tokens.ink,
                              ),
                            ),
                          ],
                          if (history.canRedo) ...[
                            const SizedBox(width: 8),
                            _TreeTopbarPill(
                              tokens: tokens,
                              tooltip: 'Повторить · Ctrl+Shift+Z',
                              onTap: () => unawaited(_performRedo()),
                              child: Icon(
                                Icons.redo_rounded,
                                size: 19,
                                color: tokens.ink,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                if (selectedTreeId != null) ...[
                  const SizedBox(width: 8),
                  PopupMenuButton<_TreeToolbarAction>(
                    tooltip: 'Действия дерева',
                    onSelected: (action) =>
                        _handleTreeToolbarAction(selectedTreeId, action),
                    itemBuilder: (context) => _buildTreeToolbarMenuItems(),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: tokens.surfaceStrong,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: tokens.surfaceLine),
                      ),
                      child: Icon(
                        Icons.more_horiz_rounded,
                        size: 19,
                        color: tokens.ink,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (!useBlur) return body;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: body,
      ),
    );
  }

  Future<void> _handleTreeToolbarAction(
    String selectedTreeId,
    _TreeToolbarAction action,
  ) async {
    final branchRootPerson = _findBranchRootPerson();

    switch (action) {
      case _TreeToolbarAction.refresh:
        await _loadData(selectedTreeId);
        return;
      case _TreeToolbarAction.openHistory:
        await _showTreeHistorySheet();
        return;
      case _TreeToolbarAction.openRelatives:
        context.go('/relatives');
        return;
      case _TreeToolbarAction.openChats:
        context.go('/chats');
        return;
      case _TreeToolbarAction.createPost:
        context.push('/post/create');
        return;
      case _TreeToolbarAction.toggleEditMode:
        if (!mounted) {
          return;
        }
        setState(() {
          _isEditMode = !_isEditMode;
          if (!_isEditMode) {
            _selectedEditPersonId = null;
          }
          // Edit and selection are mutually exclusive — both want
          // long-press / tap. Entering one closes the other.
          if (_isEditMode && _isSelectionMode) {
            _isSelectionMode = false;
            _selectedPersonIds.clear();
          }
        });
        return;
      case _TreeToolbarAction.toggleSelectionMode:
        if (!mounted) {
          return;
        }
        setState(() {
          _isSelectionMode = !_isSelectionMode;
          if (!_isSelectionMode) {
            _selectedPersonIds.clear();
          }
          // Symmetric guard — entering selection closes edit mode.
          if (_isSelectionMode && _isEditMode) {
            _isEditMode = false;
            _selectedEditPersonId = null;
          }
        });
        return;
      case _TreeToolbarAction.openBranchChat:
        await _openBranchChat(selectedTreeId, branchRootPerson);
        return;
      case _TreeToolbarAction.openBranchDetails:
        if (branchRootPerson != null) {
          _openPersonDetails(branchRootPerson);
        }
        return;
      case _TreeToolbarAction.copyPublicLink:
        await _copyPublicTreeLink();
        return;
      case _TreeToolbarAction.resetBranchFocus:
        _resetBranchFocus();
        return;
      case _TreeToolbarAction.resetLayout:
        await _resetManualTreeLayout(selectedTreeId);
        return;
    }
  }

  Future<void> _openPersonDetails(
    FamilyPerson person, {
    String? action,
  }) async {
    final normalizedAction = action?.trim();
    final route = (normalizedAction == null || normalizedAction.isEmpty)
        ? '/relative/details/${person.id}'
        : '/relative/details/${person.id}'
            '?action=${Uri.encodeQueryComponent(normalizedAction)}';
    // Awaiting the push lets us refresh the tree once the user
    // navigates back. The detail screen edits person fields /
    // photos in place — without this refresh the tree keeps
    // showing the stale avatar / labels until the user hits
    // hard-reload. With this, swipe-back / tap-back transparently
    // pulls the updated state and Phase 1.1 propagation effects
    // (e.g., photos that fanned out to linked records on other
    // trees) come along for the ride.
    await context.push<dynamic>(route);
    if (!mounted) return;
    final treeId = _currentTreeId;
    if (treeId == null) return;
    await _loadData(treeId);
  }

  // === НОВЫЙ МЕТОД-КОЛЛБЭК для InteractiveFamilyTree ===
  Future<void> _handleNodePositionsChanged(
    Map<String, Offset> updatedPositions,
  ) async {
    final treeId = _currentTreeId;
    if (treeId == null) {
      return;
    }

    setState(() {
      _manualNodePositions = updatedPositions;
    });
    await _localStorageService.saveTreeNodePositions(treeId, updatedPositions);
  }

  Future<void> _resetManualTreeLayout(String treeId) async {
    await _localStorageService.clearTreeNodePositions(treeId);
    if (!mounted) {
      return;
    }
    setState(() {
      _manualNodePositions = <String, Offset>{};
    });
    await _loadData(treeId);
  }

  void _handleAddRelativeFromTree(FamilyPerson person, RelationType type) {
    if (_currentTreeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Не удалось определить активное дерево. Откройте его заново и повторите действие.',
          ),
        ),
      );
      return;
    }
    debugPrint(
      'Добавление родственника типа $type к ${person.name} (${person.id}) в дереве $_currentTreeId',
    );

    // Переходим на экран добавления, передавая контекст
    // AddRelativeScreen должен будет обработать эти параметры в 'extra'
    context.push(
      '/relatives/add/$_currentTreeId',
      extra: {
        'contextPersonId': person.id, // К кому добавляем
        'relationType':
            type, // Какого типа родственника добавляем (относительно contextPersonId)
        'quickAddMode': true,
      },
    ).then((result) {
      if (!mounted) {
        return;
      }
      if (result == true) {
        debugPrint('Возврат с экрана добавления (из дерева), перезагрузка...');
        _loadData(_currentTreeId!);
        return;
      }
      if (result is Map<String, dynamic> && result['updated'] == true) {
        final focusPersonId = result['focusPersonId']?.toString();
        _loadData(_currentTreeId!).then((_) {
          if (!mounted || focusPersonId == null) {
            return;
          }
          final focusedPerson = _relativesData
              .map((entry) => entry['person'])
              .whereType<FamilyPerson>()
              .firstWhere(
                (candidate) => candidate.id == focusPersonId,
                orElse: () => FamilyPerson.empty,
              );
          if (focusedPerson != FamilyPerson.empty) {
            setState(() {
              _selectedEditPersonId = focusedPerson.id;
            });
          }
        });
      }
    });
  }

  // <<< НОВЫЙ МЕТОД-КОЛЛБЭК: Обработка добавления себя из дерева >>>
  // ── Phase 1.2 voltage-indicator matcher handlers ────────────────
  // The canvas reads `_identitySuggestionCounts` to decide where
  // to show the 💡 dot; tap on the dot calls `_handleShowIdentity
  // SuggestionsForPerson` which fetches details, opens a sheet
  // with the suggestion list, dispatches link/dismiss on the
  // service, and refreshes the counts.

  Future<void> _refreshIdentitySuggestionCounts(
    String treeId,
    List<FamilyPerson> relatives,
  ) async {
    final service = _familyService;
    if (service is! IdentitySuggestionsCapableFamilyTreeService) return;
    final capable =
        service as IdentitySuggestionsCapableFamilyTreeService;
    final newCounts = <String, int>{};
    // Sequential fetch is acceptable here — only a handful of
    // persons typically and the response is tiny. Parallelizing
    // could trigger rate-limits on the auth route.
    for (final person in relatives) {
      try {
        final suggestions = await capable.getIdentitySuggestionsForPerson(
          treeId: treeId,
          personId: person.id,
        );
        if (suggestions.isNotEmpty) {
          newCounts[person.id] = suggestions.length;
        }
      } catch (_) {
        // Suggestion fetch is best-effort — failure on one
        // person shouldn't kill the whole batch.
      }
      if (!mounted || _currentTreeId != treeId) return;
    }
    if (mounted && _currentTreeId == treeId) {
      setState(() {
        _identitySuggestionCounts = newCounts;
      });
    }
  }

  Future<void> _handleShowIdentitySuggestionsForPerson(String personId) async {
    final treeId = _currentTreeId;
    if (treeId == null) return;
    final service = _familyService;
    if (service is! IdentitySuggestionsCapableFamilyTreeService) return;
    final capable =
        service as IdentitySuggestionsCapableFamilyTreeService;
    List<IdentitySuggestion> suggestions;
    try {
      suggestions = await capable.getIdentitySuggestionsForPerson(
        treeId: treeId,
        personId: personId,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось загрузить подсказки: $error')),
      );
      return;
    }
    if (!mounted || suggestions.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _IdentitySuggestionsSheet(
        suggestions: suggestions,
        onConfirm: (suggestion) async {
          Navigator.of(sheetContext).pop();
          await _confirmIdentitySuggestion(suggestion);
        },
        onDismiss: (suggestion) async {
          await _dismissIdentitySuggestion(suggestion);
          // Re-render the sheet without that suggestion. Easiest
          // way: pop and reopen; or hand the sheet a stateful
          // wrapper. For simplicity, just pop — the dot count
          // refresh below will re-show one if others remain.
          if (sheetContext.mounted) {
            Navigator.of(sheetContext).pop();
          }
          // Reload list with remaining suggestions.
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await _handleShowIdentitySuggestionsForPerson(personId);
        },
      ),
    );
  }

  Future<void> _confirmIdentitySuggestion(IdentitySuggestion suggestion) async {
    final service = _familyService;
    if (service is! IdentitySuggestionsCapableFamilyTreeService) return;
    final capable =
        service as IdentitySuggestionsCapableFamilyTreeService;
    try {
      await capable.linkIdentity(
        sourceTreeId: suggestion.sourceTreeId,
        sourcePersonId: suggestion.sourcePersonId,
        targetTreeId: suggestion.targetTreeId,
        targetPersonId: suggestion.targetPersonId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Карточки связаны. Теперь правки в одной автоматически отразятся в другой.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
      // Refresh tree (propagation may have already touched fields)
      // and recompute the 💡 counts (this pair drops out).
      final treeId = _currentTreeId;
      if (treeId != null) {
        await _loadData(treeId);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось связать карточки: $error')),
      );
    }
  }

  // ── Phase 1.3 edit-time conflict surfacing handlers ─────────────
  // Tree-level fetch, group-by personId, render ⚠️ badge on each
  // affected card. Tap → resolve sheet, applies user choice,
  // refreshes counts.

  Future<void> _refreshIdentityConflictCounts(String treeId) async {
    final service = _familyService;
    if (service is! IdentityConflictsCapableFamilyTreeService) return;
    final capable = service as IdentityConflictsCapableFamilyTreeService;
    List<IdentityFieldConflict> conflicts;
    try {
      conflicts = await capable.getIdentityConflictsForTree(treeId: treeId);
    } catch (_) {
      // Best-effort — a failed fetch shouldn't kill the tree
      // render. The badge just stays absent until next refresh.
      return;
    }
    if (!mounted || _currentTreeId != treeId) return;
    final counts = <String, int>{};
    for (final conflict in conflicts) {
      counts[conflict.targetPersonId] =
          (counts[conflict.targetPersonId] ?? 0) + 1;
    }
    setState(() {
      _identityConflictCounts = counts;
      _identityConflictsCache = conflicts;
    });
  }

  Future<void> _handleShowIdentityConflictsForPerson(String personId) async {
    final treeId = _currentTreeId;
    if (treeId == null) return;
    final service = _familyService;
    if (service is! IdentityConflictsCapableFamilyTreeService) return;
    final personConflicts = _identityConflictsCache
        .where((c) => c.targetPersonId == personId && !c.isResolved)
        .toList(growable: false);
    if (personConflicts.isEmpty) {
      // Cache stale (already resolved on another device, deleted,
      // etc.) — refresh and bail. The badge will disappear once
      // counts state catches up.
      await _refreshIdentityConflictCounts(treeId);
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _IdentityConflictsSheet(
        conflicts: personConflicts,
        onChoice: (conflict, choice) async {
          final capable =
              service as IdentityConflictsCapableFamilyTreeService;
          try {
            await capable.resolveIdentityConflict(
              treeId: treeId,
              conflictId: conflict.id,
              choice: choice,
            );
          } catch (error) {
            if (sheetContext.mounted) {
              ScaffoldMessenger.of(sheetContext).showSnackBar(
                SnackBar(content: Text('Не удалось применить выбор: $error')),
              );
            }
            return;
          }
          if (sheetContext.mounted) {
            Navigator.of(sheetContext).pop();
          }
          // overwrite changes the underlying person — pull a
          // fresh tree snapshot so the canvas shows the new
          // canonical value. keep is data-neutral but the
          // refresh below clears the badge either way.
          if (choice == 'overwrite') {
            await _loadData(treeId);
          } else {
            await _refreshIdentityConflictCounts(treeId);
          }
        },
      ),
    );
  }

  Future<void> _dismissIdentitySuggestion(IdentitySuggestion suggestion) async {
    final service = _familyService;
    if (service is! IdentitySuggestionsCapableFamilyTreeService) return;
    final capable =
        service as IdentitySuggestionsCapableFamilyTreeService;
    try {
      await capable.dismissIdentitySuggestion(
        sourceTreeId: suggestion.sourceTreeId,
        sourcePersonId: suggestion.sourcePersonId,
        targetPersonId: suggestion.targetPersonId,
      );
      // Optimistically drop the count by one — a fresh fetch
      // confirms after.
      if (mounted) {
        setState(() {
          final next = Map<String, int>.from(_identitySuggestionCounts);
          final current = next[suggestion.sourcePersonId] ?? 0;
          if (current <= 1) {
            next.remove(suggestion.sourcePersonId);
          } else {
            next[suggestion.sourcePersonId] = current - 1;
          }
          _identitySuggestionCounts = next;
        });
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось скрыть подсказку: $error')),
      );
    }
  }

  // Blank-card creator handler. Called when the user tapped the
  // canvas-level "+ Карточка" FAB, filled name + gender in the
  // compact dialog, and pressed Save. We create the person without
  // any relation; the user connects them to the rest of the tree
  // via the edge-first connector. Pairs with the connector to
  // fully replace the form-based add-relative flow.
  Future<void> _handleAddBlankPersonFromTree(
    Map<String, dynamic> personData,
  ) async {
    final treeId = _currentTreeId;
    if (treeId == null) return;
    try {
      // addRelative returns the new person id — we capture it so
      // the tree can auto-center on the new card after the
      // reload (nice UX detail: without this, a freshly-created
      // orphan ends up wherever the layout engine puts it,
      // possibly off-screen if the user is zoomed into another
      // branch).
      final newPersonId =
          await _familyService.addRelative(treeId, personData);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Карточка добавлена. Соедините её длинным нажатием.'),
          duration: const Duration(seconds: 3),
        ),
      );
      // Stamp the recenter id BEFORE the reload — when _loadData
      // sets peopleData the InteractiveFamilyTree's didUpdateWidget
      // sees both the new data + the new recenter target in one
      // pass and schedules the focus once layout is recomputed.
      setState(() {
        _recenterOnPersonIdAfterReload = newPersonId;
      });
      await _loadData(treeId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось добавить карточку: $error')),
      );
    }
  }

  // Edge-first connector handler. Called when the user has dragged
  // one card onto another and picked a relation type from the inline
  // 4-icon picker. Skips the AddRelativeScreen form entirely and
  // creates the relation directly via the family-tree service, then
  // reloads the tree so the new edge appears.
  //
  // The picker only offers four relation types (parent, spouse,
  // sibling, other). For "other" we open a small sheet to ask which
  // long-tail relation (cousin / nephew / step-* / etc.) — better
  // than guessing wrong and silently writing a bad edge.
  Future<void> _handleConnectExistingFromTree(
    String sourcePersonId,
    String targetPersonId,
    RelationType relation1to2,
  ) async {
    final treeId = _currentTreeId;
    if (treeId == null) return;
    if (sourcePersonId.isEmpty || targetPersonId.isEmpty) return;
    if (sourcePersonId == targetPersonId) return;

    // For "other" we DON'T have enough info to create a relation —
    // pop the legacy quick-add sheet pre-anchored on the target so
    // the user can pick the specific long-tail type. This is the
    // only branch where the form is still needed.
    if (relation1to2 == RelationType.other) {
      final sourcePerson = _relativesData
          .map((entry) => entry['person'])
          .whereType<FamilyPerson>()
          .firstWhere(
            (person) => person.id == sourcePersonId,
            orElse: () => FamilyPerson(
              id: sourcePersonId,
              treeId: treeId,
              name: '',
              gender: Gender.unknown,
              isAlive: true,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
      _handleAddRelativeFromTree(sourcePerson, relation1to2);
      return;
    }

    try {
      final created = await _familyService.createRelation(
        treeId: treeId,
        person1Id: sourcePersonId,
        person2Id: targetPersonId,
        relation1to2: relation1to2,
        isConfirmed: true,
      );
      if (GetIt.I.isRegistered<TreeMutationHistory>()) {
        GetIt.I<TreeMutationHistory>().recordRelationCreated(
          treeId: treeId,
          created: created,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Связь создана'),
          duration: const Duration(seconds: 2),
        ),
      );
      // Reload so the new edge renders + layout engine can rebalance.
      await _loadData(treeId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось создать связь: $error')),
      );
    }
  }

  Future<void> _handleAddSelfFromTree(
    FamilyPerson targetPerson,
    RelationType relationType,
  ) async {
    if (_currentTreeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Не удалось определить активное дерево. Откройте его заново и повторите действие.',
          ),
        ),
      );
      return;
    }

    final currentUserId = _authService.currentUserId;
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Сессия завершилась. Войдите снова.')),
      );
      context.go('/login'); // Перенаправляем на логин
      return;
    }

    // Показываем индикатор загрузки
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text("Добавляем вас в дерево..."),
              ],
            ),
          ),
        );
      },
    );

    try {
      debugPrint(
        'Добавление ТЕКУЩЕГО ПОЛЬЗОВАТЕЛЯ ($currentUserId) типа $relationType к ${targetPerson.name} (${targetPerson.id}) в дереве $_currentTreeId',
      );

      // Вызываем новый метод сервиса
      await _familyService.addCurrentUserToTree(
        treeId: _currentTreeId!,
        targetPersonId: targetPerson.id,
        relationType: relationType,
      );
      if (!mounted) return;

      // Закрываем диалог загрузки
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Вы успешно добавлены в дерево!'),
          duration: Duration(seconds: 2),
        ),
      );

      // Обновляем данные дерева, чтобы отобразить изменения и скрыть кнопку
      debugPrint('Перезагрузка дерева после добавления себя...');
      setState(() {
        _currentUserIsInTree = true;
      });
      await _loadData(_currentTreeId!);
    } catch (e, s) {
      // Закрываем диалог загрузки в случае ошибки
      if (mounted) Navigator.pop(context);

      debugPrint('Ошибка при добавлении себя в дерево: $e\\n$s');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _describeTreeActionError(
                e,
                fallbackMessage:
                    'Не удалось добавить вас в дерево. Попробуйте ещё раз.',
              ),
            ),
            duration: Duration(seconds: 5),
          ),
        );
      }
      debugPrint('Error in handleAddSelfFromTree: $e\n$s');
    }
  }

  // =============================================================

  Future<void> _showTreeHistorySheet({FamilyPerson? person}) async {
    final treeId = _currentTreeId;
    if (treeId == null) {
      return;
    }

    final historyFuture = _familyService.getTreeHistory(
      treeId: treeId,
      personId: person?.id,
    );
    final sheetTitle = person == null ? 'История дерева' : 'История изменений';
    final sheetSubtitle = person?.name ??
        _currentTreeMeta?.name ??
        widget.routeTreeName ??
        'Текущее дерево';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return TreeHistorySheet(
          historyFuture: historyFuture,
          title: sheetTitle,
          subtitle: sheetSubtitle,
          currentUserId: _authService.currentUserId,
          emptyMessage: person == null
              ? 'В журнале дерева пока нет записей.'
              : 'Для этой карточки пока нет записей в журнале.',
          errorBuilder: (error) => _describeTreeActionError(
            error,
            fallbackMessage: 'Не удалось загрузить историю.',
          ),
          onOpenPerson: (personId) async {
            Navigator.of(sheetContext).pop();
            if (!mounted) return;
            await context.push<dynamic>('/relative/details/$personId');
            if (!mounted) return;
            // Refresh tree on return so edits made on the detail
            // screen (photo, name parts, dates) show up immediately
            // instead of requiring a hard-reload.
            final treeId = _currentTreeId;
            if (treeId != null) {
              await _loadData(treeId);
            }
          },
        );
      },
    );
  }

  Future<void> _showPersonHistorySheet(FamilyPerson person) {
    return _showTreeHistorySheet(person: person);
  }

  Future<void> _navigateToAddRelative(String treeId) async {
    final result = await context.push('/relatives/add/$treeId');
    if ((result == true ||
            (result is Map<String, dynamic> && result['updated'] == true)) &&
        mounted) {
      await _loadData(treeId);
    }
  }

  Set<String> _buildBranchVisiblePersonIds(String branchRootPersonId) {
    final graphSnapshot = _graphSnapshot;
    final personIds = _relativesData
        .map((entry) => entry['person'])
        .whereType<FamilyPerson>()
        .map((person) => person.id)
        .toSet();
    if (graphSnapshot != null) {
      final branchBlock =
          graphSnapshot.findBranchBlockForPerson(branchRootPersonId);
      if (branchBlock != null) {
        return branchBlock.memberPersonIds.toSet();
      }
    }
    return personIds;
  }

  List<String> _buildBranchChatParticipantIds(String branchRootPersonId) {
    final participantIds = <String>{};
    final currentUserId = _authService.currentUserId;
    if (currentUserId != null && currentUserId.isNotEmpty) {
      participantIds.add(currentUserId);
    }

    final visibleIds = _buildBranchVisiblePersonIds(branchRootPersonId);
    for (final entry in _relativesData) {
      final person = entry['person'];
      if (person is! FamilyPerson || !visibleIds.contains(person.id)) {
        continue;
      }
      final linkedUserId = person.userId?.trim();
      if (linkedUserId != null && linkedUserId.isNotEmpty) {
        participantIds.add(linkedUserId);
      }
    }

    final sortedIds = participantIds.toList();
    sortedIds.sort();
    return sortedIds;
  }

  Future<FamilyTree?> _loadCurrentTreeMeta(String treeId) async {
    try {
      final trees = await _familyService.getUserTrees();
      for (final tree in trees) {
        if (tree.id == treeId) {
          return tree;
        }
      }
    } catch (_) {}
    return _currentTreeMeta?.id == treeId ? _currentTreeMeta : null;
  }

  void _focusBranch(FamilyPerson person) {
    if (!mounted) {
      return;
    }
    setState(() {
      _branchRootPersonId = person.id;
      _selectedPersonSheetId = person.id;
    });
  }

  // ── Phase 4: «Кем мы приходимся?» ──────────────────────────────────
  // Walks the unified-graph blood-relation path from the viewer's
  // own card to the selected person and shows a sheet with the
  // Russian relationship label + the chain of intermediate people
  // ("you → mom → her brother → his daughter"). Tap on the action
  // chip in the person sheet — _showTreePersonBloodRelation — wires
  // straight into this.
  Future<void> _showTreePersonBloodRelation(FamilyPerson person) async {
    final viewerPersonId = _graphSnapshot?.viewerPersonId;
    if (viewerPersonId == null) {
      _showSnack(
        'Чтобы найти родство, добавьте свою карточку в дерево.',
      );
      return;
    }
    if (viewerPersonId == person.id) {
      _showSnack('Это вы.');
      return;
    }
    final viewerPerson = _treePeople.firstWhere(
      (p) => p.id == viewerPersonId,
      orElse: () => person, // unreachable — viewerPersonId is in tree
    );
    final viewerIdentityId = _personIdentityIdFor(viewerPerson);
    final targetIdentityId = _personIdentityIdFor(person);
    if (viewerIdentityId == null || targetIdentityId == null) {
      _showSnack(
        'Карточки ещё не синхронизированы с графом — попробуйте через минуту.',
      );
      return;
    }

    final service = _familyService;
    if (service is! BloodRelationCapableFamilyTreeService) {
      _showSnack('Эта функция пока недоступна на бэкенде.');
      return;
    }
    final capable = service as BloodRelationCapableFamilyTreeService;

    BloodRelation? relation;
    try {
      relation = await capable.findBloodRelation(
        fromGraphPersonId: viewerIdentityId,
        toGraphPersonId: targetIdentityId,
      );
    } catch (error) {
      if (!mounted) return;
      _showSnack('Не удалось найти родство: $error');
      return;
    }
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _BloodRelationSheet(
        target: person,
        relation: relation!,
      ),
    );
  }

  String? _personIdentityIdFor(FamilyPerson person) {
    final identityId = person.identityId;
    if (identityId != null && identityId.trim().isNotEmpty) {
      return identityId.trim();
    }
    return null;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _resetBranchFocus() {
    if (!mounted) {
      return;
    }
    setState(() {
      _branchRootPersonId = null;
    });
  }

  FamilyPerson? _findBranchRootPerson() {
    final branchRootPersonId = _branchRootPersonId;
    if (branchRootPersonId == null) {
      return null;
    }

    for (final entry in _relativesData) {
      final person = entry['person'];
      if (person is FamilyPerson && person.id == branchRootPersonId) {
        return person;
      }
    }
    return null;
  }

  Future<void> _openBranchChat(
    String treeId,
    FamilyPerson? branchRootPerson,
  ) async {
    if (branchRootPerson == null) {
      return;
    }

    final participantIds = _buildBranchChatParticipantIds(branchRootPerson.id);
    if (participantIds.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('В этой ветке пока некому писать в общий чат.'),
        ),
      );
      return;
    }

    final graphBranchBlock =
        _graphSnapshot?.findBranchBlockForPerson(branchRootPerson.id);
    final title = graphBranchBlock?.label ?? 'Ветка ${branchRootPerson.name}';
    try {
      final chatId = await _chatService.createBranchChat(
        treeId: treeId,
        branchRootPersonIds: <String>[branchRootPerson.id],
        title: title,
      );
      if (!mounted) {
        return;
      }
      if (chatId == null || chatId.isEmpty) {
        throw StateError('Не удалось создать чат ветки');
      }

      context.push(
        '/chats/view/$chatId?type=branch&title=${Uri.encodeComponent(title)}',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _describeTreeActionError(
              error,
              fallbackMessage: 'Не удалось открыть чат ветки.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _copyPublicTreeLink() async {
    final treeMeta = _currentTreeMeta;
    if (treeMeta == null || !treeMeta.isPublic) {
      return;
    }

    final publicUri = PublicTreeLinkService.buildPublicTreeUri(
      treeMeta.publicRouteId,
      publicAppUrl: BackendRuntimeConfig.current.publicAppUrl,
    );

    await Clipboard.setData(ClipboardData(text: publicUri.toString()));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Публичная ссылка скопирована.')),
    );
  }
}

class _TreeTopbarPill extends StatelessWidget {
  const _TreeTopbarPill({
    required this.tokens,
    required this.child,
    required this.tooltip,
    required this.onTap,
  });

  final RodnyaDesignTokens tokens;
  final Widget child;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: tokens.surfaceStrong,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: tokens.surfaceLine),
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet shown when the user taps the 💡 voltage-indicator
/// dot on a card. Lists each suggestion with target person + tree
/// origin + match reasons + confirm/dismiss buttons.
class _IdentitySuggestionsSheet extends StatelessWidget {
  const _IdentitySuggestionsSheet({
    required this.suggestions,
    required this.onConfirm,
    required this.onDismiss,
  });

  final List<IdentitySuggestion> suggestions;
  final Future<void> Function(IdentitySuggestion suggestion) onConfirm;
  final Future<void> Function(IdentitySuggestion suggestion) onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.lightbulb_outline_rounded,
                    color: scheme.tertiary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Возможные дубликаты',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        suggestions.length == 1
                            ? 'Кажется, этот человек уже есть в одном из ваших деревьев. Связать карточки?'
                            : 'Кажется, этот человек уже есть в ${suggestions.length} ваших деревьях. Связать?',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final suggestion in suggestions) ...[
              _SuggestionRow(
                suggestion: suggestion,
                onConfirm: () => onConfirm(suggestion),
                onDismiss: () => onDismiss(suggestion),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.suggestion,
    required this.onConfirm,
    required this.onDismiss,
  });

  final IdentitySuggestion suggestion;
  final Future<void> Function() onConfirm;
  final Future<void> Function() onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reasons = suggestion.reasons.join(' · ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundImage: suggestion.targetPhotoUrl != null &&
                        suggestion.targetPhotoUrl!.isNotEmpty
                    ? NetworkImage(suggestion.targetPhotoUrl!)
                    : null,
                backgroundColor: scheme.surfaceContainer,
                child: suggestion.targetPhotoUrl == null
                    ? Text(
                        suggestion.targetDisplayName.isNotEmpty
                            ? suggestion.targetDisplayName[0]
                            : '?',
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      suggestion.targetDisplayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (suggestion.targetTreeName.isNotEmpty)
                      Text(
                        'Из «${suggestion.targetTreeName}»',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: suggestion.confidence == 'high'
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${(suggestion.score * 100).round()}%',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: suggestion.confidence == 'high'
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              reasons,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Не он'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onConfirm,
                  icon: const Icon(Icons.link_rounded, size: 18),
                  label: const Text('Связать'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Phase 1.3 conflict resolution sheet ────────────────────────────
// One row per diverging field with side-by-side "keep mine" /
// "accept other branch's value". Plain text rendering of values —
// good enough for a v1; richer formatting (date, photo preview)
// comes with the Phase 3 lens migration when the conflict surface
// becomes more central.

const Map<String, String> _kIdentityConflictFieldLabels = <String, String>{
  'name': 'ФИО',
  'maidenName': 'Девичья фамилия',
  'gender': 'Пол',
  'birthDate': 'Дата рождения',
  'deathDate': 'Дата смерти',
  'isAlive': 'Признак "жив"',
  'birthPlace': 'Место рождения',
  'deathPlace': 'Место смерти',
  'photoUrl': 'Фото',
  'primaryPhotoUrl': 'Основное фото',
  'photoGallery': 'Галерея фото',
};

String _identityConflictFieldLabel(String field) =>
    _kIdentityConflictFieldLabels[field] ?? field;

String _formatIdentityConflictValue(String field, dynamic value) {
  if (value == null) return '— пусто —';
  if (field == 'photoGallery') {
    if (value is List) {
      return value.isEmpty ? '— пусто —' : '${value.length} фото';
    }
    return value.toString();
  }
  if (value is bool) return value ? 'да' : 'нет';
  final stringValue = value.toString().trim();
  return stringValue.isEmpty ? '— пусто —' : stringValue;
}

class _IdentityConflictsSheet extends StatelessWidget {
  const _IdentityConflictsSheet({
    required this.conflicts,
    required this.onChoice,
  });

  final List<IdentityFieldConflict> conflicts;

  /// Called when the user picks a side. `choice` is `'keep'` or
  /// `'overwrite'`. Sheet dismisses on success — owner closes it.
  final Future<void> Function(IdentityFieldConflict conflict, String choice)
      onChoice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.error_outline_rounded,
                    color: scheme.error,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conflicts.length == 1
                            ? 'Расхождение в одной ветке'
                            : 'Расхождения в ${conflicts.length} полях',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Этот человек по-разному заполнен на разных ветках. '
                        'Выберите, какое значение оставить.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final conflict in conflicts) ...[
              _ConflictRow(
                conflict: conflict,
                onChoice: (choice) => onChoice(conflict, choice),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConflictRow extends StatelessWidget {
  const _ConflictRow({
    required this.conflict,
    required this.onChoice,
  });

  final IdentityFieldConflict conflict;
  final Future<void> Function(String choice) onChoice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fieldLabel = _identityConflictFieldLabel(conflict.field);
    final ourValue =
        _formatIdentityConflictValue(conflict.field, conflict.targetValue);
    final theirValue =
        _formatIdentityConflictValue(conflict.field, conflict.sourceValue);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fieldLabel,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _ConflictSide(
            label: 'Здесь',
            value: ourValue,
            actionLabel: 'Оставить',
            onTap: () => onChoice('keep'),
            isPrimary: false,
          ),
          const SizedBox(height: 8),
          _ConflictSide(
            label: 'На другой ветке',
            value: theirValue,
            actionLabel: 'Принять',
            onTap: () => onChoice('overwrite'),
            isPrimary: true,
          ),
        ],
      ),
    );
  }
}

class _ConflictSide extends StatelessWidget {
  const _ConflictSide({
    required this.label,
    required this.value,
    required this.actionLabel,
    required this.onTap,
    required this.isPrimary,
  });

  final String label;
  final String value;
  final String actionLabel;
  final Future<void> Function() onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodyMedium,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 120,
          child: isPrimary
              ? FilledButton(
                  onPressed: () => onTap(),
                  child: Text(actionLabel),
                )
              : OutlinedButton(
                  onPressed: () => onTap(),
                  child: Text(actionLabel),
                ),
        ),
      ],
    );
  }
}

// ── Phase 4: «Кем мы приходимся?» result sheet ─────────────────────
// Header with the relationship label, then a horizontal strip of
// avatars connecting the viewer to the target person, with arrows
// between cards showing the edge direction (UP/DOWN/LATERAL).
class _BloodRelationSheet extends StatelessWidget {
  const _BloodRelationSheet({
    required this.target,
    required this.relation,
  });

  final FamilyPerson target;
  final BloodRelation relation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.account_tree_rounded,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        relation.found
                            ? 'Это ваш${_genderEnding(target.gender.name)} ${relation.label}'
                            : 'Родство не найдено',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (relation.found)
                        Text(
                          'Степень родства: ${relation.degree}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        )
                      else
                        Text(
                          'Между вами и ${target.displayName} нет общего предка в дереве. Возможно, нужно добавить пропущенного родственника.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (relation.found && relation.chain.length > 1) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: relation.chain.length * 2 - 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    if (index.isOdd) {
                      // Edge arrow between two avatars.
                      final edgeIndex = (index - 1) ~/ 2;
                      final edge = relation.edges.length > edgeIndex
                          ? relation.edges[edgeIndex]
                          : '';
                      return _BloodRelationArrow(edgeType: edge);
                    }
                    final personIndex = index ~/ 2;
                    final preview = relation.chain[personIndex];
                    return _BloodRelationAvatar(
                      preview: preview,
                      isSelf: personIndex == 0,
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _genderEnding(String? gender) {
    final g = (gender ?? '').toLowerCase();
    if (g == 'female') return 'а';
    return '';
  }
}

class _BloodRelationAvatar extends StatelessWidget {
  const _BloodRelationAvatar({required this.preview, required this.isSelf});

  final BloodRelationPersonPreview preview;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasPhoto =
        preview.photoUrl != null && preview.photoUrl!.isNotEmpty;
    final initial = (preview.name?.isNotEmpty == true)
        ? preview.name!.substring(0, 1).toUpperCase()
        : '?';
    return SizedBox(
      width: 90,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: scheme.surfaceContainerHigh,
                backgroundImage:
                    hasPhoto ? NetworkImage(preview.photoUrl!) : null,
                child: hasPhoto ? null : Text(initial),
              ),
              if (isSelf)
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Вы',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            preview.name ?? '—',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _BloodRelationArrow extends StatelessWidget {
  const _BloodRelationArrow({required this.edgeType});

  /// `parent` — walker is the parent going DOWN to a child.
  /// `child`  — walker is the child going UP to a parent.
  /// `sibling` — lateral.
  final String edgeType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    IconData icon;
    String hint;
    switch (edgeType) {
      case 'parent':
        icon = Icons.south_rounded; // going down to descendant
        hint = 'ребёнок';
        break;
      case 'child':
        icon = Icons.north_rounded; // going up to ancestor
        hint = 'родитель';
        break;
      case 'sibling':
        icon = Icons.east_rounded; // lateral
        hint = 'брат/сестра';
        break;
      default:
        icon = Icons.east_rounded;
        hint = '';
    }
    return SizedBox(
      width: 32,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(height: 2),
          Text(
            hint,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 9,
            ),
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
