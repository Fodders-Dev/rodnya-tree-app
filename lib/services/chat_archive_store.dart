import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ChatArchiveSnapshot {
  const ChatArchiveSnapshot({
    required this.archivedAt,
  });

  final DateTime archivedAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'archivedAt': archivedAt.toIso8601String(),
    };
  }

  factory ChatArchiveSnapshot.fromJson(Map<String, dynamic> json) {
    return ChatArchiveSnapshot(
      archivedAt: DateTime.tryParse(json['archivedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

abstract class ChatArchiveStore {
  Future<ChatArchiveSnapshot?> getArchivedChat(String key);

  Future<Map<String, ChatArchiveSnapshot>> getAllArchivedChats();

  Future<void> saveArchivedChat(String key, ChatArchiveSnapshot snapshot);

  Future<void> clearArchivedChat(String key);
}

class SharedPreferencesChatArchiveStore implements ChatArchiveStore {
  const SharedPreferencesChatArchiveStore();

  static const String _prefix = 'chat_archive_v1:';

  static String chatKey(String chatId) => 'chat:$chatId';

  static String directUserKey(String userId) => 'user:$userId';

  @override
  Future<ChatArchiveSnapshot?> getArchivedChat(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$key');
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return ChatArchiveSnapshot.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, ChatArchiveSnapshot>> getAllArchivedChats() async {
    final prefs = await SharedPreferences.getInstance();
    final archives = <String, ChatArchiveSnapshot>{};

    for (final entry in prefs.getKeys()) {
      if (!entry.startsWith(_prefix)) {
        continue;
      }

      final raw = prefs.getString(entry);
      if (raw == null || raw.isEmpty) {
        continue;
      }

      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          continue;
        }
        archives[entry.substring(_prefix.length)] =
            ChatArchiveSnapshot.fromJson(decoded);
      } catch (_) {
        continue;
      }
    }

    return archives;
  }

  @override
  Future<void> saveArchivedChat(
    String key,
    ChatArchiveSnapshot snapshot,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$key', jsonEncode(snapshot.toJson()));
  }

  @override
  Future<void> clearArchivedChat(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$key');
  }
}
