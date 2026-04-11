import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lineage/backend/interfaces/auth_service_interface.dart';
import 'package:lineage/backend/interfaces/chat_service_interface.dart';
import 'package:lineage/backend/interfaces/family_tree_service_interface.dart';
import 'package:lineage/models/chat_attachment.dart';
import 'package:lineage/models/chat_details.dart';
import 'package:lineage/models/chat_message.dart';
import 'package:lineage/models/chat_preview.dart';
import 'package:lineage/models/chat_send_progress.dart';
import 'package:lineage/models/family_person.dart';
import 'package:lineage/models/family_relation.dart';
import 'package:lineage/models/family_tree.dart';
import 'package:lineage/providers/tree_provider.dart';
import 'package:lineage/screens/chats_list_screen.dart';
import 'package:lineage/services/chat_archive_store.dart';
import 'package:lineage/services/chat_draft_store.dart';
import 'package:lineage/services/chat_notification_settings_store.dart';
import 'package:lineage/services/local_storage_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

class _FakeAuthService implements AuthServiceInterface {
  @override
  String? get currentUserId => 'user-1';

  @override
  String? get currentUserEmail => 'user@example.com';

  @override
  String? get currentUserDisplayName => 'Артем';

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

class _FakeChatService implements ChatServiceInterface {
  List<String>? createdParticipantIds;
  List<String>? createdBranchRootPersonIds;
  String? createdTitle;
  List<ChatPreview> chatPreviews = const <ChatPreview>[];

  @override
  String? get currentUserId => 'user-1';

  @override
  String buildChatId(String otherUserId) => 'chat-$otherUserId';

  @override
  Stream<List<ChatPreview>> getUserChatsStream(String userId) {
    return Stream.value(chatPreviews);
  }

  @override
  Stream<int> getTotalUnreadCountStream(String userId) {
    return Stream.value(0);
  }

  @override
  Stream<List<ChatMessage>> getMessagesStream(String chatId) {
    return Stream.value(const <ChatMessage>[]);
  }

  @override
  Future<void> sendMessage({
    required String otherUserId,
    String text = '',
    List<XFile> attachments = const <XFile>[],
  }) async {}

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
  Future<void> sendTextMessage({
    required String otherUserId,
    required String text,
  }) async {}

  @override
  Future<void> markChatAsRead(String chatId, String userId) async {}

  @override
  Future<String?> getOrCreateChat(String otherUserId) async =>
      'chat-$otherUserId';

  @override
  Future<String?> createGroupChat({
    required List<String> participantIds,
    String? title,
    String? treeId,
  }) async {
    createdParticipantIds = List<String>.from(participantIds);
    createdTitle = title;
    return 'chat-group-1';
  }

  @override
  Future<String?> createBranchChat({
    required String treeId,
    required List<String> branchRootPersonIds,
    String? title,
  }) async {
    createdBranchRootPersonIds = List<String>.from(branchRootPersonIds);
    createdTitle = title;
    return 'chat-branch-1';
  }

