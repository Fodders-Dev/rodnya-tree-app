import '../../models/chat_message.dart';
import '../../models/chat_details.dart';
import '../../models/chat_preview.dart';
import '../../models/chat_attachment.dart';
import '../../models/chat_send_progress.dart';
import '../../models/chat_message_search_result.dart';
import 'package:image_picker/image_picker.dart';

abstract class ChatServiceInterface {
  String? get currentUserId;
  String buildChatId(String otherUserId);
  Stream<List<ChatPreview>> getUserChatsStream(String userId);
  Stream<int> getTotalUnreadCountStream(String userId);
  Stream<List<ChatMessage>> getMessagesStream(String chatId);
  Future<void> refreshMessages(String chatId) {
    throw UnsupportedError('refreshMessages is not supported');
  }

  Future<void> sendMessageToChat({
    required String chatId,
    String text = '',
    List<XFile> attachments = const <XFile>[],
    List<ChatAttachment> forwardedAttachments = const <ChatAttachment>[],
    ChatReplyReference? replyTo,
    String? clientMessageId,
    int? expiresInSeconds,
    void Function(ChatSendProgress progress)? onProgress,
  }) {
    throw UnsupportedError('sendMessageToChat is not supported');
  }

  Future<void> sendMessage({
    required String otherUserId,
    String text = '',
    List<XFile> attachments = const <XFile>[],
  });
  Future<void> sendTextMessage({
    required String otherUserId,
    required String text,
  }) {
    return sendMessage(otherUserId: otherUserId, text: text);
  }

  Future<void> markChatAsRead(String chatId, String userId);
  Future<String?> getOrCreateChat(String otherUserId);
  Future<String?> createGroupChat({
    required List<String> participantIds,
    String? title,
    String? treeId,
  }) {
    throw UnsupportedError('createGroupChat is not supported');
  }

  Future<String?> createBranchChat({
    required String treeId,
    required List<String> branchRootPersonIds,
    String? title,
  }) {
    throw UnsupportedError('createBranchChat is not supported');
  }

  Future<ChatDetails> getChatDetails(String chatId) {
    throw UnsupportedError('getChatDetails is not supported');
  }

  Future<ChatDetails> renameGroupChat({
    required String chatId,
    required String title,
  }) {
    throw UnsupportedError('renameGroupChat is not supported');
  }

  Future<ChatDetails> addGroupParticipants({
    required String chatId,
    required List<String> participantIds,
  }) {
    throw UnsupportedError('addGroupParticipants is not supported');
  }

  Future<ChatDetails> removeGroupParticipant({
    required String chatId,
    required String participantId,
  }) {
    throw UnsupportedError('removeGroupParticipant is not supported');
  }

  /// G2: самовыход из группового чата. Возвращает void — вышедший
  /// теряет доступ и не должен парсить состав, который уже не его.
  /// Дефолт-бросок: реализуют только сервисы, поддерживающие группы.
  Future<void> leaveGroup(String chatId) {
    throw UnsupportedError('leaveGroup is not supported');
  }

  Future<void> editChatMessage({
    required String chatId,
    required String messageId,
    required String text,
  }) {
    throw UnsupportedError('editChatMessage is not supported');
  }

  Future<void> deleteChatMessage({
    required String chatId,
    required String messageId,
  }) {
    throw UnsupportedError('deleteChatMessage is not supported');
  }

  Future<void> toggleMessageReaction({
    required String chatId,
    required String messageId,
    required String emoji,
  }) {
    throw UnsupportedError('toggleMessageReaction is not supported');
  }

  Future<List<ChatMessageSearchResult>> searchMessages({
    required String query,
    String? chatId,
    int limit = 50,
  }) {
    throw UnsupportedError('searchMessages is not supported');
  }
}
