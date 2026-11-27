import '../../models/audience_preset.dart';
import '../../models/circle.dart';

abstract class CircleServiceInterface {
  Future<List<FamilyCircle>> getCircles(String treeId);

  /// Pre-computed smart-set personId lists for the current user in
  /// the given tree. Used by the audience picker to surface
  /// "Моя семья" / "Близкие" as one-tap tiles. Default impl returns
  /// the empty response so older adapters compile cleanly.
  Future<AudiencePresetsResponse> getAudiencePresets(String treeId) async {
    return AudiencePresetsResponse.empty;
  }

  Future<FamilyCircle> createCircle({
    required String treeId,
    required String name,
    String? description,
  });

  Future<FamilyCircle> updateCircle({
    required String treeId,
    required String circleId,
    required String name,
    String? description,
  });

  Future<List<String>> getCircleMemberIdentityIds({
    required String treeId,
    required String circleId,
  });

  Future<FamilyCircle> replaceCircleMembers({
    required String treeId,
    required String circleId,
    List<String> identityIds = const <String>[],
    List<String> personIds = const <String>[],
  });

  Future<void> deleteCircle({
    required String treeId,
    required String circleId,
  });
}
