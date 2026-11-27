import '../backend_runtime_config.dart';
import 'semya.dart' show SemyaRole;

/// Ship FE3 (2026-05-26): семья invitation model.
///
/// Mirrors backend Ship 4 `mapInvitation` shape (semya-invitation-routes.js:28).
/// State machine: pending → accepted | declined | revoked | expired (30d lazy expiry).
///
/// `token` revealed только при создании (POST returns 201 с token);
/// subsequent GET list calls return token as well (per Ship 4 mapping),
/// но UI на recipient device gets token через share-link, не из list.
class SemyaInvitation {
  const SemyaInvitation({
    required this.id,
    required this.token,
    required this.semyaId,
    required this.inviterUserId,
    required this.role,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.recipientUserId,
    this.recipientEmail,
    this.recipientPhone,
    this.personId,
    this.acceptedAt,
    this.acceptedByUserId,
    this.declinedAt,
    this.declinedByUserId,
    this.revokedAt,
    this.revokedByUserId,
    this.expiredAt,
    this.semyaName,
    this.inviterName,
    this.targetPersonName,
    this.semyaDeleted = false,
  });

  final String id;
  final String token;
  final String semyaId;
  final String inviterUserId;
  final SemyaRole role;
  final SemyaInvitationStatus status;
  final String createdAt;
  final String expiresAt;
  final String? recipientUserId;
  final String? recipientEmail;
  final String? recipientPhone;
  final String? personId;
  final String? acceptedAt;
  final String? acceptedByUserId;
  final String? declinedAt;
  final String? declinedByUserId;
  final String? revokedAt;
  final String? revokedByUserId;
  final String? expiredAt;

  /// Ship FE9 (2026-05-27): denormalized семя name & preview metadata.
  final String? semyaName;
  final String? inviterName;
  final String? targetPersonName;
  final bool semyaDeleted;

  String get shareUrl {
    final base = BackendRuntimeConfig.current.publicAppUrl
        .trim()
        .replaceAll(RegExp(r'/+$'), '');
    return '$base/invite/${Uri.encodeComponent(token)}';
  }

  bool get isPending => status == SemyaInvitationStatus.pending;
  bool get isTerminal => !isPending;

  factory SemyaInvitation.fromJson(Map<String, dynamic> json) {
    return SemyaInvitation(
      id: (json['id'] ?? '').toString(),
      token: (json['token'] ?? '').toString(),
      semyaId: (json['semyaId'] ?? '').toString(),
      inviterUserId: (json['inviterUserId'] ?? '').toString(),
      role: SemyaRole.fromServerValue(json['role']),
      status: SemyaInvitationStatus.fromServerValue(json['status']),
      createdAt: (json['createdAt'] ?? '').toString(),
      expiresAt: (json['expiresAt'] ?? '').toString(),
      recipientUserId: _nullableString(json['recipientUserId']),
      recipientEmail: _nullableString(json['recipientEmail']),
      recipientPhone: _nullableString(json['recipientPhone']),
      personId: _nullableString(json['personId']),
      acceptedAt: _nullableString(json['acceptedAt']),
      acceptedByUserId: _nullableString(json['acceptedByUserId']),
      declinedAt: _nullableString(json['declinedAt']),
      declinedByUserId: _nullableString(json['declinedByUserId']),
      revokedAt: _nullableString(json['revokedAt']),
      revokedByUserId: _nullableString(json['revokedByUserId']),
      expiredAt: _nullableString(json['expiredAt']),
      semyaName: _nullableString(json['semyaName']),
      inviterName: _nullableString(json['inviterName']),
      targetPersonName: _nullableString(json['targetPersonName']),
      semyaDeleted: json['semyaDeleted'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'token': token,
      'semyaId': semyaId,
      'inviterUserId': inviterUserId,
      'role': role.serverValue,
      'status': status.serverValue,
      'createdAt': createdAt,
      'expiresAt': expiresAt,
      'recipientUserId': recipientUserId,
      'recipientEmail': recipientEmail,
      'recipientPhone': recipientPhone,
      'personId': personId,
      'acceptedAt': acceptedAt,
      'acceptedByUserId': acceptedByUserId,
      'declinedAt': declinedAt,
      'declinedByUserId': declinedByUserId,
      'revokedAt': revokedAt,
      'revokedByUserId': revokedByUserId,
      'expiredAt': expiredAt,
    };
  }

  /// Convenience: recipient display string (targetPersonName > email > phone > userId > 'Без получателя').
  String get recipientLabel {
    final target = targetPersonName?.trim();
    if (target != null && target.isNotEmpty) return target;
    final email = recipientEmail?.trim();
    if (email != null && email.isNotEmpty) return email;
    final phone = recipientPhone?.trim();
    if (phone != null && phone.isNotEmpty) return phone;
    final userId = recipientUserId?.trim();
    if (userId != null && userId.isNotEmpty) return userId;
    return 'Без получателя';
  }
}

enum SemyaInvitationStatus {
  pending,
  accepted,
  declined,
  revoked,
  expired,
  unknown;

