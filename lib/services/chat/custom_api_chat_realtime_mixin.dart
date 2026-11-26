part of '../custom_api_chat_service.dart';

mixin _CustomApiChatRealtimeMixin on _CustomApiChatBase {
  @override
  void _ensureChatPreviewsStream() {
    if (_chatPreviewsController != null) {
      return;
    }

    _chatPreviewsController = StreamController<List<ChatPreview>>.broadcast(
      onListen: () {
        _chatPreviewsListenerCount++;
        if (_chatPreviewsListenerCount == 1) {
          _startChatPreviewsUpdates();
        }
      },
      onCancel: () async {
        _chatPreviewsListenerCount--;
        if (_chatPreviewsListenerCount <= 0) {
          _chatPreviewsListenerCount = 0;
          await _stopChatPreviewsUpdates();
        }
      },
    );
  }

  void _startChatPreviewsUpdates() {
    if (_chatPreviewsUpdatesActive || _chatPreviewsController == null) {
      return;
    }

    _chatPreviewsUpdatesActive = true;
    // Stale-while-revalidate: hydrate from Hive synchronously so the list
    // appears immediately, then trigger the API refresh in the background.
    unawaited(_hydrateChatPreviewsFromCache());
    // Restore persisted realtime overrides BEFORE the first fetch+emit so the
    // group avatar survives a cold start (the stale /v1/chats would otherwise
    // re-blank it before any chat.updated arrives).
    unawaited(_bootstrapChatPreviewsWithOverrides());

    if (_realtimeService != null) {
      unawaited(_realtimeService.connect());
      _chatPreviewsRealtimeSubscription =
          _realtimeService.events.listen((event) {
        if (event.type == 'connection.ready') {
          _stopChatPreviewsFallbackPolling();
          _scheduleChatPreviewsRefresh(immediate: true);
          return;
        }
        if (event.type == 'connection.disconnected') {
          _startChatPreviewsFallbackPolling();
          return;
        }
        if (_shouldRefreshChatPreviewsForRealtimeEvent(event)) {
          // Patch the matching preview straight from the event's full chat
          // payload (photoUrl/title) so the group avatar appears immediately,
          // then schedule the (possibly stale) refetch — the override is
          // re-applied on top of it below so the fetch can't blank it out.
          final overriddenChatId = _captureChatPreviewOverride(event);
          if (overriddenChatId != null) {
            _patchEmittedChatPreviewsWithOverrides();
          }
          _scheduleChatPreviewsRefresh();
        }
      });
    } else {
      _startChatPreviewsFallbackPolling();
    }
  }

  /// Hydrate persisted overrides, THEN do the first fetch+emit — so the very
  /// first emitted list already carries any restored group avatar.
  Future<void> _bootstrapChatPreviewsWithOverrides() async {
    await _hydrateRealtimeOverrides();
    await _emitChatPreviews();
  }

  Future<void> _stopChatPreviewsUpdates() async {
    _chatPreviewsUpdatesActive = false;
    _stopChatPreviewsFallbackPolling();
    _chatPreviewsRealtimeDebounce?.cancel();
    _chatPreviewsRealtimeDebounce = null;
    await _chatPreviewsRealtimeSubscription?.cancel();
    _chatPreviewsRealtimeSubscription = null;
  }

  void _startChatPreviewsFallbackPolling() {
    if (!_chatPreviewsUpdatesActive ||
        _chatPreviewsController == null ||
        _chatPreviewsFallbackTimer != null) {
      return;
    }

    _chatPreviewsFallbackTimer = Timer.periodic(
      _realtimeFallbackPollInterval,
      (_) => unawaited(_emitChatPreviews()),
    );
  }

  void _stopChatPreviewsFallbackPolling() {
    _chatPreviewsFallbackTimer?.cancel();
    _chatPreviewsFallbackTimer = null;
  }

  @override
  Future<void> _emitChatPreviews() async {
    final controller = _chatPreviewsController;
    if (!_chatPreviewsUpdatesActive ||
        controller == null ||
        controller.isClosed) {
      return;
    }

    if (!_hasActiveSession) {
      await _stopChatPreviewsUpdates();
      if (!controller.isClosed) {
        controller.add(const <ChatPreview>[]);
      }
      return;
    }

    try {
      final previews = await _fetchChatPreviews();
      // Overlay realtime overrides AFTER the fetch so a fresh chat.updated
      // photoUrl/title beats a stale null from GET /v1/chats.
      final overridden = _applyRealtimeChatPreviewOverrides(previews);
      _lastEmittedPreviews = overridden;
      // Persist to cache so the next cold start can show the list before
      // the network round-trip finishes. Cache the overridden version so the
      // group photo survives a restart (the override map is in-memory).
      // Failures are non-fatal — caching is a UX optimization, not truth.
      unawaited(_writeChatPreviewsCache(overridden));
      controller.add(overridden);
    } on CustomApiException catch (error, stackTrace) {
      if (await _handleSessionError(error)) {
        await _stopChatPreviewsUpdates();
        if (!controller.isClosed) {
          controller.add(const <ChatPreview>[]);
        }
        return;
      }
      _appStatusService?.reportError(
        error,
        fallbackMessage: 'Не удалось обновить список чатов.',
      );
      if (!controller.isClosed && controller.hasListener) {
        controller.addError(error, stackTrace);
      }
    } catch (error, stackTrace) {
      if (await _handleSessionError(error)) {
        await _stopChatPreviewsUpdates();
        if (!controller.isClosed) {
          controller.add(const <ChatPreview>[]);
        }
        return;
      }
      _appStatusService?.reportError(
        error,
        fallbackMessage: 'Не удалось обновить список чатов.',
      );
      if (!controller.isClosed && controller.hasListener) {
        controller.addError(error, stackTrace);
      }
    }
  }

  bool _shouldRefreshChatPreviewsForRealtimeEvent(
    CustomApiRealtimeEvent event,
  ) {
    return event.type == 'chat.created' ||
        event.type == 'chat.updated' ||
        event.type == 'chat.message.created' ||
        event.type == 'chat.message.updated' ||
        event.type == 'chat.message.deleted';
  }

  void _scheduleChatPreviewsRefresh({bool immediate = false}) {
    _chatPreviewsRealtimeDebounce?.cancel();
    if (immediate) {
      unawaited(_emitChatPreviews());
      return;
    }

    _chatPreviewsRealtimeDebounce = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_emitChatPreviews()),
    );
  }

  /// Records the photoUrl/title from a realtime chat.updated/chat.created event
  /// (which carries the full mapped chat) so a later stale /v1/chats refetch
  /// can't blank the group photo back out. Returns the affected chatId, or
  /// null when the event carried no usable chat payload. The latest event
  /// always wins; a null/empty field falls through to the fetched value.
  String? _captureChatPreviewOverride(CustomApiRealtimeEvent event) {
    final chat = event.chat;
    if (chat == null) {
      return null;
    }
    final chatId = chat['chatId']?.toString() ?? chat['id']?.toString() ?? '';
    if (chatId.isEmpty) {
      return null;
    }
    final photoUrl = chat['photoUrl']?.toString();
    final title = chat['title']?.toString();
    final type = chat['type']?.toString();
    _realtimeChatPreviewOverrides[chatId] = ChatPreviewOverride(
      photoUrl: (photoUrl != null && photoUrl.isNotEmpty) ? photoUrl : null,
      title: (title != null && title.isNotEmpty) ? title : null,
      type: type,
    );
    // Write-through to Hive so the avatar survives a cold start.
    unawaited(_persistRealtimeOverrides());
    return chatId;
  }

  /// Re-applies overrides to the currently-emitted previews and pushes the
  /// patched list immediately, so the group avatar updates the moment the
  /// realtime event arrives — without waiting for the debounced refetch.
  void _patchEmittedChatPreviewsWithOverrides() {
    final controller = _chatPreviewsController;
    final current = _lastEmittedPreviews;
    if (controller == null || controller.isClosed || current == null) {
      return;
    }
    final patched = _applyRealtimeChatPreviewOverrides(current);
    if (identical(patched, current)) {
      return;
    }
    _lastEmittedPreviews = patched;
    controller.add(patched);
    unawaited(_writeChatPreviewsCache(patched));
  }

  @override
  void _ensureTotalUnreadStream() {
    if (_totalUnreadController != null) {
      return;
    }

    _totalUnreadController = StreamController<int>.broadcast(
      onListen: () {
        _totalUnreadListenerCount++;
        if (_totalUnreadListenerCount == 1) {
          _startTotalUnreadUpdates();
        }
      },
      onCancel: () async {
        _totalUnreadListenerCount--;
        if (_totalUnreadListenerCount <= 0) {
          _totalUnreadListenerCount = 0;
          await _stopTotalUnreadUpdates();
        }
      },
    );
  }

  void _startTotalUnreadUpdates() {
    if (_totalUnreadUpdatesActive || _totalUnreadController == null) {
      return;
    }

    _totalUnreadUpdatesActive = true;
    unawaited(_emitTotalUnread());

    if (_realtimeService != null) {
      unawaited(_realtimeService.connect());
      _totalUnreadRealtimeSubscription =
          _realtimeService.events.listen((event) {
        if (event.type == 'connection.ready') {
          _stopTotalUnreadFallbackPolling();
          _scheduleTotalUnreadRefresh(immediate: true);
          return;
        }
        if (event.type == 'connection.disconnected') {
          _startTotalUnreadFallbackPolling();
          return;
        }
        if (_applyTotalUnreadRealtimeEvent(event)) {
          return;
        }
        if (_shouldRefreshTotalUnreadForRealtimeEvent(event)) {
          _scheduleTotalUnreadRefresh();
        }
      });
    } else {
      _startTotalUnreadFallbackPolling();
    }
  }

  Future<void> _stopTotalUnreadUpdates() async {
    _totalUnreadUpdatesActive = false;
    _stopTotalUnreadFallbackPolling();
    _totalUnreadRealtimeDebounce?.cancel();
    _totalUnreadRealtimeDebounce = null;
    await _totalUnreadRealtimeSubscription?.cancel();
    _totalUnreadRealtimeSubscription = null;
  }

  void _startTotalUnreadFallbackPolling() {
    if (!_totalUnreadUpdatesActive ||
        _totalUnreadController == null ||
        _totalUnreadFallbackTimer != null) {
      return;
    }

    _totalUnreadFallbackTimer = Timer.periodic(
      _realtimeFallbackPollInterval,
      (_) => unawaited(_emitTotalUnread()),
    );
  }

  void _stopTotalUnreadFallbackPolling() {
    _totalUnreadFallbackTimer?.cancel();
    _totalUnreadFallbackTimer = null;
  }

  @override
  Future<void> _emitTotalUnread() async {
    final controller = _totalUnreadController;
    if (!_totalUnreadUpdatesActive ||
        controller == null ||
        controller.isClosed) {
      return;
    }

    if (!_hasActiveSession) {
      await _stopTotalUnreadUpdates();
      if (!controller.isClosed) {
        controller.add(0);
      }
      return;
    }

    try {
      controller.add(await _fetchTotalUnreadCount());
    } on CustomApiException catch (error, stackTrace) {
      if (await _handleSessionError(error)) {
        await _stopTotalUnreadUpdates();
        if (!controller.isClosed) {
          controller.add(0);
        }
        return;
      }
      _appStatusService?.reportError(
        error,
        fallbackMessage: 'Не удалось обновить счётчик непрочитанных.',
      );
      if (!controller.isClosed && controller.hasListener) {
        controller.addError(error, stackTrace);
      }
    } catch (error, stackTrace) {
      if (await _handleSessionError(error)) {
        await _stopTotalUnreadUpdates();
        if (!controller.isClosed) {
          controller.add(0);
        }
        return;
      }
      _appStatusService?.reportError(
        error,
        fallbackMessage: 'Не удалось обновить счётчик непрочитанных.',
      );
      if (!controller.isClosed && controller.hasListener) {
        controller.addError(error, stackTrace);
      }
    }
  }

  void _scheduleTotalUnreadRefresh({bool immediate = false}) {
    _totalUnreadRealtimeDebounce?.cancel();
    if (immediate) {
      unawaited(_emitTotalUnread());
      return;
    }

    _totalUnreadRealtimeDebounce = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_emitTotalUnread()),
    );
  }

  bool _applyTotalUnreadRealtimeEvent(CustomApiRealtimeEvent event) {
    if (event.type != 'chat.unread.changed') {
      return false;
    }

    final totalUnread = int.tryParse(
      event.payload['totalUnread']?.toString() ?? '',
    );
    final controller = _totalUnreadController;
    if (totalUnread == null || controller == null || controller.isClosed) {
      return false;
    }

    _totalUnreadRealtimeDebounce?.cancel();
    controller.add(totalUnread);
    return true;
  }

  bool _shouldRefreshTotalUnreadForRealtimeEvent(
    CustomApiRealtimeEvent event,
  ) {
    return event.type == 'chat.message.created' ||
        event.type == 'chat.message.deleted' ||
        event.type == 'chat.read.updated' ||
        event.type == 'notification.created';
  }

  @override
  _ChatMessageStreamState _ensureMessageStream(String chatId) {
    final existingState = _messageStates[chatId];
    if (existingState != null) {
      return existingState;
    }

    final state = _ChatMessageStreamState(chatId);
    state.controller = StreamController<List<ChatMessage>>.broadcast(
      onListen: () {
        state.listenerCount += 1;
        if (state.listenerCount == 1) {
          _startMessageState(state);
        } else if (state.messages.isNotEmpty) {
          state.controller.add(List<ChatMessage>.unmodifiable(state.messages));
        }
      },
      onCancel: () async {
        state.listenerCount -= 1;
        if (state.listenerCount <= 0) {
          state.listenerCount = 0;
          await _disposeMessageState(chatId);
        }
      },
    );
    _messageStates[chatId] = state;
    return state;
  }

  void _startMessageState(_ChatMessageStreamState state) {
    if (state.started) {
      return;
    }

    state.started = true;
    if (!_hasActiveSession) {
      state.messages = const <ChatMessage>[];
      state.controller.add(const <ChatMessage>[]);
      return;
    }

    unawaited(_hydrateMessageState(state));

    if (_realtimeService != null) {
      unawaited(_realtimeService.connect());
      state.realtimeSubscription = _realtimeService.events.listen((event) {
        if (event.type == 'connection.ready') {
          _scheduleMessageRefresh(state, immediate: true);
          return;
        }

        if (event.chatId != state.chatId) {
          return;
        }

        switch (event.type) {
          case 'chat.message.created':
          case 'chat.message.updated':
            final payload = event.message;
            if (payload == null) {
              _scheduleMessageRefresh(state);
              return;
            }
            _mergeRealtimeMessage(state, payload);
            return;
          case 'chat.message.deleted':
            final messageId = event.payload['messageId']?.toString();
            if (messageId == null || messageId.isEmpty) {
              _scheduleMessageRefresh(state);
              return;
            }
            _removeRealtimeMessage(state, messageId);
            return;
          case 'message.reaction.changed':
            final messageId = event.payload['messageId']?.toString();
            final rawReactions = event.payload['reactions'];
            if (messageId == null ||
                messageId.isEmpty ||
                rawReactions is! List<dynamic>) {
              _scheduleMessageRefresh(state);
              return;
            }
            _applyReactionUpdate(state, messageId, rawReactions);
            return;
          case 'message.delivered':
            final messageId = event.payload['messageId']?.toString();
            final userIds = _stringListFromDynamic(event.payload['userIds']);
            final deliveredTo =
                _stringListFromDynamic(event.payload['deliveredTo']);
            if (messageId == null || messageId.isEmpty) {
              _scheduleMessageRefresh(state);
              return;
            }
            _applyDeliveryUpdate(
              state,
              messageId: messageId,
              userIds: deliveredTo.isNotEmpty ? deliveredTo : userIds,
            );
            return;
          case 'message.read':
            final readerUserId = event.userId;
            if (readerUserId == null || readerUserId.isEmpty) {
              _scheduleMessageRefresh(state);
              return;
            }
            _applyReadUpdate(
              state,
              readerUserId,
              messageIds: _stringListFromDynamic(event.payload['messageIds']),
            );
            return;
          case 'chat.read.updated':
            final readerUserId = event.userId;
            if (readerUserId == null || readerUserId.isEmpty) {
              _scheduleMessageRefresh(state);
              return;
            }
            _applyReadUpdate(state, readerUserId);
            return;
          default:
            return;
        }
      });
    }
  }

  Future<void> _disposeMessageState(String chatId) async {
    final state = _messageStates.remove(chatId);
    if (state == null) {
      return;
    }

    state.refreshDebounce?.cancel();
    // Flush any pending debounced cache write so the next cold read sees
    // the freshest known state — then cancel the timer.
    final pendingFlush = _dirtyMessageCacheFlushTimers.remove(chatId);
    if (pendingFlush != null) {
      pendingFlush.cancel();
      final snapshot = List<ChatMessage>.unmodifiable(state.messages);
      _cacheMessages((cache) => cache.write(chatId, snapshot));
    }
    await state.realtimeSubscription?.cancel();
    await state.controller.close();
  }

  @override
  void _scheduleMessageRefresh(
    _ChatMessageStreamState state, {
    bool immediate = false,
  }) {
    state.refreshDebounce?.cancel();
    if (immediate) {
      unawaited(_refreshMessageState(state));
      return;
    }

    final debounceMs = _pollInterval.inMilliseconds.clamp(150, 1000);
    state.refreshDebounce = Timer(
      Duration(milliseconds: debounceMs),
      () => unawaited(_refreshMessageState(state)),
    );
  }

  @override
  void _mergeRealtimeMessage(
    _ChatMessageStreamState state,
    Map<String, dynamic> rawMessage,
  ) {
    final incomingMessage = _parseChatMessage(rawMessage);
    final existingIndex = state.messages.indexWhere(
      (message) => message.id == incomingMessage.id,
    );

    final nextMessages = List<ChatMessage>.from(state.messages);
    if (existingIndex == -1) {
      nextMessages.add(incomingMessage);
    } else {
      nextMessages[existingIndex] = incomingMessage;
    }
    nextMessages.sort(_sortMessagesDescending);
    state.messages = nextMessages;
    state.messagesVersion++;
    _cacheMessages(
      (cache) => cache.appendOne(state.chatId, incomingMessage),
    );
    if (!state.controller.isClosed) {
      state.controller.add(List<ChatMessage>.unmodifiable(nextMessages));
    }
  }

  void _removeRealtimeMessage(
    _ChatMessageStreamState state,
    String messageId,
  ) {
    final nextMessages = state.messages
        .where((message) => message.id != messageId)
        .toList(growable: false);
    state.messages = nextMessages;
    state.messagesVersion++;
    _cacheMessages(
      (cache) => cache.removeOne(state.chatId, messageId),
    );
    if (!state.controller.isClosed) {
      state.controller.add(List<ChatMessage>.unmodifiable(nextMessages));
    }
  }

  /// Removes a message from the in-memory stream (when the chat is open) and
  /// from the Hive cache. Idempotent — safe to call when the message is
  /// already gone. Used by [deleteChatMessage] so a locally-initiated delete
  /// (including the «already gone» 404 case) prunes the cache without relying
  /// on the realtime echo.
  @override
  void _pruneLocalMessage(String chatId, String messageId) {
    final normalizedMessageId = messageId.trim();
    if (normalizedMessageId.isEmpty) {
      return;
    }
    final state = _messageStates[chatId];
    if (state != null) {
      _removeRealtimeMessage(state, normalizedMessageId);
    } else {
      _cacheMessages(
        (cache) => cache.removeOne(chatId, normalizedMessageId),
      );
    }
  }

  @override
  void _applyReactionUpdate(
    _ChatMessageStreamState state,
    String messageId,
    List<dynamic> rawReactions,
  ) {
    final messageIndex = state.messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (messageIndex < 0) {
      _scheduleMessageRefresh(state);
      return;
    }

    final nextMessages = List<ChatMessage>.from(state.messages);
    final nextMessage = nextMessages[messageIndex].copyWith(
      reactions: ChatMessageReactionSummary.listFromDynamic(rawReactions),
    );
    nextMessages[messageIndex] = nextMessage;
    state.messages = nextMessages;
    state.messagesVersion++;
    // Reactions arrive in bursts — debounce the Hive write instead of
    // flushing on every event.
    _scheduleDebouncedMessageCacheFlush(state);
    if (!state.controller.isClosed) {
      state.controller.add(List<ChatMessage>.unmodifiable(nextMessages));
    }
  }

  void _applyDeliveryUpdate(
    _ChatMessageStreamState state, {
    required String messageId,
    required List<String> userIds,
  }) {
    if (userIds.isEmpty) {
      return;
    }

    final messageIndex = state.messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (messageIndex < 0) {
      _scheduleMessageRefresh(state);
      return;
    }

    final nextMessages = List<ChatMessage>.from(state.messages);
    final message = nextMessages[messageIndex];
    final deliveredTo = <String>{
      ...message.deliveredTo,
      ...userIds,
    }.where((userId) => userId.trim().isNotEmpty).toList(growable: false);
    final nextMessage = message.copyWith(deliveredTo: deliveredTo);
    nextMessages[messageIndex] = nextMessage;
    state.messages = nextMessages;
    state.messagesVersion++;
    // Delivery receipts can arrive several times per second when a chat
    // catches up after a reconnect — coalesce into a single Hive write.
    _scheduleDebouncedMessageCacheFlush(state);
    if (!state.controller.isClosed) {
      state.controller.add(List<ChatMessage>.unmodifiable(nextMessages));
    }
  }

  void _applyReadUpdate(
    _ChatMessageStreamState state,
    String readerUserId, {
    List<String> messageIds = const <String>[],
  }) {
    if (state.messages.isEmpty) {
      return;
    }
    final targetMessageIds = messageIds.toSet();
    final nextMessages = state.messages.map((message) {
      if (message.senderId == readerUserId ||
          (targetMessageIds.isNotEmpty &&
              !targetMessageIds.contains(message.id))) {
        return message;
      }
      return message.copyWith(
        isRead: true,
        deliveredTo: <String>{
          ...message.deliveredTo,
          readerUserId,
        }.toList(growable: false),
        readBy: <String>{
          ...message.readBy,
          readerUserId,
        }.toList(growable: false),
      );
    }).toList(growable: false);
    state.messages = nextMessages;
    state.messagesVersion++;
    // Read markers can fire for every visible message on focus — debounce
    // the Hive flush so a single chat-open doesn't translate into N writes.
    _scheduleDebouncedMessageCacheFlush(state);
    if (!state.controller.isClosed) {
      state.controller.add(List<ChatMessage>.unmodifiable(nextMessages));
    }
  }
}
