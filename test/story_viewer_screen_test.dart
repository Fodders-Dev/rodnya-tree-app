import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:rodnya/backend/interfaces/story_service_interface.dart';
import 'package:rodnya/models/story.dart';
import 'package:rodnya/screens/story_viewer_screen.dart';

class _FakeStoryService implements StoryServiceInterface {
  final List<String> markedStoryIds = <String>[];
  final List<String> deletedStoryIds = <String>[];
  final Map<String, Story> storiesById;

  _FakeStoryService(this.storiesById);

  @override
  Future<List<Story>> getStories({String? treeId, String? authorId}) async =>
      storiesById.values.toList(growable: false);

  @override
  Future<Story> createStory({
    required String treeId,
    required StoryType type,
    String? text,
    media,
    String? thumbnailUrl,
    DateTime? expiresAt,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Story> markViewed(String storyId) async {
    markedStoryIds.add(storyId);
    final story = storiesById[storyId]!;
    final updated = story.copyWith(
      viewedBy: <String>[...story.viewedBy, 'user-1'],
    );
    storiesById[storyId] = updated;
    return updated;
  }

  @override
  Future<void> deleteStory(String storyId) async {
    deletedStoryIds.add(storyId);
    storiesById.remove(storyId);
  }
}

void main() {
  final getIt = GetIt.instance;

  Story buildStory({
    required String id,
    required String authorId,
    required String authorName,
    List<String>? viewedBy,
  }) {
    return Story(
      id: id,
      treeId: 'tree-1',
      authorId: authorId,
      authorName: authorName,
      type: StoryType.text,
      text: 'Семейное обновление',
      createdAt: DateTime(2026, 4, 13, 12),
      expiresAt: DateTime(2026, 4, 14, 12),
      viewedBy: viewedBy,
    );
  }

  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('StoryViewerScreen отмечает чужую story как просмотренную',
      (tester) async {
    final story = buildStory(
      id: 'story-1',
      authorId: 'user-2',
      authorName: 'Анна',
    );
    final service = _FakeStoryService({'story-1': story});
    getIt.registerSingleton<StoryServiceInterface>(service);

    await tester.pumpWidget(
      MaterialApp(
        home: StoryViewerScreen(
          stories: [story],
          currentUserId: 'user-1',
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(service.markedStoryIds, ['story-1']);
    expect(find.text('Просмотрено'), findsOneWidget);
  });

  testWidgets('StoryViewerScreen не считает автора просмотревшим свою story',
      (tester) async {
    final story = buildStory(
      id: 'story-2',
      authorId: 'user-1',
      authorName: 'Алексей',
      viewedBy: const ['user-1', 'user-2'],
    );
    final service = _FakeStoryService({'story-2': story});
    getIt.registerSingleton<StoryServiceInterface>(service);

    await tester.pumpWidget(
      MaterialApp(
        home: StoryViewerScreen(
          stories: [story],
          currentUserId: 'user-1',
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(service.markedStoryIds, isEmpty);
    expect(find.text('Просмотров: 1'), findsOneWidget);
  });
}
