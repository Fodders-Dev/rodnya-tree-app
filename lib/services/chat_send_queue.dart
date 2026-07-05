import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:image_picker/image_picker.dart';

import '../backend/interfaces/chat_service_interface.dart';
import '../models/chat_attachment.dart';
import '../models/chat_message.dart';
import '../models/chat_send_progress.dart';
import 'app_status_service.dart';
import '../utils/perf_log.dart';
import 'custom_api_auth_service.dart';

enum ChatPendingMessageStatus { pending, sent, failed }

/// Пофайловый статус загрузки вложения исходящего сообщения —
/// деривация из (status, progress): загрузка идёт строго последовательно
/// в порядке attachments, completed растёт по одному (UX-аудит P1:
/// вместо одного общего бара «2/5» — состояние на каждом превью).
enum ChatAttachmentUploadStatus { queued, uploading, done, failed }

class ChatPendingMessage {
  const ChatPendingMessage({
    required this.localId,
    required this.chatId,
    required this.senderId,
    required this.text,
    required this.timestamp,
    required this.attachments,
    required this.forwardedAttachments,
    required this.status,
    this.replyTo,
    this.progress,
    this.errorText,
    this.expiresInSeconds,
  });

  final String localId;
  final String chatId;
  final String senderId;
  final String text;
  final DateTime timestamp;
  final List<XFile> attachments;
  final List<ChatAttachment> forwardedAttachments;
  final ChatPendingMessageStatus status;
  final ChatReplyReference? replyTo;
  final ChatSendProgress? progress;
  final String? errorText;
  final int? expiresInSeconds;

  /// Статусы загрузки по каждому вложению (длина == attachments.length).
  /// Правила: sent → все done; failed → i < completed done, остальные
  /// failed (упавший файл ≈ первый не-загруженный); pending+preparing →
  /// все queued; pending+uploading → i < completed done, i == completed
  /// uploading, дальше queued; pending+sending (или без progress при
  /// вложениях — уже финальный POST) → все done.
  List<ChatAttachmentUploadStatus> get attachmentUploadStatuses {
    final total = attachments.length;
    if (total == 0) {
      return const <ChatAttachmentUploadStatus>[];
    }
    if (status == ChatPendingMessageStatus.sent) {
      return List<ChatAttachmentUploadStatus>.filled(
        total,
        ChatAttachmentUploadStatus.done,
      );
    }
    final currentProgress = progress;
    final completed = currentProgress?.completed ?? 0;
    if (status == ChatPendingMessageStatus.failed) {
      // Стадия sending — файлы УЖЕ загружены (сервис эмитит completed/
      // total в POST-единицах 1/1, не в файловых): упал финальный POST,
      // плитки все done, сообщение ретраится целиком кнопкой «Повторить».
      // Иначе (uploading/preparing) — completed в файловых единицах:
      // догруженные done, начиная с упавшего — failed.
      if (currentProgress?.stage == ChatSendProgressStage.sending) {
        return List<ChatAttachmentUploadStatus>.filled(
          total,
          ChatAttachmentUploadStatus.done,
        );
      }
      return List<ChatAttachmentUploadStatus>.generate(
        total,
        (i) => i < completed
            ? ChatAttachmentUploadStatus.done
            : ChatAttachmentUploadStatus.failed,
      );
    }
    switch (currentProgress?.stage) {
      case ChatSendProgressStage.preparing:
        return List<ChatAttachmentUploadStatus>.filled(
          total,
          ChatAttachmentUploadStatus.queued,
        );
      case ChatSendProgressStage.uploading:
        return List<ChatAttachmentUploadStatus>.generate(
          total,
          (i) => i < completed
              ? ChatAttachmentUploadStatus.done
              : (i == completed
                  ? ChatAttachmentUploadStatus.uploading
                  : ChatAttachmentUploadStatus.queued),
        );
      case ChatSendProgressStage.sending:
      case null:
        return List<ChatAttachmentUploadStatus>.filled(
          total,
          ChatAttachmentUploadStatus.done,
        );
    }
  }

