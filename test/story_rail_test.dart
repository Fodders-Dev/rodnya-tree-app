import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineage/models/story.dart';
import 'package:lineage/widgets/story_rail.dart';

Story _buildStory({
  required String id,
  required String authorId,
  required String authorName,
  StoryType type = StoryType.text,
  DateTime? createdAt,
  List<String>? viewedBy,
}) {
  final created = createdAt ?? DateTime(2026, 4, 15, 12);
  return Story(
    id: id,
    treeId: 'tree-1',
    authorId: authorId,
    authorName: authorName,
    type: type,
    text: 'История',
    createdAt: created,
    expiresAt: created.add(const Duration(hours: 24)),
    viewedBy: viewedBy,
  );
}

void main() {
  testWidgets('StoryRail shows visual empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StoryRail(
            title: 'Stories',
            currentUserId: 'user-1',
            stories: const [],
            isLoading: false,
            onCreateStory: () {},
            onOpenStories: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Stories'), findsOneWidget);
    expect(find.text('Добавьте первую историю.'), findsOneWidget);
    expect(find.text('Создать'), findsOneWidget);
    expect(find.bySemanticsLabel('story-rail-add'), findsOneWidget);
  });

  testWidgets('StoryRail groups stories into compact visual tiles', (
    tester,
  ) async {
    final stories = [
      _buildStory(
        id: 'story-1',
        authorId: 'user-1',
        authorName: 'Вы',
        type: StoryType.image,
        viewedBy: const ['user-1'],
      ),
      _buildStory(
        id: 'story-2',
        authorId: 'user-2',
        authorName: 'Анна',
        type: StoryType.video,
        viewedBy: const [],
        createdAt: DateTime(2026, 4, 15, 13),
      ),
      _buildStory(
        id: 'story-3',
        authorId: 'user-2',
        authorName: 'Анна',
        type: StoryType.video,
        viewedBy: const [],
        createdAt: DateTime(2026, 4, 15, 14),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StoryRail(
            title: 'Stories',
            currentUserId: 'user-1',
            stories: stories,
            isLoading: false,
            onCreateStory: () {},
            onOpenStories: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Stories'), findsOneWidget);
    expect(find.text('Создать'), findsOneWidget);
    expect(find.text('Вы'), findsWidgets);
    expect(find.text('Анна'), findsWidgets);
    expect(find.byIcon(Icons.videocam_rounded), findsWidgets);
    expect(find.bySemanticsLabel('story-rail-group-own'), findsOneWidget);
    expect(find.bySemanticsLabel('story-rail-group-user-2'), findsOneWidget);
  });
}
