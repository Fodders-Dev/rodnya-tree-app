import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../backend/interfaces/family_tree_service_interface.dart';
import '../models/family_tree.dart';
import '../services/local_storage_service.dart';

class TreeProvider with ChangeNotifier {
  static const _treeIdKey = 'selected_tree_id';
  static const _treeNameKey = 'selected_tree_name';
  static const _treeKindKey = 'selected_tree_kind';

  final LocalStorageService _localStorageService =
      GetIt.I<LocalStorageService>();

  String? _selectedTreeId;
  String? _selectedTreeName;
  TreeKind? _selectedTreeKind;
  List<FamilyTree> _availableTrees = const <FamilyTree>[];
  bool _hasLoadedAvailableTrees = false;
  Future<void>? _availableTreesRefreshTask;

  String? get selectedTreeId => _selectedTreeId;
  String? get selectedTreeName => _selectedTreeName;
  TreeKind? get selectedTreeKind => _selectedTreeKind;

  /// Phase 6.1: read-only view of the user's available branches
  /// (legacy: trees) so the BranchSwitcher widget can render the
  /// dropdown without re-fetching from the service. Always reflects
  /// the last successful load — empty when load hasn't finished or
  /// the user has no branches yet.
  List<FamilyTree> get availableTrees => _availableTrees;
  bool get hasLoadedAvailableTrees => _hasLoadedAvailableTrees;

  FamilyTreeServiceInterface? get _familyTreeService =>
      GetIt.I.isRegistered<FamilyTreeServiceInterface>()
          ? GetIt.I<FamilyTreeServiceInterface>()
          : null;

  Future<void> loadInitialTree() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedTrees = await _localStorageService.getAllTrees();
      final hydratedFromCache = await _hydrateInitialTreeFromCache(
        prefs,
        cachedTrees,
      );

      if (hydratedFromCache) {
        notifyListeners();
        _scheduleAvailableTreesRefresh();
        return;
      }

