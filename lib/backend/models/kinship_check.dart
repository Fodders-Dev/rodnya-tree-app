import 'blood_relation.dart';

/// Phase 6 chunk 3 (PHASE-6-PROPOSAL.md §2.4-§2.6): bilateral
/// «мы родственники?» check.
///
/// Backend collection: `kinshipChecks`. State machine:
///   pending → accepted | rejected | expired (14d timeout).
///
/// Naming: `KinshipCheck` (NOT `RelationRequest` — collides с Phase 1
/// `relationRequests` collection used для invite-to-tree). See
/// DECISIONS.md 2026-05-13 «Phase 6 chunk 1 naming».
class KinshipCheck {
  const KinshipCheck({
    required this.id,
    required this.initiatorUserId,
    required this.targetUserId,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.respondedAt,
    this.result,
  });

  final String id;
  final String initiatorUserId;
  final String targetUserId;
  final KinshipCheckStatus status;
  final String createdAt;
  final String expiresAt;
  final String? respondedAt;

  /// `null` для pending/rejected/expired. Populated server-side
  /// at accept time с findBloodRelation(maxDepth=4) result.
  /// Per §5.X: anonymized per-viewer (each side sees own visible
  /// nodes unmasked, other side's invisible nodes как «?»).
  final BloodRelation? result;

  factory KinshipCheck.fromJson(Map<String, dynamic> json) {
    final resultRaw = json['result'];
    return KinshipCheck(
      id: (json['id'] ?? '').toString(),
      initiatorUserId: (json['initiatorUserId'] ?? '').toString(),
      targetUserId: (json['targetUserId'] ?? '').toString(),
      status: KinshipCheckStatus.fromServerValue(json['status']),
      createdAt: (json['createdAt'] ?? '').toString(),
      expiresAt: (json['expiresAt'] ?? '').toString(),
      respondedAt: _nullableString(json['respondedAt']),
      result: resultRaw is Map<String, dynamic>
          ? BloodRelation.fromJson(resultRaw)
          : (resultRaw is Map
              ? BloodRelation.fromJson(Map<String, dynamic>.from(resultRaw))
              : null),
    );
  }
}

enum KinshipCheckStatus {
  pending,
  accepted,
  rejected,
  expired,
  unknown;

  String get serverValue {
    switch (this) {
      case KinshipCheckStatus.pending:
        return 'pending';
      case KinshipCheckStatus.accepted:
        return 'accepted';
      case KinshipCheckStatus.rejected:
        return 'rejected';
      case KinshipCheckStatus.expired:
        return 'expired';
      case KinshipCheckStatus.unknown:
        return 'unknown';
    }
  }

  static KinshipCheckStatus fromServerValue(Object? raw) {
    switch (raw?.toString()) {
      case 'pending':
        return KinshipCheckStatus.pending;
      case 'accepted':
        return KinshipCheckStatus.accepted;
      case 'rejected':
        return KinshipCheckStatus.rejected;
      case 'expired':
        return KinshipCheckStatus.expired;
      default:
        return KinshipCheckStatus.unknown;
    }
  }
}

/// Decision payload sent at respond time. Backend accepts только
/// `accepted` либо `rejected`; `expired` set'ится автоматически
/// после 14d (sweep, never client-driven).
enum KinshipCheckDecision {
  accepted,
  rejected;

  String get serverValue {
    switch (this) {
      case KinshipCheckDecision.accepted:
        return 'accepted';
      case KinshipCheckDecision.rejected:
        return 'rejected';
    }
  }
}

/// Result wrapper для create call. `created=false` означает
/// idempotent re-request (existing pending found, no new
/// notification dispatched).
class KinshipCheckCreateResult {
  const KinshipCheckCreateResult({
    required this.check,
    required this.created,
  });

  final KinshipCheck check;
  final bool created;

  factory KinshipCheckCreateResult.fromJson(Map<String, dynamic> json) {
    final checkRaw = json['check'];
    if (checkRaw is! Map) {
      throw const FormatException('kinship-check response без `check` field');
    }
    return KinshipCheckCreateResult(
      check: KinshipCheck.fromJson(Map<String, dynamic>.from(checkRaw)),
      created: json['created'] == true,
    );
  }
}

/// Error codes mirror'ются с backend (kinship-checks-routes.js).
/// UI surfaces «friendly» строку, не error code — но controller
/// keeps код для analytics + DECISIONS-traceability.
class KinshipCheckError implements Exception {
  const KinshipCheckError({
    required this.code,
    required this.message,
    this.retryAfterMs,
  });

  /// Code values: 'INVALID_INPUT' | 'SELF_CHECK_FORBIDDEN' |
  /// 'TARGET_NOT_FOUND' | 'REJECTION_COOLDOWN' | 'NOT_FOUND' |
  /// 'NOT_PENDING' | 'NETWORK' | 'UNKNOWN'.
  final String code;
  final String message;
  final int? retryAfterMs;

  @override
  String toString() => 'KinshipCheckError($code): $message';
}

String? _nullableString(Object? raw) {
  if (raw == null) return null;
  final s = raw.toString();
  if (s.isEmpty) return null;
  return s;
}
