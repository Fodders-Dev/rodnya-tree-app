import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:rodnya/backend/interfaces/auth_service_interface.dart';
import 'package:rodnya/backend/interfaces/post_service_interface.dart';
import 'package:rodnya/models/post.dart';
import 'package:rodnya/screens/post_detail_screen.dart';
import 'package:rodnya/theme/app_theme.dart';

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
  _FakePostService({required this.onGetPost});

  final Future<Post?> Function(String postId) onGetPost;

  @override
  Future<Post?> getPost(String postId) => onGetPost(postId);

  @override
  Future<Post> updatePost(
      {required String postId, required String content}) async {
    return Post(
      id: postId,
      treeId: 'tree-1',
      authorId: 'user-1',
      authorName: 'Иван',
      content: content,
      createdAt: DateTime(2026, 5, 1),
      editedAt: DateTime(2026, 5, 2),
    );
  }

  @override
  Future<void> deletePost(String postId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GoRouter _buildRouter(PostServiceInterface postService) {
  return GoRouter(
    initialLocation: '/post/post-1',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: Text('HOME_FEED')),
      ),
      GoRoute(
        path: '/post/:postId',
        builder: (_, state) => PostDetailScreen(
          postId: state.pathParameters['postId'] ?? '',
          postServiceOverride: postService,
        ),
      ),
    ],
  );
}

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
      'PostDetailScreen renders loading then loaded post and supports edit',
      (tester) async {
    final completer = Completer<Post?>();
    final service = _FakePostService(onGetPost: (_) => completer.future);
    getIt.registerSingleton<PostServiceInterface>(service);

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: _buildRouter(service),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(
      Post(
        id: 'post-1',
        treeId: 'tree-1',
        authorId: 'user-1',
        authorName: 'Иван',
        content: 'Содержимое поста',
        createdAt: DateTime(2026, 5, 1),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Содержимое поста'), findsOneWidget);
    expect(find.textContaining('Иван', findRichText: true), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Редактировать'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('post-edit-content-field')),
      'Новый текст в детальном',
    );
    await tester.tap(find.byKey(const Key('post-edit-save-button')));
    await tester.pumpAndSettle();

    expect(find.text('Новый текст в детальном'), findsOneWidget);
  });

  testWidgets('PostDetailScreen shows not-found empty CTA to return to feed',
      (tester) async {
    final service = _FakePostService(onGetPost: (_) async => null);
    getIt.registerSingleton<PostServiceInterface>(service);

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: _buildRouter(service),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Публикация не найдена'), findsOneWidget);
    await tester.tap(find.text('Вернуться в ленту'));
    await tester.pumpAndSettle();
    expect(find.text('HOME_FEED'), findsOneWidget);
  });

  testWidgets('PostDetailScreen shows error and retries', (tester) async {
    var calls = 0;
    final service = _FakePostService(
      onGetPost: (_) async {
        calls++;
        if (calls == 1) {
          throw Exception('network down');
        }
        return Post(
          id: 'post-1',
          treeId: 'tree-1',
          authorId: 'u2',
          authorName: 'Мария',
          content: 'Загрузилось со 2 раза',
          createdAt: DateTime(2026, 5, 1),
        );
      },
    );
    getIt.registerSingleton<PostServiceInterface>(service);

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: _buildRouter(service),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Не удалось открыть пост'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('Загрузилось со 2 раза'), findsOneWidget);
  });
}
