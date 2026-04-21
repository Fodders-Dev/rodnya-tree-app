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

  final LocalStorageService _localStorageService = GetIt.I<LocalStorageService>();

  String? _selectedTreeId;
  String? _selectedTreeName;
  TreeKind? _selectedTreeKind;
  List<FamilyTree> _availableTrees = const <FamilyTree>[];
  bool _hasLoadedAvailableTrees = false;

  String? get selectedTreeId => _selectedTreeId;
  String? get selectedTreeName => _selectedTreeName;
  TreeKind? get selectedTreeKind => _selectedTreeKind;

  FamilyTreeServiceInterface? get _familyTreeService =>
      GetIt.I.isRegistered<FamilyTreeServiceInterface>()
          ? GetIt.I<FamilyTreeServiceInterface>()
          : null;

  Future<void> loadInitialTree() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final availableTrees = await _loadAvailableTrees(forceRefresh: true);
      final storedTreeId = prefs.getString(_treeIdKey);

      if (storedTreeId != null && storedTreeId.isNotEmpty) {
        final selectedTree = _findTree(storedTreeId, availableTrees);
        if (selectedTree != null) {
          _applySelectionFromTree(selectedTree, notify: false);
        } else {
          await _clearPersistedSelection(prefs);
        }
      } else {
        _selectedTreeKind = treeKindFromRaw(prefs.getString(_treeKindKey));
      }

      await selectDefaultTreeIfNeeded(preloadedTrees: availableTrees);
      notifyListeners();
    } catch (error) {
      debugPrint(
        'TreeProvider: Error loading initial tree from SharedPreferences: $error',
      );
    }
  }

  Future<void> refreshAvailableTrees() async {
    await _loadAvailableTrees(forceRefresh: true);
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
