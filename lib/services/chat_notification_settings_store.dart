import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum ChatNotificationLevel { all, silent, muted }

extension ChatNotificationLevelX on ChatNotificationLevel {
  String get label {
    switch (this) {
      case ChatNotificationLevel.all:
        return 'Все уведомления';
      case ChatNotificationLevel.silent:
        return 'Тихо';
      case ChatNotificationLevel.muted:
        return 'Выключены';
    }
  }

  String get summary {
    switch (this) {
      case ChatNotificationLevel.all:
        return 'Сообщения этого чата приходят как обычно.';
      case ChatNotificationLevel.silent:
        return 'Новые сообщения показываются без звука, но чат не выпадает из потока.';
      case ChatNotificationLevel.muted:
        return 'Чат останется в списке и сохранит unread, но локальные уведомления не будут всплывать.';
    }
  }

  static ChatNotificationLevel fromStorage(String rawValue) {
    return ChatNotificationLevel.values.firstWhere(
      (value) => value.name == rawValue,
      orElse: () => ChatNotificationLevel.all,
    );
  }
}

class ChatNotificationSettingsSnapshot {
  const ChatNotificationSettingsSnapshot({
    required this.level,
    required this.updatedAt,
  });

  ChatNotificationSettingsSnapshot.defaults()
      : level = ChatNotificationLevel.all,
        updatedAt = DateTime.fromMillisecondsSinceEpoch(0);

  final ChatNotificationLevel level;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'level': level.name,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ChatNotificationSettingsSnapshot.fromJson(
    Map<String, dynamic> json,
  ) {
    return ChatNotificationSettingsSnapshot(
      level: ChatNotificationLevelX.fromStorage(
        json['level']?.toString() ?? '',
      ),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

abstract class ChatNotificationSettingsStore {
  Future<ChatNotificationSettingsSnapshot?> getSettings(String key);

  Future<Map<String, ChatNotificationSettingsSnapshot>> getAllSettings();

  Future<void> saveSettings(
    String key,
    ChatNotificationSettingsSnapshot snapshot,
  );

  Future<void> clearSettings(String key);
}

class SharedPreferencesChatNotificationSettingsStore
    implements ChatNotificationSettingsStore {
  const SharedPreferencesChatNotificationSettingsStore();

  static const String _prefix = 'chat_notification_settings_v1:';

  static String chatKey(String chatId) => 'chat:$chatId';

  static String directUserKey(String userId) => 'user:$userId';

  @override
  Future<ChatNotificationSettingsSnapshot?> getSettings(String key) async {
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
      return ChatNotificationSettingsSnapshot.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, ChatNotificationSettingsSnapshot>> getAllSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final entries = <String, ChatNotificationSettingsSnapshot>{};

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
        final snapshot = ChatNotificationSettingsSnapshot.fromJson(decoded);
        if (snapshot.level == ChatNotificationLevel.all) {
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
  Future<void> saveSettings(
    String key,
    ChatNotificationSettingsSnapshot snapshot,
  ) async {
    if (snapshot.level == ChatNotificationLevel.all) {
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
