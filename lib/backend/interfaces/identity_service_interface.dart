import '../../models/identity_claim.dart';
import '../../models/merge_proposal.dart';
import '../../models/person_attribute.dart';
import '../../models/public_identity_result.dart';

abstract class IdentityServiceInterface {
  Future<List<MergeProposal>> getPendingMergeProposals();

  Future<MergeProposal> reviewMergeProposal(
    String proposalId, {
    required bool accept,
    String? reason,
  });

  /// D1: применённые слияния зрителя — секция «Объединённые ранее».
  Future<List<MergeProposal>> getMergedProposals();

  /// D1: разъединить применённое слияние (право — любой ответственный).
  Future<MergeProposal> unmergeMergeProposal(String proposalId);

  Future<List<PersonAttribute>> getPersonAttributes({
    required String treeId,
    required String personId,
  });

  Future<List<PersonAttribute>> updatePersonAttributeVisibility({
    required String treeId,
    required String personId,
    String? visibility,
    Map<String, String> attributes = const <String, String>{},
  });

  Future<IdentityClaim> createIdentityClaim({
    required String treeId,
    required String personId,
    String? evidence,
  });

  Future<List<IdentityClaim>> getPendingIdentityClaims();

  Future<IdentityClaim> reviewIdentityClaim(
    String claimId, {
    required bool approve,
    String? reason,
  });

  Future<bool> setPublicDiscoverability(bool enabled);

  Future<List<PublicIdentityResult>> searchPublicIdentities({
    String? query,
    String? birthYear,
  });
}
