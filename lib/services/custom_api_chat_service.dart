import 'dart:async';
import 'dart:convert';

import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../backend/backend_runtime_config.dart';
import '../backend/interfaces/chat_service_interface.dart';
import '../backend/interfaces/storage_service_interface.dart';
import '../models/chat_attachment.dart';
import '../models/chat_details.dart';
import '../models/chat_message.dart';
import '../models/chat_preview.dart';
import '../models/chat_send_progress.dart';
import 'custom_api_auth_service.dart';
import 'custom_api_realtime_service.dart';

class CustomApiChatService implements ChatServiceInterface {
  CustomApiChatService({
    required CustomApiAuthService authService,
    required BackendRuntimeConfig runtimeConfig,
    http.Client? httpClient,
    CustomApiRealtimeService? realtimeService,
    StorageServiceInterface? storageService,
    Duration? pollInterval,
    Duration? overviewPollInterval,
  })  : _authService = authService,
        _runtimeConfig = runtimeConfig,
        _httpClient = httpClient ?? http.Client(),
        _realtimeService = realtimeService,
        _storageService = storageService,
        _pollInterval = pollInterval ?? const Duration(seconds: 3),
        _overviewPollInterval =
            overviewPollInterval ?? const Duration(seconds: 12);

  final CustomApiAuthService _authService;
  final BackendRuntimeConfig _runtimeConfig;
  final http.Client _httpClient;
  final CustomApiRealtimeService? _realtimeService;
  final StorageServiceInterface? _storageService;
  final Duration _pollInterval;
  final Duration _overviewPollInterval;
  StreamController<List<ChatPreview>>? _chatPreviewsController;
  Timer? _chatPreviewsTimer;
  StreamSubscription<CustomApiRealtimeEvent>? _chatPreviewsRealtimeSubscription;
  int _chatPreviewsListenerCount = 0;
  bool _chatPreviewsPollingEnabled = false;

  StreamController<int>? _totalUnreadController;
  Timer? _totalUnreadTimer;
  StreamSubscription<CustomApiRealtimeEvent>? _totalUnreadRealtimeSubscription;
  int _totalUnreadListenerCount = 0;
  bool _totalUnreadPollingEnabled = false;

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
    return Stream<List<ChatMessage>>.multi((controller) {
      Timer? timer;
      StreamSubscription<CustomApiRealtimeEvent>? realtimeSubscription;
      var pollingEnabled = true;

      Future<void> emitMessages() async {
        if (!pollingEnabled) {
          return;
        }
        if (!_hasActiveSession) {
          pollingEnabled = false;
          timer?.cancel();
          await realtimeSubscription?.cancel();
          controller.add(const <ChatMessage>[]);
          return;
        }
        try {
          controller.add(await _fetchMessages(chatId));
        } on CustomApiException catch (error, stackTrace) {
          if (await _handleSessionError(error)) {
            pollingEnabled = false;
            timer?.cancel();
            await realtimeSubscription?.cancel();
            controller.add(const <ChatMessage>[]);
            return;
          }
          controller.addError(error, stackTrace);
        } catch (error, stackTrace) {
          if (await _handleSessionError(error)) {
            pollingEnabled = false;
            timer?.cancel();
            await realtimeSubscription?.cancel();
            controller.add(const <ChatMessage>[]);
            return;
          }
          controller.addError(error, stackTrace);
        }
      }

      unawaited(emitMessages());
      timer = Timer.periodic(_pollInterval, (_) {
        unawaited(emitMessages());
      });

      if (_realtimeService != null) {
        unawaited(_realtimeService!.connect());
        realtimeSubscription = _realtimeService!.events.where((event) {
          if (event.type == 'chat.read.updated') {
            return event.chatId == chatId;
          }
          if (event.type == 'chat.message.created' ||
              event.type == 'chat.message.updated' ||
              event.type == 'chat.message.deleted') {
            return event.chatId == chatId;
          }
          return false;
        }).listen((_) {
          unawaited(emitMessages());
        });
      }

      controller.onCancel = () async {
        timer?.cancel();
        await realtimeSubscription?.cancel();
      };
    });
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
        unawaited(_emitChatPreviews());
      });
    }
  }

  Future<void> _stopChatPreviewsPolling() async {
    _chatPreviewsPollingEnabled = false;
    _chatPreviewsTimer?.cancel();
    _chatPreviewsTimer = null;
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
      controller.addError(error, stackTrace);
    } catch (error, stackTrace) {
      if (await _handleSessionError(error)) {
        await _stopChatPreviewsPolling();
        if (!controller.isClosed) {
          controller.add(const <ChatPreview>[]);
        }
        return;
      }
      controller.addError(error, stackTrace);
    }
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
        unawaited(_emitTotalUnread());
      });
    }
  }

  Future<void> _stopTotalUnreadPolling() async {
    _totalUnreadPollingEnabled = false;
    _totalUnreadTimer?.cancel();
    _totalUnreadTimer = null;
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
      controller.addError(error, stackTrace);
    } catch (error, stackTrace) {
      if (await _handleSessionError(error)) {
        await _stopTotalUnreadPolling();
        if (!controller.isClosed) {
          controller.add(0);
        }
        return;
      }
      controller.addError(error, stackTrace);
    }
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

    return rawMessages.whereType<Map<String, dynamic>>().map((message) {
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
    }).toList();
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
        uploadedAttachments.add(
          ChatAttachment(
            type: _attachmentTypeForFile(attachment, uploadedUrl),
            url: uploadedUrl,
            mimeType: attachment.mimeType,
            fileName: _attachmentFileName(attachment, uploadedUrl),
            sizeBytes: await attachment.length(),
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
      return true;
    }

    await _authService.signOut();
    return true;
  }
}
