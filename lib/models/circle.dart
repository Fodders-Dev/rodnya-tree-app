enum FamilyCircleKind {
  allTree,
  favorites,
  descendantsOf,
  ancestorsOf,
  pair,
  custom,
}

class FamilyCircle {
  const FamilyCircle({
    required this.id,
    required this.treeId,
    required this.kind,
    required this.name,
    this.description,
    this.createdBy,
    this.anchorPersonId,
    this.anchorPersonIds = const [],
    required this.isSystem,
    required this.memberCount,
    required this.createdAt,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? createdAt;

  final String id;
  final String treeId;
  final FamilyCircleKind kind;
  final String name;
  final String? description;
  final String? createdBy;
  final String? anchorPersonId;
  final List<String> anchorPersonIds;
  final bool isSystem;
  final int memberCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isAllTree => kind == FamilyCircleKind.allTree;
  bool get isFavorites => kind == FamilyCircleKind.favorites;
  bool get isAuto =>
      kind == FamilyCircleKind.descendantsOf ||
      kind == FamilyCircleKind.ancestorsOf ||
      kind == FamilyCircleKind.pair;

  factory FamilyCircle.fromJson(Map<String, dynamic> json) {
    return FamilyCircle(
      id: json['id']?.toString() ?? '',
      treeId: json['treeId']?.toString() ?? '',
      kind: _kindFromString(json['kind']?.toString()),
      name: json['name']?.toString().trim().isNotEmpty == true
          ? json['name'].toString().trim()
          : 'Круг',
      description: json['description']?.toString(),
      createdBy: json['createdBy']?.toString(),
      anchorPersonId: json['anchorPersonId']?.toString(),
      anchorPersonIds: _stringList(json['anchorPersonIds']),
      isSystem: json['isSystem'] == true,
      memberCount: int.tryParse(json['memberCount']?.toString() ?? '') ?? 0,
      createdAt: _parseDate(json['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'treeId': treeId,
      'kind': _kindToString(kind),
      'name': name,
      'description': description,
      'createdBy': createdBy,
      'anchorPersonId': anchorPersonId,
      'anchorPersonIds': anchorPersonIds,
      'isSystem': isSystem,
      'memberCount': memberCount,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static FamilyCircleKind _kindFromString(String? value) {
    switch (value) {
      case 'all_tree':
        return FamilyCircleKind.allTree;
      case 'favorites':
        return FamilyCircleKind.favorites;
      case 'descendants_of':
        return FamilyCircleKind.descendantsOf;
      case 'ancestors_of':
        return FamilyCircleKind.ancestorsOf;
      case 'pair':
        return FamilyCircleKind.pair;
      default:
        return FamilyCircleKind.custom;
    }
  }

  static String _kindToString(FamilyCircleKind value) {
    switch (value) {
      case FamilyCircleKind.allTree:
        return 'all_tree';
      case FamilyCircleKind.favorites:
        return 'favorites';
      case FamilyCircleKind.descendantsOf:
        return 'descendants_of';
      case FamilyCircleKind.ancestorsOf:
        return 'ancestors_of';
      case FamilyCircleKind.pair:
        return 'pair';
      case FamilyCircleKind.custom:
        return 'custom';
    }
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value
        .map((entry) => entry?.toString().trim() ?? '')
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value.toString());
  }
}
