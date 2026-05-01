import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/services/chat_pin_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('HybridChatPinStore merges newer remote pin into local cache', () async {
    final localStore = const SharedPreferencesChatPinStore();
    final remoteClient = _FakeRemoteChatPinClient();
    final store = HybridChatPinStore(
      localStore: localStore,
      remoteClient: remoteClient,
    );
    final key = SharedPreferencesChatPinStore.chatKey('chat-1');

    await localStore.savePinnedMessage(
      key,
      ChatPinnedMessageSnapshot(
        messageId: 'm-1',
        senderId: 'user-2',
        senderName: 'Анна',
        text: 'Локальный закреп',
        attachmentCount: 0,
        pinnedAt: DateTime.utc(2026, 4, 30, 10),
      ),
    );
    remoteClient.pinnedMessage = ChatPinnedMessageSnapshot(
      messageId: 'm-2',
      senderId: 'user-3',
      senderName: 'Петр',
      text: 'Закреп с другого устройства',
      attachmentCount: 1,
      pinnedAt: DateTime.utc(2026, 4, 30, 12),
    );

    final snapshot = await store.getPinnedMessage(key);

    expect(snapshot?.messageId, 'm-2');
    expect(snapshot?.text, 'Закреп с другого устройства');
    expect((await localStore.getPinnedMessage(key))?.messageId, 'm-2');
  });

  test('HybridChatPinStore writes chat-key pins to local and remote', () async {
    final localStore = const SharedPreferencesChatPinStore();
    final remoteClient = _FakeRemoteChatPinClient();
    final store = HybridChatPinStore(
      localStore: localStore,
      remoteClient: remoteClient,
    );
    final key = SharedPreferencesChatPinStore.chatKey('chat-1');
    final snapshot = ChatPinnedMessageSnapshot(
      messageId: 'm-3',
      senderId: 'user-2',
      senderName: 'Анна',
      text: 'Важная договоренность',
      attachmentCount: 0,
      pinnedAt: DateTime.utc(2026, 4, 30, 13),
    );

    await store.savePinnedMessage(key, snapshot);

    expect(remoteClient.pinnedChatId, 'chat-1');
    expect(remoteClient.pinnedMessageId, 'm-3');
    expect((await localStore.getPinnedMessage(key))?.messageId, 'm-3');

    await store.clearPinnedMessage(key);

    expect(remoteClient.clearedChatId, 'chat-1');
    expect(await localStore.getPinnedMessage(key), isNull);
  });
}

class _FakeRemoteChatPinClient implements RemoteChatPinClient {
  ChatPinnedMessageSnapshot? pinnedMessage;
  String? pinnedChatId;
  String? pinnedMessageId;
  String? clearedChatId;

  @override
  Future<ChatPinnedMessageSnapshot?> getChatPinnedMessage(String chatId) async {
    return pinnedMessage;
  }

  @override
  Future<ChatPinnedMessageSnapshot?> pinChatMessage({
    required String chatId,
    required String messageId,
  }) async {
    pinnedChatId = chatId;
    pinnedMessageId = messageId;
    pinnedMessage = ChatPinnedMessageSnapshot(
      messageId: messageId,
      senderId: 'user-2',
      senderName: 'Анна',
      text: 'Серверный закреп',
      attachmentCount: 0,
      pinnedAt: DateTime.utc(2026, 4, 30, 14),
    );
    return pinnedMessage;
  }

  @override
  Future<void> clearChatPinnedMessage(String chatId) async {
    clearedChatId = chatId;
    pinnedMessage = null;
  }
}
