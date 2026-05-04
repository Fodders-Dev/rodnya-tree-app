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
}
