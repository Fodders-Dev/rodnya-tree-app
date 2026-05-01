class MergePersonPreview {
  const MergePersonPreview({
    required this.name,
    this.birthYear,
    this.contextLabel,
  });

  final String name;
  final String? birthYear;
  final String? contextLabel;

  factory MergePersonPreview.fromJson(Map<String, dynamic> json) {
    return MergePersonPreview(
      name: json['name']?.toString().trim().isNotEmpty == true
          ? json['name'].toString().trim()
          : 'Без имени',
      birthYear: json['birthYear']?.toString(),
      contextLabel: json['contextLabel']?.toString().trim().isNotEmpty == true
          ? json['contextLabel'].toString().trim()
          : null,
    );
  }
}

class MergeProposal {
  const MergeProposal({
    required this.id,
    required this.status,
    required this.matchScore,
    required this.confidence,
    required this.reasons,
    required this.personA,
    required this.personB,
    required this.createdAt,
    this.requiredReviewCount = 0,
    this.reviewCount = 0,
    this.resolvedAt,
  });

  final String id;
  final String status;
  final double matchScore;
  final String confidence;
  final List<String> reasons;
  final MergePersonPreview personA;
  final MergePersonPreview personB;
  final int requiredReviewCount;
  final int reviewCount;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  bool get isPending => status == 'pending';

  factory MergeProposal.fromJson(Map<String, dynamic> json) {
    return MergeProposal(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      matchScore: (json['matchScore'] as num?)?.toDouble() ?? 0,
      confidence: json['confidence']?.toString() ?? 'medium',
      reasons: (json['reasons'] as List<dynamic>? ?? const <dynamic>[])
          .map((reason) => reason.toString())
          .where((reason) => reason.trim().isNotEmpty)
          .toList(growable: false),
      personA: MergePersonPreview.fromJson(
        Map<String, dynamic>.from(json['personA'] as Map? ?? const {}),
      ),
      personB: MergePersonPreview.fromJson(
        Map<String, dynamic>.from(json['personB'] as Map? ?? const {}),
      ),
      requiredReviewCount: (json['requiredReviewCount'] as num?)?.toInt() ?? 0,
      reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      resolvedAt: DateTime.tryParse(json['resolvedAt']?.toString() ?? ''),
    );
  }
}
