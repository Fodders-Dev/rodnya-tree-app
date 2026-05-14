import '../models/kinship_check.dart';

/// Phase 6 chunk 3 (PHASE-6-PROPOSAL.md §2.4-§2.6 + §3.3): capability
/// mixin для bilateral «мы родственники?» check endpoints.
///
/// Implementation lives в [CustomApiFamilyTreeService]. Older
/// backends без `/v1/kinship-checks` endpoint → caps detection
/// `is KinshipCheckCapableFamilyTreeService` returns false → UI
/// hides discover FAB.
///
/// Methods return `null` либо empty list on network failure (graceful
/// degradation) — controller surface'ит generic «попробуйте позже»
/// rather than crashing UI. Specific known error codes (rejection
/// cooldown, target not found) throw [KinshipCheckError] чтобы UI
/// мог render targeted copy.
abstract class KinshipCheckCapableFamilyTreeService {
  /// `POST /v1/kinship-checks`. Initiator creates pending request.
  /// Returns existing pending request if duplicate (server-side
  /// idempotency); `created=false` сигнализирует что notification
  /// was NOT re-dispatched.
  ///
  /// Throws [KinshipCheckError] для:
  ///   - SELF_CHECK_FORBIDDEN (target == initiator)
  ///   - TARGET_NOT_FOUND (unknown userId)
  ///   - REJECTION_COOLDOWN (target previously rejected; 30d cooldown
  ///     per DECISIONS.md 2026-05-14).
  Future<KinshipCheckCreateResult?> createKinshipCheck({
    required String targetUserId,
  });

  /// `GET /v1/me/kinship-checks/received?status=<optional>`.
  /// Pending received = «Запросы вам» — target needs to respond.
  Future<List<KinshipCheck>> listReceivedKinshipChecks({
    KinshipCheckStatus? status,
  });

  /// `GET /v1/me/kinship-checks/issued?status=<optional>`.
  /// Pending issued = «Ваши запросы» — initiator sent, waiting либо
  /// result available.
  Future<List<KinshipCheck>> listIssuedKinshipChecks({
    KinshipCheckStatus? status,
  });

  /// `POST /v1/kinship-checks/:checkId/respond` body `{decision}`.
  /// On accept — backend computes BFS (maxDepth=4, §2.5) and stores
  /// result; returned check carries [KinshipCheck.result].
  ///
  /// Throws [KinshipCheckError] для:
  ///   - NOT_FOUND (id mismatch либо foreign check)
  ///   - NOT_PENDING (already responded либо expired).
  Future<KinshipCheck?> respondToKinshipCheck({
    required String checkId,
    required KinshipCheckDecision decision,
  });
}
