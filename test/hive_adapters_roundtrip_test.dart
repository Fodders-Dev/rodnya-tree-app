// D2: страховочные Hive round-trip тесты для всех патченных адаптеров —
// фиксируют ТЕКУЩЕЕ поведение ДО выкорчёвывания ручных правок из
// .g.dart. Включают legacy-кейсы: запись старого формата (меньше полей)
// обязана читаться с правильными дефолтами — для этого пишем урезанным
// «старым» адаптером через отдельный HiveImpl-реестр в тот же каталог,
// а читаем прод-адаптером.

// ignore: implementation_imports
import 'package:hive/src/hive_impl.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:rodnya/models/chat_attachment.dart';
import 'package:rodnya/models/chat_message.dart';
import 'package:rodnya/models/chat_message_adapter.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/models/family_relation.dart';
import 'package:rodnya/models/family_tree.dart';
import 'package:rodnya/models/user_profile.dart';

void _registerProdAdapters(HiveInterface hive) {
  // Подмножество AppStartupService._registerHiveAdapters, достаточное
  // для пяти моделей (те же idempotency-гарды).
  if (!hive.isAdapterRegistered(UserProfileAdapter().typeId)) {
    hive.registerAdapter(UserProfileAdapter());
  }
  if (!hive.isAdapterRegistered(FamilyTreeAdapter().typeId)) {
    hive.registerAdapter(FamilyTreeAdapter());
  }
  if (!hive.isAdapterRegistered(TreeKindAdapter().typeId)) {
    hive.registerAdapter(TreeKindAdapter());
  }
  if (!hive.isAdapterRegistered(FamilyPersonAdapter().typeId)) {
    hive.registerAdapter(FamilyPersonAdapter());
  }
  if (!hive.isAdapterRegistered(FamilyRelationAdapter().typeId)) {
    hive.registerAdapter(FamilyRelationAdapter());
  }
  if (!hive.isAdapterRegistered(ChatMessageAdapter().typeId)) {
    hive.registerAdapter(ChatMessageAdapter());
  }
  if (!hive.isAdapterRegistered(GenderAdapter().typeId)) {
    hive.registerAdapter(GenderAdapter());
  }
  if (!hive.isAdapterRegistered(RelationTypeAdapter().typeId)) {
    hive.registerAdapter(RelationTypeAdapter());
  }
  if (!hive.isAdapterRegistered(FamilyPersonDetailsAdapter().typeId)) {
    hive.registerAdapter(FamilyPersonDetailsAdapter());
  }
  if (!hive.isAdapterRegistered(CareerAdapter().typeId)) {
    hive.registerAdapter(CareerAdapter());
  }
  if (!hive.isAdapterRegistered(EventAdapter().typeId)) {
    hive.registerAdapter(EventAdapter());
  }
}

/// Пишет запись «старым» (урезанным) адаптером в отдельном HiveImpl,
/// закрывает бокс и возвращает каталог — основной Hive читает её
/// прод-адаптером. typeId совпадает, поэтому формат кадра одинаков.
Future<Directory> _writeWithLegacyAdapter<T>({
  required TypeAdapter<T> legacyAdapter,
  required String boxName,
  required String key,
  required T value,
  void Function(HiveInterface hive)? registerExtras,
}) async {
  final dir = await Directory.systemTemp.createTemp('rodnya_legacy_hive');
  final legacyHive = HiveImpl();
  legacyHive.init(dir.path);
  legacyHive.registerAdapter(legacyAdapter);
  registerExtras?.call(legacyHive);
  final box = await legacyHive.openBox<T>(boxName);
  await box.put(key, value);
  await legacyHive.close();
  return dir;
}

// ── «Старые» адаптеры: те же typeId, меньше полей ──

/// FamilyTree до полей 10 (isCertified) и 12 (kind).
class _LegacyFamilyTreeAdapter extends TypeAdapter<FamilyTree> {
  @override
  final int typeId = 2;

  @override
  FamilyTree read(BinaryReader reader) => throw UnimplementedError();

  @override
  void write(BinaryWriter writer, FamilyTree obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.creatorId)
      ..writeByte(4)
      ..write(obj.memberIds)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.updatedAt)
      ..writeByte(7)
      ..write(obj.isPrivate)
      ..writeByte(8)
      ..write(obj.members)
      ..writeByte(9)
      ..write(obj.publicSlug);
  }
}

