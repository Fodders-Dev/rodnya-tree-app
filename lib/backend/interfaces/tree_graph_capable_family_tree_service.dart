import '../../models/family_person.dart';
import '../../models/tree_graph_snapshot.dart';

abstract class TreeGraphCapableFamilyTreeService {
  Future<TreeGraphSnapshot> getTreeGraphSnapshot(String treeId);

  Future<List<String>> getRelationPath({
    required String treeId,
    required String targetPersonId,
  });

  Future<void> reassignParentSet({
    required String treeId,
    required String childPersonId,
    required String parentPersonId,
    required String parentSetId,
    String? parentSetType,
    bool isPrimaryParentSet = true,
  });

  Future<void> disconnectRelation({
    required String treeId,
    required String relationId,
  });

  Future<void> setRelationType({
    required String treeId,
    required FamilyPerson anchorPerson,
    required FamilyPerson targetPerson,
    required String relationType,
    String? customRelationLabel1to2,
    String? customRelationLabel2to1,
  });

  Future<void> setUnionStatus({
    required String treeId,
    required String relationId,
    required String unionStatus,
  });
}
