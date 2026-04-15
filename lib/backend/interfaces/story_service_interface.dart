import 'package:image_picker/image_picker.dart';

import '../../models/story.dart';

abstract class StoryServiceInterface {
  Future<List<Story>> getStories({String? treeId, String? authorId});

  Future<Story> createStory({
    required String treeId,
    required StoryType type,
    String? text,
    XFile? media,
    String? thumbnailUrl,
    DateTime? expiresAt,
  });

  Future<Story> markViewed(String storyId);

  Future<void> deleteStory(String storyId);
}