      final availableTrees = await _loadAvailableTrees(forceRefresh: true);
      await _applyInitialSelectionFromTrees(prefs, availableTrees);
      notifyListeners();
    } catch (error) {
      debugPrint(
        'TreeProvider: Error loading initial tree from SharedPreferences: $error',
      );
    }
  }

  Future<void> refreshAvailableTrees() async {
    final runningRefresh = _availableTreesRefreshTask;
    if (runningRefresh != null) {
      await runningRefresh;
      return;
    }
    await _refreshAvailableTreesFromBackend();
  }

  Future<void> selectTree(
    String? treeId,
    String? treeName, {
    TreeKind? treeKind,
  }) async {
    if (treeId == null || treeId.isEmpty) {
      await _applySelection(
        treeId: null,
        treeName: null,
        treeKind: null,
      );
      return;
    }

    final resolvedTree = await _resolveTree(treeId);
    await _applySelection(
      treeId: treeId,
      treeName: treeName ?? resolvedTree?.name,
      treeKind: treeKind ?? resolvedTree?.kind,
    );
  }

  Future<void> clearSelection() async {
    await selectTree(null, null);
  }

  Future<void> selectDefaultTreeIfNeeded({
    List<FamilyTree>? preloadedTrees,
  }) async {
    if (_selectedTreeId != null) {
      return;
    }

    final availableTrees = preloadedTrees ?? await _loadAvailableTrees();
    if (availableTrees.isEmpty) {
      return;
    }

    final defaultTree = availableTrees.first;
    await _applySelection(
      treeId: defaultTree.id,
      treeName: defaultTree.name,
      treeKind: defaultTree.kind,
    );
  }

  Future<List<FamilyTree>> _loadAvailableTrees({
    bool forceRefresh = false,
  }) async {
    if (_hasLoadedAvailableTrees && !forceRefresh) {
      return _availableTrees;
    }

    final familyTreeService = _familyTreeService;
    List<FamilyTree> resolvedTrees = const <FamilyTree>[];

    if (familyTreeService != null) {
      try {
        resolvedTrees = await familyTreeService.getUserTrees();
      } catch (error) {
        debugPrint('TreeProvider: Error loading trees from backend: $error');
      }
    }

    if (resolvedTrees.isEmpty) {
      resolvedTrees = await _localStorageService.getAllTrees();
    }

    _availableTrees = resolvedTrees;
    _hasLoadedAvailableTrees = true;
    return _availableTrees;
  }

  Future<bool> _hydrateInitialTreeFromCache(
    SharedPreferences prefs,
    List<FamilyTree> cachedTrees,
  ) async {
    if (cachedTrees.isNotEmpty) {
      _availableTrees = cachedTrees;
      _hasLoadedAvailableTrees = true;
    }

    final storedTreeId = prefs.getString(_treeIdKey);
    _selectedTreeKind = treeKindFromRaw(prefs.getString(_treeKindKey));

    if (storedTreeId != null && storedTreeId.isNotEmpty) {
      final cachedTree = _findTree(storedTreeId, cachedTrees);
      if (cachedTree != null) {
        _applySelectionFromTree(cachedTree, notify: false);
        return true;
      }

      if (cachedTrees.isEmpty) {
        return false;
      }

      // The old selection is absent from the last known local list.
      // Use an available cached default right away; the background refresh
      // below validates it against the backend and corrects if needed.
      await _clearPersistedSelection(prefs);
    }

    final defaultTree = cachedTrees.isNotEmpty ? cachedTrees.first : null;
    if (defaultTree == null) {
      return false;
    }

    _selectedTreeId = defaultTree.id;
    _selectedTreeName = defaultTree.name;
    _selectedTreeKind = defaultTree.kind;
    await _persistSelection(
      prefs,
      treeId: defaultTree.id,
      treeName: defaultTree.name,
      treeKind: defaultTree.kind,
    );
    return true;
  }

  Future<void> _applyInitialSelectionFromTrees(
    SharedPreferences prefs,
    List<FamilyTree> availableTrees,
  ) async {
    final storedTreeId = prefs.getString(_treeIdKey);

    if (storedTreeId != null && storedTreeId.isNotEmpty) {
      final selectedTree = _findTree(storedTreeId, availableTrees);
      if (selectedTree != null) {
        _applySelectionFromTree(selectedTree, notify: false);
        await _persistSelection(
          prefs,
          treeId: selectedTree.id,
          treeName: selectedTree.name,
          treeKind: selectedTree.kind,
        );
      } else {
        await _clearPersistedSelection(prefs);
      }
    } else {
      _selectedTreeKind = treeKindFromRaw(prefs.getString(_treeKindKey));
    }

    await _selectDefaultTreeIfNeededFrom(availableTrees, prefs);
  }

  Future<void> _selectDefaultTreeIfNeededFrom(
    List<FamilyTree> availableTrees,
    SharedPreferences prefs,
  ) async {
    if (_selectedTreeId != null || availableTrees.isEmpty) {
      return;
    }

    final defaultTree = availableTrees.first;
    _selectedTreeId = defaultTree.id;
    _selectedTreeName = defaultTree.name;
    _selectedTreeKind = defaultTree.kind;
    await _persistSelection(
      prefs,
      treeId: defaultTree.id,
      treeName: defaultTree.name,
      treeKind: defaultTree.kind,
    );
  }

  void _scheduleAvailableTreesRefresh() {
    if (_availableTreesRefreshTask != null) {
      return;
    }

    final task = _refreshAvailableTreesFromBackend();
    _availableTreesRefreshTask = task;
    unawaited(
      task.catchError((Object error, StackTrace stackTrace) {
        debugPrint(
          'TreeProvider: background tree refresh failed: $error\n$stackTrace',
        );
      }).whenComplete(() {
        if (identical(_availableTreesRefreshTask, task)) {
          _availableTreesRefreshTask = null;
        }
      }),
    );
  }

  Future<void> _refreshAvailableTreesFromBackend() async {
    final prefs = await SharedPreferences.getInstance();
    final availableTrees = await _loadAvailableTrees(forceRefresh: true);

    if (availableTrees.isEmpty) {
      notifyListeners();
      return;
    }

    final selectedTreeId = _selectedTreeId;
    if (selectedTreeId != null && selectedTreeId.isNotEmpty) {
      final selectedTree = _findTree(selectedTreeId, availableTrees);
      if (selectedTree != null) {
        _applySelectionFromTree(selectedTree, notify: false);
        await _persistSelection(
          prefs,
          treeId: selectedTree.id,
          treeName: selectedTree.name,
          treeKind: selectedTree.kind,
        );
        notifyListeners();
        return;
      }

      await _clearPersistedSelection(prefs);
    }

    await _selectDefaultTreeIfNeededFrom(availableTrees, prefs);
    notifyListeners();
  }

  Future<FamilyTree?> _resolveTree(String treeId) async {
    final cachedTree = _findTree(treeId, _availableTrees);
    if (cachedTree != null) {
      return cachedTree;
    }

    final availableTrees = await _loadAvailableTrees();
    final resolvedTree = _findTree(treeId, availableTrees);
    if (resolvedTree != null) {
      return resolvedTree;
    }

    return _localStorageService.getTree(treeId);
  }

  FamilyTree? _findTree(String treeId, List<FamilyTree> trees) {
    for (final tree in trees) {
      if (tree.id == treeId) {
        return tree;
      }
    }
    return null;
  }

  void _applySelectionFromTree(FamilyTree tree, {required bool notify}) {
    _selectedTreeId = tree.id;
    _selectedTreeName = tree.name;
    _selectedTreeKind = tree.kind;
    if (notify) {
      notifyListeners();
    }
  }

  Future<void> _applySelection({
    required String? treeId,
    required String? treeName,
    required TreeKind? treeKind,
  }) async {
    if (_selectedTreeId == treeId &&
        _selectedTreeName == treeName &&
        _selectedTreeKind == treeKind) {
      return;
    }

    _selectedTreeId = treeId;
    _selectedTreeName = treeName;
    _selectedTreeKind = treeKind;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    if (treeId == null) {
      await _clearPersistedSelection(prefs);
      return;
    }

    await _persistSelection(
      prefs,
      treeId: treeId,
      treeName: treeName,
      treeKind: treeKind,
    );
  }

  Future<void> _persistSelection(
    SharedPreferences prefs, {
    required String treeId,
    required String? treeName,
    required TreeKind? treeKind,
  }) async {
    await prefs.setString(_treeIdKey, treeId);
    if (treeName != null && treeName.isNotEmpty) {
      await prefs.setString(_treeNameKey, treeName);
    } else {
      await prefs.remove(_treeNameKey);
    }
    if (treeKind != null) {
      await prefs.setString(_treeKindKey, treeKind.name);
    } else {
      await prefs.remove(_treeKindKey);
    }
  }

  Future<void> _clearPersistedSelection(SharedPreferences prefs) async {
    _selectedTreeId = null;
    _selectedTreeName = null;
    _selectedTreeKind = null;
    await prefs.remove(_treeIdKey);
    await prefs.remove(_treeNameKey);
    await prefs.remove(_treeKindKey);
  }
}
