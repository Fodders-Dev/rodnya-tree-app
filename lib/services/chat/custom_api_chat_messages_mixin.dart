part of '../custom_api_chat_service.dart';

mixin _CustomApiChatMessagesMixin on _CustomApiChatBase {
  @override
  Stream<List<ChatMessage>> getMessagesStream(String chatId) {
    return _ensureMessageStream(chatId).controller.stream;
  }

  Future<ChatMessagesPage> fetchMessagesPage(
    String chatId, {
    int limit = 50,
    String? beforeId,
    String? afterId,
  }) async {
    final normalizedBeforeId = beforeId?.trim();
    final normalizedAfterId = afterId?.trim();
    if ((normalizedBeforeId?.isNotEmpty ?? false) &&
        (normalizedAfterId?.isNotEmpty ?? false)) {
      throw const CustomApiException(
        'Нельзя запрашивать сообщения одновременно до и после курсора',
      );
    }

    final normalizedLimit = limit.clamp(1, 200).toInt();
    final response = await _requestJson(
      method: 'GET',
      path: '/v1/chats/$chatId/messages',
      queryParameters: <String, String>{
        'limit': '$normalizedLimit',
        if (normalizedBeforeId != null && normalizedBeforeId.isNotEmpty)
          'before': normalizedBeforeId,
        if (normalizedAfterId != null && normalizedAfterId.isNotEmpty)
          'after': normalizedAfterId,
      },
    );

    final rawMessages = response['messages'];
    final messages = rawMessages is List<dynamic>
        ? rawMessages
            .whereType<Map<String, dynamic>>()
            .map(_parseChatMessage)
            .toList()
        : const <ChatMessage>[];
    if (messages.isNotEmpty) {
      _cacheMessages(
        (cache) => cache.mergePage(chatId, messages),
      );
    }
    return ChatMessagesPage(
      messages: messages,
      hasMore: response['hasMore'] == true,
    );
  }

  @override
  Future<List<ChatMessageSearchResult>> searchMessages({
    required String query,
    String? chatId,
    int limit = 50,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const <ChatMessageSearchResult>[];
    }

    final response = await _requestJson(
      method: 'GET',
      path: '/v1/chats/search',
      queryParameters: <String, String>{
        'q': normalizedQuery,
        if (chatId != null && chatId.trim().isNotEmpty) 'chatId': chatId.trim(),
        'limit': limit.clamp(1, 100).toString(),
      },
    );
    final rawResults = response['results'];
    if (rawResults is! List<dynamic>) {
      return const <ChatMessageSearchResult>[];
    }
    return rawResults
        .whereType<Map>()
        .map((entry) => ChatMessageSearchResult.fromMap(
              Map<String, dynamic>.from(entry),
            ))
        .where(
            (result) => result.messageId.isNotEmpty && result.chatId.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<void> refreshMessages(String chatId) async {
    final state = _messageStates[chatId];
    if (state == null) {
      if (!_hasActiveSession) {
        return;
      }
      await _fetchMessages(chatId);
      return;
    }

    await _refreshMessageState(state);
  }

  @override
  Future<void> sendTextMessage({
    required String otherUserId,
    required String text,
  }) async {
    await sendMessage(otherUserId: otherUserId, text: text);
  }

  @override
  Future<void> sendMessage({
    required String otherUserId,
    String text = '',
    List<XFile> attachments = const <XFile>[],
  }) async {
    final chatId = await getOrCreateChat(otherUserId);
    if (chatId == null || chatId.isEmpty) {
      throw const CustomApiException('Не удалось определить чат');
    }

    await sendMessageToChat(
      chatId: chatId,
      text: text,
      attachments: attachments,
    );
  }

  @override
  Future<void> sendMessageToChat({
    required String chatId,
    String text = '',
    List<XFile> attachments = const <XFile>[],
    List<ChatAttachment> forwardedAttachments = const <ChatAttachment>[],
    ChatReplyReference? replyTo,
    String? clientMessageId,
    int? expiresInSeconds,
    void Function(ChatSendProgress progress)? onProgress,
  }) async {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty &&
        attachments.isEmpty &&
        forwardedAttachments.isEmpty) {
      throw const CustomApiException('Сообщение не должно быть пустым');
    }

    final uploadedAttachments = await _uploadAttachments(
      attachments,
      onProgress: onProgress,
    );
    final allAttachments = <ChatAttachment>[
      ...forwardedAttachments
          .where((attachment) => attachment.url.trim().isNotEmpty),
      ...uploadedAttachments,
    ];

    onProgress?.call(
      const ChatSendProgress(
        stage: ChatSendProgressStage.sending,
        completed: 1,
        total: 1,
      ),
    );

    final response = await _requestJson(
      method: 'POST',
      path: '/v1/chats/$chatId/messages',
      body: {
        'text': trimmedText,
        if (allAttachments.isNotEmpty)
          'attachments':
              allAttachments.map((attachment) => attachment.toMap()).toList(),
        if (allAttachments.isNotEmpty)
          'mediaUrls':
              allAttachments.map((attachment) => attachment.url).toList(),
        if (allAttachments.isNotEmpty) 'imageUrl': allAttachments.first.url,
        if (replyTo != null && replyTo.messageId.isNotEmpty)
          'replyTo': replyTo.toMap(),
        if (clientMessageId != null && clientMessageId.trim().isNotEmpty)
          'clientMessageId': clientMessageId.trim(),
        if (expiresInSeconds != null && expiresInSeconds > 0)
          'expiresInSeconds': expiresInSeconds,
      },
    );
    final messageState = _messageStates[chatId];
    if (messageState != null) {
      final rawMessage = response['message'];
      if (rawMessage is Map<String, dynamic>) {
        _mergeRealtimeMessage(messageState, rawMessage);
      } else {
        _scheduleMessageRefresh(messageState, immediate: true);
      }
    }
  }

  @override
  Future<void> markChatAsRead(String chatId, String userId) async {
    await _requestJson(
      method: 'POST',
      path: '/v1/chats/$chatId/read',
      body: const <String, dynamic>{},
    );
  }

  @override
  Future<void> editChatMessage({
    required String chatId,
    required String messageId,
    required String text,
  }) async {
    await _requestJson(
      method: 'PATCH',
      path: '/v1/chats/$chatId/messages/$messageId',
      body: {
        'text': text.trim(),
      },
    );
  }

  @override
  Future<void> deleteChatMessage({
    required String chatId,
    required String messageId,
  }) async {
    try {
      await _requestJson(
        method: 'DELETE',
        path: '/v1/chats/$chatId/messages/$messageId',
      );
    } on CustomApiException catch (error) {
      // 404 = the server no longer has this message (already deleted from
      // another device, a «delete for everyone» we missed, or expired). For a
      // delete, «already gone» IS success — swallow it and fall through to the
      // local prune below instead of leaving a stale copy stuck in the cache.
      if (error.statusCode != 404) {
        rethrow;
      }
    }
    // Prune locally right away rather than waiting for the realtime
    // `chat.message.deleted` echo: the echo never arrives on a 404, and can be
    // missed entirely when realtime is down — which is exactly how a deleted
    // message used to get stuck in the local cache forever.
    _pruneLocalMessage(chatId, messageId);
  }

  @override
  Future<void> toggleMessageReaction({
    required String chatId,
    required String messageId,
    required String emoji,
  }) async {
    final normalizedEmoji = emoji.trim();
    if (normalizedEmoji.isEmpty) {
      return;
    }

    final response = await _requestJson(
      method: 'POST',
      path: '/v1/chats/$chatId/messages/$messageId/reactions',
      body: <String, dynamic>{
        'emoji': normalizedEmoji,
      },
    );

    final state = _messageStates[chatId];
    final rawReactions = response['reactions'];
    if (state == null) {
      return;
    }
    if (rawReactions is List<dynamic>) {
      _applyReactionUpdate(state, messageId, rawReactions);
    } else {
      _scheduleMessageRefresh(state, immediate: true);
    }
  }

  @override
  Future<void> _hydrateMessageState(_ChatMessageStreamState state) async {
    if (_messageCache == null) {
      await _refreshMessageState(state);
      return;
    }

    var cachedMessages = const <ChatMessage>[];
    try {
      cachedMessages = await _messageCache.read(state.chatId);
    } catch (_) {
      cachedMessages = const <ChatMessage>[];
    }

    if (cachedMessages.isNotEmpty) {
      // Show the cached window instantly (no flash-of-empty), then re-sync it
      // against the server. This is a full newest-window fetch — NOT an
      // after-cursor delta — so it can RECONCILE deletions that happened while
      // this device was away. A delta fetch only ever adds, so a message
      // deleted elsewhere would otherwise stay cached forever.
      state.messages = cachedMessages;
      if (!state.controller.isClosed) {
        state.controller.add(List<ChatMessage>.unmodifiable(cachedMessages));
      }
    }

    await _refreshMessageState(state);
  }

  @override
  Future<void> _refreshMessageState(_ChatMessageStreamState state) async {
    if (state.isFetching) {
      state.hasQueuedRefresh = true;
      return;
    }

    if (!_hasActiveSession) {
      state.messages = const <ChatMessage>[];
      if (!state.controller.isClosed) {
        state.controller.add(const <ChatMessage>[]);
      }
      return;
    }

    state.isFetching = true;
    final versionAtRequestStart = state.messagesVersion;
    try {
      // Fetch the authoritative newest window (keepCount-wide) so a single
      // round-trip re-syncs the whole cached window — including reconciling
      // deletions we may have missed.
      final page = await fetchMessagesPage(state.chatId, limit: 200);
      final pageMessages = page.messages;
      // NEVER destructively replace the local list with a server page. This
      // refresh fires on every websocket reconnect / app resume / chat reopen.
      // A blind `= pageMessages` caused data loss two ways: (1) truncation — a
      // chat with more messages than the page limit was cut to the newest
      // page (there is no scroll-up pagination); (2) empty-wipe — a transient
      // empty page (backend listChatMessages returns [] mid group/branch
      // mutation) erased everything. So always MERGE (union by id).
      //
      // On the CLEAN path (nothing landed locally while this fetch was in
      // flight) we then reconcile server-side deletions the realtime
      // `chat.message.deleted` event may have missed (offline, another device,
      // cold start): a message absent from the page yet strictly inside the
      // fetched window is a genuine deletion and is pruned. Truncation and
      // empty/short-page glitches never drop a message because only interior
      // holes are pruned. On the DIRTY path (a realtime/send update bumped the
      // version mid-fetch) we skip reconciliation and preserve the local state
      // so a just-arrived message the stale page can't know about survives.
      if (state.messagesVersion == versionAtRequestStart) {
        state.messages = _reconcileWithServerPage(
          _mergeMessageLists(state.messages, pageMessages),
          pageMessages,
        );
      } else {
        state.messages = _mergeMessageListsPreservingExisting(
          state.messages,
          pageMessages,
        );
      }
      state.messagesVersion++;
      _cacheMessages(
        (cache) => cache.write(state.chatId, state.messages),
      );
      if (!state.controller.isClosed) {
        state.controller.add(List<ChatMessage>.unmodifiable(state.messages));
      }
    } on CustomApiException catch (error, stackTrace) {
      if (await _handleSessionError(error)) {
        state.messages = const <ChatMessage>[];
        if (!state.controller.isClosed) {
          state.controller.add(const <ChatMessage>[]);
        }
      } else {
        _appStatusService?.reportError(
          error,
          fallbackMessage: 'Не удалось обновить сообщения.',
        );
        if (!state.controller.isClosed) {
          state.controller.addError(error, stackTrace);
        }
      }
    } catch (error, stackTrace) {
      if (await _handleSessionError(error)) {
        state.messages = const <ChatMessage>[];
        if (!state.controller.isClosed) {
          state.controller.add(const <ChatMessage>[]);
        }
      } else {
        _appStatusService?.reportError(
          error,
          fallbackMessage: 'Не удалось обновить сообщения.',
        );
        if (!state.controller.isClosed) {
          state.controller.addError(error, stackTrace);
        }
      }
    } finally {
      state.isFetching = false;
      if (state.hasQueuedRefresh) {
        state.hasQueuedRefresh = false;
        unawaited(_refreshMessageState(state));
      }
    }
  }

  List<ChatMessage> _mergeMessageLists(
    List<ChatMessage> existingMessages,
    List<ChatMessage> incomingMessages,
  ) {
    if (incomingMessages.isEmpty) {
      return existingMessages;
    }

    final byId = <String, ChatMessage>{};
    for (final message in existingMessages) {
      if (message.id.trim().isNotEmpty) {
        byId[message.id] = message;
      }
    }
    for (final message in incomingMessages) {
      if (message.id.trim().isNotEmpty) {
        byId[message.id] = message;
      }
    }

    final nextMessages = byId.values.toList();
    nextMessages.sort(_sortMessagesDescending);
    return nextMessages;
  }

  List<ChatMessage> _mergeMessageListsPreservingExisting(
    List<ChatMessage> existingMessages,
    List<ChatMessage> incomingMessages,
  ) {
    if (incomingMessages.isEmpty) {
      return existingMessages;
    }

    final byId = <String, ChatMessage>{};
    for (final message in incomingMessages) {
      if (message.id.trim().isNotEmpty) {
        byId[message.id] = message;
      }
    }
    for (final message in existingMessages) {
      if (message.id.trim().isNotEmpty) {
        byId[message.id] = message;
      }
    }

    final nextMessages = byId.values.toList();
    nextMessages.sort(_sortMessagesDescending);
    return nextMessages;
  }

  /// Reconciles server-side deletions that the realtime `chat.message.deleted`
  /// event may have missed (this device was offline, the delete came from
  /// another device, or it happened before a cold start). [mergedMessages] is
  /// the union of the local state and the freshly fetched [serverPage]. A
  /// message that is absent from [serverPage] yet sits strictly INSIDE the
  /// page's window — the page returned a still-present message both newer AND
  /// older than it — is a genuine hole (a deletion) and is dropped.
  ///
  /// Only interior holes are pruned; a message at or beyond a window edge is
  /// always kept. That keeps three things safe:
  ///  * older-than-window history is never truncated (the page is only the
  ///    newest N messages);
  ///  * a transient empty/short page (fewer than two messages — e.g. mid
  ///    group/branch mutation) can't flank anything, so it prunes nothing;
  ///  * a just-sent message not yet visible to the read replica lives at the
  ///    newest edge and is preserved.
  /// Anything wrongly dropped by a rare partial-page glitch reappears on the
  /// next refetch (merge re-adds it), so the worst case is a brief flicker,
  /// never permanent loss.
  List<ChatMessage> _reconcileWithServerPage(
    List<ChatMessage> mergedMessages,
    List<ChatMessage> serverPage,
  ) {
    if (serverPage.length < 2) {
      return mergedMessages;
    }
    final serverIds = <String>{};
    var newest = serverPage.first.timestamp;
    var oldest = serverPage.first.timestamp;
    for (final message in serverPage) {
      if (message.id.trim().isNotEmpty) {
        serverIds.add(message.id);
      }
      if (message.timestamp.isAfter(newest)) {
        newest = message.timestamp;
      }
      if (message.timestamp.isBefore(oldest)) {
        oldest = message.timestamp;
      }
    }
    return mergedMessages.where((message) {
      if (serverIds.contains(message.id)) {
        return true;
      }
      final strictlyInsideWindow = message.timestamp.isAfter(oldest) &&
          message.timestamp.isBefore(newest);
      return !strictlyInsideWindow;
    }).toList(growable: false);
  }

  Future<List<ChatMessage>> _fetchMessages(String chatId) async {
    return (await fetchMessagesPage(chatId, limit: 100)).messages;
  }
}
