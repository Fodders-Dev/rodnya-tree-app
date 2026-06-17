import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../backend/backend_runtime_config.dart';
import '../backend/interfaces/chat_service_interface.dart';
import '../backend/interfaces/storage_service_interface.dart';
import '../models/chat_attachment.dart';
import '../models/chat_details.dart';
import '../models/chat_message.dart';
import '../models/chat_message_search_result.dart';
import '../models/chat_messages_page.dart';
import '../models/chat_preview.dart';
import '../models/chat_send_progress.dart';
import '../utils/voice_waveform.dart';
import 'app_status_service.dart';
import 'chat_draft_store.dart';
import 'chat_message_cache.dart';
import 'chat_preview_cache.dart';
import 'chat_pin_store.dart';
import 'custom_api_auth_service.dart';
import 'custom_api_realtime_service.dart';

class _ChatMessageStreamState {
  _ChatMessageStreamState(this.chatId);

  final String chatId;
  late final StreamController<List<ChatMessage>> controller;
  StreamSubscription<CustomApiRealtimeEvent>? realtimeSubscription;
  Timer? refreshDebounce;
  int listenerCount = 0;
  bool started = false;
  bool isFetching = false;
  bool hasQueuedRefresh = false;
  List<ChatMessage> messages = const <ChatMessage>[];
  int messagesVersion = 0;
}

class _UploadedAttachmentMetadata {
  const _UploadedAttachmentMetadata({
    this.durationMs,
    this.waveform = const <double>[],
    this.width,
    this.height,
  });

  final int? durationMs;
  final List<double> waveform;
  final int? width;
  final int? height;
}

