import '../../models/gathering.dart';
import '../../models/post.dart' show TreeContentScopeType;

/// Phase E: backend access for «Встречи» (Gatherings). Mirrors the post
/// service's audience surface (scopeType / circleId / anchorPersonIds /
/// branchIds). RSVP endpoints arrive in E3.
abstract class GatheringServiceInterface {
  /// Gatherings for a tree the viewer can see, soonest-first.
  Future<List<Gathering>> getGatherings({required String treeId});

  /// Create a gathering. [title] and [startAt] are required.
  Future<Gathering> createGathering({
    required String treeId,
    required String title,
    String? description,
    required DateTime startAt,
    DateTime? endAt,
    bool isAllDay = false,
    String? place,
    TreeContentScopeType scopeType = TreeContentScopeType.wholeTree,
    List<String> anchorPersonIds = const [],
    String? circleId,
    List<String>? branchIds,
  });

  /// Delete a gathering (server enforces author-only).
  Future<void> deleteGathering(String gatheringId);

  /// Set the current user's RSVP. [status] ∈ {'yes','maybe','no'};
  /// [headcount] = extra people brought (besides the responder). Returns
  /// the updated gathering with refreshed public rsvps. (Phase E3.)
  Future<Gathering> setRsvp(
    String gatheringId,
    String status, {
    int? headcount,
    String? note,
  });
}
