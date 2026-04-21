import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/chat_message.dart';
import '../models/family_person.dart';
import '../models/family_relation.dart';
import '../models/family_tree.dart';
import '../models/user_profile.dart';

class LocalStorageService {
  static const String _boxUsers = 'usersBox';
  static const String _boxTrees = 'treesBox';
  static const String _boxPersons = 'personsBox';
  static const String _boxRelations = 'relationsBox';
  static const String _boxMessages = 'messagesBox';
  static const String _boxTreeLayouts = 'treeLayoutsBox';

  final Map<String, Future<Box<dynamic>>> _boxOpenTasks =
      <String, Future<Box<dynamic>>>{};
  final Map<String, Map<String, RelationType>> _relationCache =
      <String, Map<String, RelationType>>{};

  LocalStorageService._();

  static Future<LocalStorageService> createInstance() async {
    return LocalStorageService._();
  }

  Future<Box<UserProfile>> _usersBox() => _openBox<UserProfile>(_boxUsers);

  Future<Box<FamilyTree>> _treesBox() => _openBox<FamilyTree>(_boxTrees);

  Future<Box<FamilyPerson>> _personsBox() => _openBox<FamilyPerson>(_boxPersons);

  Future<Box<FamilyRelation>> _relationsBox() =>
      _openBox<FamilyRelation>(_boxRelations);

  Future<Box<ChatMessage>> _messagesBox() =>
      _openBox<ChatMessage>(_boxMessages);

  Future<Box<String>> _treeLayoutsBox() => _openBox<String>(_boxTreeLayouts);

