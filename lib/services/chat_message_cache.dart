import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';

import '../models/chat_message.dart';
import 'hive_box_recovery.dart';

abstract class ChatMessageCache {
  Future<List<ChatMessage>> read(String chatId);

  Future<void> write(
    String chatId,
    List<ChatMessage> messages, {
    int keepCount = 200,
  });

  Future<void> mergePage(
    String chatId,
    List<ChatMessage> messages, {
    int keepCount = 200,
  });

  Future<void> appendOne(
    String chatId,
    ChatMessage message, {
    int keepCount = 200,
  });

  Future<void> removeOne(String chatId, String messageId);

  Future<void> evictOlder(String chatId, {int keepCount = 200});

  Future<void> clearAll();
}

class HiveChatMessageCache implements ChatMessageCache {
  HiveChatMessageCache({
    this.boxName = 'chat_messages_v1',
    this.maxChats = 120,
  });

  final String boxName;

  /// Soft cap on the number of distinct chats whose history we keep on
  /// disk. Each entry already trims to ~200 messages by `keepCount`,
  /// so the worst case here is ~120 × 200 ≈ 24 000 messages, plenty
  /// for the UI without unbounded disk growth.
  final int maxChats;

  Future<Box<String>>? _openTask;

  Future<Box<String>> _box() {
    return _openTask ??= openBoxWithRecovery<String>(boxName);
  }

  @override
  Future<List<ChatMessage>> read(String chatId) async {
    final normalizedChatId = chatId.trim();
    if (normalizedChatId.isEmpty) {
      return const <ChatMessage>[];
    }

    final rawValue = (await _box()).get(normalizedChatId);
    if (rawValue == null || rawValue.trim().isEmpty) {
      return const <ChatMessage>[];
    }

    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is! List<dynamic>) {
        return const <ChatMessage>[];
      }
      return _sortedMessages(
        decoded
            .whereType<Map>()
            .map((entry) =>
                ChatMessage.fromMap(Map<String, dynamic>.from(entry)))
            .toList(),
      );
    } catch (_) {
      return const <ChatMessage>[];
    }
  }

  @override
  Future<void> write(
    String chatId,
    List<ChatMessage> messages, {
    int keepCount = 200,
  }) async {
    final normalizedChatId = chatId.trim();
    if (normalizedChatId.isEmpty) {
      return;
    }

    final normalizedMessages = _trimmedMessages(messages, keepCount: keepCount);
    final box = await _box();
    if (box.containsKey(normalizedChatId)) {
      // Re-insert moves the entry to the back of the keyset so it
      // survives the next eviction sweep.
      await box.delete(normalizedChatId);
    }
    await box.put(
      normalizedChatId,
      jsonEncode(
        normalizedMessages.map(_messageToJson).toList(growable: false),
      ),
    );
    await _evictExcess(box);
  }

  Future<void> _evictExcess(Box<String> box) async {
    if (maxChats <= 0) return;
    final overflow = box.length - maxChats;
    if (overflow <= 0) return;
    final keysToEvict = box.keys.take(overflow).toList(growable: false);
    for (final key in keysToEvict) {
      await box.delete(key);
    }
  }

  @override
  Future<void> mergePage(
    String chatId,
    List<ChatMessage> messages, {
    int keepCount = 200,
  }) async {
    if (messages.isEmpty) {
      return;
    }
    await write(
      chatId,
      <ChatMessage>[
        ...await read(chatId),
        ...messages,
      ],
      keepCount: keepCount,
    );
  }

  @override
  Future<void> appendOne(
    String chatId,
    ChatMessage message, {
    int keepCount = 200,
  }) {
    return mergePage(chatId, <ChatMessage>[message], keepCount: keepCount);
  }

  @override
  Future<void> removeOne(String chatId, String messageId) async {
    final normalizedMessageId = messageId.trim();
    if (normalizedMessageId.isEmpty) {
      return;
    }

    final nextMessages = (await read(chatId))
        .where((message) => message.id != normalizedMessageId)
        .toList(growable: false);
    await write(chatId, nextMessages);
  }

  @override
  Future<void> evictOlder(String chatId, {int keepCount = 200}) async {
    await write(chatId, await read(chatId), keepCount: keepCount);
  }

  @override
  Future<void> clearAll() async {
    try {
      await (await _box()).clear();
    } catch (_) {}
  }

  Map<String, dynamic> _messageToJson(ChatMessage message) {
    return <String, dynamic>{
      ...message.toMap(),
      'id': message.id,
    };
  }

  List<ChatMessage> _trimmedMessages(
    List<ChatMessage> messages, {
    required int keepCount,
  }) {
    final byId = <String, ChatMessage>{};
    for (final message in messages) {
      if (message.id.trim().isEmpty) {
        continue;
      }
      byId[message.id] = message;
    }

    final sortedMessages = _sortedMessages(byId.values);
    if (keepCount <= 0 || sortedMessages.length <= keepCount) {
      return sortedMessages;
    }
    return sortedMessages.take(keepCount).toList(growable: false);
  }

  List<ChatMessage> _sortedMessages(Iterable<ChatMessage> messages) {
    final sortedMessages = messages.toList();
    sortedMessages.sort((left, right) {
      final timestampCompare = right.timestamp.compareTo(left.timestamp);
      if (timestampCompare != 0) {
        return timestampCompare;
      }
      return right.id.compareTo(left.id);
    });
    return sortedMessages;
  }
}
