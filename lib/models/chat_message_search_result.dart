class ChatMessageSearchResult {
  const ChatMessageSearchResult({
    required this.messageId,
    required this.chatId,
    required this.senderId,
    required this.senderName,
    required this.snippet,
    required this.matchedAt,
    this.text = '',
  });

  final String messageId;
  final String chatId;
  final String senderId;
  final String senderName;
  final String text;
  final String snippet;
  final DateTime matchedAt;

  factory ChatMessageSearchResult.fromMap(Map<String, dynamic> map) {
    return ChatMessageSearchResult(
      messageId: map['messageId']?.toString() ?? map['id']?.toString() ?? '',
      chatId: map['chatId']?.toString() ?? '',
      senderId: map['senderId']?.toString() ?? '',
      senderName: map['senderName']?.toString() ?? 'Участник',
      text: map['text']?.toString() ?? '',
      snippet: map['snippet']?.toString() ?? '',
      matchedAt: DateTime.tryParse(map['matchedAt']?.toString() ?? '') ??
          DateTime.tryParse(map['timestamp']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