  ChatPendingMessage copyWith({
    ChatPendingMessageStatus? status,
    ChatSendProgress? progress,
    String? errorText,
  }) {
    return ChatPendingMessage(
      localId: localId,
      chatId: chatId,
      senderId: senderId,
      text: text,
      timestamp: timestamp,
      attachments: attachments,
      forwardedAttachments: forwardedAttachments,
      status: status ?? this.status,
      replyTo: replyTo,
      progress: progress ?? this.progress,
      errorText: errorText,
      expiresInSeconds: expiresInSeconds,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'localId': localId,
      'chatId': chatId,
      'senderId': senderId,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'attachments': attachments.map(_xFileToJson).toList(growable: false),
      'forwardedAttachments': forwardedAttachments
          .map((attachment) => attachment.toMap())
          .toList(growable: false),
      'status': status.name,
      if (replyTo != null) 'replyTo': replyTo!.toMap(),
      if (progress != null) 'progress': _progressToJson(progress!),
      if (errorText != null && errorText!.trim().isNotEmpty)
        'errorText': errorText,
      if (expiresInSeconds != null) 'expiresInSeconds': expiresInSeconds,
    };
  }

  factory ChatPendingMessage.fromJson(Map<String, dynamic> json) {
    final status = ChatPendingMessageStatus.values.firstWhere(
      (value) => value.name == json['status']?.toString(),
      orElse: () => ChatPendingMessageStatus.failed,
    );
    return ChatPendingMessage(
      localId: json['localId']?.toString() ?? '',
      chatId: json['chatId']?.toString() ?? '',
      senderId: json['senderId']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.now(),
      attachments: _xFilesFromJson(json['attachments']),
      forwardedAttachments:
          ChatAttachment.listFromDynamic(json['forwardedAttachments']),
      status: status,
      replyTo: _replyFromJson(json['replyTo']),
      progress: _progressFromJson(json['progress']),
      errorText: json['errorText']?.toString(),
      expiresInSeconds: _asInt(json['expiresInSeconds']),
    );
  }

  static Map<String, dynamic> _xFileToJson(XFile file) {
    return <String, dynamic>{
      'path': file.path,
      'name': file.name,
      if (file.mimeType != null && file.mimeType!.isNotEmpty)
        'mimeType': file.mimeType,
    };
  }

  static List<XFile> _xFilesFromJson(dynamic raw) {
    if (raw is! List<dynamic>) {
      return const <XFile>[];
    }
    return raw
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .map((entry) {
          final filePath = entry['path']?.toString() ?? '';
          if (filePath.trim().isEmpty) {
            return null;
          }
          return XFile(
            filePath,
            name: entry['name']?.toString(),
            mimeType: entry['mimeType']?.toString(),
          );
        })
        .whereType<XFile>()
        .toList(growable: false);
  }

  static ChatReplyReference? _replyFromJson(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      final reply = ChatReplyReference.fromMap(raw);
      return reply.messageId.isEmpty ? null : reply;
    }
    if (raw is Map) {
      final reply = ChatReplyReference.fromMap(Map<String, dynamic>.from(raw));
      return reply.messageId.isEmpty ? null : reply;
    }
    return null;
  }

  static Map<String, dynamic> _progressToJson(ChatSendProgress progress) {
    return <String, dynamic>{
      'stage': progress.stage.name,
      'completed': progress.completed,
      'total': progress.total,
    };
  }

  static ChatSendProgress? _progressFromJson(dynamic raw) {
    if (raw is! Map) {
      return null;
    }
    final map = Map<String, dynamic>.from(raw);
    final stage = ChatSendProgressStage.values.firstWhere(
      (value) => value.name == map['stage']?.toString(),
      orElse: () => ChatSendProgressStage.sending,
    );
    return ChatSendProgress(
      stage: stage,
      completed: _asInt(map['completed']) ?? 0,
      total: _asInt(map['total']) ?? 1,
    );
  }

  static int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }
}

