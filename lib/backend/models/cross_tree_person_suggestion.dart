/// Lightweight DTO for the cross-tree person picker. The Flutter
/// add-relative screen calls `GET /v1/persons/search` and renders
/// these as the "Из моих других деревьев" suggestion list.
///
/// We keep this deliberately thin — only what the picker UI needs
/// to draw a row + tap to pre-fill. The full Person payload is
/// fetched on demand when (and if) the user actually picks a row.
/// Phase 0 of the unified-graph migration: see Phase 1 follow-ups
/// for upgrading this into a richer canonical PersonIdentity view.
class CrossTreePersonSuggestion {
  const CrossTreePersonSuggestion({
    required this.id,
    required this.treeId,
    required this.treeName,
    required this.displayName,
    this.identityId,
    this.photoUrl,
    this.birthDate,
    this.gender = 'unknown',
  });

  /// The source person's id (lives on `treeId`). When picked, this
  /// becomes the `sourcePersonId` field on the create-person POST,
  /// which causes the backend to share an `identityId` between the
  /// source and the new card.
  final String id;

  /// Phase 3.4 (DECISIONS.md ответ Q4): canonical graphPerson.id (=
  /// identityId) — нужен branch wizard'у для anchor
  /// descendants-of/ancestors-of. На старых backend'ах без Phase 3.4
  /// addendum'а — null; UI gracefully fall back на «выбор недоступен».
  final String? identityId;
  final String treeId;
  final String treeName;
  final String displayName;
  final String? photoUrl;

  /// Backend returns ISO-8601 — we keep it as a string here so the
  /// picker doesn't have to parse for a row that may never get
  /// tapped. The form widget that consumes a pick parses on demand.
  final String? birthDate;

  /// "male" | "female" | "unknown". Mirrors `Person.gender`.
  final String gender;

  factory CrossTreePersonSuggestion.fromJson(Map<String, dynamic> json) {
    final rawIdentityId = json['identityId'];
    return CrossTreePersonSuggestion(
      id: (json['id'] ?? '').toString(),
      identityId: rawIdentityId is String && rawIdentityId.isNotEmpty
          ? rawIdentityId
          : null,
      treeId: (json['treeId'] ?? '').toString(),
      treeName: (json['treeName'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      photoUrl:
          json['photoUrl'] is String && (json['photoUrl'] as String).isNotEmpty
              ? json['photoUrl'] as String
              : null,
      birthDate:
          json['birthDate'] is String && (json['birthDate'] as String).isNotEmpty
              ? json['birthDate'] as String
              : null,
      gender:
          (json['gender'] is String && (json['gender'] as String).isNotEmpty
                  ? json['gender'] as String
                  : 'unknown')
              .toString(),
    );
  }
}
