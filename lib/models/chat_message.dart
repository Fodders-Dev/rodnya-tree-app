import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../utils/date_parser.dart';

import 'chat_attachment.dart';
import '../utils/url_utils.dart';

part 'chat_message.g.dart';

class ChatReplyReference {
  const ChatReplyReference({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.text,
  });

  final String messageId;
  final String senderId;
  final String senderName;
  final String text;

  factory ChatReplyReference.fromMap(Map<String, dynamic> map) {
    return ChatReplyReference(
      messageId: map['messageId']?.toString() ?? map['id']?.toString() ?? '',
      senderId: map['senderId']?.toString() ?? '',
      senderName: map['senderName']?.toString() ?? 'Участник',
      text: map['text']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'messageId': messageId,
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
    };
  }
}

@HiveType(typeId: 4)
class ChatMessage extends HiveObject {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String chatId;
  @HiveField(2)
  final String senderId;
  @HiveField(3)
  final String text;
  @HiveField(4)
  final DateTime timestamp;
  @HiveField(5)
  final bool isRead;
  @HiveField(8)
  final List<String> participants;
  @HiveField(9)
  final String? senderName;
  @HiveField(10)
  final List<ChatAttachment> attachments;
  final ChatReplyReference? replyTo;
  final String? clientMessageId;
  final DateTime? expiresAt;
  final DateTime? updatedAt;

  ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.text,
    required this.timestamp,
    required this.isRead,
    required this.participants,
    this.senderName,
    this.attachments = const <ChatAttachment>[],
    this.replyTo,
    this.clientMessageId,
    this.expiresAt,
    this.updatedAt,
  });

  String? get imageUrl {
    for (final attachment in attachments) {
      if (attachment.type == ChatAttachmentType.image &&
          attachment.url.trim().isNotEmpty) {
        return UrlUtils.normalizeImageUrl(attachment.url);
      }
    }
    if (attachments.isNotEmpty) {
      return UrlUtils.normalizeImageUrl(attachments.first.url);
    }
    return null;
  }

  List<String>? get mediaUrls {
    if (attachments.isEmpty) {
      return null;
    }
    return attachments
        .map((attachment) => attachment.url.trim())
        .where((url) => url.isNotEmpty)
        .map((url) => UrlUtils.normalizeImageUrl(url)!)
        .toList();
  }

  DateTime getDateTime() {
    return timestamp;
  }

  ChatMessage copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? text,
    DateTime? timestamp,
    bool? isRead,
    List<String>? participants,
    String? senderName,
    List<ChatAttachment>? attachments,
    ChatReplyReference? replyTo,
    String? clientMessageId,
    DateTime? expiresAt,
    DateTime? updatedAt,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      participants: participants ?? this.participants,
      senderName: senderName ?? this.senderName,
      attachments: attachments ?? this.attachments,
      replyTo: replyTo ?? this.replyTo,
      clientMessageId: clientMessageId ?? this.clientMessageId,
      expiresAt: expiresAt ?? this.expiresAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    final parsedTimestamp = parseDateTimeRequired(map['timestamp']);

    return ChatMessage(
      id: map['id'] ?? '',
      chatId: map['chatId'] ?? '',
      senderId: map['senderId'] ?? '',
      text: map['text'] ?? '',
      timestamp: parsedTimestamp,
      isRead: map['isRead'] ?? false,
      participants: List<String>.from(map['participants'] ?? []),
      senderName: map['senderName'],
      attachments: _attachmentsFromMap(map),
      replyTo: _replyReferenceFromMap(map),
      clientMessageId: map['clientMessageId']?.toString(),
      expiresAt: parseDateTime(map['expiresAt']),
      updatedAt: parseDateTime(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'chatId': chatId,
      'senderId': senderId,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'isRead': isRead,
      'attachments':
          attachments.map((attachment) => attachment.toMap()).toList(),
      'imageUrl': imageUrl,
      'mediaUrls': mediaUrls,
      'participants': participants,
      'senderName': senderName,
      'clientMessageId': clientMessageId,
      'expiresAt': expiresAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      if (replyTo != null) 'replyTo': replyTo!.toMap(),
    };
  }

  factory ChatMessage.fromFirestore(dynamic doc) {
    final data =
        (doc.data != null ? (doc.data() as Map<String, dynamic>?) : null) ?? {};
    return ChatMessage(
      id: doc.id,
      chatId: data['chatId'] ?? '',
      senderId: data['senderId'] ?? '',
      text: data['text'] ?? '',
      timestamp: parseDateTime(data['timestamp']) ?? DateTime.now(),
      isRead: data['isRead'] ?? false,
      participants: (data['participants'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      senderName: data['senderName'] as String?,
      attachments: _attachmentsFromMap(data),
      replyTo: _replyReferenceFromMap(data),
      clientMessageId: data['clientMessageId']?.toString(),
      expiresAt: parseDateTime(data['expiresAt']),
      updatedAt: parseDateTime(data['updatedAt']),
    );
  }

  static ChatMessage create({
    required String chatId,
    required String senderId,
    required String text,
    List<ChatAttachment>? attachments,
    String? imageUrl,
    List<String>? mediaUrls,
    required List<String> participants,
    String? senderName,
    ChatReplyReference? replyTo,
    String? clientMessageId,
    DateTime? expiresAt,
  }) {
    return ChatMessage(
      id: const Uuid().v4(),
      chatId: chatId,
      senderId: senderId,
      text: text,
      timestamp: DateTime.now(),
      isRead: false,
      participants: participants,
      senderName: senderName,
      attachments: attachments ?? _legacyAttachments(imageUrl, mediaUrls),
      replyTo: replyTo,
      clientMessageId: clientMessageId,
      expiresAt: expiresAt,
    );
  }

  static ChatReplyReference? _replyReferenceFromMap(Map<String, dynamic> map) {
    final rawReply = map['replyTo'];
    if (rawReply is Map<String, dynamic>) {
      final reply = ChatReplyReference.fromMap(rawReply);
      return reply.messageId.isEmpty ? null : reply;
    }
    if (rawReply is Map) {
      final reply =
          ChatReplyReference.fromMap(Map<String, dynamic>.from(rawReply));
      return reply.messageId.isEmpty ? null : reply;
    }
    return null;
  }

  static List<ChatAttachment> _attachmentsFromMap(Map<String, dynamic> map) {
    final explicitAttachments =
        ChatAttachment.listFromDynamic(map['attachments']);
    if (explicitAttachments.isNotEmpty) {
      return explicitAttachments;
    }

    return _legacyAttachments(
      map['imageUrl']?.toString(),
      map['mediaUrls'] is List<dynamic>
          ? List<String>.from(map['mediaUrls'])
          : null,
    );
  }

  static List<ChatAttachment> _legacyAttachments(
    String? imageUrl,
    List<String>? mediaUrls,
  ) {
    final normalizedUrls = <String>{
      ...?mediaUrls
          ?.map((value) => value.trim())
          .where((value) => value.isNotEmpty),
      if (imageUrl != null && imageUrl.trim().isNotEmpty) imageUrl.trim(),
    }.toList();

    return normalizedUrls
        .map(
          (url) => ChatAttachment(
            type: ChatAttachmentType.image,
            url: UrlUtils.normalizeImageUrl(url) ?? url,
          ),
        )
        .toList();
  }
}
