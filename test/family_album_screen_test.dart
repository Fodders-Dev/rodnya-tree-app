// Album v1: «Альбом семьи» collects every photo from the family's posts
// into a grid; tap → MediaLightbox; warm empty state when there are none.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/post_service_interface.dart';
import 'package:rodnya/models/post.dart';
import 'package:rodnya/screens/family_album_screen.dart';
import 'package:rodnya/theme/app_theme.dart';
import 'package:rodnya/widgets/media_lightbox.dart';

class _FakePostService implements PostServiceInterface {
  _FakePostService({required this.posts});

  final List<Post> posts;

  @override
  Future<List<Post>> getPosts({
    String? treeId,
    String? authorId,
    bool onlyBranches = false,
  }) async =>
      posts;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Post _post({
  required String id,
  required String authorId,
  required String authorName,
  required List<String> imageUrls,
  required DateTime createdAt,
}) {
  return Post(
    id: id,
    treeId: 'tree-1',
    authorId: authorId,
    authorName: authorName,
    content: '',
    imageUrls: imageUrls,
    createdAt: createdAt,
  );
}

Widget _host(_FakePostService svc) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: FamilyAlbumScreen(serviceOverride: svc),
    );

void main() {
  testWidgets('renders photos from all posts in a grid (newest-first)',
      (tester) async {
    final svc = _FakePostService(
      posts: [
        _post(
          id: 'p1',
          authorId: 'a1',
          authorName: 'Анна',
          imageUrls: const [
            'https://example.com/1.jpg',
            'https://example.com/2.jpg',
          ],
          createdAt: DateTime(2026, 4, 2),
        ),
        _post(
          id: 'p2',
          authorId: 'a2',
          authorName: 'Иван',
          imageUrls: const ['https://example.com/3.jpg'],
          createdAt: DateTime(2026, 4, 1),
        ),
      ],
    );

    await tester.pumpWidget(_host(svc));
    await tester.pumpAndSettle();

    expect(find.text('Альбом семьи'), findsOneWidget);
    // 3 photos collected across both posts.
    expect(find.byKey(const Key('album-thumb-0')), findsOneWidget);
    expect(find.byKey(const Key('album-thumb-1')), findsOneWidget);
    expect(find.byKey(const Key('album-thumb-2')), findsOneWidget);
    expect(find.byKey(const Key('album-thumb-3')), findsNothing);
    // >1 author → the «по автору» filter strip appears.
    expect(find.byKey(const Key('album-author-all')), findsOneWidget);
  });

  testWidgets('dedups repeated photo URLs and skips video URLs',
      (tester) async {
    final svc = _FakePostService(
      posts: [
        _post(
          id: 'p1',
          authorId: 'a1',
          authorName: 'Анна',
          imageUrls: const [
            'https://example.com/dup.jpg',
            'https://example.com/dup.jpg', // duplicate
            'https://example.com/clip.mp4', // video → skipped
          ],
          createdAt: DateTime(2026, 4, 2),
        ),
      ],
    );

    await tester.pumpWidget(_host(svc));
    await tester.pumpAndSettle();

    // Only the single unique photo remains.
    expect(find.byKey(const Key('album-thumb-0')), findsOneWidget);
    expect(find.byKey(const Key('album-thumb-1')), findsNothing);
    // Single author → no filter strip.
    expect(find.byKey(const Key('album-author-all')), findsNothing);
  });

  testWidgets('shows warm empty state when there are no photos',
      (tester) async {
    final svc = _FakePostService(posts: const []);
    await tester.pumpWidget(_host(svc));
    await tester.pumpAndSettle();

    expect(find.text('Пока нет фотографий'), findsOneWidget);
    expect(find.textContaining('Поделись первым моментом'), findsOneWidget);
    expect(find.byKey(const Key('album-thumb-0')), findsNothing);
  });

  testWidgets('tapping a thumb opens the MediaLightbox', (tester) async {
    final svc = _FakePostService(
      posts: [
        _post(
          id: 'p1',
          authorId: 'a1',
          authorName: 'Анна',
          imageUrls: const ['https://example.com/1.jpg'],
          createdAt: DateTime(2026, 4, 2),
        ),
      ],
    );

    await tester.pumpWidget(_host(svc));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('album-thumb-0')));
    // The lightbox image loader never "settles" (network image spinner),
    // so pump a couple of frames past the open transition rather than
    // pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(MediaLightbox), findsOneWidget);
  });
}
