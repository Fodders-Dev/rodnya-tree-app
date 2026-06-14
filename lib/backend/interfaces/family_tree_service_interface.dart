import '../../models/family_person.dart';
import '../../models/family_relation.dart';
import '../../models/relation_request.dart';
import '../../models/family_tree.dart';
import '../../models/person_dossier.dart';
import '../../models/tree_change_record.dart';
import '../models/include_rules.dart';
import '../models/selectable_tree.dart';
import '../models/tree_invitation.dart';

abstract class FamilyTreeServiceInterface {
  /// Phase 3.4 (DECISIONS.md ответ Q4): wizard передаёт
  /// [includeRules] чтобы новая ветка получила BFS-rule сразу
  /// при создании. Если `null` — backend применит default
  /// `manual` rule (legacy behaviour). Серверная валидация:
  /// invalid `type` → 400 (см. PHASE-3.4-PROPOSAL §2.1).
  Future<String> createTree({
    required String name,
    required String description,
    required bool isPrivate,
    TreeKind kind = TreeKind.family,
    IncludeRules? includeRules,
  });
  Future<List<FamilyTree>> getUserTrees();
  Future<List<FamilyPerson>> getRelatives(String treeId);
  Future<List<FamilyRelation>> getRelations(String treeId);
  Stream<List<FamilyPerson>> getRelativesStream(String treeId);
  Stream<List<FamilyRelation>> getRelationsStream(String treeId);
  Future<String> addRelative(String treeId, Map<String, dynamic> personData);
  Future<void> updateRelative(String personId, Map<String, dynamic> personData);
  Future<FamilyPerson> getPersonById(String treeId, String personId);
  Future<PersonDossier> getPersonDossier(String treeId, String personId);
  Future<void> proposePersonProfileContribution({
    required String treeId,
    required String personId,
    required Map<String, dynamic> fields,
    String? message,
  });
  Future<RelationType> getRelationToUser(String treeId, String relativeId);
  Future<void> addRelation(
    String treeId,
    String person1Id,
    String person2Id,
    RelationType relationType,
  );
  Future<FamilyRelation> createRelation({
    required String treeId,
    required String person1Id,
    required String person2Id,
    required RelationType relation1to2,
    bool isConfirmed,
    DateTime? marriageDate,
    DateTime? divorceDate,
    String? customRelationLabel1to2,
    String? customRelationLabel2to1,
    // B2: статус союза ('current'/'past') — текущий/бывший супруг·партнёр
    // как свойство СОЮЗА (тип в пикере остаётся примитивным spouse/partner).
    // null → бэк решает по типу/дате развода (обратная совместимость).
    String? unionStatus,
  });

  /// Snip a relation between two persons. Mirrors the existing method
  /// on `TreeGraphCapableFamilyTreeService` but exposed via the main
  /// interface so generic mutation handlers (undo/redo etc.) can use
  /// it without depending on the graph mixin.
  Future<void> disconnectRelation({
    required String treeId,
    required String relationId,
  });
  Future<List<FamilyPerson>> getOfflineProfilesByCreator(
    String treeId,
    String creatorId,
  );
  Future<String?> findSpouseId(String treeId, String personId);
  Future<void> checkAndCreateSpouseRelationIfNeeded(
    String treeId,
    String childId,
    String newParentId,
  );
  Future<void> checkAndCreateParentSiblingRelations(
    String treeId,
    String parentId,
    String childId,
  );
  Stream<List<TreeInvitation>> getPendingTreeInvitations();
  Future<List<RelationRequest>> getRelationRequests({required String treeId});
  Future<List<RelationRequest>> getPendingRelationRequests({String? treeId});
  Future<void> respondToTreeInvitation(String invitationId, bool accept);
  Future<void> respondToRelationRequest({
    required String requestId,
    required RequestStatus response,
  });
  Future<List<SelectableTree>> getSelectableTreesForCurrentUser();
  Future<RelationType> getRelationBetween(
    String treeId,
    String person1Id,
    String person2Id,
  );
  Future<bool> isCurrentUserInTree(String treeId);
  Future<void> addCurrentUserToTree({
    required String treeId,
    required String targetPersonId,
    required RelationType relationType,
  });
  Future<void> removeTree(String treeId);
  Future<void> deleteRelative(String treeId, String personId);

  /// Detach a user account from a person record. Owner-only. Use to
  /// recover when an invite link landed on the wrong slot — the
  /// person record stays in the tree (with whatever name/gender the
  /// owner originally set), the user account gets unhooked and is
  /// free to be linked elsewhere via a fresh invite.
  Future<FamilyPerson> unlinkUserFromPerson({
    required String treeId,
    required String personId,
  });
  Future<FamilyPerson> addRelativeMedia({
    required String treeId,
    required String personId,
    required Map<String, dynamic> mediaData,
  });
  Future<FamilyPerson> updateRelativeMedia({
    required String treeId,
    required String personId,
    required String mediaId,
    required Map<String, dynamic> mediaData,
  });
  Future<FamilyPerson> deleteRelativeMedia({
    required String treeId,
    required String personId,
    required String mediaId,
    String? fallbackUrl,
  });
  Future<List<TreeChangeRecord>> getTreeHistory({
    required String treeId,
    String? personId,
    String? type,
    String? actorId,
  });
  Future<bool> hasDirectRelation({
    required String treeId,
    required String person1Id,
    required String person2Id,
  });
  Future<bool> hasPendingRelationRequest({
    required String treeId,
    required String senderId,
    required String recipientId,
  });
  Future<void> sendRelationRequest({
    required String treeId,
    required String recipientId,
    required RelationType relationType,
    String? message,
  });
  Future<void> sendTreeInvitation({
    required String treeId,
    String? recipientUserId,
    String? recipientEmail,
    String? relationToTree,
  });
  Future<void> sendOfflineRelationRequestByEmail({
    required String treeId,
    required String email,
    required String offlineRelativeId,
    required RelationType relationType,
  });
}