/// ChatMessage эпохи imageUrl/mediaUrls (поля 6/7), до attachments (10),
/// reactions (11), deliveredTo (12) и readBy (13).
class _LegacyChatMessageAdapter extends TypeAdapter<ChatMessage> {
  @override
  final int typeId = 4;

  @override
  ChatMessage read(BinaryReader reader) => throw UnimplementedError();

  @override
  void write(BinaryWriter writer, ChatMessage obj) {
    writer
      ..writeByte(10)
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
      ..writeByte(6)
      ..write(obj.imageUrl)
      ..writeByte(7)
      ..write(obj.mediaUrls)
      ..writeByte(8)
      ..write(obj.participants)
      ..writeByte(9)
      ..write(obj.senderName);
  }
}

/// UserProfile «ядро» — до строковых анкетных полей (21+), фото (7/39),
/// девичьей фамилии (38) и visibility-карт (27-30, 35-37).
class _LegacyUserProfileAdapter extends TypeAdapter<UserProfile> {
  @override
  final int typeId = 0;

  @override
  UserProfile read(BinaryReader reader) => throw UnimplementedError();

  @override
  void write(BinaryWriter writer, UserProfile obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.email)
      ..writeByte(2)
      ..write(obj.displayName)
      ..writeByte(3)
      ..write(obj.firstName)
      ..writeByte(4)
      ..write(obj.lastName)
      ..writeByte(5)
      ..write(obj.middleName)
      ..writeByte(6)
      ..write(obj.username)
      ..writeByte(8)
      ..write(obj.phoneNumber)
      ..writeByte(14)
      ..write(obj.createdAt)
      ..writeByte(11)
      ..write(obj.birthDate);
  }
}

/// FamilyPerson до visibility (27) и точности дат (28/29).
class _LegacyFamilyPersonAdapter extends TypeAdapter<FamilyPerson> {
  @override
  final int typeId = 1;

  @override
  FamilyPerson read(BinaryReader reader) => throw UnimplementedError();

