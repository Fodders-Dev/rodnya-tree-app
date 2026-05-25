// Phase B Ship FE1: Semya entity model + membership + role enum.
//
// Backend collection: `semyi` (Latin transliteration). UI surface
// uses Cyrillic «семя/семья» — это purely identifier mismatch.
//
// Per ENTITY-DESIGN.md §1.1-§1.2 schema. Frontend consumes endpoints:
//   GET   /v1/me/semya
//   GET   /v1/semya/:id
//   POST  /v1/semya  (Ship FE2+ scope)
//   PATCH /v1/semya/:id (Ship FE2+)
//   DELETE /v1/semya/:id (Ship FE2+)

class Semya {
  const Semya({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.treeId,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.deletedAt,
  });

  final String id;
  final String name;
  final String ownerId;
  final String treeId;
  final String? description;
  final String createdAt;
  final String updatedAt;

  /// `null` для active семя. Populated when owner soft-delete'нул.
  /// Soft-deleted семьи скрываются из listSemyiForUser, поэтому
  /// frontend rarely sees this populated — но preserved для audit
  /// либо post-delete restore screens (90d window per Q5).
  final String? deletedAt;

  bool get isActive => deletedAt == null;

  factory Semya.fromJson(Map<String, dynamic> json) {
    return Semya(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      ownerId: (json['ownerId'] ?? '').toString(),
      treeId: (json['treeId'] ?? '').toString(),
      description: _nullableString(json['description']),
      createdAt: (json['createdAt'] ?? '').toString(),
      updatedAt: (json['updatedAt'] ?? '').toString(),
      deletedAt: _nullableString(json['deletedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ownerId': ownerId,
      'treeId': treeId,
      'description': description,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'deletedAt': deletedAt,
    };
  }

  Semya copyWith({
    String? name,
    String? description,
    String? updatedAt,
    String? deletedAt,
  }) {
    return Semya(
      id: id,
      name: name ?? this.name,
      ownerId: ownerId,
      treeId: treeId,
      description: description ?? this.description,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}

/// Member role (per ENTITY-DESIGN §2.1):
///   owner   — full control (rename, delete, role transitions)
///   editor  — add/edit persons; invite if `hasInviteGrant` (Q7)
///   viewer  — read-only access
enum SemyaRole {
  owner,
  editor,
  viewer,
  unknown;

  String get serverValue {
    switch (this) {
      case SemyaRole.owner:
        return 'owner';
      case SemyaRole.editor:
        return 'editor';
      case SemyaRole.viewer:
        return 'viewer';
      case SemyaRole.unknown:
        return 'unknown';
    }
  }

  static SemyaRole fromServerValue(Object? raw) {
    switch (raw?.toString()) {
      case 'owner':
        return SemyaRole.owner;
      case 'editor':
        return SemyaRole.editor;
      case 'viewer':
        return SemyaRole.viewer;
      default:
        return SemyaRole.unknown;
    }
  }

  /// Display label для UI chips. Russian per project UX language.
  String get displayLabel {
    switch (this) {
      case SemyaRole.owner:
        return 'Владелец';
      case SemyaRole.editor:
        return 'Редактор';
      case SemyaRole.viewer:
        return 'Зритель';
      case SemyaRole.unknown:
        return 'Не определена';
    }
  }
}

/// Membership row from GET /v1/semya/:id response либо
/// listMembershipsForSemya endpoint. `hasInviteGrant` meaningful
/// только для editor role (per ENTITY-DESIGN §3.4) — owner always
/// has implicit invite power; viewer cannot invite.
class SemyaMembership {
  const SemyaMembership({
    required this.id,
    required this.semyaId,
    required this.userId,
    required this.role,
    required this.joinedAt,
    this.invitedByUserId,
    this.hasInviteGrant = false,
  });

  final String id;
  final String semyaId;
  final String userId;
  final SemyaRole role;
  final String joinedAt;
  final String? invitedByUserId;
  final bool hasInviteGrant;

  factory SemyaMembership.fromJson(Map<String, dynamic> json) {
    return SemyaMembership(
      id: (json['id'] ?? '').toString(),
      semyaId: (json['semyaId'] ?? '').toString(),
      userId: (json['userId'] ?? '').toString(),
      role: SemyaRole.fromServerValue(json['role']),
      joinedAt: (json['joinedAt'] ?? '').toString(),
      invitedByUserId: _nullableString(json['invitedByUserId']),
      hasInviteGrant: json['hasInviteGrant'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'semyaId': semyaId,
      'userId': userId,
      'role': role.serverValue,
      'joinedAt': joinedAt,
      'invitedByUserId': invitedByUserId,
      'hasInviteGrant': hasInviteGrant,
    };
  }
}

/// Combined response shape от GET /v1/semya/:id — backend returns
/// {semya, membership} pair. Membership = caller's role в этой семе
/// (resolved via requireSemyaAccess middleware), saves second
/// roundtrip для UI permission checks.
class SemyaDetails {
  const SemyaDetails({
    required this.semya,
    required this.membership,
  });

  final Semya semya;
  final SemyaMembership membership;

  /// Convenience: caller's role в этой семе.
  SemyaRole get callerRole => membership.role;

  /// Convenience: can caller mutate persons/relations?
  bool get canEdit =>
      callerRole == SemyaRole.owner || callerRole == SemyaRole.editor;

  /// Convenience: can caller invite new members?
  bool get canInvite =>
      callerRole == SemyaRole.owner ||
      (callerRole == SemyaRole.editor && membership.hasInviteGrant);

  factory SemyaDetails.fromJson(Map<String, dynamic> json) {
    final semyaRaw = json['semya'];
    final memRaw = json['membership'];
    if (semyaRaw is! Map) {
      throw const FormatException('SemyaDetails response без `semya` field');
    }
    if (memRaw is! Map) {
      throw const FormatException(
        'SemyaDetails response без `membership` field',
      );
    }
    return SemyaDetails(
      semya: Semya.fromJson(Map<String, dynamic>.from(semyaRaw)),
      membership: SemyaMembership.fromJson(Map<String, dynamic>.from(memRaw)),
    );
  }
}

/// Backend error wrapper. Codes mirror'ятся с backend route files.
/// UI surfaces friendly message; controller keeps code для analytics.
class SemyaError implements Exception {
  const SemyaError({
    required this.code,
    required this.message,
  });

  /// Known codes:
  ///   'TREE_ALREADY_BOUND' | 'TREE_NOT_FOUND' | 'OWNER_NOT_FOUND'
  ///   | 'INVALID_NAME' | 'INVALID_OWNER_ID' | 'INVALID_TREE_ID'
  ///   | 'SEMYA_NOT_FOUND' | 'NOT_OWNER' | 'NETWORK' | 'UNKNOWN'.
  final String code;
  final String message;

  @override
  String toString() => 'SemyaError($code): $message';
}

String? _nullableString(Object? raw) {
  if (raw == null) return null;
  final s = raw.toString();
  if (s.isEmpty || s == 'null') return null;
  return s;
}