class CustomApiChatService
    implements
        ChatServiceInterface,
        RemoteChatDraftClient,
        RemoteChatPinClient {
  CustomApiChatService({
    required CustomApiAuthService authService,
    required BackendRuntimeConfig runtimeConfig,
    http.Client? httpClient,
    CustomApiRealtimeService? realtimeService,
    StorageServiceInterface? storageService,
    ChatMessageCache? messageCache,
    ChatPreviewCache? previewCache,
    AppStatusService? appStatusService,
    Duration? pollInterval,
    Duration? overviewPollInterval,
    Duration? realtimeFallbackPollInterval,
  })  : _authService = authService,
        _runtimeConfig = runtimeConfig,
        _httpClient = httpClient ?? http.Client(),
        _realtimeService = realtimeService,
        _storageService = storageService,
        _messageCache = messageCache,
        _previewCache = previewCache,
        _appStatusService = appStatusService,
        _pollInterval = pollInterval ?? const Duration(seconds: 3),
        _realtimeFallbackPollInterval = realtimeFallbackPollInterval ??
            overviewPollInterval ??
            const Duration(seconds: 30);

  final CustomApiAuthService _authService;
  final BackendRuntimeConfig _runtimeConfig;
  final http.Client _httpClient;
  final CustomApiRealtimeService? _realtimeService;
  final StorageServiceInterface? _storageService;
  final ChatMessageCache? _messageCache;
  final ChatPreviewCache? _previewCache;
  final AppStatusService? _appStatusService;
  final Duration _pollInterval;
  final Duration _realtimeFallbackPollInterval;

  /// Snapshot of the most recently emitted previews — keeps us from
  /// re-hydrating the cache on every realtime tick when nothing changed.
  List<ChatPreview>? _lastEmittedPreviews;
  StreamController<List<ChatPreview>>? _chatPreviewsController;
  Timer? _chatPreviewsFallbackTimer;
  Timer? _chatPreviewsRealtimeDebounce;
  StreamSubscription<CustomApiRealtimeEvent>? _chatPreviewsRealtimeSubscription;
  int _chatPreviewsListenerCount = 0;
  bool _chatPreviewsUpdatesActive = false;

  StreamController<int>? _totalUnreadController;
  Timer? _totalUnreadFallbackTimer;
  Timer? _totalUnreadRealtimeDebounce;
  StreamSubscription<CustomApiRealtimeEvent>? _totalUnreadRealtimeSubscription;
  int _totalUnreadListenerCount = 0;
  bool _totalUnreadUpdatesActive = false;
  final Map<String, _ChatMessageStreamState> _messageStates =
      <String, _ChatMessageStreamState>{};

  @override
  String? get currentUserId => _authService.currentUserId;

  @override
  String buildChatId(String otherUserId) {
    final userId = currentUserId;
    if (userId == null || userId.isEmpty) {
      throw const CustomApiException('Пользователь не авторизован');
    }

    final ids = <String>[userId, otherUserId]..sort();
    return ids.join('_');
  }

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

  @override
  Stream<List<ChatMessage>> getMessagesStream(String chatId) {
    return _ensureMessageStream(chatId).controller.stream;
  }

  Future<void> refreshChatOverview() async {
    if (_chatPreviewsUpdatesActive) {
      await _emitChatPreviews();
    }
    if (_totalUnreadUpdatesActive) {
      await _emitTotalUnread();
    }
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
    await _requestJson(
      method: 'DELETE',
      path: '/v1/chats/$chatId/messages/$messageId',
    );
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

    return ChatDetails.fromMap({
      ...rawChat,
      'participants': response['participants'],
      'branchRoots': response['branchRoots'],
    });
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

    return ChatDetails.fromMap({
      ...rawChat,
      'participants': response['participants'],
      'branchRoots': response['branchRoots'],
    });
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

    return ChatDetails.fromMap({
      ...rawChat,
      'participants': response['participants'],
      'branchRoots': response['branchRoots'],
    });
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
  }

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
      });
    }).toList();
  }

  Future<int> _fetchTotalUnreadCount() async {
    final response = await _requestJson(
      method: 'GET',
      path: '/v1/chats/unread-count',
    );

    return (response['totalUnread'] as num?)?.toInt() ?? 0;
  }

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
    unawaited(_emitChatPreviews());

    if (_realtimeService != null) {
      unawaited(_realtimeService!.connect());
      _chatPreviewsRealtimeSubscription =
          _realtimeService!.events.listen((event) {
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
          _scheduleChatPreviewsRefresh();
        }
      });
    } else {
      _startChatPreviewsFallbackPolling();
    }
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
      _lastEmittedPreviews = previews;
      // Persist to cache so the next cold start can show the list before
      // the network round-trip finishes. Failures are non-fatal — caching
      // is a UX optimization, not a source of truth.
      unawaited(_writeChatPreviewsCache(previews));
      controller.add(previews);
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
      controller.addError(error, stackTrace);
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
      controller.addError(error, stackTrace);
    }
  }

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

  Future<void> _writeChatPreviewsCache(List<ChatPreview> previews) async {
    final cache = _previewCache;
    if (cache == null) return;
    try {
      await cache.write(previews);
    } catch (_) {
      // Best-effort — never fail the foreground stream because of cache.
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
      unawaited(_realtimeService!.connect());
      _totalUnreadRealtimeSubscription =
          _realtimeService!.events.listen((event) {
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
      controller.addError(error, stackTrace);
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
      controller.addError(error, stackTrace);
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
      unawaited(_realtimeService!.connect());
      state.realtimeSubscription = _realtimeService!.events.listen((event) {
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

  Future<void> _hydrateMessageState(_ChatMessageStreamState state) async {
    if (_messageCache == null) {
      await _refreshMessageState(state);
      return;
    }

    var cachedMessages = const <ChatMessage>[];
    try {
      cachedMessages = await _messageCache!.read(state.chatId);
    } catch (_) {
      cachedMessages = const <ChatMessage>[];
    }

    if (cachedMessages.isNotEmpty) {
      state.messages = cachedMessages;
      if (!state.controller.isClosed) {
        state.controller.add(List<ChatMessage>.unmodifiable(cachedMessages));
      }
      await _refreshMessageState(state, afterId: cachedMessages.first.id);
      return;
    }

    await _refreshMessageState(state);
  }

  Future<void> _refreshMessageState(
    _ChatMessageStreamState state, {
    String? afterId,
  }) async {
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
      final normalizedAfterId = afterId?.trim();
      final hasAfterId =
          normalizedAfterId != null && normalizedAfterId.isNotEmpty;
      final page = await fetchMessagesPage(
        state.chatId,
        limit: hasAfterId ? 200 : 100,
        afterId: hasAfterId ? normalizedAfterId : null,
      );
      final pageMessages = page.messages;
      state.messages = hasAfterId
          ? _mergeMessageLists(state.messages, pageMessages)
          : state.messagesVersion == versionAtRequestStart
              ? pageMessages
              : _mergeMessageListsPreservingExisting(
                  state.messages,
                  pageMessages,
                );
      state.messagesVersion++;
      if (!hasAfterId) {
        _cacheMessages(
          (cache) => cache.write(state.chatId, state.messages),
        );
      }
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

  List<String> _stringListFromDynamic(dynamic value) {
    if (value is! List) {
      return const <String>[];
    }
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
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

  void _cacheMessages(
    Future<void> Function(ChatMessageCache cache) operation,
  ) {
    final cache = _messageCache;
    if (cache == null) {
      return;
    }

    unawaited(() async {
      try {
        await operation(cache);
      } catch (_) {
        // Cache failures should not break chat rendering or delivery.
      }
    }());
  }

  /// Coalesce cache writes that come from rapid-fire metadata updates
  /// (reactions, delivery receipts, read markers). Each of these used to
  /// trigger an immediate full Hive read+modify+write of the 200-message
  /// window — fine for one event, expensive when 20 reactions land in
  /// half a second. Now we mark the chat dirty and flush at most once
  /// every ~800 ms, which keeps the offline cache eventually consistent
  /// without the I/O storm.
  final Map<String, Timer> _dirtyMessageCacheFlushTimers = <String, Timer>{};

  void _scheduleDebouncedMessageCacheFlush(_ChatMessageStreamState state) {
    if (_messageCache == null) return;
    _dirtyMessageCacheFlushTimers[state.chatId]?.cancel();
    _dirtyMessageCacheFlushTimers[state.chatId] = Timer(
      const Duration(milliseconds: 800),
      () {
        _dirtyMessageCacheFlushTimers.remove(state.chatId);
        // Snapshot the current message list at flush time — captures any
        // updates that arrived during the debounce window in a single
        // write rather than N separate ones.
        final snapshot = List<ChatMessage>.unmodifiable(state.messages);
        _cacheMessages(
          (cache) => cache.write(state.chatId, snapshot),
        );
      },
    );
  }

  int _sortMessagesDescending(ChatMessage left, ChatMessage right) {
    final timestampCompare = right.timestamp.compareTo(left.timestamp);
    if (timestampCompare != 0) {
      return timestampCompare;
    }
    return right.id.compareTo(left.id);
  }

  ChatMessage _parseChatMessage(Map<String, dynamic> message) {
    return ChatMessage.fromMap({
      'id': message['id'],
      'chatId': message['chatId'],
      'senderId': message['senderId'],
      'text': message['text'],
      'timestamp': message['timestamp'],
      'updatedAt': message['updatedAt'],
      'isRead': message['isRead'],
      'attachments': message['attachments'],
      'imageUrl': message['imageUrl'],
      'mediaUrls': message['mediaUrls'],
      'participants': message['participants'],
      'senderName': message['senderName'],
      'clientMessageId': message['clientMessageId'],
      'expiresAt': message['expiresAt'],
      'replyTo': message['replyTo'],
      'reactions': message['reactions'],
      'deliveredTo': message['deliveredTo'],
      'readBy': message['readBy'],
    });
  }

  ChatPinnedMessageSnapshot? _parsePinnedMessageSnapshot(dynamic value) {
    if (value is! Map) {
      return null;
    }
    final snapshot = ChatPinnedMessageSnapshot.fromJson(
      Map<String, dynamic>.from(value),
    );
    return snapshot.messageId.trim().isEmpty ? null : snapshot;
  }

  Future<List<ChatMessage>> _fetchMessages(String chatId) async {
    return (await fetchMessagesPage(chatId, limit: 100)).messages;
  }

  Future<List<ChatAttachment>> _uploadAttachments(
    List<XFile> attachments, {
    void Function(ChatSendProgress progress)? onProgress,
  }) async {
    if (attachments.isEmpty) {
      return const <ChatAttachment>[];
    }

    final storageService = _storageService ??
        (GetIt.I.isRegistered<StorageServiceInterface>()
            ? GetIt.I<StorageServiceInterface>()
            : null);
    final userId = currentUserId;
    if (storageService == null || userId == null || userId.isEmpty) {
      throw const CustomApiException('Не удалось подготовить вложения');
    }

    onProgress?.call(
      const ChatSendProgress(
        stage: ChatSendProgressStage.preparing,
        completed: 0,
        total: 1,
      ),
    );
    onProgress?.call(
      ChatSendProgress(
        stage: ChatSendProgressStage.uploading,
        completed: 0,
        total: attachments.length,
      ),
    );

    final uploadedAttachments = <ChatAttachment>[];
    for (var index = 0; index < attachments.length; index++) {
      final attachment = attachments[index];
      final initialType = _attachmentTypeForFile(attachment, '');
      final initialPresentation = _attachmentPresentationForFile(
        attachment,
        initialType,
      );
      final useVoiceFolder = _looksLikeVoiceNoteAttachment(attachment);
      final uploadedUrl = await storageService.uploadImage(
        attachment,
        initialPresentation == ChatAttachmentPresentation.voiceNote ||
                useVoiceFolder
            ? 'chat-voice/$userId'
            : 'chat-media/$userId',
      );
      if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
        final attachmentType = _attachmentTypeForFile(attachment, uploadedUrl);
        final presentation = _attachmentPresentationForFile(
          attachment,
          attachmentType,
        );
        final metadata = await _buildAttachmentMetadata(
          attachment,
          attachmentType,
        );
        // V4 (ревью FR3): для исходящего видео генерим постер (первый кадр)
        // и грузим его — thumbnailUrl уезжает в сообщении, поэтому превью
        // видят и отправитель, и получатель. Best-effort: нет постера →
        // остаётся тёмная плитка с play-иконкой.
        final thumbnailUrl = attachmentType == ChatAttachmentType.video
            ? await _buildVideoPosterUrl(attachment, storageService, userId)
            : null;
        uploadedAttachments.add(
          ChatAttachment(
            type: attachmentType,
            url: uploadedUrl,
            presentation: presentation,
            mimeType: attachment.mimeType,
            fileName: _attachmentFileName(attachment, uploadedUrl),
            sizeBytes: await attachment.length(),
            durationMs: metadata.durationMs,
            waveform: metadata.waveform,
            width: metadata.width,
            height: metadata.height,
            thumbnailUrl: thumbnailUrl,
          ),
        );
      }
      onProgress?.call(
        ChatSendProgress(
          stage: ChatSendProgressStage.uploading,
          completed: index + 1,
          total: attachments.length,
        ),
      );
    }
    return uploadedAttachments;
  }

  /// V4 (ревью FR3): постер (первый кадр) локального видео → загруженный URL.
  /// Только не-web (video_thumbnail — нативный MediaMetadataRetriever на
  /// Android). Любой сбой → null: получим тёмную плитку с play-иконкой, но
  /// отправку видео не ломаем.
  Future<String?> _buildVideoPosterUrl(
    XFile attachment,
    StorageServiceInterface storageService,
    String userId,
  ) async {
    if (kIsWeb) {
      return null;
    }
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: attachment.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 720,
        quality: 70,
      );
      if (bytes == null || bytes.isEmpty) {
        return null;
      }
      final poster = XFile.fromData(
        bytes,
        name: 'poster_${attachment.name}.jpg',
        mimeType: 'image/jpeg',
      );
      return await storageService.uploadImage(poster, 'chat-media/$userId');
    } catch (_) {
      return null;
    }
  }

  Future<_UploadedAttachmentMetadata> _buildAttachmentMetadata(
    XFile attachment,
    ChatAttachmentType type,
  ) async {
    if (type == ChatAttachmentType.audio) {
      return _UploadedAttachmentMetadata(
        durationMs: _durationFromAttachmentName(attachment.name),
        waveform: await _buildVoiceWaveform(attachment),
      );
    }
    if (type != ChatAttachmentType.video) {
      return const _UploadedAttachmentMetadata();
    }

    final sourceUri = _attachmentUri(attachment.path);
    final controller = _isRemoteLikeUri(sourceUri)
        ? VideoPlayerController.networkUrl(sourceUri)
        : VideoPlayerController.contentUri(sourceUri);
    try {
      await controller.initialize();
      final value = controller.value;
      final durationMs = value.duration.inMilliseconds > 0
          ? value.duration.inMilliseconds
          : null;
      final width = value.size.width > 0 ? value.size.width.round() : null;
      final height = value.size.height > 0 ? value.size.height.round() : null;
      return _UploadedAttachmentMetadata(
        durationMs: durationMs,
        width: width,
        height: height,
      );
    } catch (_) {
      return const _UploadedAttachmentMetadata();
    } finally {
      await controller.dispose();
    }
  }

  Future<List<double>> _buildVoiceWaveform(XFile attachment) async {
    try {
      return buildVoiceWaveformFromBytes(await attachment.readAsBytes());
    } catch (_) {
      return const <double>[];
    }
  }

  ChatAttachmentPresentation _attachmentPresentationForFile(
    XFile attachment,
    ChatAttachmentType type,
  ) {
    if (type == ChatAttachmentType.audio &&
        _looksLikeVoiceNoteAttachment(attachment)) {
      return ChatAttachmentPresentation.voiceNote;
    }
    final normalizedName = attachment.name.toLowerCase().trim();
    if (type == ChatAttachmentType.video &&
        (normalizedName.startsWith('video_note') ||
            normalizedName.startsWith('video-note'))) {
      return ChatAttachmentPresentation.videoNote;
    }
    return ChatAttachmentPresentation.defaultPresentation;
  }

  bool _looksLikeVoiceNoteAttachment(XFile attachment) {
    final candidates = <String>[
      attachment.name,
      attachment.path,
    ].map((value) => value.toLowerCase().trim()).where((value) {
      return value.isNotEmpty;
    });
    return candidates.any((value) =>
        value.startsWith('voice_note') ||
        value.startsWith('voice-note') ||
        value.contains('/voice_note') ||
        value.contains(r'\voice_note') ||
        value.contains('/voice-note') ||
        value.contains(r'\voice-note'));
  }

  ChatAttachmentType _attachmentTypeForFile(
    XFile attachment,
    String uploadedUrl,
  ) {
    final mimeType = (attachment.mimeType ?? '').toLowerCase().trim();
    final name = attachment.name.toLowerCase().trim();
    final url = uploadedUrl.toLowerCase().trim();

    if (mimeType.startsWith('image/') ||
        ['.jpg', '.jpeg', '.png', '.webp', '.heic', '.gif'].any(
          (ext) => name.endsWith(ext) || url.endsWith(ext),
        )) {
      return ChatAttachmentType.image;
    }

    if (mimeType.startsWith('video/') ||
        ['.mp4', '.mov', '.webm', '.avi', '.mkv'].any(
          (ext) => name.endsWith(ext) || url.endsWith(ext),
        )) {
      return ChatAttachmentType.video;
    }

    if (mimeType.startsWith('audio/') ||
        ['.m4a', '.aac', '.mp3', '.wav', '.ogg', '.flac'].any(
          (ext) => name.endsWith(ext) || url.endsWith(ext),
        )) {
      return ChatAttachmentType.audio;
    }

    return ChatAttachmentType.file;
  }

  String? _attachmentFileName(XFile attachment, String uploadedUrl) {
    final name = attachment.name.trim();
    if (name.isNotEmpty) {
      return name;
    }

    final uri = Uri.tryParse(uploadedUrl);
    final lastSegment = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last.trim()
        : '';
    return lastSegment.isNotEmpty ? lastSegment : null;
  }

  int? _durationFromAttachmentName(String rawName) {
    final match = RegExp(r'_(\d+)s_').firstMatch(rawName.trim().toLowerCase());
    final seconds = int.tryParse(match?.group(1) ?? '');
    if (seconds == null || seconds <= 0) {
      return null;
    }
    return Duration(seconds: seconds).inMilliseconds;
  }

  Uri _attachmentUri(String rawPath) {
    final parsedUri = Uri.tryParse(rawPath);
    if (parsedUri != null && parsedUri.hasScheme) {
      return parsedUri;
    }
    return Uri.file(rawPath);
  }

  bool _isRemoteLikeUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https' || scheme == 'blob';
  }

  Future<Map<String, dynamic>> _requestJson({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
  }) async {
    final uri = _buildUri(path, queryParameters: queryParameters);
    late http.Response response;

    switch (method) {
      case 'GET':
        response = await _httpClient.get(uri, headers: _headers());
        break;
      case 'POST':
        response = await _httpClient.post(
          uri,
          headers: _headers(),
          body: jsonEncode(body ?? const <String, dynamic>{}),
        );
        break;
      case 'PUT':
        response = await _httpClient.put(
          uri,
          headers: _headers(),
          body: jsonEncode(body ?? const <String, dynamic>{}),
        );
        break;
      case 'PATCH':
        response = await _httpClient.patch(
          uri,
          headers: _headers(),
          body: jsonEncode(body ?? const <String, dynamic>{}),
        );
        break;
      case 'DELETE':
        response = await _httpClient.delete(
          uri,
          headers: _headers(),
          body: body == null ? null : jsonEncode(body),
        );
        break;
      default:
        throw CustomApiException('Неподдерживаемый HTTP-метод: $method');
    }

    if (response.body.isEmpty) {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return const <String, dynamic>{};
      }
      throw CustomApiException(
        'Пустой ответ от backend',
        statusCode: response.statusCode,
      );
    }

    final dynamic decoded = jsonDecode(response.body);
    final payload = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'data': decoded};

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return payload;
    }

    throw CustomApiException(
      payload['message']?.toString() ??
          payload['error']?.toString() ??
          'Ошибка backend (${response.statusCode})',
      statusCode: response.statusCode,
    );
  }

  Uri _buildUri(String path, {Map<String, String>? queryParameters}) {
    final normalizedBase = _runtimeConfig.apiBaseUrl.replaceAll(
      RegExp(r'/$'),
      '',
    );
    final uri = Uri.parse('$normalizedBase$path');
    if (queryParameters == null || queryParameters.isEmpty) {
      return uri;
    }
    return uri.replace(
      queryParameters: <String, String>{
        ...uri.queryParameters,
        ...queryParameters,
      },
    );
  }

  Map<String, String> _headers() {
    final token = _authService.accessToken;
    if (token == null || token.isEmpty) {
      throw const CustomApiException('Нет активной customApi session');
    }

    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  bool get _hasActiveSession {
    final token = _authService.accessToken;
    final userId = _authService.currentUserId;
    return token != null &&
        token.isNotEmpty &&
        userId != null &&
        userId.isNotEmpty;
  }

  Future<bool> _handleSessionError(Object error) async {
    final isUnauthorized = error is CustomApiException &&
        (error.statusCode == 401 ||
            error.statusCode == 403 ||
            error.message.contains('Нет активной customApi session'));
    final normalized = error.toString().toLowerCase();
    final looksLikeExpiredSession = normalized.contains('сесс') ||
        normalized.contains('unauthorized') ||
        normalized.contains('expired');
    if (!isUnauthorized && !looksLikeExpiredSession) {
      return false;
    }

    if (_authService.currentUserId == null) {
      _appStatusService?.reportSessionExpired();
      return true;
    }

    await _authService.clearSessionLocally(sessionExpired: true);
    return true;
  }
}