  Future<Box<T>> _openBox<T>(String boxName) async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box<T>(boxName);
    }

    final existingTask = _boxOpenTasks[boxName];
    if (existingTask != null) {
      return (await existingTask) as Box<T>;
    }

    final openTask =
        Hive.openBox<T>(boxName).then<Box<dynamic>>((box) => box);
    _boxOpenTasks[boxName] = openTask;

    try {
      final box = await openTask;
      return box as Box<T>;
    } catch (_) {
      _boxOpenTasks.remove(boxName);
      rethrow;
    }
  }

  Future<void> saveUser(UserProfile user) async {
    final box = await _usersBox();
    await box.put(user.id, user);
  }

  Future<UserProfile?> getUser(String userId) async {
    final box = await _usersBox();
    return box.get(userId);
  }

  Future<void> deleteUser(String userId) async {
    try {
      final box = await _usersBox();
      await box.delete(userId);
    } catch (error) {
      debugPrint('LocalStorage: Error deleting user $userId: $error');
    }
  }

  Future<void> saveTree(FamilyTree tree) async {
    final box = await _treesBox();
    await box.put(tree.id, tree);
  }

  Future<void> saveTrees(List<FamilyTree> trees) async {
    try {
      final box = await _treesBox();
      await box.clear();
      final treesMap = <String, FamilyTree>{for (final tree in trees) tree.id: tree};
      if (treesMap.isNotEmpty) {
        await box.putAll(treesMap);
      }
    } catch (error) {
      debugPrint('LocalStorage: Error saving trees: $error');
    }
  }

  Future<List<FamilyTree>> getAllTrees() async {
    final box = await _treesBox();
    return box.values.toList();
  }

  Future<FamilyTree?> getTree(String treeId) async {
    final box = await _treesBox();
    return box.get(treeId);
  }

  Future<void> deleteTree(String treeId) async {
    try {
      final box = await _treesBox();
      await box.delete(treeId);
      await clearTreeNodePositions(treeId);
    } catch (error) {
      debugPrint('LocalStorage: Error deleting tree $treeId: $error');
    }
  }

  Future<void> deletePersonsByTreeId(String treeId) async {
    final box = await _personsBox();
    final keysToDelete = box.keys.where((key) {
      final person = box.get(key);
      return person?.treeId == treeId;
    }).toList();
    if (keysToDelete.isEmpty) {
      return;
    }
    await box.deleteAll(keysToDelete);
  }

  Future<void> deleteRelationsByTreeId(String treeId) async {
    final box = await _relationsBox();
    final keysToDelete = box.keys.where((key) {
      final relation = box.get(key);
      return relation?.treeId == treeId;
    }).toList();
    if (keysToDelete.isEmpty) {
      clearRelationCacheForTree(treeId);
      return;
    }
    await box.deleteAll(keysToDelete);
    clearRelationCacheForTree(treeId);
  }

  Future<Map<String, Offset>> getTreeNodePositions(String treeId) async {
    final box = await _treeLayoutsBox();
    final rawValue = box.get(treeId);
    if (rawValue == null || rawValue.isEmpty) {
      return const <String, Offset>{};
    }

    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is! Map<String, dynamic>) {
        return const <String, Offset>{};
      }

      final positions = <String, Offset>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! Map<String, dynamic>) {
          continue;
        }
        final dx = (value['x'] as num?)?.toDouble();
        final dy = (value['y'] as num?)?.toDouble();
        if (dx == null || dy == null) {
          continue;
        }
        positions[entry.key] = Offset(dx, dy);
      }
      return positions;
    } catch (error) {
      debugPrint(
        'LocalStorage: Failed to decode node positions for tree $treeId: $error',
      );
      return const <String, Offset>{};
    }
  }

  Future<void> saveTreeNodePositions(
    String treeId,
    Map<String, Offset> positions,
  ) async {
    final box = await _treeLayoutsBox();
    if (positions.isEmpty) {
      await box.delete(treeId);
      return;
    }

    final normalized = <String, Map<String, double>>{};
    for (final entry in positions.entries) {
      normalized[entry.key] = <String, double>{
        'x': entry.value.dx,
        'y': entry.value.dy,
      };
    }
    await box.put(treeId, jsonEncode(normalized));
  }

  Future<void> clearTreeNodePositions(String treeId) async {
    final box = await _treeLayoutsBox();
    await box.delete(treeId);
  }

  Future<void> savePerson(FamilyPerson person) async {
    final box = await _personsBox();
    await box.put(person.id, person);
  }

  Future<FamilyPerson?> getPerson(String personId) async {
    final box = await _personsBox();
    return box.get(personId);
  }

  Future<List<FamilyPerson>> getPersonsByTreeId(String treeId) async {
    final box = await _personsBox();
    return box.values.where((person) => person.treeId == treeId).toList();
  }

  Future<void> savePersons(List<FamilyPerson> persons) async {
    if (persons.isEmpty) {
      return;
    }
    final box = await _personsBox();
    final personsMap = <String, FamilyPerson>{
      for (final person in persons) person.id: person,
    };
    await box.putAll(personsMap);
  }

  Future<void> saveRelation(FamilyRelation relation) async {
    final box = await _relationsBox();
    await box.put(relation.id, relation);
    clearRelationCacheForTree(relation.treeId);
  }

  Future<void> saveRelations(List<FamilyRelation> relations) async {
    if (relations.isEmpty) {
      return;
    }
    final box = await _relationsBox();
    final relationsMap = <String, FamilyRelation>{
      for (final relation in relations) relation.id: relation,
    };
    await box.putAll(relationsMap);
    final treeIds = relations.map((relation) => relation.treeId).toSet();
    for (final treeId in treeIds) {
      clearRelationCacheForTree(treeId);
    }
  }

  Future<List<FamilyRelation>> getRelationsByTreeId(String treeId) async {
    final box = await _relationsBox();
    return box.values.where((relation) => relation.treeId == treeId).toList();
  }

  String _getRelationCacheKey(String id1, String id2) {
    return id1.compareTo(id2) < 0 ? '${id1}_$id2' : '${id2}_$id1';
  }

  RelationType? getCachedRelationBetween(
    String treeId,
    String user1Id,
    String user2Id,
  ) {
    final treeCache = _relationCache[treeId];
    if (treeCache == null) {
      return null;
    }
    final pairKey = _getRelationCacheKey(user1Id, user2Id);
    final cachedRelation = treeCache[pairKey];
    if (cachedRelation == null) {
      return null;
    }
    final isDirectOrder = user1Id.compareTo(user2Id) < 0;
    return isDirectOrder
        ? cachedRelation
        : FamilyRelation.getMirrorRelation(cachedRelation);
  }

  void cacheRelationBetween(
    String treeId,
    String user1Id,
    String user2Id,
    RelationType relation,
  ) {
    _relationCache.putIfAbsent(treeId, () => <String, RelationType>{});
    final pairKey = _getRelationCacheKey(user1Id, user2Id);
    final relationToCache = user1Id.compareTo(user2Id) < 0
        ? relation
        : FamilyRelation.getMirrorRelation(relation);
    _relationCache[treeId]![pairKey] = relationToCache;
  }

  void clearRelationCacheForTree(String treeId) {
    _relationCache.remove(treeId);
  }

  Future<void> saveMessage(ChatMessage message) async {
    final box = await _messagesBox();
    await box.put(message.id, message);
  }

  Future<List<ChatMessage>> getMessagesByChatId(String chatId) async {
    final box = await _messagesBox();
    final messages = box.values.where((message) => message.chatId == chatId).toList();
    messages.sort((left, right) => left.getDateTime().compareTo(right.getDateTime()));
    return messages;
  }

  Future<void> clearCache() async {
    try {
      await (await _usersBox()).clear();
      await (await _treesBox()).clear();
      await (await _personsBox()).clear();
      await (await _relationsBox()).clear();
      await (await _messagesBox()).clear();
      await (await _treeLayoutsBox()).clear();
      _relationCache.clear();
    } catch (error) {
      debugPrint('Error clearing Hive cache: $error');
    }
  }

  Future<void> deleteRelative(String personId) async {
    final box = await _personsBox();
    final person = box.get(personId);
    await box.delete(personId);
    if (person != null) {
      clearRelationCacheForTree(person.treeId);
    }
  }

  Future<void> deleteRelationsByPersonId(String treeId, String personId) async {
    final box = await _relationsBox();
    final keysToDelete = box.keys.where((key) {
      final relation = box.get(key);
      return relation != null &&
          relation.treeId == treeId &&
          (relation.person1Id == personId || relation.person2Id == personId);
    }).toList();

    if (keysToDelete.isEmpty) {
      return;
    }

    await box.deleteAll(keysToDelete);
    clearRelationCacheForTree(treeId);
  }
}
