// S1/S3: профиль скролла ленты на 200 синтетических постах. Замер
// суммарного времени прокачки кадров при прокрутке — печатается в
// [perf]-лог; до/после виртуализации сравниваются эти числа.
//
// Это НЕ строгий бенчмарк устройства — это регресс-сторож: на Column
// (до S3) первый кадр строил все 200 карточек разом; на SliverList
// должен строиться только вьюпорт.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:rodnya/backend/interfaces/auth_service_interface.dart';
import 'package:rodnya/backend/interfaces/family_tree_service_interface.dart';
import 'package:rodnya/backend/interfaces/gathering_service_interface.dart';
import 'package:rodnya/backend/interfaces/poll_service_interface.dart';
import 'package:rodnya/backend/interfaces/post_service_interface.dart';
import 'package:rodnya/backend/interfaces/story_service_interface.dart';
import 'package:rodnya/backend/models/tree_invitation.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/models/family_relation.dart';
import 'package:rodnya/models/family_tree.dart';
import 'package:rodnya/models/gathering.dart';
import 'package:rodnya/models/poll.dart';
import 'package:rodnya/models/post.dart';
import 'package:rodnya/models/story.dart';
import 'package:rodnya/providers/tree_provider.dart';
import 'package:rodnya/screens/home_screen.dart';
import 'package:rodnya/services/app_status_service.dart';
import 'package:rodnya/services/local_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuthService implements AuthServiceInterface {
  @override
  String? get currentUserId => 'user-1';

  @override
  String? get currentUserDisplayName => 'Тестовый';

  @override
  Stream<String?> get authStateChanges => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocalStorageService implements LocalStorageService {
  _FakeLocalStorageService(this.trees);

  final List<FamilyTree> trees;

  @override
  Future<List<FamilyTree>> getAllTrees() async => trees;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFamilyTreeService implements FamilyTreeServiceInterface {
  @override
  Future<List<FamilyTree>> getUserTrees() async => const <FamilyTree>[];

  @override
  Future<List<FamilyPerson>> getRelatives(String treeId) async =>
      const <FamilyPerson>[];

  @override
  Future<List<FamilyRelation>> getRelations(String treeId) async => const [];

  @override
  Stream<List<TreeInvitation>> getPendingTreeInvitations() =>
      Stream.value(const <TreeInvitation>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePostService implements PostServiceInterface {
  _FakePostService(this.posts);

  final List<Post> posts;

  @override
  Future<List<Post>> getPosts({
    String? treeId,
    String? authorId,
    bool onlyBranches = false,
  }) async =>
      posts;

  // Сторож остаётся жёстким: все 200 постов одной страницей (сценарий
  // старого бэка без пагинации) — виртуализация обязана вывозить.
  @override
  Future<PostsPage> getPostsPage({
    String? treeId,
    int limit = 20,
    String? before,
  }) async =>
      PostsPage(posts: posts, nextCursor: null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// S2/S3 прод-профиль: бэк отдаёт страницами по [limit] с курсором.
class _PaginatedFakePostService implements PostServiceInterface {
  _PaginatedFakePostService(this.posts);

  final List<Post> posts;
  int pageRequests = 0;

  @override
  Future<List<Post>> getPosts({
    String? treeId,
    String? authorId,
    bool onlyBranches = false,
  }) async =>
      posts;

  @override
  Future<PostsPage> getPostsPage({
    String? treeId,
    int limit = 20,
    String? before,
  }) async {
    pageRequests += 1;
    var source = posts;
    if (before != null && before.isNotEmpty) {
      final separator = before.lastIndexOf('|');
      final beforeId = separator == -1 ? '' : before.substring(separator + 1);
      final index = posts.indexWhere((post) => post.id == beforeId);
      source = index == -1 ? posts : posts.sublist(index + 1);
    }
    final page = source.take(limit).toList(growable: false);
    final hasMore = source.length > limit;
    final last = page.isEmpty ? null : page.last;
    return PostsPage(
      posts: page,
      nextCursor: hasMore && last != null
          ? '${last.createdAt.toIso8601String()}|${last.id}'
          : null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeStoryService implements StoryServiceInterface {
  @override
  Future<List<Story>> getStories({
    String? treeId,
    String? authorId,
    bool includeArchive = false,
  }) async =>
      const <Story>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGatheringService implements GatheringServiceInterface {
  @override
  Future<List<Gathering>> getGatherings({required String treeId}) async =>
      const <Gathering>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePollService implements PollServiceInterface {
  @override
  Future<List<Poll>> getPolls({required String treeId}) async => const <Poll>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Post> _syntheticPosts(int count) {
  return List<Post>.generate(count, (index) {
    return Post(
      id: 'post-$index',
      treeId: 'tree-1',
      authorId: 'user-${index % 7}',
      authorName: 'Родственник ${index % 7}',
      content: 'Синтетический пост №$index — немного текста, чтобы карточка '
          'имела реальную высоту. Семья, дача, пироги и фотографии.',
      createdAt: DateTime(2026, 1, 1).add(Duration(minutes: index)),
      commentCount: index % 5,
    );
  });
}

void main() {
  final getIt = GetIt.instance;

  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{'coach_marks_home_tour_shown_v1': true},
    );
    await getIt.reset();
    getIt.registerSingleton<AuthServiceInterface>(_FakeAuthService());
    getIt.registerSingleton<LocalStorageService>(
      _FakeLocalStorageService([
        FamilyTree(
          id: 'tree-1',
          name: 'Тестовое дерево',
          description: '',
          creatorId: 'user-1',
          memberIds: const ['user-1'],
          createdAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 1),
          isPrivate: true,
          members: const ['user-1'],
        ),
      ]),
    );
    getIt.registerSingleton<FamilyTreeServiceInterface>(
      _FakeFamilyTreeService(),
    );
    getIt.registerSingleton<PostServiceInterface>(
      _FakePostService(_syntheticPosts(200)),
    );
    getIt.registerSingleton<StoryServiceInterface>(_FakeStoryService());
    getIt.registerSingleton<GatheringServiceInterface>(_FakeGatheringService());
    getIt.registerSingleton<PollServiceInterface>(_FakePollService());
    getIt.registerSingleton<AppStatusService>(AppStatusService());
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('[perf] скролл ленты на 200 постах — без падений и с замером',
      (tester) async {
    tester.view.physicalSize = const Size(412, 892); // A50-габарит
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final treeProvider = TreeProvider();
    await treeProvider.selectTree('tree-1', 'Тестовое дерево');

    final buildWatch = Stopwatch()..start();
    await tester.pumpWidget(
      ChangeNotifierProvider<TreeProvider>.value(
        value: treeProvider,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    buildWatch.stop();

    // 30 свайпов вниз — суммарное время прокачки кадров.
    final scrollable = find.byType(Scrollable).first;
    final scrollWatch = Stopwatch()..start();
    for (var i = 0; i < 30; i++) {
      await tester.fling(scrollable, const Offset(0, -600), 2500);
      await tester.pumpAndSettle();
    }
    scrollWatch.stop();

    debugPrint(
      '[perf] feed.first-build-200: ${buildWatch.elapsedMilliseconds}ms',
    );
    debugPrint(
      '[perf] feed.scroll-30-flings: ${scrollWatch.elapsedMilliseconds}ms',
    );

    // Дошли глубоко в ленту, ничего не упало.
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '[perf] прод-профиль: страницы по 20, докрутка тянет следующие (S2/S3)',
      (tester) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final paginated = _PaginatedFakePostService(_syntheticPosts(200));
    await getIt.unregister<PostServiceInterface>();
    getIt.registerSingleton<PostServiceInterface>(paginated);

    final treeProvider = TreeProvider();
    await treeProvider.selectTree('tree-1', 'Тестовое дерево');

    final buildWatch = Stopwatch()..start();
    await tester.pumpWidget(
      ChangeNotifierProvider<TreeProvider>.value(
        value: treeProvider,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    buildWatch.stop();

    // Холодный старт — РОВНО одна страница, не вся лента.
    expect(paginated.pageRequests, 1);

    final scrollable = find.byType(Scrollable).first;
    final scrollWatch = Stopwatch()..start();
    for (var i = 0; i < 30; i++) {
      await tester.fling(scrollable, const Offset(0, -600), 2500);
      await tester.pumpAndSettle();
    }
    scrollWatch.stop();

    debugPrint(
      '[perf] feed.first-build-paged: ${buildWatch.elapsedMilliseconds}ms',
    );
    debugPrint(
      '[perf] feed.scroll-30-flings-paged: ${scrollWatch.elapsedMilliseconds}ms',
    );

    // Докрутка реально тянула следующие страницы.
    expect(paginated.pageRequests, greaterThan(1));
    expect(tester.takeException(), isNull);
  });
}
