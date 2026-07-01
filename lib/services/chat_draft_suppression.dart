import 'dart:async';

class ChatDraftSuppressionEvent {
  const ChatDraftSuppressionEvent({
    required this.chatId,
    required this.text,
  });

  final String chatId;
  final String text;
}

class ChatDraftSuppression {
  ChatDraftSuppression._();

  static final ChatDraftSuppression instance = ChatDraftSuppression._();

  static const Duration _defaultTtl = Duration(minutes: 10);
  final StreamController<ChatDraftSuppressionEvent> _events =
      StreamController<ChatDraftSuppressionEvent>.broadcast();
  final Map<String, _SuppressedDraft> _suppressedByChatId =
      <String, _SuppressedDraft>{};

  Stream<ChatDraftSuppressionEvent> get events => _events.stream;

  void suppressSentDraft({
    required String chatId,
    required String text,
    DateTime? now,
  }) {
    final normalizedChatId = _normalizeChatId(chatId);
    final normalizedText = _normalizeText(text);
    if (normalizedChatId.isEmpty || normalizedText.isEmpty) {
      return;
    }

    final timestamp = now ?? DateTime.now();
    _suppressedByChatId[normalizedChatId] = _SuppressedDraft(
      normalizedText: normalizedText,
      expiresAt: timestamp.add(_defaultTtl),
      suppressAnyUntilLocalEdit: true,
    );
    _events.add(
      ChatDraftSuppressionEvent(
        chatId: normalizedChatId,
        text: text,
      ),
    );
  }

  bool shouldSuppressDraft({
    required String chatId,
    required String text,
    DateTime? now,
  }) {
    final normalizedChatId = _normalizeChatId(chatId);
    final normalizedText = _normalizeText(text);
    if (normalizedChatId.isEmpty || normalizedText.isEmpty) {
      return false;
    }

    _pruneExpired(now ?? DateTime.now());
    final suppressed = _suppressedByChatId[normalizedChatId];
    return suppressed != null &&
        (suppressed.suppressAnyUntilLocalEdit ||
            suppressed.normalizedText == normalizedText);
  }

  bool shouldSuppressDraftKey({
    required String key,
    required String text,
    DateTime? now,
  }) {
    final chatId = chatIdFromDraftKey(key);
    if (chatId == null) {
      return false;
    }
    return shouldSuppressDraft(chatId: chatId, text: text, now: now);
  }

  void recordLocalDraftEdit({
    required String key,
    required String text,
    DateTime? now,
  }) {
    final chatId = chatIdFromDraftKey(key);
    if (chatId == null) {
      return;
    }

    _pruneExpired(now ?? DateTime.now());
    final suppressed = _suppressedByChatId[chatId];
    if (suppressed == null) {
      return;
    }

    final normalizedText = _normalizeText(text);
    if (normalizedText.isNotEmpty &&
        normalizedText != suppressed.normalizedText) {
      _suppressedByChatId.remove(chatId);
    }
  }

  void clearForChat(String chatId) {
    _suppressedByChatId.remove(_normalizeChatId(chatId));
  }

  void resetForTesting() {
    _suppressedByChatId.clear();
  }

  static String? chatIdFromDraftKey(String key) {
    const prefix = 'chat:';
    if (!key.startsWith(prefix)) {
      return null;
    }
    final chatId = _normalizeChatId(key.substring(prefix.length));
    return chatId.isEmpty ? null : chatId;
  }

  static String _normalizeChatId(String value) {
    return value.trim();
  }

  static String _normalizeText(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  void _pruneExpired(DateTime now) {
    _suppressedByChatId.removeWhere(
      (_, suppressed) => !suppressed.expiresAt.isAfter(now),
    );
  }
}

class _SuppressedDraft {
  const _SuppressedDraft({
    required this.normalizedText,
    required this.expiresAt,
    required this.suppressAnyUntilLocalEdit,
  });

  final String normalizedText;
  final DateTime expiresAt;
  final bool suppressAnyUntilLocalEdit;
}
