// D2: РУКОПИСНЫЙ Hive-адаптер ChatMessage — намеренно вне build_runner.
//
// Сериализация сложнее, чем умеет hive_generator: вложения и реакции
// пишутся примитивами (toMap-списками, без собственных typeId), а read
// поддерживает legacy-кадры эпохи imageUrl/mediaUrls (поля 6/7) —
// восстанавливает из них вложения через ChatMessage.create. Раньше это
// жило ручными правками в chat_message.g.dart, и любой build_runner
// молча их сносил. typeId = 4 и индексы полей — дисковый формат,
// менять нельзя.

import 'package:hive/hive.dart';

import 'chat_attachment.dart';
import 'chat_message.dart';

class ChatMessageAdapter extends TypeAdapter<ChatMessage> {
  @override
  final int typeId = 4;

  @override
  ChatMessage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ChatMessage(
      id: fields[0] as String,
      chatId: fields[1] as String,
      senderId: fields[2] as String,
      text: fields[3] as String,
      timestamp: fields[4] as DateTime,
      isRead: fields[5] as bool,
      participants: (fields[8] as List).cast<String>(),
      senderName: fields[9] as String?,
      attachments: (fields[10] as List?)
              ?.whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .map(ChatAttachment.fromMap)
              .toList() ??
          ChatMessage.create(
            chatId: fields[1] as String,
            senderId: fields[2] as String,
            text: fields[3] as String,
            imageUrl: fields[6] as String?,
            mediaUrls: (fields[7] as List?)?.cast<String>(),
            participants: (fields[8] as List).cast<String>(),
            senderName: fields[9] as String?,
          ).attachments,
      reactions: ChatMessageReactionSummary.listFromDynamic(fields[11]),
      deliveredTo: (fields[12] as List?)?.cast<String>() ?? const <String>[],
      readBy: (fields[13] as List?)?.cast<String>() ?? const <String>[],
    );
  }

  @override
  void write(BinaryWriter writer, ChatMessage obj) {
    writer
      ..writeByte(14)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.chatId)
      ..writeByte(2)
      ..write(obj.senderId)
      ..writeByte(3)
      ..write(obj.text)
      ..writeByte(4)
      ..write(obj.timestamp)
      ..writeByte(5)
      ..write(obj.isRead)
      // Поля 6/7 — legacy imageUrl/mediaUrls: пишем, чтобы старые
      // версии приложения могли читать новые записи.
      ..writeByte(6)
      ..write(obj.imageUrl)
      ..writeByte(7)
      ..write(obj.mediaUrls)
      ..writeByte(8)
      ..write(obj.participants)
      ..writeByte(9)
      ..write(obj.senderName)
      ..writeByte(10)
      ..write(obj.attachments.map((attachment) => attachment.toMap()).toList())
      ..writeByte(11)
      ..write(obj.reactions.map((reaction) => reaction.toMap()).toList())
      ..writeByte(12)
      ..write(obj.deliveredTo)
      ..writeByte(13)
      ..write(obj.readBy);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
