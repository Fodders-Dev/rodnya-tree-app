import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:image_picker/image_picker.dart';

import '../backend/interfaces/chat_service_interface.dart';
import '../models/chat_attachment.dart';
import '../models/chat_message.dart';
import '../models/chat_send_progress.dart';
import 'custom_api_auth_service.dart';

enum ChatPendingMessageStatus { pending, sent, failed }

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
    this.boxName = 'chat_send_queue_v1',
  }) : _chatService = chatService;

  ChatSendQueue.memory({
    required ChatServiceInterface chatService,
  })  : _chatService = chatService,
        boxName = null;

  final ChatServiceInterface _chatService;
  final String? boxName;
  final Map<String, List<ChatPendingMessage>> _messagesByChat =
      <String, List<ChatPendingMessage>>{};
  final Set<String> _loadedChatIds = <String>{};
  final Set<String> _inFlightMessageIds = <String>{};
  Future<Box<String>>? _openTask;
  int _localCounter = 0;
  bool _isDisposed = false;

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

  Future<void> _send(ChatPendingMessage message) async {
    if (!_messageExists(message.chatId, message.localId) ||
        !_inFlightMessageIds.add(message.localId)) {
      return;
    }

    try {
      await _chatService.sendMessageToChat(
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
      );
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
      if (!_messageExists(message.chatId, message.localId)) {
        return;
      }
      _upsert(
        message.copyWith(
          status: ChatPendingMessageStatus.failed,
          errorText: _messageErrorText(error),
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
    super.dispose();
  }
}
