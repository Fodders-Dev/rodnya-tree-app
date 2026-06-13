class MergePersonPreview {
  const MergePersonPreview({
    required this.name,
    this.birthYear,
    this.contextLabel,
    this.ownership = 'other',
  });

  final String name;
  final String? birthYear;
  final String? contextLabel;

  /// A-copy: чья карточка — 'own' (ваша), 'shared' (общая) либо 'other'.
  /// Старый бэк без поля → 'other'.
  final String ownership;

  bool get isOwn => ownership == 'own';
  bool get isShared => ownership == 'shared';

  /// Бейдж владельца: «Ваша карточка» / «Общая» / «Карточка <имя>».
  String get ownershipBadge {
    if (isOwn) return 'Ваша карточка';
    if (isShared) return 'Общая';
    return 'Карточка: $name';
  }

  factory MergePersonPreview.fromJson(Map<String, dynamic> json) {
    return MergePersonPreview(
      name: json['name']?.toString().trim().isNotEmpty == true
          ? json['name'].toString().trim()
          : 'Без имени',
      birthYear: json['birthYear']?.toString(),
      contextLabel: json['contextLabel']?.toString().trim().isNotEmpty == true
          ? json['contextLabel'].toString().trim()
          : null,
      ownership: json['ownership']?.toString() == 'own'
          ? 'own'
          : json['ownership']?.toString() == 'shared'
              ? 'shared'
              : 'other',
    );
  }
}

/// K1: один ответственный за решение — имя (если бэк смог отрезолвить),
/// его голос и признак «это вы».
class MergeReviewer {
  const MergeReviewer({
    required this.userId,
    this.displayName,
    this.decision,
    this.isViewer = false,
  });

  final String userId;
  final String? displayName;

  /// 'accepted' | 'rejected' | null (ещё не голосовал).
  final String? decision;
  final bool isViewer;

  bool get hasDecided => decision != null;
  bool get accepted => decision == 'accepted';

  /// Тёплый лейбл для 50+: «Вы» / имя / нейтральный фолбэк без сырых id.
  String get label {
    if (isViewer) return 'Вы';
    final name = displayName?.trim();
    return (name != null && name.isNotEmpty) ? name : 'Родственник';
  }

  factory MergeReviewer.fromJson(Map<String, dynamic> json) {
    return MergeReviewer(
      userId: json['userId']?.toString() ?? '',
      displayName: json['displayName']?.toString().trim().isNotEmpty == true
          ? json['displayName'].toString().trim()
          : null,
      decision: json['decision']?.toString().trim().isNotEmpty == true
          ? json['decision'].toString().trim()
          : null,
      isViewer: json['isViewer'] == true,
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
    this.myDecision,
    bool? awaitingMyDecision,
    this.reviewers = const <MergeReviewer>[],
    this.resolvedAt,
  }) : _awaitingMyDecision = awaitingMyDecision;

  final String id;
  final String status;
  final double matchScore;
  final String confidence;
  final List<String> reasons;
  final MergePersonPreview personA;
  final MergePersonPreview personB;
  final int requiredReviewCount;
  final int reviewCount;

  /// K1: голос зрителя ('accepted' | 'rejected' | null).
  final String? myDecision;
  final bool? _awaitingMyDecision;

  /// K1: имена и статусы всех ответственных («Вы ✓ · Наталья — ждём»).
  final List<MergeReviewer> reviewers;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  bool get isPending => status == 'pending';

  /// Ждёт ли предложение решения ИМЕННО зрителя. Старый бэк поля не
  /// отдаёт — тогда фолбэк на прежнее поведение (pending = ждёт).
  bool get awaitingMyDecision => _awaitingMyDecision ?? isPending;

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
      myDecision: json['myDecision']?.toString().trim().isNotEmpty == true
          ? json['myDecision'].toString().trim()
          : null,
      awaitingMyDecision: json.containsKey('awaitingMyDecision')
          ? json['awaitingMyDecision'] == true
          : null,
      reviewers: (json['reviewers'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((entry) =>
              MergeReviewer.fromJson(Map<String, dynamic>.from(entry)))
          .toList(growable: false),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      resolvedAt: DateTime.tryParse(json['resolvedAt']?.toString() ?? ''),
    );
  }
}
