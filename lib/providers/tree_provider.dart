import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get_it/get_it.dart';
import '../services/local_storage_service.dart';
import '../models/family_tree.dart';

class TreeProvider with ChangeNotifier {
  String? _selectedTreeId;
  String? _selectedTreeName;

  final LocalStorageService _localStorageService = GetIt.I<LocalStorageService>();

  static const _treeIdKey = 'selected_tree_id';
  static const _treeNameKey = 'selected_tree_name';

  String? get selectedTreeId => _selectedTreeId;
  String? get selectedTreeName => _selectedTreeName;

  Future<void> loadInitialTree() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loadedId = prefs.getString(_treeIdKey);
      final loadedName = prefs.getString(_treeNameKey);

      if (loadedId != null) {
        print('TreeProvider: Found tree ID $loadedId in SharedPreferences. Verifying...');
        final FamilyTree? existingTree = await _localStorageService.getTree(loadedId);
        if (existingTree != null) {
          _selectedTreeId = loadedId;
          _selectedTreeName = existingTree.name;
          print('TreeProvider: Verified. Loaded initial tree ID: $_selectedTreeId, Name: $_selectedTreeName');
          notifyListeners();
        } else {
          print('TreeProvider: Tree ID $loadedId from SharedPreferences not found in cache. Clearing selection.');
          _selectedTreeId = null;
          _selectedTreeName = null;
          await prefs.remove(_treeIdKey);
          await prefs.remove(_treeNameKey);
        }
      } else {
        print('TreeProvider: No tree selected in SharedPreferences.');
      }
    } catch (e) {
      print('TreeProvider: Error loading initial tree from SharedPreferences: $e');
    }
  }

  Future<void> selectTree(String? treeId, String? treeName) async {
    if (_selectedTreeId != treeId) {
      _selectedTreeId = treeId;
      _selectedTreeName = treeName;
      print('TreeProvider: Selected tree ID: $_selectedTreeId, Name: $_selectedTreeName');
      notifyListeners();
      try {
        final prefs = await SharedPreferences.getInstance();
        if (treeId == null) {
          await prefs.remove(_treeIdKey);
          await prefs.remove(_treeNameKey);
           print('TreeProvider: Cleared tree selection in SharedPreferences');
        } else {
          await prefs.setString(_treeIdKey, treeId);
          if (treeName != null) {
             await prefs.setString(_treeNameKey, treeName);
          } else {
             await prefs.remove(_treeNameKey);
          }
           print('TreeProvider: Saved tree selection to SharedPreferences');
        }
      } catch (e) {
         print('TreeProvider: Error saving tree selection to SharedPreferences: $e');
      }
    }
  }

  Future<void> clearSelection() async {
    await selectTree(null, null);
  }

  Future<void> selectDefaultTreeIfNeeded() async {
    if (_selectedTreeId == null) {
      print('TreeProvider: No tree currently selected. Checking cache for defaults...');
      try {
        final List<FamilyTree> availableTrees = await _localStorageService.getAllTrees();
        if (availableTrees.isNotEmpty) {
          final defaultTree = availableTrees.first;
          print('TreeProvider: Found ${availableTrees.length} trees in cache. Selecting first one as default: ${defaultTree.id}');
          await selectTree(defaultTree.id, defaultTree.name);
        } else {
          print('TreeProvider: No available trees found in cache.');
        }
      } catch (e) {
        print('TreeProvider: Error selecting default tree: $e');
      }
    }
  }
}