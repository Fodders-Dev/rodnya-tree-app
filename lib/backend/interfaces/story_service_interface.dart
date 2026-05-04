import 'package:image_picker/image_picker.dart';

import '../../models/post.dart' show TreeContentScopeType;
import '../../models/reaction_summary.dart';
import '../../models/story.dart';

abstract class StoryServiceInterface {
  /// When [includeArchive] is true the backend should return stories
  /// whose `expiresAt` is in the past as well as currently-active ones —
  /// used by the archive screen so users can revisit their old stories
  /// (the IG/TG model). When the backend doesn't support the flag yet
  /// the call still succeeds and just returns the active set, which
  /// makes the archive page render an empty state rather than error.
  Future<List<Story>> getStories({
    String? treeId,
    String? authorId,
    bool includeArchive = false,
  });

  Future<Story> createStory({
    required String treeId,
    required StoryType type,
    String? text,
    XFile? media,
    String? thumbnailUrl,
    DateTime? expiresAt,
    String? circleId,
    TreeContentScopeType scopeType = TreeContentScopeType.wholeTree,
    List<String> anchorPersonIds = const <String>[],
  });

  Future<Story> markViewed(String storyId);

  Future<void> deleteStory(String storyId);

  /// Toggle the current user's emoji reaction on a story. Mirrors the
  /// post / comment / chat-message reaction shape so the same
  /// [ReactionPicker] / chip-strip UI works across surfaces. Returns
  /// the updated reaction summaries straight from the server.
  Future<List<ReactionSummary>> toggleStoryReaction({
    required String storyId,
    required String emoji,
  }) {
    throw UnsupportedError('toggleStoryReaction is not supported');
  }
}
