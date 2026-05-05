import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';

import '../models/user_profile.dart';
import 'hive_box_recovery.dart';

/// On-disk cache for the current user's profile.
///
/// Reasons we want this:
/// - Profile screen waits for `getUserProfile` + `getUserTrees` +
///   `getRelatives` per tree + `getPosts` + `_pendingContributions`
///   serially. On a cold start with a slow network the screen sits on
///   a spinner for 1.5–3 s while every roundtrip ladders up.
/// - The header fields are tiny (name, avatar, profileCode) — caching
///   them lets us paint the chrome immediately and progressively swap
///   in fresh data when the API answers.
///
/// Storage shape mirrors the other Hive caches in this folder: one
/// JSON-encoded blob keyed by user id. We deliberately don't sync
/// secondary collections (posts, trees, contributions) here — those
/// already have their own caches (`PostsCache` / `TreeGraphCache`).
abstract class UserProfileCache {
  Future<UserProfile?> read(String userId);

  Future<void> write(UserProfile profile);

  Future<void> clear(String userId);

  Future<void> clearAll();
}

class HiveUserProfileCache implements UserProfileCache {
  HiveUserProfileCache({
    this.boxName = 'user_profile_v1',
    this.maxEntries = 6,
  });

  final String boxName;

  /// Soft cap on cached user profiles. We only ever cache the current
  /// user's profile, but keep room for a few past users to handle
  /// account-switching without re-network on the immediate next
  /// signin to a recently-used account.
  final int maxEntries;

  Future<Box<String>>? _openTask;

  Future<Box<String>> _box() {
    return _openTask ??= openBoxWithRecovery<String>(boxName);
  }

  @override
  Future<UserProfile?> read(String userId) async {
    if (userId.isEmpty) return null;
    try {
      final raw = (await _box()).get(userId);
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return UserProfile.fromMap(
        Map<String, dynamic>.from(decoded),
        userId,
      );
    } catch (_) {
      // Corrupt blob → swallow, let API repopulate.
      return null;
    }
  }

  @override
  Future<void> write(UserProfile profile) async {
    if (profile.id.isEmpty) return;
    try {
      final box = await _box();
      if (box.containsKey(profile.id)) {
        await box.delete(profile.id);
      }
      await box.put(profile.id, jsonEncode(profile.toMap()));
      await _evictExcess(box);
    } catch (_) {
      // Best-effort.
    }
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
  Future<void> clear(String userId) async {
    if (userId.isEmpty) return;
    try {
      await (await _box()).delete(userId);
    } catch (_) {}
  }

  @override
  Future<void> clearAll() async {
    try {
      await (await _box()).clear();
    } catch (_) {}
  }
}

class InMemoryUserProfileCache implements UserProfileCache {
  final Map<String, UserProfile> _store = <String, UserProfile>{};

  @override
  Future<UserProfile?> read(String userId) async => _store[userId];

  @override
  Future<void> write(UserProfile profile) async {
    _store[profile.id] = profile;
  }

  @override
  Future<void> clear(String userId) async {
    _store.remove(userId);
  }

  @override
  Future<void> clearAll() async {
    _store.clear();
  }
}
