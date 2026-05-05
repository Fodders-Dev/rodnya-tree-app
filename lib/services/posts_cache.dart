import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';

import '../models/post.dart';

/// Per-tree posts cache.
///
/// Posts are scoped by tree (a tree's feed is independent), so the
/// Hive box uses `treeId` as the key and the value is the
/// JSON-encoded list of recent posts. Used by the home feed to
/// serve a cached batch immediately on tab-open / cold-start, then
/// refresh against the API in the background.
abstract class PostsCache {
  Future<List<Post>> read(String treeId);

  Future<void> write(String treeId, List<Post> posts);

  Future<void> remove(String treeId);

  Future<void> clearAll();
}

class HivePostsCache implements PostsCache {
  HivePostsCache({
    this.boxName = 'posts_v1',
    this.maxKeys = 30,
  });

  final String boxName;

  /// Soft cap on the number of distinct keys (trees + per-user-profile
  /// scopes). Each key holds up to 100 posts, so the worst case here
  /// is ~30 × 100 ≈ 3 000 cached posts on disk.
  final int maxKeys;

  Future<Box<String>>? _openTask;

  Future<Box<String>> _box() {
    if (Hive.isBoxOpen(boxName)) {
      return Future<Box<String>>.value(Hive.box<String>(boxName));
    }
    return _openTask ??= Hive.openBox<String>(boxName);
  }

  @override
  Future<List<Post>> read(String treeId) async {
    final trimmed = treeId.trim();
    if (trimmed.isEmpty) return const <Post>[];
    try {
      final raw = (await _box()).get(trimmed);
      if (raw == null || raw.trim().isEmpty) return const <Post>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) return const <Post>[];
      return decoded
          .whereType<Map>()
          .map((entry) => Post.fromJson(Map<String, dynamic>.from(entry)))
          .toList(growable: false);
    } catch (_) {
      return const <Post>[];
    }
  }

  @override
  Future<void> write(String treeId, List<Post> posts) async {
    final trimmed = treeId.trim();
    if (trimmed.isEmpty) return;
    try {
      // Cap at 100 posts per tree — the home feed lazy-loads more
      // as the user scrolls, no need to keep an unbounded list on
      // disk.
      final capped = posts.take(100).toList(growable: false);
      final box = await _box();
      if (box.containsKey(trimmed)) {
        // Re-insert: bump this key to the back of the keyset so it
        // counts as freshest on the next eviction sweep.
        await box.delete(trimmed);
      }
      await box.put(
        trimmed,
        jsonEncode(capped.map((p) => p.toJson()).toList(growable: false)),
      );
      await _evictExcess(box);
    } catch (_) {}
  }

  Future<void> _evictExcess(Box<String> box) async {
    if (maxKeys <= 0) return;
    final overflow = box.length - maxKeys;
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

class InMemoryPostsCache implements PostsCache {
  final Map<String, List<Post>> _store = <String, List<Post>>{};

  @override
  Future<List<Post>> read(String treeId) async =>
      List<Post>.of(_store[treeId] ?? const []);

  @override
  Future<void> write(String treeId, List<Post> posts) async {
    _store[treeId] = List<Post>.of(posts);
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