  String get serverValue {
    switch (this) {
      case SemyaInvitationStatus.pending:
        return 'pending';
      case SemyaInvitationStatus.accepted:
        return 'accepted';
      case SemyaInvitationStatus.declined:
        return 'declined';
      case SemyaInvitationStatus.revoked:
        return 'revoked';
      case SemyaInvitationStatus.expired:
        return 'expired';
      case SemyaInvitationStatus.unknown:
        return 'unknown';
    }
  }

  static SemyaInvitationStatus fromServerValue(Object? raw) {
    switch (raw?.toString()) {
      case 'pending':
        return SemyaInvitationStatus.pending;
      case 'accepted':
        return SemyaInvitationStatus.accepted;
      case 'declined':
        return SemyaInvitationStatus.declined;
      case 'revoked':
        return SemyaInvitationStatus.revoked;
      case 'expired':
        return SemyaInvitationStatus.expired;
      default:
        return SemyaInvitationStatus.unknown;
    }
  }

  /// Russian label для UI badges. Matches design tokens / chips.
  String get displayLabel {
    switch (this) {
      case SemyaInvitationStatus.pending:
        return 'Ожидает';
      case SemyaInvitationStatus.accepted:
        return 'Принято';
      case SemyaInvitationStatus.declined:
        return 'Отклонено';
      case SemyaInvitationStatus.revoked:
        return 'Отозвано';
      case SemyaInvitationStatus.expired:
        return 'Истекло';
      case SemyaInvitationStatus.unknown:
        return 'Неизвестно';
    }
  }
}

/// Result от POST /v1/invitation/:token/accept. Backend returns
/// {invitation, membership} pair.
class SemyaInvitationAcceptResult {
  const SemyaInvitationAcceptResult({
    required this.invitation,
    required this.semyaId,
    required this.role,
    required this.membershipId,
    this.treeId,
    this.linkedPersonId,
  });

  final SemyaInvitation invitation;
  final String semyaId;
  final SemyaRole role;
  final String membershipId;
  final String? treeId;
  final String? linkedPersonId;

  factory SemyaInvitationAcceptResult.fromJson(Map<String, dynamic> json) {
    final invRaw = json['invitation'];
    final memRaw = json['membership'];
    if (invRaw is! Map) {
      throw const FormatException('accept response без `invitation` field');
    }
    final invitation = SemyaInvitation.fromJson(
      Map<String, dynamic>.from(invRaw),
    );
    final memMap =
        memRaw is Map ? Map<String, dynamic>.from(memRaw) : <String, dynamic>{};
    return SemyaInvitationAcceptResult(
      invitation: invitation,
      semyaId: (memMap['semyaId'] ?? invitation.semyaId).toString(),
      role: SemyaRole.fromServerValue(memMap['role']),
      membershipId: (memMap['id'] ?? '').toString(),
      treeId: _nullableString(json['treeId']),
      linkedPersonId: _nullableString(json['linkedPersonId']),
    );
  }
}

String? _nullableString(Object? raw) {
  if (raw == null) return null;
  final s = raw.toString();
  if (s.isEmpty || s == 'null') return null;
  return s;
}
