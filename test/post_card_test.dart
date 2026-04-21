import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:rodnya/backend/interfaces/auth_service_interface.dart';
import 'package:rodnya/backend/interfaces/post_service_interface.dart';
import 'package:rodnya/models/post.dart';
import 'package:rodnya/widgets/post_card.dart';

void main() {
  final getIt = GetIt.instance;

  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  setUp(() async {
    await getIt.reset();
    getIt.registerSingleton<AuthServiceInterface>(_FakeAuthService());
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets(
      'PostCard syncs likes from server response instead of local guess',
      (tester) async {
    getIt.registerSingleton<PostServiceInterface>(
      _FakePostService(
        onToggleLike: (_) async => Post(
          id: 'post-1',
          treeId: 'tree-1',
          authorId: 'author-1',
          authorName: 'Анна',
          content: 'Семейная новость',
          createdAt: DateTime(2026, 4, 13, 10),
          likedBy: const ['user-1', 'user-2'],
          commentCount: 0,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostCard(
            post: Post(
              id: 'post-1',
              treeId: 'tree-1',
              authorId: 'author-1',
              authorName: 'Анна',
              content: 'Семейная новость',
              createdAt: DateTime(2026, 4, 13, 10),
              likedBy: const [],
              commentCount: 0,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('PostCard rolls back like state when backend rejects update',
      (tester) async {
    getIt.registerSingleton<PostServiceInterface>(
      _FakePostService(
        onToggleLike: (_) async => throw Exception('like failed'),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostCard(
            post: Post(
              id: 'post-1',
              treeId: 'tree-1',
              authorId: 'author-1',
              authorName: 'Анна',
              content: 'Семейная новость',
              createdAt: DateTime(2026, 4, 13, 10),
              likedBy: const [],
              commentCount: 0,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.text('0'), findsWidgets);
    expect(find.textContaining('Не удалось обновить реакцию'), findsOneWidget);
  });
}

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

class _FakePostService implements PostServiceInterface {
  _FakePostService({
    required this.onToggleLike,
  });

  final Future<Post> Function(String postId) onToggleLike;

  @override
  Future<Post> toggleLike(String postId) => onToggleLike(postId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
