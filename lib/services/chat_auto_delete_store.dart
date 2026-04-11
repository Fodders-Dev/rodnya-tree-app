import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum ChatAutoDeleteOption { off, oneHour, oneDay, sevenDays }

extension ChatAutoDeleteOptionX on ChatAutoDeleteOption {
  String get label {
    switch (this) {
      case ChatAutoDeleteOption.off:
        return 'Выключено';
      case ChatAutoDeleteOption.oneHour:
        return '1 час';
      case ChatAutoDeleteOption.oneDay:
        return '1 день';
      case ChatAutoDeleteOption.sevenDays:
        return '7 дней';
    }
  }

  String get summary {
    switch (this) {
      case ChatAutoDeleteOption.off:
        return 'Сообщения остаются в истории, пока кто-то не удалит их вручную.';
      case ChatAutoDeleteOption.oneHour:
        return 'Новые сообщения этого чата исчезают через час после отправки.';
      case ChatAutoDeleteOption.oneDay:
        return 'Новые сообщения этого чата исчезают через сутки после отправки.';
      case ChatAutoDeleteOption.sevenDays:
        return 'Новые сообщения этого чата исчезают через неделю после отправки.';
    }
  }

  Duration? get ttl {
    switch (this) {
      case ChatAutoDeleteOption.off:
        return null;
      case ChatAutoDeleteOption.oneHour:
        return const Duration(hours: 1);
      case ChatAutoDeleteOption.oneDay:
        return const Duration(days: 1);
      case ChatAutoDeleteOption.sevenDays:
        return const Duration(days: 7);
    }
  }

  static ChatAutoDeleteOption fromStorage(String rawValue) {
    return ChatAutoDeleteOption.values.firstWhere(
      (value) => value.name == rawValue,
      orElse: () => ChatAutoDeleteOption.off,
    );
  }
}

class ChatAutoDeleteSnapshot {
  const ChatAutoDeleteSnapshot({
    required this.option,
    required this.updatedAt,
  });

  ChatAutoDeleteSnapshot.defaults()
      : option = ChatAutoDeleteOption.off,
        updatedAt = DateTime.fromMillisecondsSinceEpoch(0);

  final ChatAutoDeleteOption option;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'option': option.name,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ChatAutoDeleteSnapshot.fromJson(Map<String, dynamic> json) {
    return ChatAutoDeleteSnapshot(
      option: ChatAutoDeleteOptionX.fromStorage(
        json['option']?.toString() ?? '',
      ),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

abstract class ChatAutoDeleteStore {
  Future<ChatAutoDeleteSnapshot?> getSettings(String key);

  Future<Map<String, ChatAutoDeleteSnapshot>> getAllSettings();

  Future<void> saveSettings(String key, ChatAutoDeleteSnapshot snapshot);

  Future<void> clearSettings(String key);
}

class SharedPreferencesChatAutoDeleteStore implements ChatAutoDeleteStore {
  const SharedPreferencesChatAutoDeleteStore();

  static const String _prefix = 'chat_auto_delete_v1:';

  static String chatKey(String chatId) => 'chat:$chatId';

  static String directUserKey(String userId) => 'user:$userId';

  @override
  Future<ChatAutoDeleteSnapshot?> getSettings(String key) async {
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
      return ChatAutoDeleteSnapshot.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, ChatAutoDeleteSnapshot>> getAllSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final entries = <String, ChatAutoDeleteSnapshot>{};

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
        final snapshot = ChatAutoDeleteSnapshot.fromJson(decoded);
        if (snapshot.option == ChatAutoDeleteOption.off) {
          continue;
        }
        entries[entry.substring(_prefix.length)] = snapshot;
      } catch (_) {
        continue;
      }
    }

    return entries;
  }

  @override
  Future<void> saveSettings(String key, ChatAutoDeleteSnapshot snapshot) async {
    if (snapshot.option == ChatAutoDeleteOption.off) {
      await clearSettings(key);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$key', jsonEncode(snapshot.toJson()));
  }

  @override
  Future<void> clearSettings(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$key');
  }
}
