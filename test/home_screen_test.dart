import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:rodnya/backend/interfaces/auth_service_interface.dart';
import 'package:rodnya/backend/interfaces/family_tree_service_interface.dart';
import 'package:rodnya/backend/interfaces/post_service_interface.dart';
import 'package:rodnya/backend/interfaces/story_service_interface.dart';
import 'package:rodnya/backend/backend_runtime_config.dart';
import 'package:rodnya/backend/models/tree_invitation.dart';
import 'package:rodnya/models/family_tree.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/models/family_relation.dart';
import 'package:rodnya/models/post.dart';
import 'package:rodnya/models/story.dart';
import 'package:rodnya/providers/tree_provider.dart';
import 'package:rodnya/screens/home_screen.dart';
import 'package:rodnya/services/app_status_service.dart';
import 'package:rodnya/services/browser_notification_bridge.dart';
import 'package:rodnya/services/custom_api_notification_service.dart';
import 'package:rodnya/services/local_storage_service.dart';
import 'package:rodnya/widgets/event_card.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuthService implements AuthServiceInterface {
  @override
  String? get currentUserId => 'user-1';

  @override
  String? get currentUserEmail => 'user@example.com';

  @override
  String? get currentUserDisplayName => 'Тестовый пользователь';

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
  _FakeLocalStorageService([List<FamilyTree> trees = const []])
      : _treesById = {for (final tree in trees) tree.id: tree};

  final Map<String, FamilyTree> _treesById;

  @override
  Future<List<FamilyTree>> getAllTrees() async => _treesById.values.toList();

  @override
  Future<FamilyTree?> getTree(String treeId) async => _treesById[treeId];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFamilyTreeService implements FamilyTreeServiceInterface {
  _FakeFamilyTreeService({
    this.invitations = const [],
    List<FamilyTree>? trees,
  }) : trees = trees ?? [_buildTree(id: 'tree-1', name: 'Тестовое дерево')];

  final List<TreeInvitation> invitations;
  final List<FamilyTree> trees;

  @override
  Future<List<FamilyTree>> getUserTrees() async => trees;

  @override
  Future<List<FamilyPerson>> getRelatives(String treeId) async => [
        FamilyPerson(
          id: 'person-1',
          treeId: treeId,
          name: 'Иван Петров',
          gender: Gender.male,
          birthDate: DateTime.now().add(const Duration(days: 1)),
          isAlive: true,
          createdAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 1),
        ),
      ];

  @override
  Future<List<FamilyRelation>> getRelations(String treeId) async => const [];

  @override
  Stream<List<TreeInvitation>> getPendingTreeInvitations() =>
      Stream.value(invitations);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePostService implements PostServiceInterface {
  @override
  Future<List<Post>> getPosts({
    String? treeId,
    String? authorId,
    bool onlyBranches = false,
  }) async =>
      throw Exception('feed unavailable');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeStoryService implements StoryServiceInterface {
  @override
  Future<List<Story>> getStories({String? treeId, String? authorId}) async =>
      const <Story>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBrowserNotificationBridge implements BrowserNotificationBridge {
  _FakeBrowserNotificationBridge({
    required this.permissionStatusValue,
  });

  BrowserNotificationPermissionStatus permissionStatusValue;
  int permissionRequests = 0;
  int pushSubscriptionRequests = 0;
  int pushUnsubscribeCalls = 0;

  @override
  bool get isSupported => true;

  @override
  bool get isPushSupported => true;

  @override
  BrowserNotificationPermissionStatus get permissionStatus =>
      permissionStatusValue;

  @override
  Future<BrowserNotificationPermissionStatus> requestPermission({
    bool prompt = true,
  }) async {
    permissionRequests += 1;
    if (permissionStatusValue ==
        BrowserNotificationPermissionStatus.defaultState) {
      permissionStatusValue = BrowserNotificationPermissionStatus.granted;
    }
    return permissionStatusValue;
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? tag,
    VoidCallback? onClick,
  }) async {}

  @override
  Future<BrowserPushSubscription?> subscribeToPush({
    required String publicKey,
  }) async {
    pushSubscriptionRequests += 1;
    return const BrowserPushSubscription(token: '{"endpoint":"test"}');
  }

  @override
  Future<void> unsubscribeFromPush() async {
    pushUnsubscribeCalls += 1;
  }
}

FamilyTree _buildTree({
  required String id,
  required String name,
}) {
  final now = DateTime(2024, 1, 1);
  return FamilyTree(
    id: id,
    name: name,
    description: '',
    creatorId: 'user-1',
    memberIds: const ['user-1'],
    createdAt: now,
    updatedAt: now,
    isPrivate: true,
    members: const ['user-1'],
  );
}

void main() {
  final getIt = GetIt.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    getIt.registerSingleton<AuthServiceInterface>(_FakeAuthService());
    getIt.registerSingleton<LocalStorageService>(
      _FakeLocalStorageService(
          [_buildTree(id: 'tree-1', name: 'Тестовое дерево')]),
    );
    getIt.registerSingleton<FamilyTreeServiceInterface>(
      _FakeFamilyTreeService(),
    );
    getIt.registerSingleton<PostServiceInterface>(_FakePostService());
    getIt.registerSingleton<StoryServiceInterface>(_FakeStoryService());
    getIt.registerSingleton<AppStatusService>(AppStatusService());
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets(
    'HomeScreen не падает без legacy post feed и показывает fallback-секцию',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final treeProvider = TreeProvider();
      await treeProvider.selectTree('tree-1', 'Тестовое дерево');

      await tester.pumpWidget(
        ChangeNotifierProvider<TreeProvider>.value(
          value: treeProvider,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Тестовое дерево'), findsWidgets);
      expect(find.text('События'), findsOneWidget);
      expect(find.text('Дерево активно'), findsNothing);
      expect(find.bySemanticsLabel('story-rail-add'), findsOneWidget);
      expect(find.text('Обновите позже.'), findsOneWidget);
      expect(find.text('Лента недоступна'), findsWidgets);
      expect(find.text('Новый пост'), findsOneWidget);
      expect(find.text('Открыть родных'), findsOneWidget);
      expect(find.text('Открыть дерево'), findsOneWidget);
      expect(find.text('День рождения'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    },
  );

  testWidgets(
    'HomeScreen без выбранного дерева ведёт к первому действию',
    (tester) async {
      final treeProvider = TreeProvider();

      await tester.pumpWidget(
        ChangeNotifierProvider<TreeProvider>.value(
          value: treeProvider,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Главная'), findsOneWidget);
      expect(find.text('Нет активного дерева'), findsOneWidget);
      expect(find.text('Выбрать дерево'), findsOneWidget);
      expect(find.text('Создать граф'), findsOneWidget);
      expect(find.text('События'), findsNothing);
      expect(find.text('Лента новостей'), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
    },
  );

  testWidgets(
    'HomeScreen показывает приглашение и ведёт сразу во вкладку приглашений',
    (tester) async {
      await getIt.reset();
      getIt.registerSingleton<AuthServiceInterface>(_FakeAuthService());
      getIt.registerSingleton<LocalStorageService>(
        _FakeLocalStorageService(
            [_buildTree(id: 'tree-1', name: 'Тестовое дерево')]),
      );
      getIt.registerSingleton<FamilyTreeServiceInterface>(
        _FakeFamilyTreeService(
          invitations: [
            TreeInvitation(
              invitationId: 'invite-1',
              tree: FamilyTree(
                id: 'tree-2',
                name: 'Семья Шуфляк',
                description: '',
                creatorId: 'user-2',
                memberIds: const ['user-2'],
                createdAt: DateTime(2024, 1, 1),
                updatedAt: DateTime(2024, 1, 1),
                isPrivate: true,
                members: const ['user-2'],
              ),
            ),
          ],
        ),
      );
      getIt.registerSingleton<PostServiceInterface>(_FakePostService());
      getIt.registerSingleton<StoryServiceInterface>(_FakeStoryService());
      getIt.registerSingleton<AppStatusService>(AppStatusService());

      final treeProvider = TreeProvider();
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                ChangeNotifierProvider<TreeProvider>.value(
              value: treeProvider,
              child: const HomeScreen(),
            ),
          ),
          GoRoute(
            path: '/trees',
            builder: (context, state) => Scaffold(
              body: Center(
                child: Text('trees ${state.uri.queryParameters['tab']}'),
              ),
            ),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text('Семья Шуфляк'), findsOneWidget);
      expect(find.textContaining('Семья Шуфляк'), findsOneWidget);

      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();

      expect(find.text('trees invitations'), findsOneWidget);
    },
  );

  testWidgets(
    'HomeScreen монтируется с browser notification service без отдельного prompt',
    (tester) async {
      final bridge = _FakeBrowserNotificationBridge(
        permissionStatusValue: BrowserNotificationPermissionStatus.defaultState,
      );
      final notificationService = await CustomApiNotificationService.create(
        runtimeConfig: const BackendRuntimeConfig(),
        browserNotificationBridge: bridge,
      );
      await notificationService.setNotificationsEnabled(false);
      getIt
          .registerSingleton<CustomApiNotificationService>(notificationService);

      final treeProvider = TreeProvider();
      await treeProvider.selectTree('tree-1', 'Тестовое дерево');

      await tester.pumpWidget(
        ChangeNotifierProvider<TreeProvider>.value(
          value: treeProvider,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Включите уведомления о семье'), findsNothing);
      expect(find.byTooltip('Активность'), findsOneWidget);
      expect(notificationService.notificationsEnabled, isFalse);
      expect(bridge.permissionRequests, 0);
    },
  );

  testWidgets(
    'HomeScreen показывает компактные фильтры событий на главной',
    (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final treeProvider = TreeProvider();
      await treeProvider.selectTree('tree-1', 'Тестовое дерево');

      await tester.pumpWidget(
        ChangeNotifierProvider<TreeProvider>.value(
          value: treeProvider,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ChoiceChip, 'Все'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Родня'), findsOneWidget);
      expect(find.bySemanticsLabel('home-event-filter-all'), findsOneWidget);
      expect(find.bySemanticsLabel('home-event-filter-rodnya'), findsOneWidget);
      expect(find.byType(EventCard), findsAtLeastNWidgets(2));

      await tester.tap(find.widgetWithText(ChoiceChip, 'Родня'));
      await tester.pumpAndSettle();

      expect(find.byType(EventCard), findsOneWidget);
      expect(find.text('День рождения'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    'HomeScreen открывает экран активности из app bar',
    (tester) async {
      final treeProvider = TreeProvider();
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                ChangeNotifierProvider<TreeProvider>.value(
              value: treeProvider,
              child: const HomeScreen(),
            ),
          ),
          GoRoute(
            path: '/notifications',
            builder: (context, state) =>
                const Scaffold(body: Center(child: Text('notifications'))),
          ),
        ],
      );
      if (!getIt.isRegistered<PostServiceInterface>()) {
        getIt.registerSingleton<PostServiceInterface>(_FakePostService());
      }

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Активность'));
      await tester.pumpAndSettle();

      expect(find.text('notifications'), findsOneWidget);
    },
  );
}
