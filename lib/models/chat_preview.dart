import '../utils/date_parser.dart';
import '../utils/url_utils.dart';

class ChatPreview {
  final String id;
  final String chatId;
  final String userId;
  final String type;
  final String? title;
  final String? photoUrl;
  final List<String> participantIds;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserPhotoUrl;
  final String lastMessage;
  final DateTime lastMessageTime;
  final int unreadCount;
  final String lastMessageSenderId;
  final bool isArchived;
  final String notificationLevel;

  ChatPreview({
    required this.id,
    required this.chatId,
    required this.userId,
    this.type = 'direct',
    this.title,
    this.photoUrl,
    this.participantIds = const <String>[],
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserPhotoUrl,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.unreadCount,
    required this.lastMessageSenderId,
    this.isArchived = false,
    this.notificationLevel = 'all',
  });

  bool get isGroup => type == 'group' || type == 'branch';
  bool get isBranch => type == 'branch';

  String get displayName {
    if (!isGroup) {
      return otherUserName;
    }

    final normalizedTitle = (title ?? '').trim();
    if (normalizedTitle.isNotEmpty) {
      return normalizedTitle;
    }

    return isBranch ? 'Чат ветки' : 'Групповой чат';
  }

  String? get displayPhotoUrl => isGroup ? photoUrl : otherUserPhotoUrl;

  String? get normalizedOtherUserPhotoUrl =>
      UrlUtils.normalizeImageUrl(otherUserPhotoUrl);

  factory ChatPreview.fromMap(Map<String, dynamic> map) {
    return ChatPreview(
      id: map['id'] ?? '',
      chatId: map['chatId'] ?? '',
      userId: map['userId'] ?? '',
      type: map['type']?.toString() ?? 'direct',
      title: map['title']?.toString(),
      photoUrl: map['photoUrl']?.toString(),
      participantIds: List<String>.from(map['participantIds'] ?? const []),
      otherUserId: map['otherUserId'] ?? '',
      otherUserName: map['otherUserName'] ?? 'Пользователь',
      otherUserPhotoUrl: map['otherUserPhotoUrl'],
      lastMessage: map['lastMessage'] ?? '',
      lastMessageTime: parseDateTimeRequired(map['lastMessageTime']),
      unreadCount: map['unreadCount'] ?? 0,
      lastMessageSenderId: map['lastMessageSenderId'] ?? '',
      isArchived: map['isArchived'] == true,
      notificationLevel:
          map['notificationLevel']?.toString().trim().isNotEmpty == true
              ? map['notificationLevel'].toString().trim()
              : 'all',
    );
  }

  /// Serialize for Hive cache. Round-trips through [ChatPreview.fromMap].
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'chatId': chatId,
      'userId': userId,
      'type': type,
      'title': title,
      'photoUrl': photoUrl,
      'participantIds': participantIds,
      'otherUserId': otherUserId,
      'otherUserName': otherUserName,
      'otherUserPhotoUrl': otherUserPhotoUrl,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime.toIso8601String(),
      'unreadCount': unreadCount,
      'lastMessageSenderId': lastMessageSenderId,
      'isArchived': isArchived,
      'notificationLevel': notificationLevel,
    };
  }
}
