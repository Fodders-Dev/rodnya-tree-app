import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ChatDraftSnapshot {
  const ChatDraftSnapshot({
    required this.text,
    required this.updatedAt,
  });

  final String text;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'text': text,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ChatDraftSnapshot.fromJson(Map<String, dynamic> json) {
    return ChatDraftSnapshot(
      text: json['text']?.toString() ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

abstract class ChatDraftStore {
  Future<ChatDraftSnapshot?> getDraft(String key);

  Future<Map<String, ChatDraftSnapshot>> getAllDrafts();

  Future<void> saveDraft(String key, String text);

  Future<void> clearDraft(String key);
}

class SharedPreferencesChatDraftStore implements ChatDraftStore {
  const SharedPreferencesChatDraftStore();

  static const String _prefix = 'chat_draft_v1:';

  static String chatKey(String chatId) => 'chat:$chatId';

  static String directUserKey(String userId) => 'user:$userId';

  @override
  Future<ChatDraftSnapshot?> getDraft(String key) async {
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
      final snapshot = ChatDraftSnapshot.fromJson(decoded);
      return snapshot.text.trim().isEmpty ? null : snapshot;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, ChatDraftSnapshot>> getAllDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = <String, ChatDraftSnapshot>{};

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

        final snapshot = ChatDraftSnapshot.fromJson(decoded);
        if (snapshot.text.trim().isEmpty) {
          continue;
        }

        drafts[entry.substring(_prefix.length)] = snapshot;
      } catch (_) {
        continue;
      }
    }

    return drafts;
  }

  @override
  Future<void> saveDraft(String key, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      await clearDraft(key);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final snapshot = ChatDraftSnapshot(
      text: text,
      updatedAt: DateTime.now(),
    );
    await prefs.setString('$_prefix$key', jsonEncode(snapshot.toJson()));
  }

  @override
  Future<void> clearDraft(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$key');
  }
}
