import 'chat_message.dart';

class ChatMessagesPage {
  const ChatMessagesPage({
    required this.messages,
    required this.hasMore,
  });

  final List<ChatMessage> messages;
  final bool hasMore;
}
