part of '../custom_api_chat_service.dart';

abstract class _CustomApiChatBase
    implements
        ChatServiceInterface,
        RemoteChatDraftClient,
        RemoteChatPinClient {
  _CustomApiChatBase({
    required CustomApiAuthService authService,
    required BackendRuntimeConfig runtimeConfig,
    http.Client? httpClient,
    CustomApiRealtimeService? realtimeService,
    StorageServiceInterface? storageService,
    ChatMessageCache? messageCache,
    ChatPreviewCache? previewCache,
    ChatPreviewOverrideCache? overrideCache,
    AppStatusService? appStatusService,
    Duration? pollInterval,
    Duration? overviewPollInterval,
    Duration? realtimeFallbackPollInterval,
  })  : _authService = authService,
        _runtimeConfig = runtimeConfig,
        // SPEED-4: горячий путь отправки — держим keep-alive тёплым 5 минут
        // (дефолтные 15с рвали соединение за время набора текста → свежий
        // TCP+TLS handshake на следующем сообщении).
        _httpClient = httpClient ?? createWarmHttpClient(),
        _realtimeService = realtimeService,
        _storageService = storageService,
        _messageCache = messageCache,
        _previewCache = previewCache,
        // Persist overrides whenever the app wired a (Hive) preview cache —
        // that's our reliable "Hive is available" signal. Tests that inject
        // neither stay fully in-memory; the cold-start test injects its own.
        _overrideCache = overrideCache ??
            (previewCache != null ? HiveChatPreviewOverrideCache() : null),
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

  // Realtime-sourced overrides for chat-list previews, keyed by chatId. A
  // realtime chat.updated/chat.created carries the FULL mapped chat (with a
  // correct photoUrl/title), whereas GET /v1/chats can return a stale null
  // group photoUrl until the backend is restarted. We overlay these on top of
  // the fetch result so the fresh event value wins and survives a stale
  // refetch (which would otherwise blank the group avatar back out).
  final Map<String, ChatPreviewOverride> _realtimeChatPreviewOverrides =
      <String, ChatPreviewOverride>{};

  // Persistence for the override map (cold-start survival). Defaults to a Hive
  // box when a (Hive) preview cache is wired — i.e. in the real app — and to
  // null in tests that don't opt in. Hydrated once before the first emit.
  final ChatPreviewOverrideCache? _overrideCache;

  bool _overridesHydrated = false;

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
      'call': message['call'],
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

  Future<Map<String, dynamic>> _requestJson({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
  }) async {
    StartupTrace.logRequest(method, path);
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

    final payload = tryDecodeJsonMap(response.body);
    if (payload == null) {
      throw CustomApiException(
        'Сервер вернул некорректный ответ (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }

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
            error.message.contains('Нет активной customApi session'));
    if (!isUnauthorized) {
      return false;
    }

    if (_authService.currentUserId == null) {
      _appStatusService?.reportSessionExpired();
      return true;
    }

    await _authService.clearSessionLocally(sessionExpired: true);
    return true;
  }

  // Forwarders for cross-mixin calls.
  void _applyReactionUpdate(
    _ChatMessageStreamState state,
    String messageId,
    List<dynamic> rawReactions,
  );
  List<ChatPreview> _applyRealtimeChatPreviewOverrides(
    List<ChatPreview> previews,
  );
  Future<void> _emitChatPreviews();
  Future<void> _emitTotalUnread();
  void _ensureChatPreviewsStream();
  _ChatMessageStreamState _ensureMessageStream(String chatId);
  void _ensureTotalUnreadStream();
  Future<List<ChatPreview>> _fetchChatPreviews();
  Future<int> _fetchTotalUnreadCount();
  Future<void> _hydrateChatPreviewsFromCache();
  Future<void> _hydrateMessageState(_ChatMessageStreamState state);
  Future<void> _hydrateRealtimeOverrides();
  void _mergeRealtimeMessage(
    _ChatMessageStreamState state,
    Map<String, dynamic> rawMessage,
  );
  Future<void> _persistRealtimeOverrides();
  void _pruneLocalMessage(String chatId, String messageId);
  Future<void> _refreshMessageState(_ChatMessageStreamState state);
  void _scheduleMessageRefresh(
    _ChatMessageStreamState state, {
    bool immediate = false,
  });
  Future<List<ChatAttachment>> _uploadAttachments(
    List<XFile> attachments, {
    void Function(ChatSendProgress progress)? onProgress,
  });
  Future<void> _writeChatPreviewsCache(List<ChatPreview> previews);
  @override
  Future<String?> getOrCreateChat(String otherUserId);
}
