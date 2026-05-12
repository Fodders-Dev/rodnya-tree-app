/// Phase 4 chunk 1 (PHASE-4-PROPOSAL.md §3.1): DTO для
/// `GET /v1/trees/:treeId/extended-network` response'а.
///
/// Slice — это BFS-вычисленный «расширенный» subgraph viewer'а,
/// фильтрованный через privacy fence (`_connectedVisibilityMaxHops
/// = 4`). Каждый node — preview shape (id + name + photo +
/// birth/death + isAlive + hop distance); полные attributes lazy
/// fetch'ются tap-on-node (Phase 4 chunk 4 wireframe).
///
/// **ownerMap sparse** (DECISIONS.md 2026-05-12 nice-to-have #1):
/// содержит только foreign nodes (owner != viewer). Для viewer-
/// owned nodes — null returned, UI helper отображает как «моя
/// карточка».
class ExtendedNetworkSlice {
  const ExtendedNetworkSlice({
    required this.graphPersons,
    required this.graphRelations,
    required this.branchMembership,
    required this.ownerMap,
    required this.stats,
  });

  final List<ExtendedNetworkPerson> graphPersons;
  final List<ExtendedNetworkRelation> graphRelations;

  /// `graphPersonId → list of treeIds` где этот person представлен
  /// как `persons.identityId`. Даёт UI'ю signal «этот узел также
  /// есть в моей ветке X».
  final Map<String, List<String>> branchMembership;

  /// Sparse: только foreign nodes. Lookup через
  /// [getOwnerInfo] (returns null для viewer-owned).
  final Map<String, ExtendedNetworkOwnerInfo> ownerMap;

  final ExtendedNetworkStats stats;

  /// Sparse-aware lookup: null для viewer-owned nodes.
  ExtendedNetworkOwnerInfo? getOwnerInfo(String graphPersonId) {
    return ownerMap[graphPersonId];
  }

  /// True если этот node принадлежит другому юзеру (явный entry
  /// в sparse ownerMap).
  bool isForeignNode(String graphPersonId) {
    return ownerMap.containsKey(graphPersonId);
  }

  factory ExtendedNetworkSlice.fromJson(Map<String, dynamic> json) {
    final personsRaw = json['graphPersons'];
    final relationsRaw = json['graphRelations'];
    final branchMembershipRaw = json['branchMembership'];
    final ownerMapRaw = json['ownerMap'];
    final statsRaw = json['stats'];

    final persons = <ExtendedNetworkPerson>[];
    if (personsRaw is List) {
      for (final entry in personsRaw) {
        if (entry is Map<String, dynamic>) {
          persons.add(ExtendedNetworkPerson.fromJson(entry));
        }
      }
    }
    final relations = <ExtendedNetworkRelation>[];
    if (relationsRaw is List) {
      for (final entry in relationsRaw) {
        if (entry is Map<String, dynamic>) {
          relations.add(ExtendedNetworkRelation.fromJson(entry));
        }
      }
    }
    final branchMembership = <String, List<String>>{};
    if (branchMembershipRaw is Map) {
      branchMembershipRaw.forEach((key, value) {
        if (value is List) {
          branchMembership[key.toString()] = value
              .where((e) => e != null)
              .map((e) => e.toString())
              .toList(growable: false);
        }
      });
    }
    final ownerMap = <String, ExtendedNetworkOwnerInfo>{};
    if (ownerMapRaw is Map) {
      ownerMapRaw.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          ownerMap[key.toString()] =
              ExtendedNetworkOwnerInfo.fromJson(value);
        }
      });
    }
    final stats = statsRaw is Map<String, dynamic>
        ? ExtendedNetworkStats.fromJson(statsRaw)
        : const ExtendedNetworkStats(
            totalCount: 0,
            myCount: 0,
            extendedCount: 0,
            anonymousCount: 0,
            maxHopsReached: false,
            capReached: false,
          );
    return ExtendedNetworkSlice(
      graphPersons: persons,
      graphRelations: relations,
      branchMembership: branchMembership,
      ownerMap: ownerMap,
      stats: stats,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'graphPersons': graphPersons.map((p) => p.toJson()).toList(),
      'graphRelations': graphRelations.map((r) => r.toJson()).toList(),
      'branchMembership': branchMembership,
      'ownerMap': {
        for (final entry in ownerMap.entries) entry.key: entry.value.toJson(),
      },
      'stats': stats.toJson(),
    };
  }

  static const ExtendedNetworkSlice empty = ExtendedNetworkSlice(
    graphPersons: <ExtendedNetworkPerson>[],
    graphRelations: <ExtendedNetworkRelation>[],
    branchMembership: <String, List<String>>{},
    ownerMap: <String, ExtendedNetworkOwnerInfo>{},
    stats: ExtendedNetworkStats(
      totalCount: 0,
      myCount: 0,
      extendedCount: 0,
      anonymousCount: 0,
      maxHopsReached: false,
      capReached: false,
    ),
  );
}

