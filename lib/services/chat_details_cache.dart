import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';

import '../models/chat_details.dart';

/// Per-chat details cache (title / participants / branch roots / etc).
///
/// Mirrors [ChatPreviewCache] / [ChatMessageCache] — Hive box keyed by
/// chatId. Used by the chat screen so opening a chat while offline
/// shows the title + member list pulled from cache instead of a
/// "Чат недоступен" / loading spinner. Each entry is a JSON-encoded
/// `ChatDetails.toMap()` blob.
abstract class ChatDetailsCache {
  Future<ChatDetails?> read(String chatId);

  Future<void> write(String chatId, ChatDetails details);

  Future<void> remove(String chatId);

  Future<void> clearAll();
}

class HiveChatDetailsCache implements ChatDetailsCache {
  HiveChatDetailsCache({
    this.boxName = 'chat_details_v1',
    this.maxEntries = 80,
  });

  final String boxName;

  /// Soft cap on the number of cached chats. After each write we
  /// drop the oldest-INSERTED entries beyond this. Approximates LRU
  /// well enough since chat-details writes happen on chat open, so
  /// recently opened chats sit at the back of the keyset.
  final int maxEntries;

  Future<Box<String>>? _openTask;

  Future<Box<String>> _box() {
    if (Hive.isBoxOpen(boxName)) {
      return Future<Box<String>>.value(Hive.box<String>(boxName));
    }
    return _openTask ??= Hive.openBox<String>(boxName);
  }

  @override
  Future<ChatDetails?> read(String chatId) async {
    final trimmed = chatId.trim();
    if (trimmed.isEmpty) return null;
    try {
      final raw = (await _box()).get(trimmed);
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return ChatDetails.fromMap(Map<String, dynamic>.from(decoded));
    } catch (_) {
      // Corrupt entry → swallow and let the API refresh repopulate.
      return null;
    }
  }

  @override
  Future<void> write(String chatId, ChatDetails details) async {
    final trimmed = chatId.trim();
    if (trimmed.isEmpty) return;
    try {
      final box = await _box();
      // Re-insert puts the entry at the END of the keyset (Hive
      // returns keys in insertion order). On next eviction this
      // entry is the freshest so it survives.
      if (box.containsKey(trimmed)) {
        await box.delete(trimmed);
      }
      await box.put(trimmed, jsonEncode(details.toMap()));
      await _evictExcess(box);
    } catch (_) {
      // Best-effort — never fail the foreground call because of cache.
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
  Future<void> remove(String chatId) async {
    final trimmed = chatId.trim();
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

/// Test helper that keeps everything in memory.
class InMemoryChatDetailsCache implements ChatDetailsCache {
  final Map<String, ChatDetails> _store = <String, ChatDetails>{};

  @override
  Future<ChatDetails?> read(String chatId) async => _store[chatId];

  @override
  Future<void> write(String chatId, ChatDetails details) async {
    _store[chatId] = details;
  }

  @override
  Future<void> remove(String chatId) async {
    _store.remove(chatId);
  }

  @override
  Future<void> clearAll() async {
    _store.clear();
  }
}