  @override
  Future<ChatDetails> getChatDetails(String chatId) async => const ChatDetails(
        chatId: 'chat-group-1',
        type: 'group',
        title: 'Семья Кузнецовых',
        participantIds: ['user-1', 'user-2'],
        participants: [
          ChatParticipantSummary(userId: 'user-1', displayName: 'Артем'),
          ChatParticipantSummary(userId: 'user-2', displayName: 'Иван'),
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
  Future<void> editChatMessage({
    required String chatId,
    required String messageId,
    required String text,
  }) async {}

  @override
  Future<void> deleteChatMessage({
    required String chatId,
    required String messageId,
  }) async {}
}

class _FakeFamilyTreeService extends Fake
    implements FamilyTreeServiceInterface {
  @override
  Future<List<FamilyPerson>> getRelatives(String treeId) async => [
        FamilyPerson(
          id: 'person-root-1',
          treeId: treeId,
          userId: 'user-root-1',
          name: 'Иван Кузнецов',
          gender: Gender.male,
          isAlive: true,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          relation: 'Отец',
        ),
        FamilyPerson(
          id: 'person-root-2',
          treeId: treeId,
          userId: 'user-root-2',
          name: 'Мария Понькина',
          gender: Gender.female,
          isAlive: true,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          relation: 'Сестра',
        ),
        FamilyPerson(
          id: 'person-child-1',
          treeId: treeId,
          userId: 'user-child-1',
          name: 'Олег Кузнецов',
          gender: Gender.male,
          isAlive: true,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          relation: 'Брат',
        ),
        FamilyPerson(
          id: 'person-child-2',
          treeId: treeId,
          userId: 'user-child-2',
          name: 'Катя Понькина',
          gender: Gender.female,
          isAlive: true,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          relation: 'Племянница',
        ),
      ];

  @override
  Future<List<FamilyRelation>> getRelations(String treeId) async => [
        FamilyRelation(
          id: 'rel-1',
          treeId: treeId,
          person1Id: 'person-root-1',
          person2Id: 'person-child-1',
          relation1to2: RelationType.parent,
          relation2to1: RelationType.child,
          isConfirmed: true,
          createdAt: DateTime(2026),
        ),
        FamilyRelation(
          id: 'rel-2',
          treeId: treeId,
          person1Id: 'person-root-2',
          person2Id: 'person-child-2',
          relation1to2: RelationType.parent,
          relation2to1: RelationType.child,
          isConfirmed: true,
          createdAt: DateTime(2026),
        ),
      ];

  @override
  Future<List<FamilyTree>> getUserTrees() async => const <FamilyTree>[];
}

class _FakeLocalStorageService extends Fake implements LocalStorageService {
  @override
  Future<FamilyTree?> getTree(String treeId) async {
    return FamilyTree(
      id: treeId,
      name: 'Семья Кузнецовых',
      description: '',
      creatorId: 'user-1',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      memberIds: const ['user-1', 'user-root-1', 'user-root-2'],
      isPrivate: true,
      members: const ['user-1', 'user-root-1', 'user-root-2'],
      kind: TreeKind.family,
    );
  }
}

class _MemoryChatDraftStore implements ChatDraftStore {
  final Map<String, ChatDraftSnapshot> _drafts = <String, ChatDraftSnapshot>{};

  @override
  Future<void> clearDraft(String key) async {
    _drafts.remove(key);
  }

  @override
  Future<Map<String, ChatDraftSnapshot>> getAllDrafts() async {
    return Map<String, ChatDraftSnapshot>.from(_drafts);
  }

  @override
  Future<ChatDraftSnapshot?> getDraft(String key) async {
    return _drafts[key];
  }

  @override
  Future<void> saveDraft(String key, String text) async {
    _drafts[key] = ChatDraftSnapshot(
      text: text,
      updatedAt: DateTime(2026, 4, 11, 12, _drafts.length),
    );
  }
}

class _MemoryChatArchiveStore implements ChatArchiveStore {
  final Map<String, ChatArchiveSnapshot> _archived =
      <String, ChatArchiveSnapshot>{};

  @override
  Future<void> clearArchivedChat(String key) async {
    _archived.remove(key);
  }

  @override
  Future<Map<String, ChatArchiveSnapshot>> getAllArchivedChats() async {
    return Map<String, ChatArchiveSnapshot>.from(_archived);
  }

  @override
  Future<ChatArchiveSnapshot?> getArchivedChat(String key) async {
    return _archived[key];
  }

  @override
  Future<void> saveArchivedChat(
      String key, ChatArchiveSnapshot snapshot) async {
    _archived[key] = snapshot;
  }
}

class _MemoryChatNotificationSettingsStore
    implements ChatNotificationSettingsStore {
  final Map<String, ChatNotificationSettingsSnapshot> _settings =
      <String, ChatNotificationSettingsSnapshot>{};

  @override
  Future<void> clearSettings(String key) async {
    _settings.remove(key);
  }

  @override
  Future<Map<String, ChatNotificationSettingsSnapshot>> getAllSettings() async {
    return Map<String, ChatNotificationSettingsSnapshot>.from(_settings);
  }

  @override
  Future<ChatNotificationSettingsSnapshot?> getSettings(String key) async {
    return _settings[key];
  }

  @override
  Future<void> saveSettings(
    String key,
    ChatNotificationSettingsSnapshot snapshot,
  ) async {
    if (snapshot.level == ChatNotificationLevel.all) {
      _settings.remove(key);
      return;
    }
    _settings[key] = snapshot;
  }
}

void main() {
  final getIt = GetIt.instance;

  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  setUp(() async {
    await getIt.reset();
    getIt.registerSingleton<AuthServiceInterface>(_FakeAuthService());
    getIt.registerSingleton<ChatServiceInterface>(_FakeChatService());
    getIt.registerSingleton<FamilyTreeServiceInterface>(
        _FakeFamilyTreeService());
    getIt.registerSingleton<LocalStorageService>(_FakeLocalStorageService());
  });

  tearDown(() async {
    await getIt.reset();
  });

  Widget buildApp({
    ChatDraftStore? draftStore,
    ChatArchiveStore? archiveStore,
    ChatNotificationSettingsStore? notificationSettingsStore,
  }) {
    final treeProvider = TreeProvider();
    treeProvider.selectTree(
      'tree-1',
      'Семья Кузнецовых',
      treeKind: TreeKind.family,
    );

    final router = GoRouter(
      initialLocation: '/chats',
      routes: [
        GoRoute(
          path: '/chats',
          builder: (context, state) => ChatsListScreen(
            draftStore: draftStore,
            archiveStore: archiveStore,
            notificationSettingsStore: notificationSettingsStore,
          ),
        ),
        GoRoute(
          path: '/chats/view/:chatId',
          builder: (context, state) => Text(state.uri.toString()),
        ),
        GoRoute(
          path: '/relatives',
          builder: (context, state) => const Text('relatives-screen'),
        ),
        GoRoute(
          path: '/tree',
          builder: (context, state) => const Text('tree-screen'),
        ),
      ],
    );

    return ChangeNotifierProvider<TreeProvider>.value(
      value: treeProvider,
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('ChatsListScreen показывает CTA в пустом состоянии',
      (tester) async {
    await tester.pumpWidget(buildApp());

    await tester.pumpAndSettle();

    expect(find.text('Пока нет чатов'), findsOneWidget);
    expect(find.text('Создать чат'), findsOneWidget);
    expect(find.text('Открыть родных'), findsOneWidget);
    expect(find.text('Открыть дерево'), findsOneWidget);
  });

  testWidgets('Пустое состояние чатов ведет в родных и дерево', (tester) async {
    await tester.pumpWidget(buildApp());

    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Открыть родных'));
    await tester.tap(find.text('Открыть родных'));
    await tester.pumpAndSettle();
    expect(find.text('relatives-screen'), findsOneWidget);

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Открыть дерево'));
    await tester.tap(find.text('Открыть дерево'));
    await tester.pumpAndSettle();
    expect(find.text('tree-screen'), findsOneWidget);
  });

  testWidgets('Composer creates multi-branch chat from selected roots',
      (tester) async {
    final chatService = getIt<ChatServiceInterface>() as _FakeChatService;

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Новый чат'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ветки'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Иван Кузнецов'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Мария Понькина'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Открыть чат веток'));
    await tester.pumpAndSettle();

    expect(
      chatService.createdBranchRootPersonIds,
      equals(['person-root-1', 'person-root-2']),
    );
    expect(chatService.createdTitle, 'Ветки: Иван Кузнецов, Мария Понькина');
    expect(
      find.textContaining(
        '/chats/view/chat-branch-1?type=branch&title=',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Desktop shell показывает контекст и быстрые действия',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Навигация по чатам'), findsOneWidget);
    expect(find.text('Контекст дерева: Семья Кузнецовых'), findsOneWidget);
    expect(find.text('Создать чат'), findsWidgets);
    expect(find.text('Открыть родных'), findsWidgets);
    expect(find.text('Открыть дерево'), findsWidgets);
  });

  testWidgets('ChatsListScreen склоняет overview counts корректно',
      (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('0 чатов'), findsOneWidget);
    expect(find.text('4 родных в поиске'), findsOneWidget);
    expect(find.text('Все прочитано'), findsOneWidget);
  });

  testWidgets('ChatsListScreen shows draft preview and draft count',
      (tester) async {
    final chatService = getIt<ChatServiceInterface>() as _FakeChatService;
    chatService.chatPreviews = [
      ChatPreview(
        id: 'preview-1',
        chatId: 'chat-1',
        userId: 'user-1',
        otherUserId: 'user-root-1',
        otherUserName: 'Иван Кузнецов',
        lastMessage: 'Старое сообщение',
        lastMessageTime: DateTime(2026, 4, 10, 18, 0),
        unreadCount: 0,
        lastMessageSenderId: 'user-root-1',
      ),
    ];
    final draftStore = _MemoryChatDraftStore();
    await draftStore.saveDraft(
      SharedPreferencesChatDraftStore.chatKey('chat-1'),
      'Нужно обсудить встречу в воскресенье',
    );

    await tester.pumpWidget(buildApp(draftStore: draftStore));
    await tester.pumpAndSettle();

    expect(find.text('1 черновик'), findsOneWidget);
    expect(
      find.text('Черновик: Нужно обсудить встречу в воскресенье'),
      findsOneWidget,
    );
  });

  testWidgets('ChatsListScreen shows muted chat indicator and overview',
      (tester) async {
    final chatService = getIt<ChatServiceInterface>() as _FakeChatService;
    chatService.chatPreviews = [
      ChatPreview(
        id: 'preview-muted-1',
        chatId: 'chat-muted-1',
        userId: 'user-1',
        otherUserId: 'user-root-1',
        otherUserName: 'Иван Кузнецов',
        lastMessage: 'Напиши, когда доедешь',
        lastMessageTime: DateTime(2026, 4, 10, 19, 0),
        unreadCount: 2,
        lastMessageSenderId: 'user-root-1',
      ),
    ];
    final notificationSettingsStore = _MemoryChatNotificationSettingsStore();
    await notificationSettingsStore.saveSettings(
      SharedPreferencesChatNotificationSettingsStore.chatKey('chat-muted-1'),
      ChatNotificationSettingsSnapshot(
        level: ChatNotificationLevel.muted,
        updatedAt: DateTime(2026, 4, 11, 12, 0),
      ),
    );

    await tester.pumpWidget(
      buildApp(notificationSettingsStore: notificationSettingsStore),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 чат без уведомлений'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_off_outlined), findsWidgets);
  });

  testWidgets('ChatsListScreen archives chat and moves it out of main flow',
      (tester) async {
    final chatService = getIt<ChatServiceInterface>() as _FakeChatService;
    chatService.chatPreviews = [
      ChatPreview(
        id: 'preview-1',
        chatId: 'chat-1',
        userId: 'user-1',
        otherUserId: 'user-root-1',
        otherUserName: 'Иван Кузнецов',
        lastMessage: 'Старое сообщение',
        lastMessageTime: DateTime(2026, 4, 10, 18, 0),
        unreadCount: 0,
        lastMessageSenderId: 'user-root-1',
      ),
      ChatPreview(
        id: 'preview-2',
        chatId: 'chat-2',
        userId: 'user-1',
        otherUserId: 'user-root-2',
        otherUserName: 'Мария Понькина',
        lastMessage: 'Новый чат',
        lastMessageTime: DateTime(2026, 4, 10, 19, 0),
        unreadCount: 2,
        lastMessageSenderId: 'user-root-2',
      ),
    ];
    final archiveStore = _MemoryChatArchiveStore();

    await tester.pumpWidget(buildApp(archiveStore: archiveStore));
    await tester.pumpAndSettle();

    expect(find.text('Иван Кузнецов'), findsOneWidget);
    expect(find.text('Мария Понькина'), findsOneWidget);

    await tester.longPress(find.text('Иван Кузнецов'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Архивировать чат'));
    await tester.pumpAndSettle();

    expect(find.text('Иван Кузнецов'), findsNothing);
    expect(find.text('Мария Понькина'), findsOneWidget);
    expect(find.text('1 чат в архиве'), findsWidgets);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Архив (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Иван Кузнецов'), findsOneWidget);
    expect(find.text('Мария Понькина'), findsNothing);
  });

  testWidgets('ChatsListScreen unarchives chat from archive filter',
      (tester) async {
    final chatService = getIt<ChatServiceInterface>() as _FakeChatService;
    chatService.chatPreviews = [
      ChatPreview(
        id: 'preview-1',
        chatId: 'chat-1',
        userId: 'user-1',
        otherUserId: 'user-root-1',
        otherUserName: 'Иван Кузнецов',
        lastMessage: 'Старое сообщение',
        lastMessageTime: DateTime(2026, 4, 10, 18, 0),
        unreadCount: 0,
        lastMessageSenderId: 'user-root-1',
      ),
    ];
    final archiveStore = _MemoryChatArchiveStore();
    await archiveStore.saveArchivedChat(
      SharedPreferencesChatArchiveStore.chatKey('chat-1'),
      ChatArchiveSnapshot(archivedAt: DateTime(2026, 4, 11, 12, 0)),
    );

    await tester.pumpWidget(buildApp(archiveStore: archiveStore));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Архив (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Иван Кузнецов'), findsOneWidget);

    await tester.longPress(find.text('Иван Кузнецов'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Вернуть в основной список'));
    await tester.pumpAndSettle();

    expect(find.text('Иван Кузнецов'), findsOneWidget);
    expect(find.text('Архив (1)'), findsNothing);
  });
}