class ChatSendQueue extends ChangeNotifier {
  ChatSendQueue({
    required ChatServiceInterface chatService,
    AppStatusService? appStatusService,
    this.boxName = 'chat_send_queue_v1',
  })  : _chatService = chatService,
        _appStatusService = appStatusService {
    _bindAppStatusService();
  }

  ChatSendQueue.memory({
    required ChatServiceInterface chatService,
    AppStatusService? appStatusService,
  })  : _chatService = chatService,
        _appStatusService = appStatusService,
        boxName = null {
    _bindAppStatusService();
  }

  final ChatServiceInterface _chatService;
  final AppStatusService? _appStatusService;
  final String? boxName;
  final Map<String, List<ChatPendingMessage>> _messagesByChat =
      <String, List<ChatPendingMessage>>{};
  final Set<String> _loadedChatIds = <String>{};
  final Set<String> _inFlightMessageIds = <String>{};
  Future<Box<String>>? _openTask;
  int _localCounter = 0;
  bool _isDisposed = false;
  bool _wasOffline = false;

  /// Binds to [AppStatusService] (when supplied) so we can auto-retry
  /// failed messages the moment connectivity is restored. Without this
  /// the user has to manually tap "Повторить" on each failed bubble
  /// after the network returns — which is what the user noticed
  /// during the offline test.
  void _bindAppStatusService() {
    final svc = _appStatusService;
    if (svc == null) return;
    _wasOffline = svc.isOffline;
    svc.addListener(_handleAppStatusChanged);
  }

  void _handleAppStatusChanged() {
    final svc = _appStatusService;
    if (svc == null || _isDisposed) return;
    final isOffline = svc.isOffline;
    final cameBackOnline = _wasOffline && !isOffline;
    _wasOffline = isOffline;
    if (cameBackOnline) {
      // Connectivity restored — retry every failed message across
      // every chat we've touched in this session. _send() handles
      // the in-flight de-dup, so racing this with a manual retry
      // is safe.
      for (final entry in _messagesByChat.entries) {
        for (final message in entry.value) {
          if (message.status == ChatPendingMessageStatus.failed) {
            unawaited(retry(message.chatId, message.localId));
          }
        }
      }
    }
  }

  Future<Box<String>?> _box() {
    final resolvedBoxName = boxName;
    if (resolvedBoxName == null) {
      return Future<Box<String>?>.value(null);
    }
    if (Hive.isBoxOpen(resolvedBoxName)) {
      return Future<Box<String>?>.value(Hive.box<String>(resolvedBoxName));
    }
    return (_openTask ??= Hive.openBox<String>(resolvedBoxName))
        .then<Box<String>?>((box) => box);
  }

  List<ChatPendingMessage> messagesFor(String chatId) {
    return List<ChatPendingMessage>.unmodifiable(
      _messagesByChat[chatId] ?? const <ChatPendingMessage>[],
    );
  }

