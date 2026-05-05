import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';

import '../models/user_profile.dart';

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
}

class HiveUserProfileCache implements UserProfileCache {
  HiveUserProfileCache({this.boxName = 'user_profile_v1'});

  final String boxName;
  Future<Box<String>>? _openTask;

  Future<Box<String>> _box() {
    if (Hive.isBoxOpen(boxName)) {
      return Future<Box<String>>.value(Hive.box<String>(boxName));
    }
    return _openTask ??= Hive.openBox<String>(boxName);
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
      await (await _box()).put(profile.id, jsonEncode(profile.toMap()));
    } catch (_) {
      // Best-effort.
    }
  }

  @override
  Future<void> clear(String userId) async {
    if (userId.isEmpty) return;
    try {
      await (await _box()).delete(userId);
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
}
