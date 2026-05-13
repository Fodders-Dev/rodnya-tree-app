// Phase 4 chunk 4c: end-to-end integration test через TreeViewScreen.
//
// Covers intercept correctness E (per chunk 4 prep verify) +
// full search flow + chat routing. Exercise'ит REAL gesture path
// через InteractiveViewer → GestureDetector → host callback,
// which standalone widget tests struggled с (chunk 4a).
//
// Mocking strategy: FamilyTreeServiceInterface implements
// ExtendedNetworkCapable + BloodRelationCapable mixins. Slice
// includes 2 own + 1 foreign person + relations. Chat service
// returns 'chat-$userId' для verify navigation.
//
// FeatureFlags.testOverrideExtendedRenderPath = true в setUp →
// все InteractiveFamilyTree instances в widget tree honor extended
// render path (Element 1 tint + Element 2 edge color активны).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:rodnya/backend/interfaces/auth_service_interface.dart';
import 'package:rodnya/backend/interfaces/blood_relation_capable_family_tree_service.dart';
import 'package:rodnya/backend/interfaces/chat_service_interface.dart';
import 'package:rodnya/backend/interfaces/extended_network_capable_family_tree_service.dart';
import 'package:rodnya/backend/interfaces/family_tree_service_interface.dart';
import 'package:rodnya/backend/models/blood_relation.dart';
import 'package:rodnya/backend/models/extended_network_slice.dart';
import 'package:rodnya/config/feature_flags.dart';
import 'package:rodnya/models/chat_attachment.dart';
import 'package:rodnya/models/chat_message.dart';
import 'package:rodnya/models/chat_message_search_result.dart';
import 'package:rodnya/models/chat_preview.dart';
import 'package:rodnya/models/chat_send_progress.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/models/family_relation.dart';
import 'package:rodnya/models/family_tree.dart';
import 'package:rodnya/providers/tree_provider.dart';
import 'package:rodnya/screens/tree_view_screen.dart';
import 'package:rodnya/services/app_status_service.dart';
import 'package:rodnya/services/local_storage_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuth implements AuthServiceInterface {
  @override
  String? get currentUserId => 'user-me';
  @override
  String? get currentUserEmail => 'me@example.com';
  @override
  String? get currentUserDisplayName => 'Я';
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

