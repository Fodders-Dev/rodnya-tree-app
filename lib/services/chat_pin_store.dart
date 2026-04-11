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
