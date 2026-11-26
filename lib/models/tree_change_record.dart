class TreeChangeRecord {
  const TreeChangeRecord({
    required this.id,
    required this.treeId,
    required this.type,
    required this.createdAt,
    this.actorId,
    this.actorName,
    this.personId,
    this.personName,
    this.personIds = const <String>[],
    this.relationId,
    this.mediaId,
    this.details = const <String, dynamic>{},
  });

  final String id;
  final String treeId;
  final String? actorId;
  final String? actorName;
  final String type;
  final String? personId;
  final String? personName;
  final List<String> personIds;
  final String? relationId;
  final String? mediaId;
  final DateTime createdAt;
  final Map<String, dynamic> details;

  factory TreeChangeRecord.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final rawDetails = json['details'];

    return TreeChangeRecord(
      id: json['id']?.toString() ?? '',
      treeId: json['treeId']?.toString() ?? '',
      actorId: json['actorId']?.toString(),
      actorName: json['actorName']?.toString(),
      type: json['type']?.toString() ?? 'unknown',
      personId: json['personId']?.toString(),
      personName: json['personName']?.toString(),
      personIds: (json['personIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => value.toString())
          .toList(),
      relationId: json['relationId']?.toString(),
      mediaId: json['mediaId']?.toString(),
      createdAt: createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      details: rawDetails is Map<String, dynamic>
          ? Map<String, dynamic>.from(rawDetails)
          : const <String, dynamic>{},
    );
  }
}
