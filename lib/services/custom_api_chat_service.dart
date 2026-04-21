import 'dart:async';
import 'dart:convert';

import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../backend/backend_runtime_config.dart';
import '../backend/interfaces/chat_service_interface.dart';
import '../backend/interfaces/storage_service_interface.dart';
import '../models/chat_attachment.dart';
import '../models/chat_details.dart';
import '../models/chat_message.dart';
import '../models/chat_preview.dart';
import '../models/chat_send_progress.dart';
import 'app_status_service.dart';
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
}

class _UploadedAttachmentMetadata {
  const _UploadedAttachmentMetadata({
    this.durationMs,
    this.width,
    this.height,
  });

  final int? durationMs;
  final int? width;
  final int? height;
}

class CustomApiChatService implements ChatServiceInterface {
  CustomApiChatService({
    required CustomApiAuthService authService,
    required BackendRuntimeConfig runtimeConfig,
    http.Client? httpClient,
    CustomApiRealtimeService? realtimeService,
    StorageServiceInterface? storageService,
    AppStatusService? appStatusService,
    Duration? pollInterval,
    Duration? overviewPollInterval,
  })  : _authService = authService,
        _runtimeConfig = runtimeConfig,
        _httpClient = httpClient ?? http.Client(),
        _realtimeService = realtimeService,
        _storageService = storageService,
        _appStatusService = appStatusService,
        _pollInterval = pollInterval ?? const Duration(seconds: 3),
        _overviewPollInterval =
            overviewPollInterval ?? const Duration(seconds: 12);

  final CustomApiAuthService _authService;
  final BackendRuntimeConfig _runtimeConfig;
  final http.Client _httpClient;
  final CustomApiRealtimeService? _realtimeService;
  final StorageServiceInterface? _storageService;
  final AppStatusService? _appStatusService;
  final Duration _pollInterval;
  final Duration _overviewPollInterval;
  StreamController<List<ChatPreview>>? _chatPreviewsController;
  Timer? _chatPreviewsTimer;
  Timer? _chatPreviewsRealtimeDebounce;
  StreamSubscription<CustomApiRealtimeEvent>? _chatPreviewsRealtimeSubscription;
  int _chatPreviewsListenerCount = 0;
  bool _chatPreviewsPollingEnabled = false;

  StreamController<int>? _totalUnreadController;
  Timer? _totalUnreadTimer;
  Timer? _totalUnreadRealtimeDebounce;
  StreamSubscription<CustomApiRealtimeEvent>? _totalUnreadRealtimeSubscription;
  int _totalUnreadListenerCount = 0;
  bool _totalUnreadPollingEnabled = false;
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
    _ensureChatPreviewsStream();
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

