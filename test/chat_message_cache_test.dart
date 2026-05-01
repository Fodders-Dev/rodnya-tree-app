import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:rodnya/models/chat_message.dart';
import 'package:rodnya/services/chat_message_cache.dart';

void main() {
  late Directory hiveDirectory;
  var boxCounter = 0;

  setUpAll(() {
    hiveDirectory = Directory.systemTemp.createTempSync(
      'rodnya_chat_message_cache_test_',
    );
    Hive.init(hiveDirectory.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (hiveDirectory.existsSync()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  HiveChatMessageCache createCache() {
    boxCounter += 1;
    final boxName = 'chat_messages_test_$boxCounter';
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
    return HiveChatMessageCache(boxName: boxName);
  }

  test('HiveChatMessageCache writes, sorts and preserves extended fields',
      () async {
    final cache = createCache();
    final updatedAt = DateTime.utc(2026, 4, 30, 12, 5);
    final expiresAt = DateTime.utc(2026, 5);
    final replied = ChatMessage(
      id: 'm-new',
      chatId: 'chat-1',
      senderId: 'user-1',
      text: 'Ответ',
      timestamp: DateTime.utc(2026, 4, 30, 12),
      isRead: false,
      participants: const ['user-1', 'other-user'],
      senderName: 'Dev User',
      replyTo: const ChatReplyReference(
        messageId: 'm-old',
        senderId: 'other-user',
        senderName: 'Собеседник',
        text: 'Вопрос',
      ),
      clientMessageId: 'client-1',
      expiresAt: expiresAt,
      updatedAt: updatedAt,
    );

    await cache.write(
      'chat-1',
      [
        ChatMessage(
          id: 'm-old',
          chatId: 'chat-1',
          senderId: 'other-user',
          text: 'Вопрос',
          timestamp: DateTime.utc(2026, 4, 29, 9),
          isRead: true,
          participants: const ['user-1', 'other-user'],
        ),
        replied,
        ChatMessage(
          id: 'm-z',
          chatId: 'chat-1',
          senderId: 'other-user',
          text: 'То же время',
          timestamp: DateTime.utc(2026, 4, 30, 12),
          isRead: true,
          participants: const ['user-1', 'other-user'],
        ),
      ],
      keepCount: 2,
    );

    final messages = await cache.read('chat-1');
    expect(messages.map((message) => message.id).toList(), ['m-z', 'm-new']);
    expect(messages.last.replyTo?.messageId, 'm-old');
    expect(messages.last.clientMessageId, 'client-1');
    expect(messages.last.expiresAt, expiresAt);
    expect(messages.last.updatedAt, updatedAt);
  });

  test('HiveChatMessageCache merges, removes and evicts older messages',
      () async {
    final cache = createCache();
    await cache.write('chat-1', [
      _message('m-1', DateTime.utc(2026, 4, 30, 10), text: 'old text'),
      _message('m-2', DateTime.utc(2026, 4, 30, 11)),
    ]);

    await cache.mergePage('chat-1', [
      _message('m-1', DateTime.utc(2026, 4, 30, 10), text: 'updated text'),
      _message('m-3', DateTime.utc(2026, 4, 30, 12)),
    ]);

    var messages = await cache.read('chat-1');
    expect(messages.map((message) => message.id).toList(), [
      'm-3',
      'm-2',
      'm-1',
    ]);
    expect(messages.last.text, 'updated text');

    await cache.removeOne('chat-1', 'm-2');
    messages = await cache.read('chat-1');
    expect(messages.map((message) => message.id).toList(), ['m-3', 'm-1']);

    await cache.evictOlder('chat-1', keepCount: 1);
    messages = await cache.read('chat-1');
    expect(messages.map((message) => message.id).toList(), ['m-3']);
  });
}

ChatMessage _message(
  String id,
  DateTime timestamp, {
  String text = 'Сообщение',
}) {
  return ChatMessage(
    id: id,
    chatId: 'chat-1',
    senderId: 'user-1',
    text: text,
    timestamp: timestamp,
    isRead: false,
    participants: const ['user-1', 'other-user'],
  );
}
