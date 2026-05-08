import '../models/branch_digest.dart';

/// Phase 6.3 capability mixin: services that can return the
/// "Эта неделя в семье" digest for a single branch implement
/// this. Services that don't expose the endpoint just don't
/// surface the home-screen digest strip — older clients keep
/// rendering the legacy events list.
abstract class BranchDigestCapableFamilyTreeService {
  /// Returns null when the branch is unknown to the user (404
  /// from the server). Throws on auth/network failure.
  Future<BranchDigest?> getBranchDigest({
    required String treeId,
    int days = 7,
  });
}
