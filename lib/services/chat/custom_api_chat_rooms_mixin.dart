part of '../custom_api_chat_service.dart';

mixin _CustomApiChatRoomsMixin on _CustomApiChatBase {
  @override
  Stream<List<ChatPreview>> getUserChatsStream(String userId) {
    final wasActive = _chatPreviewsUpdatesActive;
    _ensureChatPreviewsStream();
    if (wasActive) {
      scheduleMicrotask(() => unawaited(_emitChatPreviews()));
    }
    return _chatPreviewsController!.stream;
  }

  @override
  Stream<int> getTotalUnreadCountStream(String userId) {
    _ensureTotalUnreadStream();
    return _totalUnreadController!.stream;
  }

  Future<void> refreshChatOverview() async {
    if (_chatPreviewsUpdatesActive) {
      await _emitChatPreviews();
    }
    if (_totalUnreadUpdatesActive) {
      await _emitTotalUnread();
    }
  }

  @override
  Future<ChatDraftSnapshot?> getChatDraft(String chatId) async {
    final response = await _requestJson(
      method: 'GET',
      path: '/v1/chats/$chatId/draft',
    );
    final draft = response['draft'];
    if (draft is! Map<String, dynamic>) {
      return null;
    }
    final snapshot = ChatDraftSnapshot.fromJson(draft);
    return snapshot.text.trim().isEmpty ? null : snapshot;
  }

  @override
  Future<Map<String, ChatDraftSnapshot>> getChatDrafts() async {
    final response = await _requestJson(
      method: 'GET',
      path: '/v1/chats/drafts',
    );
    final rawDrafts = response['drafts'];
    if (rawDrafts is! List<dynamic>) {
      return const <String, ChatDraftSnapshot>{};
    }

    final drafts = <String, ChatDraftSnapshot>{};
    for (final entry in rawDrafts.whereType<Map>()) {
      final map = Map<String, dynamic>.from(entry);
      final chatId = (map['chatId']?.toString() ?? '').trim();
      if (chatId.isEmpty) {
        continue;
      }
      final snapshot = ChatDraftSnapshot.fromJson(map);
      if (snapshot.text.trim().isEmpty) {
        continue;
      }
      drafts[SharedPreferencesChatDraftStore.chatKey(chatId)] = snapshot;
    }
    return drafts;
  }

  @override
  Future<void> saveChatDraft({
    required String chatId,
    required String text,
  }) async {
    await _requestJson(
      method: 'PUT',
      path: '/v1/chats/$chatId/draft',
      body: <String, dynamic>{'text': text},
    );
  }

  @override
  Future<void> clearChatDraft(String chatId) async {
    await _requestJson(
      method: 'DELETE',
      path: '/v1/chats/$chatId/draft',
    );
  }

  @override
  Future<ChatPinnedMessageSnapshot?> getChatPinnedMessage(String chatId) async {
    final response = await _requestJson(
      method: 'GET',
      path: '/v1/chats/$chatId/pin',
    );
    return _parsePinnedMessageSnapshot(response['pin']);
  }

  @override
  Future<ChatPinnedMessageSnapshot?> pinChatMessage({
    required String chatId,
    required String messageId,
  }) async {
    final response = await _requestJson(
      method: 'POST',
      path: '/v1/chats/$chatId/messages/$messageId/pin',
    );
    return _parsePinnedMessageSnapshot(response['pin']);
  }

  @override
  Future<void> clearChatPinnedMessage(String chatId) async {
    await _requestJson(
      method: 'DELETE',
      path: '/v1/chats/$chatId/pin',
    );
  }

  @override
  Future<String?> getOrCreateChat(String otherUserId) async {
    final response = await _requestJson(
      method: 'POST',
      path: '/v1/chats/direct',
      body: {
        'otherUserId': otherUserId,
      },
    );

    final chatId = response['chatId']?.toString();
    if (chatId == null || chatId.isEmpty) {
      throw const CustomApiException(
        'Backend не вернул идентификатор чата',
      );
    }
    return chatId;
  }

  @override
  Future<String?> createGroupChat({
    required List<String> participantIds,
    String? title,
    String? treeId,
  }) async {
    final response = await _requestJson(
      method: 'POST',
      path: '/v1/chats/groups',
      body: {
        'participantIds': participantIds,
        if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
        if (treeId != null && treeId.trim().isNotEmpty) 'treeId': treeId.trim(),
      },
    );

    final chatId = response['chatId']?.toString();
    if (chatId == null || chatId.isEmpty) {
      throw const CustomApiException(
        'Backend не вернул идентификатор группового чата',
      );
    }
    return chatId;
  }

  @override
  Future<String?> createBranchChat({
    required String treeId,
    required List<String> branchRootPersonIds,
    String? title,
  }) async {
    final response = await _requestJson(
      method: 'POST',
      path: '/v1/chats/branches',
      body: {
        'treeId': treeId.trim(),
        'branchRootPersonIds': branchRootPersonIds,
        if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
      },
    );

    final chatId = response['chatId']?.toString();
    if (chatId == null || chatId.isEmpty) {
      throw const CustomApiException(
        'Backend не вернул идентификатор чата ветки',
      );
    }
    return chatId;
  }

  @override
  Future<ChatDetails> getChatDetails(String chatId) async {
    final response = await _requestJson(
      method: 'GET',
      path: '/v1/chats/$chatId',
    );

    final rawChat = response['chat'];
    if (rawChat is! Map<String, dynamic>) {
      throw const CustomApiException('Не удалось загрузить данные чата');
    }

    return ChatDetails.fromMap({
      ...rawChat,
      'participants': response['participants'],
      'branchRoots': response['branchRoots'],
    });
  }

  @override
  Future<ChatDetails> renameGroupChat({
    required String chatId,
    required String title,
  }) async {
    final response = await _requestJson(
      method: 'PATCH',
      path: '/v1/chats/$chatId',
      body: {
        'title': title.trim(),
      },
    );

    final rawChat = response['chat'];
    if (rawChat is! Map<String, dynamic>) {
      throw const CustomApiException('Не удалось обновить название чата');
    }

    final details = ChatDetails.fromMap({
      ...rawChat,
      'participants': response['participants'],
      'branchRoots': response['branchRoots'],
    });
    unawaited(refreshChatOverview());
    return details;
  }

  @override
  Future<ChatDetails> updateGroupChatPhoto({
    required String chatId,
    required XFile photo,
  }) async {
    final storageService = _storageService;
    if (storageService == null) {
      throw const CustomApiException(
        'Загрузка изображения чата сейчас недоступна',
      );
    }

    final photoUrl = await storageService.uploadImage(photo, 'chat');
    if (photoUrl == null || photoUrl.trim().isEmpty) {
      throw const CustomApiException('Не удалось загрузить изображение чата');
    }

    final response = await _requestJson(
      method: 'PATCH',
      path: '/v1/chats/$chatId',
      body: {
        'photoUrl': photoUrl.trim(),
      },
    );

    final rawChat = response['chat'];
    if (rawChat is! Map<String, dynamic>) {
      throw const CustomApiException('Не удалось обновить изображение чата');
    }

    final details = ChatDetails.fromMap({
      ...rawChat,
      'participants': response['participants'],
      'branchRoots': response['branchRoots'],
    });
    unawaited(refreshChatOverview());
    return details;
  }

  @override
  Future<ChatDetails> addGroupParticipants({
    required String chatId,
    required List<String> participantIds,
  }) async {
    final response = await _requestJson(
      method: 'POST',
      path: '/v1/chats/$chatId/participants',
      body: {
        'participantIds': participantIds,
      },
    );

    final rawChat = response['chat'];
    if (rawChat is! Map<String, dynamic>) {
      throw const CustomApiException('Не удалось добавить участников');
    }

    final details = ChatDetails.fromMap({
      ...rawChat,
      'participants': response['participants'],
      'branchRoots': response['branchRoots'],
    });
    unawaited(refreshChatOverview());
    return details;
  }

  @override
  Future<ChatDetails> removeGroupParticipant({
    required String chatId,
    required String participantId,
  }) async {
    final response = await _requestJson(
      method: 'DELETE',
      path: '/v1/chats/$chatId/participants/$participantId',
    );

    final rawChat = response['chat'];
    if (rawChat is! Map<String, dynamic>) {
      throw const CustomApiException('Не удалось обновить состав чата');
    }

    final details = ChatDetails.fromMap({
      ...rawChat,
      'participants': response['participants'],
      'branchRoots': response['branchRoots'],
    });
    unawaited(refreshChatOverview());
    return details;
  }

  @override
  Future<void> leaveGroup(String chatId) async {
    // G2: участник убирает СЕБЯ — сервер берёт его из auth, тела/пути с id
    // не нужно. Ответ (обновлённый состав) игнорируем: вышедший к нему
    // уже не имеет доступа.
    await _requestJson(
      method: 'POST',
      path: '/v1/chats/$chatId/leave',
    );
    unawaited(refreshChatOverview());
  }

  @override
  Future<void> updateChatPreferences({
    required String chatId,
    bool? isArchived,
    String? notificationLevel,
  }) async {
    final body = <String, dynamic>{
      if (isArchived != null) 'isArchived': isArchived,
      if (notificationLevel != null) 'notificationLevel': notificationLevel,
    };
    if (body.isEmpty) return;
    await _requestJson(
      method: 'PATCH',
      path: '/v1/chats/$chatId/preferences',
      body: body,
    );
    unawaited(refreshChatOverview());
  }

  @override
  Future<bool> deleteChat(String chatId, {bool forAll = false}) async {
    final path = forAll ? '/v1/chats/$chatId?forAll=true' : '/v1/chats/$chatId';
    final response = await _requestJson(
      method: 'DELETE',
      path: path,
    );
    unawaited(refreshChatOverview());
    return response['deleted'] == true;
  }

  @override
  Future<List<ChatPreview>> _fetchChatPreviews() async {
    final response = await _requestJson(
      method: 'GET',
      path: '/v1/chats',
    );

    final rawChats = response['chats'];
    if (rawChats is! List<dynamic>) {
      return const <ChatPreview>[];
    }

    return rawChats.whereType<Map<String, dynamic>>().map((chat) {
      final timestamp =
          DateTime.tryParse(chat['lastMessageTime']?.toString() ?? '') ??
              DateTime.now();
      return ChatPreview.fromMap({
        'id': chat['id'],
        'chatId': chat['chatId'],
        'userId': chat['userId'],
        'type': chat['type'],
        'title': chat['title'],
        'photoUrl': chat['photoUrl'],
        'participantIds': chat['participantIds'],
        'otherUserId': chat['otherUserId'],
        'otherUserName': chat['otherUserName'],
        'otherUserPhotoUrl': chat['otherUserPhotoUrl'],
        'lastMessage': chat['lastMessage'],
        'lastMessageTime': timestamp,
        'unreadCount': chat['unreadCount'],
        'lastMessageSenderId': chat['lastMessageSenderId'],
        'isArchived': chat['isArchived'] == true,
        'notificationLevel': chat['notificationLevel'],
      });
    }).toList();
  }

  @override
  Future<int> _fetchTotalUnreadCount() async {
    final response = await _requestJson(
      method: 'GET',
      path: '/v1/chats/unread-count',
    );

    return (response['totalUnread'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> _hydrateChatPreviewsFromCache() async {
    final cache = _previewCache;
    if (cache == null) return;
    try {
      final cached = await cache.read();
      if (cached.isEmpty) return;
      final controller = _chatPreviewsController;
      if (controller == null || controller.isClosed) return;
      // Only emit cached data if we haven't already produced a fresher
      // result during the cache read — race avoidance.
      if (_lastEmittedPreviews != null) return;
      _lastEmittedPreviews = cached;
      controller.add(cached);
    } catch (_) {
      // Cache corruption is non-fatal; let the API refresh repopulate.
    }
  }

  @override
  Future<void> _writeChatPreviewsCache(List<ChatPreview> previews) async {
    final cache = _previewCache;
    if (cache == null) return;
    try {
      await cache.write(previews);
    } catch (_) {
      // Best-effort — never fail the foreground stream because of cache.
    }
  }

  /// Persists the subset of overrides worth surviving a restart: GROUP chats
  /// with a real photoUrl (exactly the disappearing-group-avatar case). Capped
  /// to [_maxPersistedOverrides] most-recent entries to bound the box size.
  @override
  Future<void> _persistRealtimeOverrides() async {
    final cache = _overrideCache;
    if (cache == null) {
      return;
    }
    final persistable = <String, ChatPreviewOverride>{};
    _realtimeChatPreviewOverrides.forEach((chatId, override) {
      if (override.isGroup &&
          override.photoUrl != null &&
          override.photoUrl!.isNotEmpty) {
        persistable[chatId] = override;
      }
    });
    final capped = persistable.length <= _maxPersistedOverrides
        ? persistable
        : Map<String, ChatPreviewOverride>.fromEntries(
            persistable.entries.toList().sublist(
                  persistable.length - _maxPersistedOverrides,
                ),
          );
    await cache.write(capped);
  }

  /// Hydrates the in-memory override map from the persistent cache once, before
  /// the first preview emit, so a stale /v1/chats refetch on cold start can't
  /// blank a restored group avatar. Idempotent; live captures win over cache.
  @override
  Future<void> _hydrateRealtimeOverrides() async {
    if (_overridesHydrated) {
      return;
    }
    _overridesHydrated = true;
    final cache = _overrideCache;
    if (cache == null) {
      return;
    }
    try {
      final stored = await cache.read();
      stored.forEach((chatId, override) {
        // A live chat.updated captured during hydration is fresher — keep it.
        _realtimeChatPreviewOverrides.putIfAbsent(chatId, () => override);
      });
    } catch (_) {
      // Best-effort — a missing/corrupt box just means no restore this boot.
    }
  }

  /// Overlays the realtime overrides on top of a preview list. A new list is
  /// returned only if something actually changed (so callers can skip a
  /// spurious emit); each unchanged preview keeps its identity.
  @override
  List<ChatPreview> _applyRealtimeChatPreviewOverrides(
    List<ChatPreview> previews,
  ) {
    if (_realtimeChatPreviewOverrides.isEmpty) {
      return previews;
    }
    var changed = false;
    final result = previews.map((preview) {
      final override = _realtimeChatPreviewOverrides[preview.chatId];
      if (override == null) {
        return preview;
      }
      final nextPhotoUrl = override.photoUrl ?? preview.photoUrl;
      final nextTitle = override.title ?? preview.title;
      if (nextPhotoUrl == preview.photoUrl && nextTitle == preview.title) {
        return preview;
      }
      changed = true;
      return ChatPreview(
        id: preview.id,
        chatId: preview.chatId,
        userId: preview.userId,
        type: preview.type,
        title: nextTitle,
        photoUrl: nextPhotoUrl,
        participantIds: preview.participantIds,
        otherUserId: preview.otherUserId,
        otherUserName: preview.otherUserName,
        otherUserPhotoUrl: preview.otherUserPhotoUrl,
        lastMessage: preview.lastMessage,
        lastMessageTime: preview.lastMessageTime,
        unreadCount: preview.unreadCount,
        lastMessageSenderId: preview.lastMessageSenderId,
      );
    }).toList();
    return changed ? result : previews;
  }
}
