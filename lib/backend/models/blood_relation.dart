/// Phase 4: shape of the GET /v1/graph/relation response. The
/// backend BFS engine returns either a no-relation result
/// (`found = false`) or the shortest blood-relation path from
/// `from` to `to`, with hydrated chain previews and a Russian
/// label ("троюродная сестра" / "прабабушка" / etc.).
class BloodRelation {
  const BloodRelation({
    required this.found,
    required this.chain,
    required this.edges,
    required this.label,
    required this.degree,
  });

  final bool found;

  /// Hydrated previews of every graphPerson on the path from the
  /// "from" side to the "to" side. First entry is the requester,
  /// last is the target. Each preview carries id + name + gender
  /// + dates + photoUrl — minimum disclosure (no editorial fields,
  /// no contact info) so the relation feature doesn't leak data
  /// from branches the user can't access.
  final List<BloodRelationPersonPreview> chain;

  /// Edge labels along the chain. Length = chain.length - 1. Each
  /// entry is "parent" / "child" / "sibling". UI uses this for the
  /// arrow direction between avatars in the result strip.
  final List<String> edges;

  /// Russian human-readable relationship label, generated server-
  /// side: "мама" / "троюродная сестра" / "прабабушка" / etc.
  /// Empty string when [found] is false.
  final String label;

  /// Consanguinity degree — for the curious user. 1 for direct
  /// parent/child/sibling, 2 for grandparent / uncle / nephew, etc.
  final int degree;

  factory BloodRelation.fromJson(Map<String, dynamic> json) {
    final found = json['found'] == true;
    final chain = (json['chain'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((entry) => BloodRelationPersonPreview.fromJson(
              Map<String, dynamic>.from(entry),
            ))
        .toList(growable: false);
    final edges = (json['edges'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList(growable: false);
    return BloodRelation(
      found: found,
      chain: chain,
      edges: edges,
      label: (json['label'] ?? '').toString(),
      degree: (json['degree'] is num)
          ? (json['degree'] as num).toInt()
          : 0,
    );
  }

  static const empty = BloodRelation(
    found: false,
    chain: [],
    edges: [],
    label: '',
    degree: 0,
  );
}

/// Minimum-disclosure preview of one graphPerson on a relation
/// chain. Mirrors the shape returned by
/// `store.previewGraphPersonsByIds`. `id` is the graphPersonId
/// (= identityId), NOT the legacy treeId-keyed personId.
class BloodRelationPersonPreview {
  const BloodRelationPersonPreview({
    required this.id,
    required this.name,
    required this.gender,
    required this.birthDate,
    required this.deathDate,
    required this.photoUrl,
  });

  final String id;
  final String? name;
  final String? gender;
  final String? birthDate;
  final String? deathDate;
  final String? photoUrl;

  factory BloodRelationPersonPreview.fromJson(Map<String, dynamic> json) {
    return BloodRelationPersonPreview(
      id: (json['id'] ?? '').toString(),
      name: json['name']?.toString(),
      gender: json['gender']?.toString(),
      birthDate: json['birthDate']?.toString(),
      deathDate: json['deathDate']?.toString(),
      photoUrl: json['photoUrl']?.toString(),
    );
  }
}
