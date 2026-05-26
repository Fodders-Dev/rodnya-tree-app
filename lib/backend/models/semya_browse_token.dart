/// Ship FE6a (2026-05-26): browse-token capability — owner-issued
/// shareable read-only link to семя's tree. Backend Ship 7 (5c00fc6).
///
/// Two shapes:
///   • [SemyaBrowseToken] — full record c plaintext secret (on create)
///   • [SemyaBrowseTokenSummary] — list view без secret (FE6b territory)
class SemyaBrowseToken {
  const SemyaBrowseToken({
    required this.id,
    required this.semyaId,
    required this.token,
    required this.createdByUserId,
    required this.createdAt,
    required this.expiresAt,
    this.revokedAt,
    this.lastUsedAt,
  });

  /// Token row id (used for revoke endpoint).
  final String id;
  final String semyaId;

  /// **Plaintext capability secret.** Leaks ONCE на create response.
  /// Subsequent listings (FE6b) return summary only. Frontend must
  /// surface immediately в share-modal без persistence.
  final String token;

  final String createdByUserId;
  final String createdAt;
  final String expiresAt;
  final String? revokedAt;
  final String? lastUsedAt;

  /// Public share URL — Andrid app links + web fallback.
  /// Format matches backend's expected resolve path.
  String get shareUrl => 'https://rodnya-tree.ru/browse/$token';

  bool get isActive {
    if (revokedAt != null && revokedAt!.isNotEmpty) return false;
    final expires = DateTime.tryParse(expiresAt);
    if (expires != null && expires.isBefore(DateTime.now())) return false;
    return true;
  }

  factory SemyaBrowseToken.fromJson(Map<String, dynamic> json) {
    return SemyaBrowseToken(
      id: (json['id'] ?? '').toString(),
      semyaId: (json['semyaId'] ?? '').toString(),
      token: (json['token'] ?? '').toString(),
      createdByUserId: (json['createdByUserId'] ?? '').toString(),
      createdAt: (json['createdAt'] ?? '').toString(),
      expiresAt: (json['expiresAt'] ?? '').toString(),
      revokedAt: _nullableString(json['revokedAt']),
      lastUsedAt: _nullableString(json['lastUsedAt']),
    );
  }
}

/// GET /v1/browse/:token response — server-resolved read-only payload.
///
/// Persons + relations carry minimal-shape fields per backend privacy
/// boundary (SHARED-TREE-PROPOSAL §3.5):
///   • Persons: name, maidenName, gender, birthDate, deathDate, identityId
///   • Relations: id, treeId, person1Id, person2Id, relation1to2, relation2to1
///
/// NO photos / bio / notes / sensitive attributes — backend filters.
class BrowsedSemyaTree {
  const BrowsedSemyaTree({
    required this.semyaId,
    required this.semyaName,
    required this.treeId,
    required this.treeName,
    required this.treeKind,
    required this.persons,
    required this.relations,
    required this.sessionExpiresAt,
    this.semyaDescription,
  });

  final String semyaId;
  final String semyaName;
  final String? semyaDescription;
  final String treeId;
  final String treeName;
  final String treeKind;
  final List<BrowsedPerson> persons;
  final List<BrowsedRelation> relations;
  final String sessionExpiresAt;

  factory BrowsedSemyaTree.fromJson(Map<String, dynamic> json) {
    final browse = json['browse'];
    if (browse is! Map<String, dynamic>) {
      throw const FormatException('browse response без `browse` field');
    }
    final semyaRaw = browse['semya'] as Map<String, dynamic>? ?? const {};
    final treeRaw = browse['tree'] as Map<String, dynamic>? ?? const {};
    final personsRaw = browse['persons'];
    final relationsRaw = browse['relations'];
    return BrowsedSemyaTree(
      semyaId: (semyaRaw['id'] ?? '').toString(),
      semyaName: (semyaRaw['name'] ?? '').toString(),
      semyaDescription: _nullableString(semyaRaw['description']),
      treeId: (treeRaw['id'] ?? '').toString(),
      treeName: (treeRaw['name'] ?? '').toString(),
      treeKind: (treeRaw['kind'] ?? 'family').toString(),
      persons: personsRaw is List
          ? personsRaw
              .whereType<Map>()
              .map((e) => BrowsedPerson.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const <BrowsedPerson>[],
      relations: relationsRaw is List
          ? relationsRaw
              .whereType<Map>()
              .map((e) => BrowsedRelation.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const <BrowsedRelation>[],
      sessionExpiresAt: (browse['sessionExpiresAt'] ?? '').toString(),
    );
  }
}

class BrowsedPerson {
  const BrowsedPerson({
    required this.id,
    required this.treeId,
    required this.name,
    this.maidenName,
    this.gender,
    this.birthDate,
    this.deathDate,
    this.identityId,
  });

  final String id;
  final String treeId;
  final String name;
  final String? maidenName;
  final String? gender; // 'male' | 'female' | 'unknown' либо null
  final String? birthDate;
  final String? deathDate;
  final String? identityId;

  factory BrowsedPerson.fromJson(Map<String, dynamic> json) {
    return BrowsedPerson(
      id: (json['id'] ?? '').toString(),
      treeId: (json['treeId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      maidenName: _nullableString(json['maidenName']),
      gender: _nullableString(json['gender']),
      birthDate: _nullableString(json['birthDate']),
      deathDate: _nullableString(json['deathDate']),
      identityId: _nullableString(json['identityId']),
    );
  }
}

class BrowsedRelation {
  const BrowsedRelation({
    required this.id,
    required this.treeId,
    required this.person1Id,
    required this.person2Id,
    this.relation1to2,
    this.relation2to1,
  });

  final String id;
  final String treeId;
  final String person1Id;
  final String person2Id;
  final String? relation1to2;
  final String? relation2to1;

  factory BrowsedRelation.fromJson(Map<String, dynamic> json) {
    return BrowsedRelation(
      id: (json['id'] ?? '').toString(),
      treeId: (json['treeId'] ?? '').toString(),
      person1Id: (json['person1Id'] ?? '').toString(),
      person2Id: (json['person2Id'] ?? '').toString(),
      relation1to2: _nullableString(json['relation1to2']),
      relation2to1: _nullableString(json['relation2to1']),
    );
  }
}

String? _nullableString(Object? raw) {
  if (raw == null) return null;
  final s = raw.toString();
  if (s.isEmpty || s == 'null') return null;
  return s;
}
