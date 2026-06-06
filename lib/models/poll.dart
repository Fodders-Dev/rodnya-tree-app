import '../utils/url_utils.dart';
import 'post.dart' show TreeContentScopeType;

/// One poll choice — server-assigned [id] + display [text].
class PollOption {
  const PollOption({required this.id, required this.text});

  final String id;
  final String text;

  factory PollOption.fromMap(Map<String, dynamic> map) => PollOption(
        id: map['id']?.toString() ?? '',
        text: map['text']?.toString() ?? '',
      );

  Map<String, dynamic> toMap() => {'id': id, 'text': text};
}

/// Phase E4/E5: an «Опрос» (Poll). Mirrors [Gathering] for the shared
/// audience fields (treeId, branchIds, author*, scopeType, anchorPersonIds,
/// circleId) + imageUrls, plus poll-specific fields: question, options,
/// allowMultiple, closesAt. Per-user votes are carried as opaque response
/// maps ({userId, optionIds}).
class Poll {
  final String id;
  final String treeId;
  final List<String> branchIds;
  final String authorId;
  final String authorName;
  final String? _authorPhotoUrl;
  final List<String>? _imageUrls;
  final String question;
  final List<PollOption> options;
  final bool allowMultiple;
  final DateTime? closesAt;
  final TreeContentScopeType scopeType;
  final List<String> anchorPersonIds;
  final String? circleId;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// Opaque vote rows from the server: {userId, optionIds:[...]}.
  final List<Map<String, dynamic>> responses;

  String? get authorPhotoUrl => _authorPhotoUrl;
  String? get renderableAuthorPhotoUrl =>
      UrlUtils.isRenderableNetworkImageUrl(_authorPhotoUrl)
          ? _authorPhotoUrl
          : null;

  List<String>? get imageUrls => _imageUrls;
  List<String> get renderableImageUrls => (_imageUrls ?? const <String>[])
      .where(UrlUtils.isRenderableNetworkImageUrl)
      .toList(growable: false);

  // ── Vote tallies (Phase E5) ──
  /// Number of distinct voters (one row per user).
  int get totalVoters => responses.length;

  /// How many voters picked [optionId].
  int votesFor(String optionId) =>
      responses.where((r) => _optionIdsOf(r).contains(optionId)).length;

  /// The option ids [userId] voted for (empty if they haven't voted).
  List<String> myVotedOptionIds(String? userId) {
    if (userId == null || userId.isEmpty) return const [];
    for (final r in responses) {
      if (r['userId']?.toString() == userId) return _optionIdsOf(r);
    }
    return const [];
  }

  static List<String> _optionIdsOf(Map<String, dynamic> r) =>
      (r['optionIds'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList();

  /// Copy with a replaced response list — used for optimistic vote updates.
  Poll copyWith({
    List<Map<String, dynamic>>? responses,
    List<String>? imageUrls,
  }) {
    return Poll(
      id: id,
      treeId: treeId,
      branchIds: branchIds,
      authorId: authorId,
      authorName: authorName,
      authorPhotoUrl: authorPhotoUrl,
      imageUrls: imageUrls ?? this.imageUrls,
      question: question,
      options: options,
      allowMultiple: allowMultiple,
      closesAt: closesAt,
      scopeType: scopeType,
      anchorPersonIds: anchorPersonIds,
      circleId: circleId,
      createdAt: createdAt,
      updatedAt: updatedAt,
      responses: responses ?? this.responses,
    );
  }

  Poll({
    required this.id,
    required this.treeId,
    required this.authorId,
    required this.authorName,
    String? authorPhotoUrl,
    List<String>? imageUrls,
    required this.question,
    required this.options,
    this.allowMultiple = false,
    this.closesAt,
    this.scopeType = TreeContentScopeType.wholeTree,
    List<String>? anchorPersonIds,
    this.circleId,
    required this.createdAt,
    this.updatedAt,
    List<Map<String, dynamic>>? responses,
    List<String>? branchIds,
  })  : _authorPhotoUrl = UrlUtils.normalizeImageUrl(authorPhotoUrl),
        _imageUrls = imageUrls
            ?.map((url) => UrlUtils.normalizeImageUrl(url))
            .whereType<String>()
            .toList(),
        anchorPersonIds = anchorPersonIds ?? [],
        responses = responses ?? const <Map<String, dynamic>>[],
        branchIds =
            (branchIds == null || branchIds.isEmpty) ? [treeId] : branchIds;

  factory Poll.fromJson(Map<String, dynamic> json) {
    final rawBranchIds = (json['branchIds'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .where((s) => s.isNotEmpty)
        .toList();
    final rawOptions = (json['options'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => PollOption.fromMap(Map<String, dynamic>.from(e)))
        .toList();
    final rawResponses = (json['responses'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final rawImageUrls = (json['imageUrls'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList();
    return Poll(
      id: json['id']?.toString() ?? '',
      treeId: json['treeId']?.toString() ?? '',
      branchIds: rawBranchIds,
      authorId: json['authorId']?.toString() ?? '',
      authorName: json['authorName']?.toString() ?? 'Аноним',
      authorPhotoUrl: json['authorPhotoUrl'] as String?,
      imageUrls: rawImageUrls,
      question: json['question']?.toString() ?? '',
      options: rawOptions,
      allowMultiple: json['allowMultiple'] == true,
      closesAt: _parseDate(json['closesAt']),
      scopeType: _scopeTypeFromString(json['scopeType']?.toString()),
      anchorPersonIds: (json['anchorPersonIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      circleId: json['circleId']?.toString(),
      createdAt: _parseDate(json['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updatedAt']),
      responses: rawResponses,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'treeId': treeId,
      'branchIds': branchIds,
      'authorId': authorId,
      'authorName': authorName,
      'authorPhotoUrl': authorPhotoUrl,
      'imageUrls': imageUrls,
      'question': question,
      'options': options.map((o) => o.toMap()).toList(),
      'allowMultiple': allowMultiple,
      'closesAt': closesAt?.toIso8601String(),
      'scopeType': _scopeTypeToString(scopeType),
      'anchorPersonIds': anchorPersonIds,
      'circleId': circleId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'responses': responses,
    };
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    final raw = value.toString();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static TreeContentScopeType _scopeTypeFromString(String? value) {
    return value == 'branches'
        ? TreeContentScopeType.branches
        : TreeContentScopeType.wholeTree;
  }

  static String _scopeTypeToString(TreeContentScopeType value) {
    return value == TreeContentScopeType.branches ? 'branches' : 'wholeTree';
  }
}
