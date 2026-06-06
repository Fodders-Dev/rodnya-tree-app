import 'package:image_picker/image_picker.dart';

import '../../models/poll.dart';
import '../../models/post.dart' show TreeContentScopeType;

/// Phase E5: backend access for «Опросы» (Polls). Mirrors the gathering
/// service's audience surface + media upload; adds option-based voting.
abstract class PollServiceInterface {
  /// Polls for a tree the viewer can see, newest-first.
  Future<List<Poll>> getPolls({required String treeId});

  /// Create a poll. [question] + at least two non-empty [options] are
  /// required. [images] are uploaded to the media pipeline.
  Future<Poll> createPoll({
    required String treeId,
    required String question,
    required List<String> options,
    bool allowMultiple = false,
    DateTime? closesAt,
    List<XFile> images = const [],
    TreeContentScopeType scopeType = TreeContentScopeType.wholeTree,
    List<String> anchorPersonIds = const [],
    String? circleId,
    List<String>? branchIds,
  });

  /// Cast / change the current user's vote. [optionIds] must be existing
  /// option ids; the server truncates to one for a single-choice poll.
  /// Returns the updated poll with refreshed public responses.
  Future<Poll> vote(String pollId, List<String> optionIds);

  /// Delete a poll (server enforces author-only).
  Future<void> deletePoll(String pollId);
}