class ExtendedNetworkPerson {
  const ExtendedNetworkPerson({
    required this.id,
    required this.name,
    required this.gender,
    required this.birthDate,
    required this.deathDate,
    required this.photoUrl,
    required this.isAlive,
    required this.hopDistance,
  });

  final String id;
  final String? name;
  final String? gender;
  final String? birthDate;
  final String? deathDate;
  final String? photoUrl;
  final bool isAlive;

  /// BFS distance от viewer'а (0 = self-node). Используется для
  /// generation-based filter chips в UI (Phase 4 chunk 2).
  final int hopDistance;

  factory ExtendedNetworkPerson.fromJson(Map<String, dynamic> json) {
    return ExtendedNetworkPerson(
      id: (json['id'] ?? '').toString(),
      name: _nullableString(json['name']),
      gender: _nullableString(json['gender']),
      birthDate: _nullableString(json['birthDate']),
      deathDate: _nullableString(json['deathDate']),
      photoUrl: _nullableString(json['photoUrl']),
      isAlive: json['isAlive'] != false,
      hopDistance: _intOrZero(json['hopDistance']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'gender': gender,
      'birthDate': birthDate,
      'deathDate': deathDate,
      'photoUrl': photoUrl,
      'isAlive': isAlive,
      'hopDistance': hopDistance,
    };
  }
}

class ExtendedNetworkRelation {
  const ExtendedNetworkRelation({
    required this.id,
    required this.person1Id,
    required this.person2Id,
    required this.relation1to2,
    required this.relation2to1,
  });

  final String id;
  final String person1Id;
  final String person2Id;
  final String? relation1to2;
  final String? relation2to1;

  factory ExtendedNetworkRelation.fromJson(Map<String, dynamic> json) {
    return ExtendedNetworkRelation(
      id: (json['id'] ?? '').toString(),
      person1Id: (json['person1Id'] ?? '').toString(),
      person2Id: (json['person2Id'] ?? '').toString(),
      relation1to2: _nullableString(json['relation1to2']),
      relation2to1: _nullableString(json['relation2to1']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'person1Id': person1Id,
      'person2Id': person2Id,
      'relation1to2': relation1to2,
      'relation2to1': relation2to1,
    };
  }
}

class ExtendedNetworkOwnerInfo {
  const ExtendedNetworkOwnerInfo({
    required this.userId,
    required this.displayName,
    required this.photoUrl,
  });

  /// `null` для anonymous-but-not-viewer nodes — например, если
  /// чей-то предок anonymous И creator не viewer (т.е.
  /// graphPerson.userId == null AND createdBy != viewer).
  final String? userId;

  final String? displayName;
  final String? photoUrl;

  factory ExtendedNetworkOwnerInfo.fromJson(Map<String, dynamic> json) {
    return ExtendedNetworkOwnerInfo(
      userId: _nullableString(json['userId']),
      displayName: _nullableString(json['displayName']),
      photoUrl: _nullableString(json['photoUrl']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'displayName': displayName,
      'photoUrl': photoUrl,
    };
  }
}

class ExtendedNetworkStats {
  const ExtendedNetworkStats({
    required this.totalCount,
    required this.myCount,
    required this.extendedCount,
    required this.anonymousCount,
    required this.maxHopsReached,
    required this.capReached,
  });

  final int totalCount;

  /// Persons где owner === viewer.
  final int myCount;

  /// `totalCount - myCount`.
  final int extendedCount;

  /// Persons без userId (anonymous predки). Не overlap'ит с
  /// myCount (anonymous person созданный viewer'ом считается в
  /// myCount если createdBy === viewer).
  final int anonymousCount;

  /// True если BFS hit `maxHops` limit (есть persons за пределом
  /// которые потенциально могут быть в Phase 5+ deeper view).
  final bool maxHopsReached;

  /// True если slice truncated to cap (1000 default, override'ится
  /// в test'ах). UI показывает hint «Сузить через фильтры».
  final bool capReached;

  factory ExtendedNetworkStats.fromJson(Map<String, dynamic> json) {
    return ExtendedNetworkStats(
      totalCount: _intOrZero(json['totalCount']),
      myCount: _intOrZero(json['myCount']),
      extendedCount: _intOrZero(json['extendedCount']),
      anonymousCount: _intOrZero(json['anonymousCount']),
      maxHopsReached: json['maxHopsReached'] == true,
      capReached: json['capReached'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalCount': totalCount,
      'myCount': myCount,
      'extendedCount': extendedCount,
      'anonymousCount': anonymousCount,
      'maxHopsReached': maxHopsReached,
      'capReached': capReached,
    };
  }
}

String? _nullableString(Object? raw) {
  if (raw == null) return null;
  final s = raw.toString();
  if (s.isEmpty) return null;
  return s;
}

int _intOrZero(Object? raw) {
  if (raw == null) return 0;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  final parsed = int.tryParse(raw.toString());
  return parsed ?? 0;
}
