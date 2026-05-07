import '../models/blood_relation.dart';

/// Phase 4 capability mixin: services that talk to a backend with
/// the `/v1/graph/relation` endpoint expose this so the UI's
/// "Кем мы приходимся?" button can light up. Older or stub
/// services don't implement this — the button just stays hidden,
/// nothing breaks.
abstract class BloodRelationCapableFamilyTreeService {
  /// Walks the unified-graph blood-relation edges and returns the
  /// shortest path from [fromGraphPersonId] to [toGraphPersonId],
  /// or `BloodRelation.empty` (with `found=false`) when no blood
  /// path exists within `maxDepth` hops.
  ///
  /// Both ids are graphPersonId (= identityId), not legacy
  /// treeId-keyed personId. Use the `identityId` field on
  /// [FamilyPerson] for the conversion at call sites.
  Future<BloodRelation> findBloodRelation({
    required String fromGraphPersonId,
    required String toGraphPersonId,
    int maxDepth = 10,
  });
}