class _FakeLocalStorage implements LocalStorageService {
  @override
  Future<Map<String, Offset>> getTreeNodePositions(String treeId) async =>
      <String, Offset>{};
  @override
  Future<void> saveTreeNodePositions(
      String treeId, Map<String, Offset> positions) async {}
  @override
  Future<void> clearTreeNodePositions(String treeId) async {}
  @override
  Future<FamilyTree?> getTree(String treeId) async {
    final now = DateTime(2024, 1, 1);
    return FamilyTree(
      id: treeId,
      name: 'Тест',
      description: '',
      creatorId: 'user-me',
      memberIds: const ['user-me'],
      createdAt: now,
      updatedAt: now,
      isPrivate: true,
      members: const ['user-me'],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeChat implements ChatServiceInterface {
  String? lastGetOrCreateChatUserId;

  @override
  String? get currentUserId => 'user-me';
  @override
  String buildChatId(String otherUserId) => 'chat-$otherUserId';
  @override
  Stream<List<ChatPreview>> getUserChatsStream(String userId) =>
      Stream.value(const <ChatPreview>[]);
  @override
  Stream<int> getTotalUnreadCountStream(String userId) => Stream.value(0);
  @override
  Stream<List<ChatMessage>> getMessagesStream(String chatId) =>
      Stream.value(const <ChatMessage>[]);
  @override
  Future<void> refreshMessages(String chatId) async {}
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
  Future<String?> getOrCreateChat(String otherUserId) async {
    lastGetOrCreateChatUserId = otherUserId;
    return 'chat-$otherUserId';
  }

  @override
  Future<List<ChatMessageSearchResult>> searchMessages({
    required String query,
    String? chatId,
    int limit = 50,
  }) async =>
      const <ChatMessageSearchResult>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _treeId = 'tree-1';
const _ownPersonId = 'p-own';
const _ownIdentityId = 'identity-me';
const _foreignPersonId = 'p-foreign';
const _foreignIdentityId = 'identity-foreign';

class _FakeFamilyTreeService
    implements
        FamilyTreeServiceInterface,
        ExtendedNetworkCapableFamilyTreeService,
        BloodRelationCapableFamilyTreeService {
  bool blocked = false;

  @override
  Future<List<FamilyTree>> getUserTrees() async {
    final now = DateTime(2024, 1, 1);
    return [
      FamilyTree(
        id: _treeId,
        name: 'Тест',
        description: '',
        creatorId: 'user-me',
        memberIds: const ['user-me'],
        createdAt: now,
        updatedAt: now,
        isPrivate: true,
        members: const ['user-me'],
      ),
    ];
  }

  @override
  Future<List<FamilyPerson>> getRelatives(String treeId) async {
    return [
      FamilyPerson(
        id: _ownPersonId,
        treeId: treeId,
        userId: 'user-me',
        identityId: _ownIdentityId,
        name: 'Иван Свой',
        gender: Gender.male,
        isAlive: true,
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      ),
      FamilyPerson(
        id: _foreignPersonId,
        treeId: treeId,
        identityId: _foreignIdentityId,
        name: 'Степа Чужой',
        gender: Gender.male,
        isAlive: true,
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      ),
    ];
  }

  @override
  Future<List<FamilyRelation>> getRelations(String treeId) async {
    return [
      FamilyRelation(
        id: 'r-1',
        treeId: treeId,
        person1Id: _ownPersonId,
        person2Id: _foreignPersonId,
        relation1to2: RelationType.parent,
        relation2to1: RelationType.child,
        isConfirmed: true,
        createdAt: DateTime(2024, 1, 1),
      ),
    ];
  }

  @override
  Future<ExtendedNetworkSlice?> getExtendedNetworkSlice({
    required String treeId,
    int maxHops = 4,
    bool includeAnonymous = true,
    List<String>? branchIds,
  }) async {
    if (blocked) return null;
    return ExtendedNetworkSlice(
      graphPersons: const <ExtendedNetworkPerson>[
        ExtendedNetworkPerson(
          id: _ownIdentityId,
          name: 'Иван Свой',
          gender: 'male',
          birthDate: null,
          deathDate: null,
          photoUrl: null,
          isAlive: true,
          hopDistance: 0,
        ),
        ExtendedNetworkPerson(
          id: _foreignIdentityId,
          name: 'Степа Чужой',
          gender: 'male',
          birthDate: null,
          deathDate: null,
          photoUrl: null,
          isAlive: true,
          hopDistance: 2,
        ),
      ],
      graphRelations: const <ExtendedNetworkRelation>[],
      branchMembership: const <String, List<String>>{},
      ownerMap: const <String, ExtendedNetworkOwnerInfo>{
        _foreignIdentityId: ExtendedNetworkOwnerInfo(
          userId: 'user-stepan',
          displayName: 'Стёпа Мочаров',
          photoUrl: null,
        ),
      },
      viewerSelfGraphPersonId: _ownIdentityId,
      stats: const ExtendedNetworkStats(
        totalCount: 2,
        myCount: 1,
        extendedCount: 1,
        anonymousCount: 0,
        maxHopsReached: false,
        capReached: false,
      ),
    );
  }

  @override
  Future<BloodRelation> findBloodRelation({
    required String fromGraphPersonId,
    required String toGraphPersonId,
    int maxDepth = 10,
  }) async {
    return const BloodRelation(
      found: true,
      chain: <BloodRelationPersonPreview>[],
      edges: <String>[],
      label: 'двоюродный брат',
      degree: 4,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _bootstrapExtendedMode(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'extended_mode_$_treeId': 'extended',
  });
  FeatureFlags.testOverrideExtendedRenderPath = true;
  await tester.binding.setSurfaceSize(const Size(1440, 1024));
}

GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: '/tree/view/$_treeId?name=%D0%A2%D0%B5%D1%81%D1%82',
    routes: [
      GoRoute(
        path: '/tree/view/:treeId',
        builder: (context, state) => TreeViewScreen(
          routeTreeId: state.pathParameters['treeId'],
          routeTreeName: state.uri.queryParameters['name'],
        ),
      ),
      GoRoute(
        path: '/relative/details/:personId',
        builder: (context, state) =>
            Scaffold(body: Text('details:${state.pathParameters['personId']}')),
      ),
      GoRoute(
        path: '/chats/view/:chatId',
        builder: (context, state) =>
            Scaffold(body: Text('chat:${state.pathParameters['chatId']}')),
      ),
    ],
  );
}

void main() {
  final getIt = GetIt.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    getIt.registerSingleton<AuthServiceInterface>(_FakeAuth());
    getIt.registerSingleton<ChatServiceInterface>(_FakeChat());
    getIt.registerSingleton<LocalStorageService>(_FakeLocalStorage());
    getIt.registerSingleton<AppStatusService>(AppStatusService());
    FeatureFlags.testOverrideExtendedRenderPath = null;
  });

  tearDown(() async {
    await getIt.reset();
    FeatureFlags.testOverrideExtendedRenderPath = null;
  });

  testWidgets(
      'extended mode → slice fetched + topbar shows search button',
      (tester) async {
    await _bootstrapExtendedMode(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = _FakeFamilyTreeService();
    getIt.registerSingleton<FamilyTreeServiceInterface>(service);
    final treeProvider = TreeProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<TreeProvider>.value(
        value: treeProvider,
        child: MaterialApp.router(routerConfig: _buildRouter()),
      ),
    );
    await tester.pumpAndSettle();

    // Topbar shows mode toggle + search button когда extended +
    // slice non-empty.
    expect(find.byTooltip('Поиск в расширенной сети'), findsOneWidget);
    expect(find.byTooltip('Фильтры расширенной сети'), findsOneWidget);
  });

  testWidgets(
      'search button opens sheet → typed query filters results',
      (tester) async {
    await _bootstrapExtendedMode(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = _FakeFamilyTreeService();
    getIt.registerSingleton<FamilyTreeServiceInterface>(service);
    final treeProvider = TreeProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<TreeProvider>.value(
        value: treeProvider,
        child: MaterialApp.router(routerConfig: _buildRouter()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Поиск в расширенной сети'));
    await tester.pumpAndSettle();

    expect(find.text('Поиск в расширенной сети'), findsOneWidget);
    // Slice has 2 persons.
    expect(find.text('Иван Свой'), findsOneWidget);
    expect(find.text('Степа Чужой'), findsOneWidget);

    // Foreign chip present для Стёпы.
    expect(find.text('не моя'), findsOneWidget);

    // Filter by «свой».
    await tester.enterText(find.byType(TextField), 'свой');
    await tester.pumpAndSettle();
    expect(find.text('Иван Свой'), findsOneWidget);
    expect(find.text('Степа Чужой'), findsNothing);
  });

  testWidgets(
      'tap foreign result в search → ForeignNodeSheet opens',
      (tester) async {
    await _bootstrapExtendedMode(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = _FakeFamilyTreeService();
    getIt.registerSingleton<FamilyTreeServiceInterface>(service);
    final treeProvider = TreeProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<TreeProvider>.value(
        value: treeProvider,
        child: MaterialApp.router(routerConfig: _buildRouter()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Поиск в расширенной сети'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Степа Чужой'));
    await tester.pumpAndSettle();

    // Foreign sheet sections.
    expect(find.text('Кто это добавил'), findsOneWidget);
    expect(find.text('Как связаны со мной'), findsOneWidget);
    // Relation resolved via fake findBloodRelation.
    expect(find.text('двоюродный брат'), findsOneWidget);
    // Action buttons.
    expect(find.text('Открыть карточку'), findsOneWidget);
    expect(find.text('Написать Стёпа Мочаров'), findsOneWidget);
  });

  testWidgets(
      'tap «Написать» в ForeignNodeSheet → ChatService.getOrCreateChat '
      'invoked + nav на /chats/view/:chatId', (tester) async {
    await _bootstrapExtendedMode(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = _FakeFamilyTreeService();
    final chatService = _FakeChat();
    getIt.unregister<ChatServiceInterface>();
    getIt.registerSingleton<ChatServiceInterface>(chatService);
    getIt.registerSingleton<FamilyTreeServiceInterface>(service);
    final treeProvider = TreeProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<TreeProvider>.value(
        value: treeProvider,
        child: MaterialApp.router(routerConfig: _buildRouter()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Поиск в расширенной сети'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Степа Чужой'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Написать Стёпа Мочаров'));
    await tester.pumpAndSettle();

    expect(chatService.lastGetOrCreateChatUserId, 'user-stepan');
    // Navigated to chat route.
    expect(find.text('chat:chat-user-stepan'), findsOneWidget);
  });

  testWidgets(
      'tap «Открыть карточку» в ForeignNodeSheet → /relative/details/:id',
      (tester) async {
    await _bootstrapExtendedMode(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = _FakeFamilyTreeService();
    getIt.registerSingleton<FamilyTreeServiceInterface>(service);
    final treeProvider = TreeProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<TreeProvider>.value(
        value: treeProvider,
        child: MaterialApp.router(routerConfig: _buildRouter()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Поиск в расширенной сети'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Степа Чужой'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Открыть карточку'));
    await tester.pumpAndSettle();

    // identityId = _foreignIdentityId — sheet's `onOpenCard` navigates
    // через person.id == identityId (fabricated FamilyPerson).
    expect(find.text('details:$_foreignIdentityId'), findsOneWidget);
  });

  testWidgets(
      'tap own result в search → recenter canvas + select (NOT foreign sheet)',
      (tester) async {
    await _bootstrapExtendedMode(tester);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = _FakeFamilyTreeService();
    getIt.registerSingleton<FamilyTreeServiceInterface>(service);
    final treeProvider = TreeProvider();

    await tester.pumpWidget(
      ChangeNotifierProvider<TreeProvider>.value(
        value: treeProvider,
        child: MaterialApp.router(routerConfig: _buildRouter()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Поиск в расширенной сети'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Иван Свой'));
    await tester.pumpAndSettle();

    // Own result → existing legacy selection flow. Foreign sheet NOT
    // shown.
    expect(find.text('Кто это добавил'), findsNothing);
    expect(find.text('Открыть карточку'), findsNothing);
  });
}
