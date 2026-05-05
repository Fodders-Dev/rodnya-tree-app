import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:rodnya/backend/interfaces/auth_service_interface.dart';
import 'package:rodnya/backend/interfaces/post_service_interface.dart';
import 'package:rodnya/models/comment.dart';
import 'package:rodnya/models/post.dart';
import 'package:rodnya/models/reaction_summary.dart';
import 'package:rodnya/widgets/comment_sheet.dart';

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

  Post buildPost() => Post(
        id: 'post-1',
        treeId: 'tree-1',
        authorId: 'author-1',
        authorName: 'Анна',
        content: 'Тест',
        createdAt: DateTime(2026, 5, 1, 10),
        likedBy: const [],
        commentCount: 2,
      );

  Comment buildComment({
    required String id,
    required String content,
    String? parentId,
    String authorName = 'Иван',
  }) =>
      Comment(
        id: id,
        postId: 'post-1',
        authorId: 'a',
        authorName: authorName,
        content: content,
        createdAt: DateTime(2026, 5, 1, 11),
        parentCommentId: parentId,
        reactions: const <ReactionSummary>[],
      );

  testWidgets('renders top-level comments and indented replies', (tester) async {
    getIt.registerSingleton<PostServiceInterface>(
      _FakePostService(
        comments: [
          buildComment(id: 'c1', content: 'Первый', authorName: 'Анна'),
          buildComment(
            id: 'c2',
            content: 'Ответ на первый',
            parentId: 'c1',
            authorName: 'Иван',
          ),
          buildComment(id: 'c3', content: 'Второй топ', authorName: 'Олег'),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CommentSheet(post: buildPost())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Первый'), findsOneWidget);
    expect(find.text('Ответ на первый'), findsOneWidget);
    expect(find.text('Второй топ'), findsOneWidget);
    // "Ответить" button is shown for every comment until one becomes
    // the active reply target — three comments → three buttons.
    expect(find.text('Ответить'), findsNWidgets(3));
  });

  testWidgets('tapping Ответить shows reply banner with author name',
      (tester) async {
    getIt.registerSingleton<PostServiceInterface>(
      _FakePostService(
        comments: [
          buildComment(id: 'c1', content: 'Первый', authorName: 'Анна'),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CommentSheet(post: buildPost())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ответить'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Отвечаем'), findsOneWidget);
    expect(find.text('Анна'), findsWidgets);
    // Active-reply target hides its own Ответить button — only one
    // comment in this fixture, so the button disappears entirely.
    expect(find.text('Ответить'), findsNothing);
  });

  testWidgets('sending while replying calls addComment with parentCommentId',
      (tester) async {
    final fake = _FakePostService(
      comments: [
        buildComment(id: 'c1', content: 'Первый', authorName: 'Анна'),
      ],
    );
    getIt.registerSingleton<PostServiceInterface>(fake);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CommentSheet(post: buildPost())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ответить'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Согласен');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(fake.lastAddedContent, 'Согласен');
    expect(fake.lastAddedParentId, 'c1');
    // Reply banner clears after a successful send.
    expect(find.textContaining('Отвечаем'), findsNothing);
  });

  testWidgets('long threads collapse to show 2 replies + show-more pill',
      (tester) async {
    getIt.registerSingleton<PostServiceInterface>(
      _FakePostService(
        comments: [
          buildComment(id: 'c1', content: 'Тред', authorName: 'Анна'),
          buildComment(
            id: 'r1',
            content: 'Первый',
            parentId: 'c1',
            authorName: 'Иван',
          ),
          buildComment(
            id: 'r2',
            content: 'Второй',
            parentId: 'c1',
            authorName: 'Олег',
          ),
          buildComment(
            id: 'r3',
            content: 'Третий',
            parentId: 'c1',
            authorName: 'Маша',
          ),
          buildComment(
            id: 'r4',
            content: 'Четвёртый',
            parentId: 'c1',
            authorName: 'Дима',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CommentSheet(post: buildPost())),
      ),
    );
    await tester.pumpAndSettle();

    // Only the first two replies are visible by default; the third &
    // fourth hide behind the pill.
    expect(find.text('Первый'), findsOneWidget);
    expect(find.text('Второй'), findsOneWidget);
    expect(find.text('Третий'), findsNothing);
    expect(find.text('Четвёртый'), findsNothing);
    expect(find.textContaining('Показать ещё'), findsOneWidget);

    await tester.ensureVisible(find.textContaining('Показать ещё'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Показать ещё'));
    await tester.pumpAndSettle();

    expect(find.text('Третий'), findsOneWidget);
    expect(find.text('Четвёртый'), findsOneWidget);
    expect(find.text('Свернуть'), findsOneWidget);

    // After expand, the Свернуть pill ends up below the sheet's visible
    // area in the small test viewport. Scroll it into view before tap
    // so we test the actual interaction, not just rendering.
    await tester.ensureVisible(find.text('Свернуть'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Свернуть'));
    await tester.pumpAndSettle();
    expect(find.text('Третий'), findsNothing);
    expect(find.textContaining('Показать ещё'), findsOneWidget);
  });

  testWidgets('cancelling reply restores normal comment send', (tester) async {
    final fake = _FakePostService(
      comments: [
        buildComment(id: 'c1', content: 'Первый', authorName: 'Анна'),
      ],
    );
    getIt.registerSingleton<PostServiceInterface>(fake);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CommentSheet(post: buildPost())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ответить'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Отвечаем'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('comment-reply-cancel')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Отвечаем'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Просто');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(fake.lastAddedContent, 'Просто');
    expect(fake.lastAddedParentId, isNull);
  });
}

class _FakeAuthService implements AuthServiceInterface {
  @override
  String? get currentUserId => 'self';

  @override
  String? get currentUserEmail => 'self@example.com';

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

class _FakePostService implements PostServiceInterface {
  _FakePostService({required this.comments});

  final List<Comment> comments;
  String? lastAddedContent;
  String? lastAddedParentId;

  @override
  Future<List<Comment>> getComments(String postId) async => comments;

  @override
  Future<Comment> addComment(
    String postId,
    String content, {
    String? parentCommentId,
  }) async {
    lastAddedContent = content;
    lastAddedParentId = parentCommentId;
    final newComment = Comment(
      id: 'new',
      postId: postId,
      authorId: 'self',
      authorName: 'Я',
      content: content,
      createdAt: DateTime(2026, 5, 1, 12),
      parentCommentId: parentCommentId,
    );
    comments.add(newComment);
    return newComment;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
