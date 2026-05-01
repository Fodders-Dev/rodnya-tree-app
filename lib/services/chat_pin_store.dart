import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ChatPinnedMessageSnapshot {
  const ChatPinnedMessageSnapshot({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.attachmentCount,
    required this.pinnedAt,
  });

  final String messageId;
  final String senderId;
  final String senderName;
  final String text;
  final int attachmentCount;
  final DateTime pinnedAt;

  ChatPinnedMessageSnapshot copyWith({
    String? senderId,
    String? senderName,
    String? text,
    int? attachmentCount,
    DateTime? pinnedAt,
  }) {
    return ChatPinnedMessageSnapshot(
      messageId: messageId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      text: text ?? this.text,
      attachmentCount: attachmentCount ?? this.attachmentCount,
      pinnedAt: pinnedAt ?? this.pinnedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'messageId': messageId,
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'attachmentCount': attachmentCount,
      'pinnedAt': pinnedAt.toIso8601String(),
    };
  }

  factory ChatPinnedMessageSnapshot.fromJson(Map<String, dynamic> json) {
    return ChatPinnedMessageSnapshot(
      messageId: json['messageId']?.toString() ?? '',
      senderId: json['senderId']?.toString() ?? '',
      senderName: json['senderName']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      attachmentCount: (json['attachmentCount'] as num?)?.toInt() ?? 0,
      pinnedAt: DateTime.tryParse(json['pinnedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

abstract class ChatPinStore {
  Future<ChatPinnedMessageSnapshot?> getPinnedMessage(String key);

  Future<void> savePinnedMessage(
    String key,
    ChatPinnedMessageSnapshot snapshot,
  );

  Future<void> clearPinnedMessage(String key);
}

abstract class RemoteChatPinClient {
  Future<ChatPinnedMessageSnapshot?> getChatPinnedMessage(String chatId);

  Future<ChatPinnedMessageSnapshot?> pinChatMessage({
    required String chatId,
    required String messageId,
  });

  Future<void> clearChatPinnedMessage(String chatId);
}

class SharedPreferencesChatPinStore implements ChatPinStore {
  const SharedPreferencesChatPinStore();

  static const String _prefix = 'chat_pin_v1:';

  static String chatKey(String chatId) => 'chat:$chatId';

  static String directUserKey(String userId) => 'user:$userId';

  @override
  Future<ChatPinnedMessageSnapshot?> getPinnedMessage(String key) async {
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
      final snapshot = ChatPinnedMessageSnapshot.fromJson(decoded);
      return snapshot.messageId.trim().isEmpty ? null : snapshot;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> savePinnedMessage(
    String key,
    ChatPinnedMessageSnapshot snapshot,
  ) async {
    if (snapshot.messageId.trim().isEmpty) {
      await clearPinnedMessage(key);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$key', jsonEncode(snapshot.toJson()));
  }

  @override
  Future<void> clearPinnedMessage(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$key');
  }
}

class HybridChatPinStore implements ChatPinStore {
  const HybridChatPinStore({
    required this.localStore,
    required this.remoteClient,
  });

  final ChatPinStore localStore;
  final RemoteChatPinClient remoteClient;

  static String? chatIdFromKey(String key) {
    const prefix = 'chat:';
    if (!key.startsWith(prefix)) {
      return null;
    }
    final chatId = key.substring(prefix.length).trim();
    return chatId.isEmpty ? null : chatId;
  }

  static String keyForChatId(String chatId) {
    return SharedPreferencesChatPinStore.chatKey(chatId);
  }

  Future<void> saveLocalPinnedMessage(
    String key,
    ChatPinnedMessageSnapshot snapshot,
  ) {
    return localStore.savePinnedMessage(key, snapshot);
  }

  Future<void> clearLocalPinnedMessage(String key) {
    return localStore.clearPinnedMessage(key);
  }

  @override
  Future<ChatPinnedMessageSnapshot?> getPinnedMessage(String key) async {
    final localSnapshot = await localStore.getPinnedMessage(key);
    final chatId = chatIdFromKey(key);
    if (chatId == null) {
      return localSnapshot;
    }

    try {
      final remoteSnapshot = await remoteClient.getChatPinnedMessage(chatId);
      if (remoteSnapshot == null || remoteSnapshot.messageId.trim().isEmpty) {
        return localSnapshot;
      }
      if (localSnapshot == null ||
          remoteSnapshot.pinnedAt.isAfter(localSnapshot.pinnedAt)) {
        await localStore.savePinnedMessage(key, remoteSnapshot);
        return remoteSnapshot;
      }
      return localSnapshot;
    } catch (_) {
      return localSnapshot;
    }
  }

  @override
  Future<void> savePinnedMessage(
    String key,
    ChatPinnedMessageSnapshot snapshot,
  ) async {
    await localStore.savePinnedMessage(key, snapshot);
    final chatId = chatIdFromKey(key);
    if (chatId == null) {
      return;
    }
    try {
      final remoteSnapshot = await remoteClient.pinChatMessage(
        chatId: chatId,
        messageId: snapshot.messageId,
      );
      if (remoteSnapshot != null &&
          remoteSnapshot.messageId.trim().isNotEmpty) {
        await localStore.savePinnedMessage(key, remoteSnapshot);
      }
    } catch (_) {
      // Local pin remains available when backend pin sync is offline/unsupported.
    }
  }

  @override
  Future<void> clearPinnedMessage(String key) async {
    await localStore.clearPinnedMessage(key);
    final chatId = chatIdFromKey(key);
    if (chatId == null) {
      return;
    }
    try {
      await remoteClient.clearChatPinnedMessage(chatId);
    } catch (_) {
      // Local clear should not be rolled back by a transient backend failure.
    }
  }
}
