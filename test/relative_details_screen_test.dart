import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:rodnya/backend/interfaces/auth_service_interface.dart';
import 'package:rodnya/backend/interfaces/chat_service_interface.dart';
import 'package:rodnya/backend/interfaces/family_tree_service_interface.dart';
import 'package:rodnya/backend/interfaces/invitation_link_service_interface.dart';
import 'package:rodnya/backend/interfaces/profile_service_interface.dart';
import 'package:rodnya/backend/interfaces/storage_service_interface.dart';
import 'package:rodnya/backend/interfaces/tree_graph_capable_family_tree_service.dart';
import 'package:rodnya/models/chat_attachment.dart';
import 'package:rodnya/models/chat_details.dart';
import 'package:rodnya/models/chat_message.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/models/family_relation.dart';
import 'package:rodnya/models/family_tree.dart';
import 'package:rodnya/models/chat_send_progress.dart';
import 'package:rodnya/models/tree_graph_snapshot.dart';
import 'package:rodnya/models/tree_change_record.dart';
import 'package:rodnya/models/user_profile.dart';
import 'package:rodnya/providers/tree_provider.dart';
import 'package:rodnya/screens/relative_details_screen.dart';
import 'package:rodnya/services/local_storage_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuthService implements AuthServiceInterface {
  @override
  String? get currentUserId => 'user-1';

  @override
  String? get currentUserEmail => 'user@example.com';

  @override
  String? get currentUserDisplayName => 'Артем Кузнецов';

  @override
  String? get currentUserPhotoUrl => null;

  @override
  List<String> get currentProviderIds => const ['password'];

  @override
  Stream<String?> get authStateChanges => const Stream.empty();

  @override
  String describeError(Object error) => error.toString();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocalStorageService implements LocalStorageService {
  final Map<String, FamilyTree> _treesById = {
    'tree-1': FamilyTree(
      id: 'tree-1',
      name: 'Семья Кузнецовых',
      description: '',
      creatorId: 'user-1',
      memberIds: const ['user-1'],
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
      isPrivate: true,
      members: const ['user-1'],
    ),
  };

  @override
  Future<List<FamilyTree>> getAllTrees() async => _treesById.values.toList();

  @override
  Future<FamilyTree?> getTree(String treeId) async => _treesById[treeId];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfileService implements ProfileServiceInterface {
  @override
  Future<UserProfile?> getUserProfile(String userId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeChatService implements ChatServiceInterface {
  @override
  String? get currentUserId => 'user-1';

  @override
  String buildChatId(String otherUserId) => 'chat-$otherUserId';

  @override
  Future<void> refreshMessages(String chatId) async {}

  @override
  Future<void> sendMessageToChat({
    required String chatId,
    String text = '',
    List<XFile> attachments = const <XFile>[],
    List<ChatAttachment> forwardedAttachments = const <ChatAttachment>[],
    ChatReplyReference? replyTo,
    String? clientMessageId,
    int? expiresInSeconds,
    void Function(ChatSendProgress progress)? onProgress,
  }) async {}

  @override
  Future<String?> createGroupChat({
    required List<String> participantIds,
    String? title,
    String? treeId,
  }) async =>
      'chat-group-1';

  @override
  Future<String?> createBranchChat({
    required String treeId,
    required List<String> branchRootPersonIds,
    String? title,
  }) async =>
      'chat-branch-1';

  @override
  Future<ChatDetails> getChatDetails(String chatId) async => const ChatDetails(
        chatId: 'chat-group-1',
        type: 'group',
        title: 'Группа',
        participantIds: ['user-1', 'user-father'],
        participants: [
          ChatParticipantSummary(userId: 'user-1', displayName: 'Артем'),
          ChatParticipantSummary(
            userId: 'user-father',
            displayName: 'Андрей Кузнецов',
          ),
        ],
        branchRoots: [],
      );

  @override
  Future<ChatDetails> renameGroupChat({
    required String chatId,
    required String title,
  }) async =>
      getChatDetails(chatId);

  @override
  Future<ChatDetails> addGroupParticipants({
    required String chatId,
    required List<String> participantIds,
  }) async =>
      getChatDetails(chatId);

  @override
  Future<ChatDetails> removeGroupParticipant({
    required String chatId,
    required String participantId,
  }) async =>
      getChatDetails(chatId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInvitationLinkService implements InvitationLinkServiceInterface {
  @override
  Uri buildInvitationLink({required String treeId, required String personId}) {
    return Uri.parse('https://example.com/invite/$treeId/$personId');
  }
}

class _FakeStorageService implements StorageServiceInterface {
  @override
  Future<String?> uploadImage(XFile imageFile, String folder) async =>
      'https://cdn.example.com/$folder/${imageFile.name}';

  @override
  Future<bool> deleteImage(String imageUrl) async => true;

  @override
  Future<String?> uploadProfileImage(XFile imageFile) async => null;

  @override
  Future<String?> uploadBytes({
    required String bucket,
    required String path,
    required Uint8List fileBytes,
    FileOptions? fileOptions,
  }) async =>
      null;
}

class _FakeFamilyTreeService
    implements FamilyTreeServiceInterface, TreeGraphCapableFamilyTreeService {
  final _father = FamilyPerson(
    id: 'father',
    treeId: 'tree-1',
    userId: 'user-father',
    name: 'Кузнецов Андрей Анатольевич',
    photoUrl: 'https://cdn.example.com/relatives/father-primary.jpg',
    photoGallery: const [
      {
        'id': 'media-1',
        'url': 'https://cdn.example.com/relatives/father-primary.jpg',
        'type': 'image',
        'isPrimary': true,
      },
      {
        'id': 'media-2',
        'url': 'https://cdn.example.com/relatives/father-second.jpg',
        'type': 'image',
        'isPrimary': false,
      },
    ],
    gender: Gender.male,
    birthDate: DateTime(1971, 12, 16),
    isAlive: true,
    createdAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 1, 1),
  );

  final _mother = FamilyPerson(
    id: 'mother',
    treeId: 'tree-1',
    userId: 'user-mother',
    name: 'Кузнецова Наталья Геннадьевна',
    gender: Gender.female,
    isAlive: true,
    createdAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 1, 1),
  );

  final _son = FamilyPerson(
    id: 'son',
    treeId: 'tree-1',
    userId: 'user-1',
    name: 'Кузнецов Артем',
    gender: Gender.male,
    isAlive: true,
    createdAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 1, 1),
  );

  final _daughter = FamilyPerson(
    id: 'daughter',
    treeId: 'tree-1',
    userId: 'user-sister',
    name: 'Кузнецова Валентина',
    gender: Gender.female,
    isAlive: true,
    createdAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 1, 1),
  );

  final _grandmother = FamilyPerson(
    id: 'grandmother',
    treeId: 'tree-1',
    creatorId: 'user-1',
    name: 'Кузнецова Валентина',
    gender: Gender.female,
    isAlive: true,
    createdAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 1, 1),
  );

  final _guardian = FamilyPerson(
    id: 'guardian',
    treeId: 'tree-1',
    creatorId: 'user-1',
    name: 'Петрова Мария Ивановна',
    gender: Gender.female,
    isAlive: true,
    createdAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 1, 1),
  );

  late final List<FamilyPerson> _people = [
    _father,
    _mother,
    _son,
    _daughter,
    _grandmother,
    _guardian,
  ];
  late final List<FamilyRelation> _relations = [
    FamilyRelation(
      id: 'father-son',
      treeId: 'tree-1',
      person1Id: 'father',
      person2Id: 'son',
      relation1to2: RelationType.parent,
      relation2to1: RelationType.child,
      isConfirmed: true,
      createdAt: DateTime(2024, 1, 1),
      parentSetId: 'parent-set-son-1',
      parentSetType: 'biological',
      isPrimaryParentSet: true,
    ),
    FamilyRelation(
      id: 'father-daughter',
      treeId: 'tree-1',
      person1Id: 'father',
      person2Id: 'daughter',
      relation1to2: RelationType.parent,
      relation2to1: RelationType.child,
      isConfirmed: true,
      createdAt: DateTime(2024, 1, 1),
      parentSetId: 'parent-set-daughter-1',
      parentSetType: 'biological',
      isPrimaryParentSet: true,
    ),
    FamilyRelation(
      id: 'father-mother',
      treeId: 'tree-1',
      person1Id: 'father',
      person2Id: 'mother',
      relation1to2: RelationType.spouse,
      relation2to1: RelationType.spouse,
      isConfirmed: true,
      createdAt: DateTime(2024, 1, 1),
      unionId: 'union-1',
      unionType: 'spouse',
      unionStatus: 'current',
    ),
    FamilyRelation(
      id: 'grandmother-father',
      treeId: 'tree-1',
      person1Id: 'grandmother',
      person2Id: 'father',
      relation1to2: RelationType.parent,
      relation2to1: RelationType.child,
      isConfirmed: true,
      createdAt: DateTime(2024, 1, 1),
      parentSetId: 'parent-set-father-1',
      parentSetType: 'biological',
      isPrimaryParentSet: true,
    ),
    FamilyRelation(
      id: 'guardian-father',
      treeId: 'tree-1',
      person1Id: 'guardian',
      person2Id: 'father',
      relation1to2: RelationType.parent,
      relation2to1: RelationType.child,
      isConfirmed: true,
      createdAt: DateTime(2024, 1, 1),
      parentSetId: 'parent-set-father-2',
      parentSetType: 'guardian',
      isPrimaryParentSet: false,
    ),
  ];
  late final List<TreeChangeRecord> _historyRecords = [
    TreeChangeRecord(
      id: 'change-1',
      treeId: 'tree-1',
      actorId: 'user-1',
      type: 'person_media.created',
      personId: 'father',
      personIds: const ['father'],
      mediaId: 'media-2',
      createdAt: DateTime(2024, 1, 2, 12, 0),
    ),
    TreeChangeRecord(
      id: 'change-2',
      treeId: 'tree-1',
      actorId: 'user-1',
      type: 'person.updated',
      personId: 'father',
      personIds: const ['father'],
      createdAt: DateTime(2024, 1, 3, 14, 30),
    ),
  ];

  @override
  Future<List<FamilyTree>> getUserTrees() async => [
        FamilyTree(
          id: 'tree-1',
          name: 'Семья Кузнецовых',
          description: '',
          creatorId: 'user-1',
          memberIds: const ['user-1', 'user-father'],
          createdAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 1),
          isPrivate: true,
          members: const ['user-1', 'user-father'],
        ),
      ];

  @override
  Future<List<FamilyPerson>> getRelatives(String treeId) async => _people;

  @override
  Future<List<FamilyRelation>> getRelations(String treeId) async => _relations;

  @override
  Future<FamilyPerson> getPersonById(String treeId, String personId) async {
    return _people.firstWhere((person) => person.id == personId);
  }

  @override
  Future<RelationType> getRelationBetween(
    String treeId,
    String person1Id,
    String person2Id,
  ) async {
    if (person1Id == 'son' && person2Id == 'father') {
      return RelationType.child;
    }
    return RelationType.other;
  }

  @override
  Future<List<TreeChangeRecord>> getTreeHistory({
    required String treeId,
    String? personId,
    String? type,
    String? actorId,
  }) async {
    return _historyRecords.where((record) {
      if (record.treeId != treeId) {
        return false;
      }
      if (personId != null &&
          personId.isNotEmpty &&
          record.personId != personId) {
        return false;
      }
      if (type != null && type.isNotEmpty && record.type != type) {
        return false;
      }
      if (actorId != null && actorId.isNotEmpty && record.actorId != actorId) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<TreeGraphSnapshot> getTreeGraphSnapshot(String treeId) async {
    return TreeGraphSnapshot(
      treeId: treeId,
      people: _people,
      relations: _relations,
      familyUnits: const [
        TreeGraphFamilyUnit(
          id: 'unit-parents',
          rootParentSetId: 'parent-set-1',
          adultIds: ['father', 'mother'],
          childIds: ['son', 'daughter'],
          relationIds: ['father-son', 'father-daughter', 'father-mother'],
          unionId: 'union-1',
          isPrimaryParentSet: true,
          parentSetType: 'biological',
          unionType: 'spouse',
          unionStatus: 'current',
          label: 'Семья Кузнецовых',
        ),
        TreeGraphFamilyUnit(
          id: 'unit-father-primary',
          rootParentSetId: 'parent-set-father-1',
          adultIds: ['grandmother'],
          childIds: ['father'],
          relationIds: ['grandmother-father'],
          unionId: null,
          isPrimaryParentSet: true,
          parentSetType: 'biological',
          unionType: 'single',
          unionStatus: 'past',
          label: 'Родители Андрея',
        ),
        TreeGraphFamilyUnit(
          id: 'unit-father-guardian',
          rootParentSetId: 'parent-set-father-2',
          adultIds: ['guardian'],
          childIds: ['father'],
          relationIds: ['guardian-father'],
          unionId: null,
          isPrimaryParentSet: false,
          parentSetType: 'guardian',
          unionType: 'single',
          unionStatus: 'current',
          label: 'Опека Марии',
        ),
      ],
      viewerDescriptors: const [
        TreeGraphViewerDescriptor(
          personId: 'father',
          primaryRelationLabel: 'Отец',
          isBlood: true,
          alternatePathCount: 1,
          pathSummary: 'Кузнецов Артем -> Кузнецов Андрей Анатольевич',
          primaryPathPersonIds: ['son', 'father'],
        ),
      ],
      branchBlocks: const [
        TreeGraphBranchBlock(
          id: 'branch-1',
          rootUnitId: 'unit-parents',
          label: 'Семья Кузнецовых',
          memberPersonIds: ['father', 'mother', 'son', 'daughter', 'guardian'],
        ),
      ],
      generationRows: const [
        TreeGraphGenerationRow(
          row: 0,
          label: 'Поколение 1',
          personIds: ['father', 'mother'],
          familyUnitIds: ['unit-parents'],
        ),
        TreeGraphGenerationRow(
          row: 1,
          label: 'Поколение 2',
          personIds: ['son', 'daughter'],
          familyUnitIds: [],
        ),
      ],
      warnings: const [
        TreeGraphWarning(
          id: 'warning-father-parent-sets',
          code: 'multiple_primary_parent_sets',
          severity: 'warning',
          message: 'У Андрея несколько основных наборов родителей.',
          hint:
              'Оставьте только один основной набор родителей, а остальные переведите в дополнительные.',
          personIds: ['father', 'grandmother', 'guardian'],
          familyUnitIds: ['unit-father-primary', 'unit-father-guardian'],
          relationIds: ['grandmother-father', 'guardian-father'],
        ),
        TreeGraphWarning(
          id: 'warning-grandmother-conflict',
          code: 'conflicting_direct_links',
          severity: 'warning',
          message: 'У Валентины есть конфликтующая прямая связь с Андреем.',
          hint: 'Проверьте тип прямой связи перед редактированием.',
          personIds: ['grandmother', 'father'],
          familyUnitIds: ['unit-father-primary'],
          relationIds: ['grandmother-father'],
        ),
      ],
      viewerPersonId: 'son',
    );
  }

  @override
  Future<List<String>> getRelationPath({
    required String treeId,
    required String targetPersonId,
  }) async {
    if (targetPersonId == 'father') {
      return const ['son', 'father'];
    }
    return const [];
  }

  @override
  Future<void> disconnectRelation({
    required String treeId,
    required String relationId,
  }) async {}

  @override
  Future<void> reassignParentSet({
    required String treeId,
    required String childPersonId,
    required String parentPersonId,
    required String parentSetId,
    String? parentSetType,
    bool isPrimaryParentSet = true,
  }) async {}

  @override
  Future<void> setRelationType({
    required String treeId,
    required FamilyPerson anchorPerson,
    required FamilyPerson targetPerson,
    required String relationType,
    String? customRelationLabel1to2,
    String? customRelationLabel2to1,
  }) async {}

  @override
  Future<void> setUnionStatus({
    required String treeId,
    required String relationId,
    required String unionStatus,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final Uint8List _transparentImageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WlH0X8AAAAASUVORK5CYII=',
);

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _TestHttpClient();
  }
}

class _TestHttpClient implements HttpClient {
  bool _autoUncompress = true;

  @override
  bool get autoUncompress => _autoUncompress;

  @override
  set autoUncompress(bool value) {
    _autoUncompress = value;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _TestHttpClientRequest();

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _TestHttpClientRequest();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestHttpClientRequest implements HttpClientRequest {
  @override
  HttpHeaders headers = _TestHttpHeaders();

  @override
  bool followRedirects = false;

  @override
  int maxRedirects = 5;

  @override
  Future<HttpClientResponse> close() async => _TestHttpClientResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  @override
  final HttpHeaders headers = _TestHttpHeaders();

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => _transparentImageBytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  bool get persistentConnection => false;

  @override
  bool get isRedirect => false;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([_transparentImageBytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestHttpHeaders implements HttpHeaders {
  @override
  void add(
    String name,
    Object value, {
    bool preserveHeaderCase = false,
  }) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final getIt = GetIt.instance;
  final originalHttpOverrides = HttpOverrides.current;

  setUpAll(() async {
    await initializeDateFormatting('ru');
    HttpOverrides.global = _TestHttpOverrides();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    getIt.registerSingleton<AuthServiceInterface>(_FakeAuthService());
    getIt.registerSingleton<LocalStorageService>(_FakeLocalStorageService());
    getIt.registerSingleton<ProfileServiceInterface>(_FakeProfileService());
    getIt.registerSingleton<ChatServiceInterface>(_FakeChatService());
    getIt.registerSingleton<InvitationLinkServiceInterface>(
      _FakeInvitationLinkService(),
    );
    getIt.registerSingleton<StorageServiceInterface>(_FakeStorageService());
    getIt.registerSingleton<FamilyTreeServiceInterface>(
      _FakeFamilyTreeService(),
    );
  });

  tearDown(() async {
    await getIt.reset();
  });

  tearDownAll(() {
    HttpOverrides.global = originalHttpOverrides;
  });

  testWidgets(
    'RelativeDetailsScreen показывает корректные роли семьи для родителя',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final treeProvider = TreeProvider();
      await treeProvider.selectTree('tree-1', 'Семья Кузнецовых');

      await tester.pumpWidget(
        ChangeNotifierProvider<TreeProvider>.value(
          value: treeProvider,
          child: const MaterialApp(
            home: RelativeDetailsScreen(personId: 'father'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Кузнецов Андрей Анатольевич'), findsWidgets);
      expect(find.text('Есть аккаунт в Родне'), findsOneWidget);
      expect(
        find.text(
          'Сейчас проще всего быстро выйти на контакт: написать человеку или помочь с обновлением профиля.',
        ),
        findsOneWidget,
      );
      expect(find.text('Написать'), findsOneWidget);
      expect(find.text('Для вас: Отец'), findsOneWidget);
      expect(find.text('Семья'), findsOneWidget);
      expect(find.text('Кузнецов Артем'), findsOneWidget);
      expect(find.text('Кузнецова Валентина'), findsWidgets);
      expect(find.text('Кузнецова Наталья Геннадьевна'), findsOneWidget);
      expect(find.text('Сын'), findsOneWidget);
      expect(find.text('Дочь'), findsOneWidget);
      expect(find.text('Жена'), findsOneWidget);
      expect(find.text('Мать'), findsWidgets);
      expect(find.text('Фотографии'), findsOneWidget);
      expect(find.text('2 фото'), findsOneWidget);
      expect(find.text('История изменений'), findsOneWidget);
      expect(find.text('Добавлено фото'), findsOneWidget);
      expect(find.text('Открыть историю'), findsOneWidget);
      expect(find.text('Связанный профиль'), findsOneWidget);
      expect(find.text('Связи и родство'), findsOneWidget);
      expect(find.text('Добавить родственника'), findsOneWidget);
      expect(find.text('Путь родства'), findsOneWidget);
      expect(find.text('Другие родители'), findsOneWidget);
      expect(find.text('Несколько основных родителей'), findsOneWidget);
      expect(
        find.text('У Андрея несколько основных наборов родителей.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Открыть историю'));
      await tester.pumpAndSettle();

      expect(find.text('История изменений'), findsWidgets);
      expect(find.text('Все'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Фото'), findsOneWidget);
      expect(find.text('Добавлено фото'), findsWidgets);
    },
  );

  testWidgets(
    'RelativeDetailsScreen открывает быстрый выбор связи для добавления родственника',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final treeProvider = TreeProvider();
      await treeProvider.selectTree('tree-1', 'Семья Кузнецовых');

      await tester.pumpWidget(
        ChangeNotifierProvider<TreeProvider>.value(
          value: treeProvider,
          child: const MaterialApp(
            home: RelativeDetailsScreen(personId: 'father'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Добавить родственника'));
      await tester.tap(find.text('Добавить родственника'));
      await tester.pumpAndSettle();

      expect(find.text('Добавить к карточке'), findsOneWidget);
      expect(find.text('Добавить родителя'), findsOneWidget);
      expect(find.text('Добавить супруга или партнёра'), findsOneWidget);
      expect(find.text('Добавить ребёнка'), findsOneWidget);
      expect(find.text('Добавить брата или сестру'), findsOneWidget);
    },
  );

  testWidgets(
    'RelativeDetailsScreen показывает расширенный путь родства из graph snapshot',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final treeProvider = TreeProvider();
      await treeProvider.selectTree('tree-1', 'Семья Кузнецовых');

      await tester.pumpWidget(
        ChangeNotifierProvider<TreeProvider>.value(
          value: treeProvider,
          child: const MaterialApp(
            home: RelativeDetailsScreen(personId: 'father'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Путь родства'));
      await tester.tap(find.text('Путь родства'));
      await tester.pumpAndSettle();

      expect(find.text('Кровная связь'), findsOneWidget);
      expect(find.text('Шагов: 1'), findsOneWidget);
      expect(find.text('Еще путей: 1'), findsOneWidget);
      expect(
        find.text('Кузнецов Артем -> Кузнецов Андрей Анатольевич'),
        findsOneWidget,
      );
      expect(find.text('Это вы'), findsOneWidget);
      expect(find.text('Выбранный человек'), findsOneWidget);
    },
  );

  testWidgets(
    'RelativeDetailsScreen открывает путь родства по initialAction',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final treeProvider = TreeProvider();
      await treeProvider.selectTree('tree-1', 'Семья Кузнецовых');

      await tester.pumpWidget(
        ChangeNotifierProvider<TreeProvider>.value(
          value: treeProvider,
          child: const MaterialApp(
            home: RelativeDetailsScreen(
              personId: 'father',
              initialAction: 'path',
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Кровная связь'), findsOneWidget);
      expect(
        find.text('Кузнецов Артем -> Кузнецов Андрей Анатольевич'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'RelativeDetailsScreen показывает дополнительные наборы родителей',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final treeProvider = TreeProvider();
      await treeProvider.selectTree('tree-1', 'Семья Кузнецовых');

      await tester.pumpWidget(
        ChangeNotifierProvider<TreeProvider>.value(
          value: treeProvider,
          child: const MaterialApp(
            home: RelativeDetailsScreen(personId: 'father'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Другие родители'));
      await tester.tap(find.text('Другие родители'));
      await tester.pumpAndSettle();

      expect(find.text('Другие родители'), findsWidgets);
      expect(find.text('Петрова Мария Ивановна'), findsWidgets);
      expect(find.text('Основной набор'), findsOneWidget);
      expect(find.text('Дополнительный набор'), findsOneWidget);
      expect(find.text('Биологическая связь'), findsOneWidget);
      expect(find.text('Опека'), findsOneWidget);
    },
  );

  testWidgets(
    'RelativeDetailsScreen показывает приглашение для родственника без аккаунта',
    (tester) async {
      final treeProvider = TreeProvider();
      await treeProvider.selectTree('tree-1', 'Семья Кузнецовых');

      await tester.pumpWidget(
        ChangeNotifierProvider<TreeProvider>.value(
          value: treeProvider,
          child: const MaterialApp(
            home: RelativeDetailsScreen(personId: 'grandmother'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Кузнецова Валентина'), findsWidgets);
      expect(find.text('Пока без аккаунта'), findsOneWidget);
      expect(
        find.text(
          'Сначала отправьте приглашение, чтобы человек подключился к дереву, чату и своему профилю.',
        ),
        findsOneWidget,
      );
      expect(find.text('Пригласить в Родню'), findsOneWidget);
      expect(find.text('Написать'), findsNothing);
      expect(find.text('Связанный профиль'), findsNothing);
    },
  );

  testWidgets(
    'RelativeDetailsScreen показывает graph warnings в редактировании связей',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final treeProvider = TreeProvider();
      await treeProvider.selectTree('tree-1', 'Семья Кузнецовых');

      await tester.pumpWidget(
        ChangeNotifierProvider<TreeProvider>.value(
          value: treeProvider,
          child: const MaterialApp(
            home: RelativeDetailsScreen(personId: 'grandmother'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Исправить связи'));
      await tester.tap(find.text('Исправить связи'));
      await tester.pumpAndSettle();

      expect(find.text('Конфликт прямых связей'), findsWidgets);
      expect(
        find.text('У Валентины есть конфликтующая прямая связь с Андреем.'),
        findsWidgets,
      );
      expect(
        find.text('Проверьте тип прямой связи перед редактированием.'),
        findsWidgets,
      );
    },
  );
}
