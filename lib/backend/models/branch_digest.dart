/// Phase 6.3: shape of the GET /v1/trees/:treeId/digest response.
/// Per-branch aggregate of "what's happening in this family this
/// week" — upcoming birthdays of living members, memorial
/// anniversaries, recent posts, newly-added persons.
class BranchDigest {
  const BranchDigest({
    required this.treeId,
    required this.treeName,
    required this.horizonDays,
    required this.generatedAt,
    required this.birthdays,
    required this.memorials,
    required this.recentPosts,
    required this.newPersons,
  });

  final String treeId;
  final String treeName;
  final int horizonDays;
  final DateTime generatedAt;
  final List<BranchDigestBirthday> birthdays;
  final List<BranchDigestMemorial> memorials;
  final List<BranchDigestPost> recentPosts;
  final List<BranchDigestNewPerson> newPersons;

  bool get isEmpty =>
      birthdays.isEmpty &&
      memorials.isEmpty &&
      recentPosts.isEmpty &&
      newPersons.isEmpty;

  factory BranchDigest.fromJson(Map<String, dynamic> json) {
    return BranchDigest(
      treeId: (json['treeId'] ?? '').toString(),
      treeName: (json['treeName'] ?? '').toString(),
      horizonDays: (json['horizonDays'] is num)
          ? (json['horizonDays'] as num).toInt()
          : 7,
      generatedAt: DateTime.tryParse((json['generatedAt'] ?? '').toString()) ??
          DateTime.now(),
      birthdays: ((json['birthdays'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map(
            (entry) => BranchDigestBirthday.fromJson(
              Map<String, dynamic>.from(entry),
            ),
          )
          .toList(growable: false),
      memorials: ((json['memorials'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map(
            (entry) => BranchDigestMemorial.fromJson(
              Map<String, dynamic>.from(entry),
            ),
          )
          .toList(growable: false),
      recentPosts: ((json['recentPosts'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map(
            (entry) =>
                BranchDigestPost.fromJson(Map<String, dynamic>.from(entry)),
          )
          .toList(growable: false),
      newPersons: ((json['newPersons'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map(
            (entry) => BranchDigestNewPerson.fromJson(
              Map<String, dynamic>.from(entry),
            ),
          )
          .toList(growable: false),
    );
  }
}

class BranchDigestBirthday {
  const BranchDigestBirthday({
    required this.personId,
    required this.name,
    required this.photoUrl,
    required this.birthDate,
    required this.daysUntil,
    required this.age,
  });

  final String personId;
  final String name;
  final String? photoUrl;
  final String? birthDate;
  final int daysUntil;
  final int age;

  factory BranchDigestBirthday.fromJson(Map<String, dynamic> json) {
    return BranchDigestBirthday(
      personId: (json['personId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      photoUrl: json['photoUrl']?.toString(),
      birthDate: json['birthDate']?.toString(),
      daysUntil: (json['daysUntil'] is num)
          ? (json['daysUntil'] as num).toInt()
          : 0,
      age: (json['age'] is num) ? (json['age'] as num).toInt() : 0,
    );
  }
}

class BranchDigestMemorial {
  const BranchDigestMemorial({
    required this.personId,
    required this.name,
    required this.photoUrl,
    required this.deathDate,
    required this.daysUntil,
    required this.yearsSince,
  });

  final String personId;
  final String name;
  final String? photoUrl;
  final String? deathDate;
  final int daysUntil;
  final int yearsSince;

  factory BranchDigestMemorial.fromJson(Map<String, dynamic> json) {
    return BranchDigestMemorial(
      personId: (json['personId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      photoUrl: json['photoUrl']?.toString(),
      deathDate: json['deathDate']?.toString(),
      daysUntil: (json['daysUntil'] is num)
          ? (json['daysUntil'] as num).toInt()
          : 0,
      yearsSince: (json['yearsSince'] is num)
          ? (json['yearsSince'] as num).toInt()
          : 0,
    );
  }
}

class BranchDigestPost {
  const BranchDigestPost({
    required this.postId,
    required this.authorId,
    required this.authorName,
    required this.authorPhotoUrl,
    required this.content,
    required this.imageUrls,
    required this.createdAt,
  });

  final String postId;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;
  final String content;
  final List<String> imageUrls;
  final DateTime? createdAt;

  factory BranchDigestPost.fromJson(Map<String, dynamic> json) {
    final rawImages = json['imageUrls'];
    final urls = rawImages is List
        ? rawImages.map((e) => e.toString()).toList(growable: false)
        : const <String>[];
    return BranchDigestPost(
      postId: (json['postId'] ?? '').toString(),
      authorId: (json['authorId'] ?? '').toString(),
      authorName: (json['authorName'] ?? '').toString(),
      authorPhotoUrl: json['authorPhotoUrl']?.toString(),
      content: (json['content'] ?? '').toString(),
      imageUrls: urls,
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
    );
  }
}

class BranchDigestNewPerson {
  const BranchDigestNewPerson({
    required this.personId,
    required this.name,
    required this.photoUrl,
    required this.createdAt,
  });

  final String personId;
  final String name;
  final String? photoUrl;
  final DateTime? createdAt;

  factory BranchDigestNewPerson.fromJson(Map<String, dynamic> json) {
    return BranchDigestNewPerson(
      personId: (json['personId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      photoUrl: json['photoUrl']?.toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
    );
  }
}
