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

abstract class RemoteChatDraftClient {
  Future<ChatDraftSnapshot?> getChatDraft(String chatId);

  Future<Map<String, ChatDraftSnapshot>> getChatDrafts();

  Future<void> saveChatDraft({
    required String chatId,
    required String text,
  });

  Future<void> clearChatDraft(String chatId);
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

class HybridChatDraftStore implements ChatDraftStore {
  HybridChatDraftStore({
    required this.localStore,
    required this.remoteClient,
  });

  final ChatDraftStore localStore;
  final RemoteChatDraftClient remoteClient;
  final Map<String, Future<void>> _pendingRemoteOperations =
      <String, Future<void>>{};

  static String? chatIdFromKey(String key) {
    const prefix = 'chat:';
    if (!key.startsWith(prefix)) {
      return null;
    }
    final chatId = key.substring(prefix.length).trim();
    return chatId.isEmpty ? null : chatId;
  }

  static String keyForChatId(String chatId) {
    return SharedPreferencesChatDraftStore.chatKey(chatId);
  }

  Future<void> saveLocalDraft(String key, String text) {
    return localStore.saveDraft(key, text);
  }

  Future<void> clearLocalDraft(String key) {
    return localStore.clearDraft(key);
  }

  Future<void> _waitForPendingRemoteOperation(String key) async {
    final pending = _pendingRemoteOperations[key];
    if (pending == null) {
      return;
    }
    try {
      await pending;
    } catch (_) {
      // Remote draft sync is best-effort; reads should still continue.
    }
  }

  Future<void> _enqueueRemoteOperation(
    String key,
    Future<void> Function() operation,
  ) {
    final previous = _pendingRemoteOperations[key] ?? Future<void>.value();
    late final Future<void> tracked;
    tracked = previous.catchError((_) {}).then((_) => operation()).whenComplete(
      () {
        if (identical(_pendingRemoteOperations[key], tracked)) {
          _pendingRemoteOperations.remove(key);
        }
      },
    );
    _pendingRemoteOperations[key] = tracked;
    return tracked;
  }

  @override
  Future<ChatDraftSnapshot?> getDraft(String key) async {
    await _waitForPendingRemoteOperation(key);
    final localDraft = await localStore.getDraft(key);
    final chatId = chatIdFromKey(key);
    if (chatId == null) {
      return localDraft;
    }

    try {
      final remoteDraft = await remoteClient.getChatDraft(chatId);
      if (remoteDraft == null) {
        return localDraft;
      }
      if (localDraft == null ||
          remoteDraft.updatedAt.isAfter(localDraft.updatedAt)) {
        await localStore.saveDraft(key, remoteDraft.text);
        return remoteDraft;
      }
      return localDraft;
    } catch (_) {
      return localDraft;
    }
  }

  @override
  Future<Map<String, ChatDraftSnapshot>> getAllDrafts() async {
    final pending = List<Future<void>>.from(_pendingRemoteOperations.values);
    if (pending.isNotEmpty) {
      try {
        await Future.wait(pending);
      } catch (_) {
        // Remote draft sync is best-effort; local drafts should still render.
      }
    }
    final merged = await localStore.getAllDrafts();
    try {
      final remoteDrafts = await remoteClient.getChatDrafts();
      for (final entry in remoteDrafts.entries) {
        final current = merged[entry.key];
        if (current == null ||
            entry.value.updatedAt.isAfter(current.updatedAt)) {
          merged[entry.key] = entry.value;
          await localStore.saveDraft(entry.key, entry.value.text);
        }
      }
    } catch (_) {
      // Local drafts should keep working offline or when backend draft sync is absent.
    }
    return merged;
  }

  @override
  Future<void> saveDraft(String key, String text) async {
    await localStore.saveDraft(key, text);
    final chatId = chatIdFromKey(key);
    if (chatId == null) {
      return;
    }
    await _enqueueRemoteOperation(key, () async {
      try {
        await remoteClient.saveChatDraft(chatId: chatId, text: text);
      } catch (_) {
        // Keep local draft; the next edit/load can retry remote sync.
      }
    });
  }

  @override
  Future<void> clearDraft(String key) async {
    await localStore.clearDraft(key);
    final chatId = chatIdFromKey(key);
    if (chatId == null) {
      return;
    }
    await _enqueueRemoteOperation(key, () async {
      try {
        await remoteClient.clearChatDraft(chatId);
      } catch (_) {
        // Local clear is still authoritative for current device.
      }
    });
  }
}
