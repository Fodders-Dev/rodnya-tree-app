import 'semya.dart' show SemyaRole;

/// Ship FE3 (2026-05-26): семья invitation model.
///
/// Mirrors backend Ship 4 `mapInvitation` shape (semya-invitation-routes.js:28).
/// State machine: pending → accepted | revoked | expired (30d lazy expiry).
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
    this.acceptedAt,
    this.acceptedByUserId,
    this.revokedAt,
    this.revokedByUserId,
    this.expiredAt,
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
  final String? acceptedAt;
  final String? acceptedByUserId;
  final String? revokedAt;
  final String? revokedByUserId;
  final String? expiredAt;

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
      acceptedAt: _nullableString(json['acceptedAt']),
      acceptedByUserId: _nullableString(json['acceptedByUserId']),
      revokedAt: _nullableString(json['revokedAt']),
      revokedByUserId: _nullableString(json['revokedByUserId']),
      expiredAt: _nullableString(json['expiredAt']),
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
      'acceptedAt': acceptedAt,
      'acceptedByUserId': acceptedByUserId,
      'revokedAt': revokedAt,
      'revokedByUserId': revokedByUserId,
      'expiredAt': expiredAt,
    };
  }

  /// Convenience: recipient display string (email > phone > userId > '?').
  String get recipientLabel {
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
  revoked,
  expired,
  unknown;

  String get serverValue {
    switch (this) {
      case SemyaInvitationStatus.pending:
        return 'pending';
      case SemyaInvitationStatus.accepted:
        return 'accepted';
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
  });

  final SemyaInvitation invitation;
  final String semyaId;
  final SemyaRole role;
  final String membershipId;

  factory SemyaInvitationAcceptResult.fromJson(Map<String, dynamic> json) {
    final invRaw = json['invitation'];
    final memRaw = json['membership'];
    if (invRaw is! Map) {
      throw const FormatException('accept response без `invitation` field');
    }
    final invitation = SemyaInvitation.fromJson(
      Map<String, dynamic>.from(invRaw),
    );
    final memMap = memRaw is Map
        ? Map<String, dynamic>.from(memRaw)
        : <String, dynamic>{};
    return SemyaInvitationAcceptResult(
      invitation: invitation,
      semyaId: (memMap['semyaId'] ?? invitation.semyaId).toString(),
      role: SemyaRole.fromServerValue(memMap['role']),
      membershipId: (memMap['id'] ?? '').toString(),
    );
  }
}

String? _nullableString(Object? raw) {
  if (raw == null) return null;
  final s = raw.toString();
  if (s.isEmpty || s == 'null') return null;
  return s;
}
