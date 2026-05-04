/// Pre-computed smart-set "Моя семья" / "Близкие" for the current user
/// in a given tree. Backend computes the personId list at request
/// time off the relations graph; the frontend treats it as a tile in
/// the audience picker — tap = post.scopeType=branches with these
/// anchorPersonIds.
class AudiencePreset {
  const AudiencePreset({
    required this.key,
    required this.label,
    required this.description,
    required this.personIds,
  });

  /// Stable id (`core_family`, `close`, or any future preset). Used
  /// to pick the right icon / accent in the UI and for telemetry.
  final String key;
  final String label;
  final String description;
  final List<String> personIds;

  factory AudiencePreset.fromJson(Map<String, dynamic> json) {
    return AudiencePreset(
      key: (json['key'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      personIds: (json['personIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e.toString())
          .where((id) => id.isNotEmpty)
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'key': key,
        'label': label,
        'description': description,
        'personIds': personIds,
      };
}

/// Response shape from `GET /v1/trees/:treeId/audience-presets`. The
/// anchor identifies the user's primary person-card on the tree (the
/// graph node smart-сет'ы are computed from). When the user has no
/// person-card yet [anchorPersonId] is null and [presets] is empty —
/// UI degrades gracefully to "Всё дерево" only.
class AudiencePresetsResponse {
  const AudiencePresetsResponse({
    required this.anchorPersonId,
    required this.presets,
  });

  final String? anchorPersonId;
  final List<AudiencePreset> presets;

  factory AudiencePresetsResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['anchorPersonId']?.toString();
    return AudiencePresetsResponse(
      anchorPersonId: (raw == null || raw.isEmpty) ? null : raw,
      presets: (json['presets'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((e) => AudiencePreset.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
    );
  }

  static const empty = AudiencePresetsResponse(
    anchorPersonId: null,
    presets: <AudiencePreset>[],
  );
}
