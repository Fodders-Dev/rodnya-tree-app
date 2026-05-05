import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';

/// On-disk cache for the family-tree graph snapshot keyed by treeId.
///
/// We persist the raw API JSON map (the value of `response['snapshot']`)
/// rather than the parsed [TreeGraphSnapshot] — round-tripping the
/// nested model would require adding `toJson` to ~6 nested classes,
/// while the raw map already round-trips cleanly through
/// [TreeGraphSnapshot.fromJson]. Used by `CustomApiFamilyTreeService`
/// so opening a tree cold-start (or while offline) shows the last
/// known graph immediately, with the API call repopulating it in the
/// background.
abstract class TreeGraphCache {
  Future<Map<String, dynamic>?> read(String treeId);

  Future<void> write(String treeId, Map<String, dynamic> snapshotJson);

  Future<void> remove(String treeId);

  Future<void> clearAll();
}

class HiveTreeGraphCache implements TreeGraphCache {
  HiveTreeGraphCache({
    this.boxName = 'tree_graph_v1',
    this.maxEntries = 12,
  });

  final String boxName;

  /// Soft cap on cached trees. A user typically owns 1–3 trees plus a
  /// handful they're a member of; 12 is a generous cushion that
  /// keeps the on-disk size bounded.
  final int maxEntries;

  Future<Box<String>>? _openTask;

  Future<Box<String>> _box() {
    if (Hive.isBoxOpen(boxName)) {
      return Future<Box<String>>.value(Hive.box<String>(boxName));
    }
    return _openTask ??= Hive.openBox<String>(boxName);
  }

  @override
  Future<Map<String, dynamic>?> read(String treeId) async {
    final trimmed = treeId.trim();
    if (trimmed.isEmpty) return null;
    try {
      final raw = (await _box()).get(trimmed);
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String treeId, Map<String, dynamic> snapshotJson) async {
    final trimmed = treeId.trim();
    if (trimmed.isEmpty) return;
    try {
      final box = await _box();
      if (box.containsKey(trimmed)) {
        await box.delete(trimmed);
      }
      await box.put(trimmed, jsonEncode(snapshotJson));
      await _evictExcess(box);
    } catch (_) {}
  }

  Future<void> _evictExcess(Box<String> box) async {
    if (maxEntries <= 0) return;
    final overflow = box.length - maxEntries;
    if (overflow <= 0) return;
    final keysToEvict = box.keys.take(overflow).toList(growable: false);
    for (final key in keysToEvict) {
      await box.delete(key);
    }
  }

  @override
  Future<void> remove(String treeId) async {
    final trimmed = treeId.trim();
    if (trimmed.isEmpty) return;
    try {
      await (await _box()).delete(trimmed);
    } catch (_) {}
  }

  @override
  Future<void> clearAll() async {
    try {
      await (await _box()).clear();
    } catch (_) {}
  }
}

class InMemoryTreeGraphCache implements TreeGraphCache {
  final Map<String, Map<String, dynamic>> _store =
      <String, Map<String, dynamic>>{};

  @override
  Future<Map<String, dynamic>?> read(String treeId) async => _store[treeId];

  @override
  Future<void> write(String treeId, Map<String, dynamic> snapshotJson) async {
    _store[treeId] = snapshotJson;
  }

  @override
  Future<void> remove(String treeId) async {
    _store.remove(treeId);
  }

  @override
  Future<void> clearAll() async {
    _store.clear();
  }
}