  @override
  void write(BinaryWriter writer, FamilyPerson obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.treeId)
      ..writeByte(3)
      ..write(obj.name)
      ..writeByte(6)
      ..write(obj.gender)
      ..writeByte(7)
      ..write(obj.birthDate)
      ..writeByte(13)
      ..write(obj.isAlive)
      ..writeByte(15)
      ..write(obj.createdAt)
      ..writeByte(16)
      ..write(obj.updatedAt);
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('rodnya_hive_d2');
    Hive.init(tempDir.path);
    _registerProdAdapters(Hive);
  });

  tearDown(() async {
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {
      // Windows иногда держит файл — каталог временный, не критично.
    }
  });

  group('UserProfile', () {
    UserProfile buildProfile() => UserProfile(
          id: 'user-1',
          email: 'a@rodnya.app',
          displayName: 'Артём',
          firstName: 'Артём',
          lastName: 'Кузнецов',
          middleName: 'Андреевич',
          username: 'artem',
          photoURL: 'https://cdn.example.com/a.jpg',
          coverPhotoURL: 'https://cdn.example.com/cover.jpg',
          phoneNumber: '+79990001122',
          gender: Gender.male,
          birthDate: DateTime(1992, 5, 4),
          createdAt: DateTime(2024, 1, 1),
          bio: 'О себе',
          familyStatus: 'Женат',
          aboutFamily: 'Большая семья',
          education: 'СамГТУ',
          work: 'Инженер',
          hometown: 'Самара',
          languages: 'русский',
          values: 'семья',
          religion: '',
          interests: 'генеалогия',
          maidenName: '',
          profileContributionPolicy: 'suggestions',
          profileVisibilityScopes: const {'bio': 'tree'},
          hiddenProfileSections: const ['work'],
          profileVisibilityTreeIds: const {
            'bio': ['tree-1'],
          },
          profileVisibilityUserIds: const {
            'bio': ['user-2'],
          },
          profileVisibilityBranchRootIds: const {
            'bio': ['person-9'],
          },
        );

    test('round-trip: фото, анкетные строки и visibility-карты живы',
        () async {
      final box = await Hive.openBox<UserProfile>('profiles_rt');
      await box.put('user-1', buildProfile());
      await box.close();

      final reopened = await Hive.openBox<UserProfile>('profiles_rt');
      final restored = reopened.get('user-1');

      expect(restored, isNotNull);
      expect(restored!.photoURL, 'https://cdn.example.com/a.jpg');
      expect(restored.coverPhotoURL, 'https://cdn.example.com/cover.jpg');
      expect(restored.bio, 'О себе');
      expect(restored.aboutFamily, 'Большая семья');
      expect(restored.maidenName, '');
      expect(restored.profileContributionPolicy, 'suggestions');
      expect(restored.profileVisibilityTreeIds, {
        'bio': ['tree-1'],
      });
      expect(restored.profileVisibilityUserIds, {
        'bio': ['user-2'],
      });
      expect(restored.profileVisibilityBranchRootIds, {
        'bio': ['person-9'],
      });
      expect(restored.hiddenProfileSections, ['work']);
    });

    test('legacy-запись (ядро полей) читается с дефолтами', () async {
      final dir = await _writeWithLegacyAdapter<UserProfile>(
        legacyAdapter: _LegacyUserProfileAdapter(),
        boxName: 'profiles_legacy',
        key: 'user-1',
        value: buildProfile(),
        registerExtras: (hive) => hive.registerAdapter(GenderAdapter()),
      );
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      });

      final readerHive = HiveImpl();
      readerHive.init(dir.path);
      _registerProdAdapters(readerHive);
      final box = await readerHive.openBox<UserProfile>('profiles_legacy');
      final restored = box.get('user-1');
      await readerHive.close();

      expect(restored, isNotNull);
      expect(restored!.id, 'user-1');
      expect(restored.displayName, 'Артём');
      // Полей не было в записи → пустые строки, не null и не краш.
      expect(restored.bio, '');
      expect(restored.maidenName, '');
      expect(restored.profileContributionPolicy, 'suggestions');
      expect(restored.photoURL, isNull);
      expect(restored.coverPhotoURL, isNull);
      expect(restored.profileVisibilityTreeIds, isNull);
    });
  });

  group('FamilyTree', () {
    FamilyTree buildTree() => FamilyTree(
          id: 'tree-1',
          name: 'Семья Кузнецовых',
          description: 'Наше дерево',
          creatorId: 'user-1',
          memberIds: const ['user-1'],
          createdAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 2, 2),
          isPrivate: true,
          members: const ['user-1'],
          isCertified: true,
          kind: TreeKind.friends,
        );

    test('round-trip: isCertified и kind живы', () async {
      final box = await Hive.openBox<FamilyTree>('trees_rt');
      await box.put('tree-1', buildTree());
      await box.close();

      final reopened = await Hive.openBox<FamilyTree>('trees_rt');
      final restored = reopened.get('tree-1');

      expect(restored, isNotNull);
      expect(restored!.isCertified, isTrue);
      expect(restored.kind, TreeKind.friends);
    });

    test('legacy-запись (10 полей) читается: isCertified=false, kind=family',
        () async {
      final dir = await _writeWithLegacyAdapter<FamilyTree>(
        legacyAdapter: _LegacyFamilyTreeAdapter(),
        boxName: 'trees_legacy',
        key: 'tree-1',
        value: buildTree(),
      );
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      });

      final readerHive = HiveImpl();
      readerHive.init(dir.path);
      _registerProdAdapters(readerHive);
      final box = await readerHive.openBox<FamilyTree>('trees_legacy');
      final restored = box.get('tree-1');
      await readerHive.close();

      expect(restored, isNotNull);
      expect(restored!.name, 'Семья Кузнецовых');
      expect(restored.isCertified, isFalse);
      expect(restored.kind, TreeKind.family);
    });
  });

  group('ChatMessage', () {
    ChatMessage buildMessage() => ChatMessage(
          id: 'msg-1',
          chatId: 'chat-1',
          senderId: 'user-1',
          text: 'Привет, родня!',
          timestamp: DateTime(2026, 6, 1, 12),
          isRead: false,
          participants: const ['user-1', 'user-2'],
          senderName: 'Артём',
          attachments: const [
            ChatAttachment(
              type: ChatAttachmentType.image,
              url: 'https://cdn.example.com/photo.jpg',
              thumbnailUrl: 'https://cdn.example.com/thumb.jpg',
            ),
          ],
          reactions: const [
            ChatMessageReactionSummary(
              emoji: '❤',
              userIds: ['user-2'],
              count: 1,
            ),
          ],
          deliveredTo: const ['user-2'],
          readBy: const ['user-2'],
        );

    test('round-trip: вложения, реакции и статусы доставки живы', () async {
      final box = await Hive.openBox<ChatMessage>('messages_rt');
      await box.put('msg-1', buildMessage());
      await box.close();

      final reopened = await Hive.openBox<ChatMessage>('messages_rt');
      final restored = reopened.get('msg-1');

      expect(restored, isNotNull);
      expect(restored!.attachments, hasLength(1));
      expect(restored.attachments.first.type, ChatAttachmentType.image);
      expect(
        restored.attachments.first.url,
        'https://cdn.example.com/photo.jpg',
      );
      expect(restored.reactions, hasLength(1));
      expect(restored.reactions.first.emoji, '❤');
      expect(restored.reactions.first.userIds, ['user-2']);
      expect(restored.deliveredTo, ['user-2']);
      expect(restored.readBy, ['user-2']);
    });

    test('legacy-запись (imageUrl/mediaUrls, без 12/13) читается с фолбэком',
        () async {
      final dir = await _writeWithLegacyAdapter<ChatMessage>(
        legacyAdapter: _LegacyChatMessageAdapter(),
        boxName: 'messages_legacy',
        key: 'msg-1',
        value: buildMessage(),
      );
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      });

      final readerHive = HiveImpl();
      readerHive.init(dir.path);
      _registerProdAdapters(readerHive);
      final box = await readerHive.openBox<ChatMessage>('messages_legacy');
      final restored = box.get('msg-1');
      await readerHive.close();

      expect(restored, isNotNull);
      expect(restored!.text, 'Привет, родня!');
      // Поле 10 отсутствует → вложение восстановлено из legacy imageUrl.
      expect(restored.attachments, hasLength(1));
      expect(
        restored.attachments.first.url,
        'https://cdn.example.com/photo.jpg',
      );
      // Полей 12/13 не было → пустые списки, не null и не краш.
      expect(restored.deliveredTo, isEmpty);
      expect(restored.readBy, isEmpty);
    });
  });

  group('FamilyRelation', () {
    test('round-trip: даты союза и тип связи живы', () async {
      final relation = FamilyRelation(
        id: 'rel-1',
        treeId: 'tree-1',
        person1Id: 'p1',
        person2Id: 'p2',
        relation1to2: RelationType.ex_spouse,
        relation2to1: RelationType.ex_spouse,
        isConfirmed: true,
        createdAt: DateTime(2024, 1, 1),
        marriageDate: DateTime(1980, 6, 21),
        divorceDate: DateTime(1995, 3, 2),
      );

      final box = await Hive.openBox<FamilyRelation>('relations_rt');
      await box.put('rel-1', relation);
      await box.close();

      final reopened = await Hive.openBox<FamilyRelation>('relations_rt');
      final restored = reopened.get('rel-1');

      expect(restored, isNotNull);
      expect(restored!.relation1to2, RelationType.ex_spouse);
      expect(restored.marriageDate, DateTime(1980, 6, 21));
      expect(restored.divorceDate, DateTime(1995, 3, 2));
    });
  });

  group('FamilyPerson (legacy)', () {
    test('legacy-запись (без 27/28/29) читается: private/exact', () async {
      final person = FamilyPerson(
        id: 'p-legacy',
        treeId: 'tree-1',
        name: 'Кузнецов Андрей',
        gender: Gender.male,
        birthDate: DateTime(1960, 4, 3),
        isAlive: true,
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      );

      final dir = await _writeWithLegacyAdapter<FamilyPerson>(
        legacyAdapter: _LegacyFamilyPersonAdapter(),
        boxName: 'persons_legacy_d2',
        key: 'p-legacy',
        value: person,
        registerExtras: (hive) => hive.registerAdapter(GenderAdapter()),
      );
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      });

      final readerHive = HiveImpl();
      readerHive.init(dir.path);
      _registerProdAdapters(readerHive);
      final box = await readerHive.openBox<FamilyPerson>('persons_legacy_d2');
      final restored = box.get('p-legacy');
      await readerHive.close();

      expect(restored, isNotNull);
      expect(restored!.visibility, 'private');
      expect(restored.birthDatePrecision, 'exact');
      expect(restored.deathDatePrecision, 'exact');
      expect(restored.birthDateIsYearOnly, isFalse);
    });
  });
}