    await _requestJson(
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
      _scheduleMessageRefresh(messageState, immediate: true);
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
          _startChatPreviewsPolling();
        }
      },
      onCancel: () async {
        _chatPreviewsListenerCount--;
        if (_chatPreviewsListenerCount <= 0) {
          _chatPreviewsListenerCount = 0;
          await _stopChatPreviewsPolling();
        }
      },
    );
  }

  void _startChatPreviewsPolling() {
    if (_chatPreviewsPollingEnabled || _chatPreviewsController == null) {
      return;
    }

    _chatPreviewsPollingEnabled = true;
    unawaited(_emitChatPreviews());
    _chatPreviewsTimer = Timer.periodic(
      _overviewPollInterval,
      (_) => unawaited(_emitChatPreviews()),
    );

    if (_realtimeService != null) {
      unawaited(_realtimeService!.connect());
      _chatPreviewsRealtimeSubscription = _realtimeService!.events
          .where((event) => event.isChatEvent || event.isNotificationEvent)
          .listen((_) {
        _scheduleChatPreviewsRefresh();
      });
    }
  }

  Future<void> _stopChatPreviewsPolling() async {
    _chatPreviewsPollingEnabled = false;
    _chatPreviewsTimer?.cancel();
    _chatPreviewsTimer = null;
    _chatPreviewsRealtimeDebounce?.cancel();
    _chatPreviewsRealtimeDebounce = null;
    await _chatPreviewsRealtimeSubscription?.cancel();
    _chatPreviewsRealtimeSubscription = null;
  }

  Future<void> _emitChatPreviews() async {
    final controller = _chatPreviewsController;
    if (!_chatPreviewsPollingEnabled ||
        controller == null ||
        controller.isClosed) {
      return;
    }

    if (!_hasActiveSession) {
      await _stopChatPreviewsPolling();
      if (!controller.isClosed) {
        controller.add(const <ChatPreview>[]);
      }
      return;
    }

    try {
      controller.add(await _fetchChatPreviews());
    } on CustomApiException catch (error, stackTrace) {
      if (await _handleSessionError(error)) {
        await _stopChatPreviewsPolling();
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
        await _stopChatPreviewsPolling();
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

  void _scheduleChatPreviewsRefresh() {
    _chatPreviewsRealtimeDebounce?.cancel();
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
          _startTotalUnreadPolling();
        }
      },
      onCancel: () async {
        _totalUnreadListenerCount--;
        if (_totalUnreadListenerCount <= 0) {
          _totalUnreadListenerCount = 0;
          await _stopTotalUnreadPolling();
        }
      },
    );
  }

  void _startTotalUnreadPolling() {
    if (_totalUnreadPollingEnabled || _totalUnreadController == null) {
      return;
    }

    _totalUnreadPollingEnabled = true;
    unawaited(_emitTotalUnread());
    _totalUnreadTimer = Timer.periodic(
      _overviewPollInterval,
      (_) => unawaited(_emitTotalUnread()),
    );

    if (_realtimeService != null) {
      unawaited(_realtimeService!.connect());
      _totalUnreadRealtimeSubscription = _realtimeService!.events
          .where((event) => event.isChatEvent || event.isNotificationEvent)
          .listen((_) {
        _scheduleTotalUnreadRefresh();
      });
    }
  }

  Future<void> _stopTotalUnreadPolling() async {
    _totalUnreadPollingEnabled = false;
    _totalUnreadTimer?.cancel();
    _totalUnreadTimer = null;
    _totalUnreadRealtimeDebounce?.cancel();
    _totalUnreadRealtimeDebounce = null;
    await _totalUnreadRealtimeSubscription?.cancel();
    _totalUnreadRealtimeSubscription = null;
  }

  Future<void> _emitTotalUnread() async {
    final controller = _totalUnreadController;
    if (!_totalUnreadPollingEnabled ||
        controller == null ||
        controller.isClosed) {
      return;
    }

    if (!_hasActiveSession) {
      await _stopTotalUnreadPolling();
      if (!controller.isClosed) {
        controller.add(0);
      }
      return;
    }

    try {
      controller.add(await _fetchTotalUnreadCount());
    } on CustomApiException catch (error, stackTrace) {
      if (await _handleSessionError(error)) {
        await _stopTotalUnreadPolling();
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
        await _stopTotalUnreadPolling();
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

  void _scheduleTotalUnreadRefresh() {
    _totalUnreadRealtimeDebounce?.cancel();
    _totalUnreadRealtimeDebounce = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_emitTotalUnread()),
    );
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

    unawaited(_refreshMessageState(state));

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
    try {
      state.messages = await _fetchMessages(state.chatId);
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
    if (!state.controller.isClosed) {
      state.controller.add(List<ChatMessage>.unmodifiable(nextMessages));
    }
  }

  void _applyReadUpdate(_ChatMessageStreamState state, String readerUserId) {
    final nextMessages = state.messages.map((message) {
      if (message.senderId == readerUserId || message.isRead) {
        return message;
      }
      return message.copyWith(isRead: true);
    }).toList(growable: false);
    state.messages = nextMessages;
    if (!state.controller.isClosed) {
      state.controller.add(List<ChatMessage>.unmodifiable(nextMessages));
    }
  }

  int _sortMessagesDescending(ChatMessage left, ChatMessage right) {
    return right.timestamp.compareTo(left.timestamp);
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
    });
  }

  Future<List<ChatMessage>> _fetchMessages(String chatId) async {
    final response = await _requestJson(
      method: 'GET',
      path: '/v1/chats/$chatId/messages',
    );

    final rawMessages = response['messages'];
    if (rawMessages is! List<dynamic>) {
      return const <ChatMessage>[];
    }

    return rawMessages
        .whereType<Map<String, dynamic>>()
        .map(_parseChatMessage)
        .toList();
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
      final uploadedUrl = await storageService.uploadImage(
        attachment,
        'chat-media/$userId',
      );
      if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
        final attachmentType = _attachmentTypeForFile(attachment, uploadedUrl);
        final metadata = await _buildAttachmentMetadata(
          attachment,
          attachmentType,
        );
        uploadedAttachments.add(
          ChatAttachment(
            type: attachmentType,
            url: uploadedUrl,
            presentation: _attachmentPresentationForFile(
              attachment,
              attachmentType,
            ),
            mimeType: attachment.mimeType,
            fileName: _attachmentFileName(attachment, uploadedUrl),
            sizeBytes: await attachment.length(),
            durationMs: metadata.durationMs,
            width: metadata.width,
            height: metadata.height,
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

  Future<_UploadedAttachmentMetadata> _buildAttachmentMetadata(
    XFile attachment,
    ChatAttachmentType type,
  ) async {
    if (type == ChatAttachmentType.audio) {
      return _UploadedAttachmentMetadata(
        durationMs: _durationFromAttachmentName(attachment.name),
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

  ChatAttachmentPresentation _attachmentPresentationForFile(
    XFile attachment,
    ChatAttachmentType type,
  ) {
    final normalizedName = attachment.name.toLowerCase().trim();
    if (type == ChatAttachmentType.audio &&
        (normalizedName.startsWith('voice_note') ||
            normalizedName.startsWith('voice-'))) {
      return ChatAttachmentPresentation.voiceNote;
    }
    if (type == ChatAttachmentType.video &&
        (normalizedName.startsWith('video_note') ||
            normalizedName.startsWith('video-note'))) {
      return ChatAttachmentPresentation.videoNote;
    }
    return ChatAttachmentPresentation.defaultPresentation;
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
  }) async {
    final uri = _buildUri(path);
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

  Uri _buildUri(String path) {
    final normalizedBase = _runtimeConfig.apiBaseUrl.replaceAll(
      RegExp(r'/$'),
      '',
    );
    return Uri.parse('$normalizedBase$path');
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
