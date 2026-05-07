import '../models/identity_field_conflict.dart';

/// Capability mixin for the Phase 1.3 edit-time conflict
/// surfacing. When the host's family tree service implements
/// this, the canvas renders a small ⚠️ dot on cards that have
/// at least one unresolved identity-field conflict; the user
/// taps it to review the divergence and pick `keep` (target
/// wins, propagation muted for this exact pair) or `overwrite`
/// (source wins, target updated).
///
/// Mirrors the Phase 1.2 [IdentitySuggestionsCapableFamilyTreeService]
/// pattern — services that don't implement this just don't
/// surface ⚠️ badges; nothing breaks for older backends.
abstract class IdentityConflictsCapableFamilyTreeService {
  /// Fetch all unresolved identity-field conflicts the user is
  /// allowed to see on this tree (target-side: rows where the
  /// linked person on `treeId` has a local edit a propagation
  /// declined to overwrite). Returns an empty list when the
  /// backend found nothing — vs. throwing on auth/network errors.
  Future<List<IdentityFieldConflict>> getIdentityConflictsForTree({
    required String treeId,
  });

  /// Apply the user's resolution to a conflict.
  /// `choice = 'keep'` — target's local value stays, propagator
  /// mutes future passes for this exact (sourceValue,
  /// targetValue) pair so the user isn't asked again.
  /// `choice = 'overwrite'` — source value wins, target person
  /// is updated and `lastPropagatedFields` is refreshed so the
  /// next propagation pass is a clean no-op.
  ///
  /// Throws on auth/network failure or invalid choice.
  Future<void> resolveIdentityConflict({
    required String treeId,
    required String conflictId,
    required String choice,
  });
}
