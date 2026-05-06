import '../models/identity_suggestion.dart';

/// Capability mixin for the Phase 1.2 voltage-indicator matcher.
/// When the host's family tree service implements this, the
/// canvas renders a 💡 dot on each card with at least one
/// suggestion; the popover calls `linkIdentity` to confirm or
/// `dismissIdentitySuggestion` to suppress.
///
/// Mirrors the existing capability pattern (see
/// IdentityDuplicateCapableFamilyTreeService and
/// CrossTreePersonSearchCapableFamilyTreeService) — services that
/// don't implement this just don't show the 💡 surface; nothing
/// breaks.
abstract class IdentitySuggestionsCapableFamilyTreeService {
  /// Fetch medium+high confidence cross-tree match suggestions
  /// for a single person. Returns an empty list when the
  /// matcher found nothing (vs. throwing on auth/network errors).
  Future<List<IdentitySuggestion>> getIdentitySuggestionsForPerson({
    required String treeId,
    required String personId,
    int limit = 10,
  });

  /// Confirm a 💡-suggested match: backend joins both records
  /// under one PersonIdentity. Phase 1.1 propagation takes over
  /// from there — future edits on either record fan out.
  ///
  /// Throws on conflict (both already claimed by different user
  /// accounts) or auth/network failure.
  Future<void> linkIdentity({
    required String sourceTreeId,
    required String sourcePersonId,
    required String targetTreeId,
    required String targetPersonId,
  });

  /// Dismiss a 💡 suggestion: backend records the per-user
  /// decision so the same pair doesn't keep surfacing. Idempotent.
  Future<void> dismissIdentitySuggestion({
    required String sourceTreeId,
    required String sourcePersonId,
    required String targetPersonId,
  });
}
