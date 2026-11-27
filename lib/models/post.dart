import '../utils/url_utils.dart';
import 'reaction_summary.dart';

enum TreeContentScopeType { wholeTree, branches }

class Post {
  final String id;
  final String treeId;

  /// Phase 3.4: list of branch ids the post is published into.
  /// One post can land in several branches at once (e.g. one
  /// family photo posted to "Моя кровь" AND "Семья жены"). The
  /// primary [treeId] is always implicit in this list — older
  /// payloads that lack the field deserialise as `[treeId]`.
  final List<String> branchIds;
  final String authorId;
  final String authorName;
  final String? _authorPhotoUrl;
  final String content;
  final List<String>? _imageUrls;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? editedAt;
  final List<String> likedBy; // Список user ID
  final int commentCount;
  final bool isPublic;
  final TreeContentScopeType scopeType;
  final List<String> anchorPersonIds;
  final String? circleId;

  /// Aggregated emoji reactions (each entry = emoji + list of user IDs
  /// who picked it). Backwards-compatible default empty list — older
  /// /v1/posts payloads without a reactions field deserialise as no
  /// reactions, no breakage.
  final List<ReactionSummary> reactions;

  // Геттеры для нормализованных URL
  String? get authorPhotoUrl => _authorPhotoUrl;
  List<String>? get imageUrls => _imageUrls;
  List<String> get renderableImageUrls => (_imageUrls ?? const <String>[])
      .where(UrlUtils.isRenderableNetworkImageUrl)
      .toList(growable: false);
  String? get renderableAuthorPhotoUrl =>
      UrlUtils.isRenderableNetworkImageUrl(_authorPhotoUrl)
          ? _authorPhotoUrl
          : null;
  int get likeCount => likedBy.length;
  bool get isEdited => editedAt != null;

  Post({
    required this.id,
    required this.treeId,
    required this.authorId,
    required this.authorName,
    String? authorPhotoUrl,
    required this.content,
    List<String>? imageUrls,
    required this.createdAt,
    this.updatedAt,
    this.editedAt,
    List<String>? likedBy,
    this.commentCount = 0,
    this.isPublic = false,
    this.scopeType = TreeContentScopeType.wholeTree,
    List<String>? anchorPersonIds,
    this.circleId,
    List<ReactionSummary>? reactions,
    List<String>? branchIds,
  })  : _authorPhotoUrl = UrlUtils.normalizeImageUrl(authorPhotoUrl),
        _imageUrls = imageUrls
            ?.map((url) => UrlUtils.normalizeImageUrl(url))
            .whereType<String>()
            .toList(),
        likedBy = likedBy ?? [],
        anchorPersonIds = anchorPersonIds ?? [],
        reactions = reactions ?? const <ReactionSummary>[],
        // Default the audience to the primary tree when the
        // server response (or local construction) didn't include
        // branchIds. Keeps every post with a non-empty audience.
        branchIds =
            (branchIds == null || branchIds.isEmpty) ? [treeId] : branchIds;

  factory Post.fromJson(Map<String, dynamic> json) {
    final rawImageUrls = (json['imageUrls'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();

    final rawBranchIds = (json['branchIds'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .where((s) => s.isNotEmpty)
        .toList();
    return Post(
      id: json['id']?.toString() ?? '',
      treeId: json['treeId']?.toString() ?? '',
      branchIds: rawBranchIds,
      authorId: json['authorId']?.toString() ?? '',
      authorName: json['authorName']?.toString() ?? 'Аноним',
      authorPhotoUrl: json['authorPhotoUrl'] as String?,
      content: json['content']?.toString() ?? '',
      imageUrls: rawImageUrls,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'].toString())
          : DateTime.now(),
      updatedAt: _parseDate(json['updatedAt']),
      editedAt: _parseDate(json['editedAt']),
      likedBy: (json['likedBy'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      commentCount: json['commentCount'] ?? 0,
      isPublic: json['isPublic'] ?? false,
      scopeType: _scopeTypeFromString(json['scopeType']?.toString()),
      anchorPersonIds: (json['anchorPersonIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      circleId: json['circleId']?.toString(),
      reactions: ReactionSummary.listFromDynamic(json['reactions']),
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
      'content': content,
      'imageUrls': imageUrls,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'editedAt': editedAt?.toIso8601String(),
      'likedBy': likedBy,
      'commentCount': commentCount,
      'isPublic': isPublic,
      'scopeType': _scopeTypeToString(scopeType),
      'anchorPersonIds': anchorPersonIds,
      'circleId': circleId,
      'reactions': reactions.map((r) => r.toMap()).toList(),
    };
  }

  Post copyWith({
    String? content,
    DateTime? updatedAt,
    DateTime? editedAt,
    List<String>? likedBy,
    int? commentCount,
    List<ReactionSummary>? reactions,
    List<String>? imageUrls,
  }) {
    return Post(
      id: id,
      treeId: treeId,
      branchIds: branchIds,
      authorId: authorId,
      authorName: authorName,
      authorPhotoUrl: authorPhotoUrl,
      content: content ?? this.content,
      imageUrls: imageUrls ?? this.imageUrls,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      editedAt: editedAt ?? this.editedAt,
      likedBy: likedBy ?? this.likedBy,
      commentCount: commentCount ?? this.commentCount,
      isPublic: isPublic,
      scopeType: scopeType,
      anchorPersonIds: anchorPersonIds,
      circleId: circleId,
      reactions: reactions ?? this.reactions,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    final raw = value.toString();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static TreeContentScopeType _scopeTypeFromString(String? value) {
    switch (value) {
      case 'branches':
        return TreeContentScopeType.branches;
      default:
        return TreeContentScopeType.wholeTree;
    }
  }

  static String _scopeTypeToString(TreeContentScopeType value) {
    switch (value) {
      case TreeContentScopeType.branches:
        return 'branches';
      case TreeContentScopeType.wholeTree:
        return 'wholeTree';
    }
  }
}
