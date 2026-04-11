import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ChatMessageReactionEntry {
  const ChatMessageReactionEntry({
    required this.messageId,
    required this.emoji,
    required this.userId,
    required this.userName,
    required this.reactedAt,
  });

  final String messageId;
  final String emoji;
  final String userId;
  final String userName;
  final DateTime reactedAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'messageId': messageId,
      'emoji': emoji,
      'userId': userId,
      'userName': userName,
      'reactedAt': reactedAt.toIso8601String(),
    };
  }

  factory ChatMessageReactionEntry.fromJson(Map<String, dynamic> json) {
    return ChatMessageReactionEntry(
      messageId: json['messageId']?.toString() ?? '',
      emoji: json['emoji']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      userName: json['userName']?.toString() ?? '',
      reactedAt: DateTime.tryParse(json['reactedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class ChatReactionCatalogSnapshot {
  const ChatReactionCatalogSnapshot({
    required this.updatedAt,
    required this.reactionsByMessage,
  });

  final DateTime updatedAt;
  final Map<String, List<ChatMessageReactionEntry>> reactionsByMessage;

  bool get isEmpty => reactionsByMessage.values.every((items) => items.isEmpty);

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'updatedAt': updatedAt.toIso8601String(),
      'reactionsByMessage': reactionsByMessage.map(
        (messageId, entries) => MapEntry(
          messageId,
          entries.map((entry) => entry.toJson()).toList(),
        ),
      ),
    };
  }

  factory ChatReactionCatalogSnapshot.fromJson(Map<String, dynamic> json) {
    final rawMap = json['reactionsByMessage'];
    final reactionsByMessage = <String, List<ChatMessageReactionEntry>>{};
    if (rawMap is Map) {
      for (final entry in rawMap.entries) {
        final messageId = entry.key.toString();
        final rawEntries = entry.value;
        if (messageId.trim().isEmpty || rawEntries is! List) {
          continue;
        }
        final parsedEntries = rawEntries
            .whereType<Map>()
            .map(
              (item) => ChatMessageReactionEntry.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .where(
              (item) =>
                  item.messageId.trim().isNotEmpty &&
                  item.userId.trim().isNotEmpty &&
                  item.emoji.trim().isNotEmpty,
            )
            .toList();
        if (parsedEntries.isNotEmpty) {
          reactionsByMessage[messageId] = parsedEntries;
        }
      }
    }

    return ChatReactionCatalogSnapshot(
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      reactionsByMessage: reactionsByMessage,
    );
  }
}

abstract class ChatReactionStore {
  Future<ChatReactionCatalogSnapshot?> getCatalog(String key);

  Future<void> saveCatalog(String key, ChatReactionCatalogSnapshot snapshot);

  Future<void> clearCatalog(String key);
}

class SharedPreferencesChatReactionStore implements ChatReactionStore {
  const SharedPreferencesChatReactionStore();

  static const String _prefix = 'chat_reactions_v1:';

  static String chatKey(String chatId) => 'chat:$chatId';

  static String directUserKey(String userId) => 'user:$userId';

  @override
  Future<ChatReactionCatalogSnapshot?> getCatalog(String key) async {
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
      final snapshot = ChatReactionCatalogSnapshot.fromJson(decoded);
      return snapshot.isEmpty ? null : snapshot;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveCatalog(
    String key,
    ChatReactionCatalogSnapshot snapshot,
  ) async {
    if (snapshot.isEmpty) {
      await clearCatalog(key);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$key', jsonEncode(snapshot.toJson()));
  }

  @override
  Future<void> clearCatalog(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$key');
  }
}