  Future<void> restoreChat(String chatId) async {
    final normalizedChatId = chatId.trim();
    if (normalizedChatId.isEmpty || _loadedChatIds.contains(normalizedChatId)) {
      return;
    }
    _loadedChatIds.add(normalizedChatId);

    final box = await _box();
    final rawValue = box?.get(normalizedChatId);
    if (rawValue == null || rawValue.trim().isEmpty) {
      _messagesByChat.putIfAbsent(
        normalizedChatId,
        () => const <ChatPendingMessage>[],
      );
      return;
    }

    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is List<dynamic>) {
        final messages = _sortedMessages(
          decoded
              .whereType<Map>()
              .map((entry) => ChatPendingMessage.fromJson(
                    Map<String, dynamic>.from(entry),
                  ))
              .where((message) =>
                  message.chatId == normalizedChatId &&
                  message.localId.trim().isNotEmpty)
              .toList(growable: false),
        );
        _messagesByChat[normalizedChatId] = messages;
        _notify();
        for (final message in messages) {
          if (message.status == ChatPendingMessageStatus.pending) {
            unawaited(_send(message));
          }
        }
      }
    } catch (_) {
      _messagesByChat[normalizedChatId] = const <ChatPendingMessage>[];
    }
  }

  Future<ChatPendingMessage> enqueue({
    required String chatId,
    required String senderId,
    required String text,
    List<XFile> attachments = const <XFile>[],
    List<ChatAttachment> forwardedAttachments = const <ChatAttachment>[],
    ChatReplyReference? replyTo,
    int? expiresInSeconds,
  }) async {
    final normalizedChatId = chatId.trim();
    if (normalizedChatId.isEmpty) {
      throw StateError('Чат недоступен');
    }
    if (text.trim().isEmpty &&
        attachments.isEmpty &&
        forwardedAttachments.isEmpty) {
      throw StateError('Сообщение не должно быть пустым');
    }

    await restoreChat(normalizedChatId);

    final message = ChatPendingMessage(
      localId: _newClientMessageId(),
      chatId: normalizedChatId,
      senderId: senderId,
      text: text,
      timestamp: DateTime.now(),
      attachments: List<XFile>.from(attachments),
      forwardedAttachments: List<ChatAttachment>.from(forwardedAttachments),
      status: ChatPendingMessageStatus.pending,
      replyTo: replyTo,
      progress: attachments.isNotEmpty
          ? ChatSendProgress(
              stage: ChatSendProgressStage.preparing,
              completed: 0,
              total: attachments.length,
            )
          : const ChatSendProgress(
              stage: ChatSendProgressStage.sending,
              completed: 1,
              total: 1,
            ),
      expiresInSeconds: expiresInSeconds,
    );
    _upsert(message);
    await _persistChat(normalizedChatId);
    _notify();
    unawaited(_send(message));
    return message;
  }

  Future<void> retry(String chatId, String clientMessageId) async {
    final message = _findMessage(chatId, clientMessageId);
    if (message == null) {
      return;
    }
    final nextMessage = message.copyWith(
      status: ChatPendingMessageStatus.pending,
      progress: message.attachments.isNotEmpty
          ? ChatSendProgress(
              stage: ChatSendProgressStage.preparing,
              completed: 0,
              total: message.attachments.length,
            )
          : const ChatSendProgress(
              stage: ChatSendProgressStage.sending,
              completed: 1,
              total: 1,
            ),
      errorText: null,
    );
    _upsert(nextMessage);
    await _persistChat(chatId);
    _notify();
    await _send(nextMessage);
  }

  Future<void> remove(String chatId, String clientMessageId) async {
    final messages = List<ChatPendingMessage>.from(
      _messagesByChat[chatId] ?? const <ChatPendingMessage>[],
    )..removeWhere((message) => message.localId == clientMessageId);
    _messagesByChat[chatId] = _sortedMessages(messages);
    await _persistChat(chatId);
    _notify();
  }

  Future<void> confirmRemoteMessages(
    String chatId,
    List<ChatMessage> remoteMessages,
  ) async {
    final confirmedIds = remoteMessages
        .map((message) => message.clientMessageId?.trim())
        .whereType<String>()
        .where((clientMessageId) => clientMessageId.isNotEmpty)
        .toSet();
    if (confirmedIds.isEmpty) {
      return;
    }

    final currentMessages =
        _messagesByChat[chatId] ?? const <ChatPendingMessage>[];
    final nextMessages = currentMessages
        .where((message) => !confirmedIds.contains(message.localId))
        .toList(growable: false);
    if (nextMessages.length == currentMessages.length) {
      return;
    }
    _messagesByChat[chatId] = nextMessages;
    await _persistChat(chatId);
    _notify();
  }

  /// S4: явный потолок ожидания ACK — дольше держать «отправляется»
  /// нечестно: переводим в failed с ретраем по тапу. С вложениями
  /// аплоад легитимно дольше — потолок мягче.
  static const Duration _sendTimeout = Duration(seconds: 10);
  static const Duration _sendTimeoutWithAttachments = Duration(seconds: 45);

  Future<void> _send(ChatPendingMessage message) async {
    if (!_messageExists(message.chatId, message.localId) ||
        !_inFlightMessageIds.add(message.localId)) {
      return;
    }

    // S1: отправка до ACK сервера.
    final sendTrace = PerfTrace('chat.send-to-ack');
    try {
      await _chatService
          .sendMessageToChat(
            chatId: message.chatId,
            text: message.text,
            attachments: message.attachments,
            forwardedAttachments: message.forwardedAttachments,
            replyTo: message.replyTo,
            clientMessageId: message.localId,
            expiresInSeconds: message.expiresInSeconds,
            onProgress: (progress) {
              _updateProgress(message.chatId, message.localId, progress);
            },
          )
          .timeout(
            message.attachments.isEmpty
                ? _sendTimeout
                : _sendTimeoutWithAttachments,
          );
      sendTrace.finish();
      if (!_messageExists(message.chatId, message.localId)) {
        return;
      }
      _upsert(
        message.copyWith(
          status: ChatPendingMessageStatus.sent,
          errorText: null,
        ),
      );
      await _persistChat(message.chatId);
      _notify();
    } catch (error) {
      sendTrace.cancel();
      if (!_messageExists(message.chatId, message.localId)) {
        return;
      }
      _upsert(
        message.copyWith(
          status: ChatPendingMessageStatus.failed,
          errorText: error is TimeoutException
              ? 'Не дождались ответа сервера. Нажмите, чтобы повторить.'
              : _messageErrorText(error),
        ),
      );
      await _persistChat(message.chatId);
      _notify();
    } finally {
      _inFlightMessageIds.remove(message.localId);
    }
  }

  void _updateProgress(
    String chatId,
    String clientMessageId,
    ChatSendProgress progress,
  ) {
    final message = _findMessage(chatId, clientMessageId);
    if (message == null) {
      return;
    }
    _upsert(message.copyWith(progress: progress));
    unawaited(_persistChat(chatId));
    _notify();
  }

  ChatPendingMessage? _findMessage(String chatId, String clientMessageId) {
    for (final message
        in _messagesByChat[chatId] ?? const <ChatPendingMessage>[]) {
      if (message.localId == clientMessageId) {
        return message;
      }
    }
    return null;
  }

  bool _messageExists(String chatId, String clientMessageId) {
    return _findMessage(chatId, clientMessageId) != null;
  }

  void _upsert(ChatPendingMessage message) {
    final messages = List<ChatPendingMessage>.from(
      _messagesByChat[message.chatId] ?? const <ChatPendingMessage>[],
    );
    final index =
        messages.indexWhere((item) => item.localId == message.localId);
    if (index == -1) {
      messages.add(message);
    } else {
      messages[index] = message;
    }
    _messagesByChat[message.chatId] = _sortedMessages(messages);
  }

  Future<void> _persistChat(String chatId) async {
    final box = await _box();
    if (box == null) {
      return;
    }
    final messages = _messagesByChat[chatId] ?? const <ChatPendingMessage>[];
    if (messages.isEmpty) {
      await box.delete(chatId);
      return;
    }
    await box.put(
      chatId,
      jsonEncode(messages.map((message) => message.toJson()).toList()),
    );
  }

  String _newClientMessageId() {
    _localCounter += 1;
    return 'local-${DateTime.now().microsecondsSinceEpoch}-$_localCounter';
  }

  String _messageErrorText(Object error) {
    if (error is CustomApiException && error.message.trim().isNotEmpty) {
      return error.message.trim();
    }
    if (error is UnsupportedError && error.message?.trim().isNotEmpty == true) {
      return error.message!.trim();
    }
    return 'Не удалось отправить сообщение.';
  }

  List<ChatPendingMessage> _sortedMessages(
    List<ChatPendingMessage> messages,
  ) {
    final sortedMessages = messages.toList();
    sortedMessages.sort((left, right) {
      final timestampCompare = right.timestamp.compareTo(left.timestamp);
      if (timestampCompare != 0) {
        return timestampCompare;
      }
      return right.localId.compareTo(left.localId);
    });
    return sortedMessages;
  }

  void _notify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _appStatusService?.removeListener(_handleAppStatusChanged);
    super.dispose();
  }
}
