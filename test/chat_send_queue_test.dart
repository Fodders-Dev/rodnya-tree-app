import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rodnya/backend/interfaces/chat_service_interface.dart';
import 'package:rodnya/models/chat_attachment.dart';
import 'package:rodnya/models/chat_details.dart';
import 'package:rodnya/models/chat_message.dart';
import 'package:rodnya/models/chat_preview.dart';
import 'package:rodnya/models/chat_send_progress.dart';
import 'package:rodnya/services/app_status_service.dart';
import 'package:rodnya/services/chat_send_queue.dart';
import 'package:rodnya/services/custom_api_auth_service.dart';

void main() {
  late Directory hiveDirectory;
  var boxCounter = 0;

  setUpAll(() {
    hiveDirectory = Directory.systemTemp.createTempSync(
      'rodnya_chat_send_queue_test_',
    );
    Hive.init(hiveDirectory.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (hiveDirectory.existsSync()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  String nextBoxName() {
    boxCounter += 1;
    final boxName = 'chat_send_queue_test_$boxCounter';
    addTearDown(() async {
      if (Hive.isBoxOpen(boxName)) {
        await Hive.box<String>(boxName).close();
      }
      try {
        await Hive.deleteBoxFromDisk(boxName);
      } catch (_) {
        // The box may not have been opened by a failed test.
      }
    });
    return boxName;
  }

  test('ChatSendQueue enqueues immediately and marks send as sent', () async {
    final chatService = _FakeChatService();
    chatService.holdSends();
    final queue = ChatSendQueue.memory(chatService: chatService);
    addTearDown(queue.dispose);

    final message = await queue.enqueue(
      chatId: 'chat-1',
      senderId: 'user-1',
      text: 'Привет',
    );

    expect(queue.messagesFor('chat-1').single.status,
        ChatPendingMessageStatus.pending);
    await _waitUntil(() => chatService.sentRequests.isNotEmpty);
    expect(chatService.sentRequests.single.clientMessageId, message.localId);

    chatService.completeSend();
    await _waitUntil(
      () =>
          queue.messagesFor('chat-1').single.status ==
          ChatPendingMessageStatus.sent,
    );
  });

  test('ChatSendQueue stores failure and retries with same clientMessageId',
      () async {
    final chatService = _FakeChatService()
      ..nextError = const CustomApiException('offline');
    final queue = ChatSendQueue.memory(chatService: chatService);
    addTearDown(queue.dispose);

    final message = await queue.enqueue(
      chatId: 'chat-1',
      senderId: 'user-1',
      text: 'Повтори',
    );

    await _waitUntil(
      () =>
          queue.messagesFor('chat-1').single.status ==
          ChatPendingMessageStatus.failed,
    );
    expect(queue.messagesFor('chat-1').single.errorText, 'offline');

    chatService.nextError = null;
    await queue.retry('chat-1', message.localId);

    expect(chatService.sentRequests, hasLength(2));
    expect(
      chatService.sentRequests.map((request) => request.clientMessageId),
      [message.localId, message.localId],
    );
    expect(queue.messagesFor('chat-1').single.status,
        ChatPendingMessageStatus.sent);
  });

  test(
      'S4: авиарежим — офлайн в очередь, онлайн доставляет ровно один раз '
      'с тем же clientMessageId', () async {
    final appStatus = AppStatusService();
    addTearDown(appStatus.dispose);
    appStatus.debugSetOffline(true);

    final chatService = _FakeChatService()
      ..nextError = const CustomApiException('Сеть недоступна');
    final queue = ChatSendQueue.memory(
      chatService: chatService,
      appStatusService: appStatus,
    );
    addTearDown(queue.dispose);

    // Офлайн: сообщение падает в очередь как failed.
    final message = await queue.enqueue(
      chatId: 'chat-1',
      senderId: 'user-1',
      text: 'Из самолёта',
    );
    await _waitUntil(
      () =>
          queue.messagesFor('chat-1').single.status ==
          ChatPendingMessageStatus.failed,
    );
    expect(chatService.sentRequests, hasLength(1));

    // Самолёт сел: связь вернулась → авторетрай без действий пользователя.
    chatService.nextError = null;
    appStatus.debugSetOffline(false);
    await _waitUntil(
      () =>
          queue.messagesFor('chat-1').single.status ==
          ChatPendingMessageStatus.sent,
    );

    // Доставлено одной успешной попыткой, оба захода — с ОДНИМ
    // clientMessageId: бэк-дедуп (store.sendMessage) схлопнет повтор,
    // если ACK первой попытки потерялся по дороге.
    expect(chatService.sentRequests, hasLength(2));
    expect(
      chatService.sentRequests.map((request) => request.clientMessageId).toSet(),
      {message.localId},
    );
  });

  test('ChatSendQueue persists failed queue entries in Hive', () async {
    final boxName = nextBoxName();
    final chatService = _FakeChatService()
      ..nextError = const CustomApiException('offline');
    final queue = ChatSendQueue(chatService: chatService, boxName: boxName);
    addTearDown(queue.dispose);

    final message = await queue.enqueue(
      chatId: 'chat-1',
      senderId: 'user-1',
      text: 'Сохрани меня',
      forwardedAttachments: const [
        ChatAttachment(
          type: ChatAttachmentType.file,
          url: 'https://cdn.example.test/file.pdf',
          fileName: 'file.pdf',
        ),
      ],
    );
    await _waitUntil(
      () =>
          queue.messagesFor('chat-1').single.status ==
          ChatPendingMessageStatus.failed,
    );

    final restoredQueue = ChatSendQueue(
      chatService: _FakeChatService(),
      boxName: boxName,
    );
    addTearDown(restoredQueue.dispose);
    await restoredQueue.restoreChat('chat-1');

    final restored = restoredQueue.messagesFor('chat-1').single;
    expect(restored.localId, message.localId);
    expect(restored.status, ChatPendingMessageStatus.failed);
    expect(restored.forwardedAttachments.single.fileName, 'file.pdf');
  });

  test('ChatSendQueue removes pending item when remote message confirms it',
      () async {
    final chatService = _FakeChatService();
    chatService.holdSends();
    final queue = ChatSendQueue.memory(chatService: chatService);
    addTearDown(queue.dispose);

    final message = await queue.enqueue(
      chatId: 'chat-1',
      senderId: 'user-1',
      text: 'Подтверждение',
    );
    await _waitUntil(() => chatService.sentRequests.isNotEmpty);
    chatService.completeSend();
    await _waitUntil(
      () =>
          queue.messagesFor('chat-1').single.status ==
          ChatPendingMessageStatus.sent,
    );

    await queue.confirmRemoteMessages('chat-1', [
      ChatMessage(
        id: 'remote-1',
        chatId: 'chat-1',
        senderId: 'user-1',
        text: 'Подтверждение',
        timestamp: DateTime.utc(2026, 4, 30, 12),
        isRead: false,
        participants: const ['user-1', 'other-user'],
        clientMessageId: message.localId,
      ),
    ]);

    expect(queue.messagesFor('chat-1'), isEmpty);
  });
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Condition was not met before timeout.');
}

class _FakeChatService implements ChatServiceInterface {
  final List<_SentQueueRequest> sentRequests = <_SentQueueRequest>[];
  Object? nextError;
  Completer<void>? _sendCompleter;

  @override
  String? get currentUserId => 'user-1';

  void holdSends() {
    _sendCompleter = Completer<void>();
  }

  void completeSend() {
    final completer = _sendCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _sendCompleter = null;
  }

  @override
  String buildChatId(String otherUserId) => 'chat-$otherUserId';

  @override
  Stream<List<ChatPreview>> getUserChatsStream(String userId) {
    return const Stream<List<ChatPreview>>.empty();
  }

  @override
  Stream<int> getTotalUnreadCountStream(String userId) {
    return const Stream<int>.empty();
  }

  @override
  Stream<List<ChatMessage>> getMessagesStream(String chatId) {
    return const Stream<List<ChatMessage>>.empty();
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
    sentRequests.add(
      _SentQueueRequest(
        chatId: chatId,
        text: text,
        clientMessageId: clientMessageId,
      ),
    );
    onProgress?.call(
      const ChatSendProgress(
        stage: ChatSendProgressStage.sending,
        completed: 1,
        total: 1,
      ),
    );

    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }

    await _sendCompleter?.future;
  }

  @override
  Future<void> sendMessage({
    required String otherUserId,
    String text = '',
    List<XFile> attachments = const <XFile>[],
  }) async {}

  @override
  Future<void> markChatAsRead(String chatId, String userId) async {}

  @override
  Future<String?> getOrCreateChat(String otherUserId) async => 'chat-1';

  @override
  Future<ChatDetails> getChatDetails(String chatId) {
    throw UnimplementedError();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SentQueueRequest {
  const _SentQueueRequest({
    required this.chatId,
    required this.text,
    required this.clientMessageId,
  });

  final String chatId;
  final String text;
  final String? clientMessageId;
}
