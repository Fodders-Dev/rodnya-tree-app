import '../utils/url_utils.dart';
import 'reaction_summary.dart';

class Comment {
  final String id;
  final String postId;
  final String authorId;
  final String? authorName;
  final String? _authorPhotoUrl;
  final String content;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? editedAt;
  final int likeCount;
  final List<String> likedBy;

  /// Aggregated emoji reactions on this comment. Backwards-compatible
  /// default empty list — older /v1/posts/:id/comments payloads
  /// without a reactions field deserialise as no reactions.
  final List<ReactionSummary> reactions;

  /// Two-level threading anchor. `null` for top-level comments;
  /// otherwise points at the id of the top-level comment this reply
  /// belongs to. Backend collapses replies-to-replies onto the
  /// canonical top-level parent so this field is always either null
  /// or a top-level id, never another reply's id.
  final String? parentCommentId;

  String? get authorPhotoUrl => _authorPhotoUrl;

  bool get isReply => parentCommentId != null && parentCommentId!.isNotEmpty;
  bool get isEdited => editedAt != null;

  Comment({
    required this.id,
    required this.postId,
    required this.authorId,
    this.authorName,
    String? authorPhotoUrl,
    required this.content,
    required this.createdAt,
    this.updatedAt,
    this.editedAt,
    this.likeCount = 0,
    this.likedBy = const [],
    List<ReactionSummary>? reactions,
    this.parentCommentId,
  })  : _authorPhotoUrl = UrlUtils.normalizeImageUrl(authorPhotoUrl),
        reactions = reactions ?? const <ReactionSummary>[];

  factory Comment.fromJson(Map<String, dynamic> json) {
    final parentRaw = json['parentCommentId']?.toString();
    return Comment(
      id: json['id']?.toString() ?? '',
      postId: json['postId']?.toString() ?? '',
      authorId: json['authorId']?.toString() ?? '',
      authorName: json['authorName']?.toString(),
      authorPhotoUrl: json['authorPhotoUrl']?.toString(),
      content: json['content']?.toString() ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'].toString())
          : DateTime.now(),
      updatedAt: _parseDate(json['updatedAt']),
      editedAt: _parseDate(json['editedAt']),
      likeCount: json['likeCount'] ?? 0,
      likedBy: (json['likedBy'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      reactions: ReactionSummary.listFromDynamic(json['reactions']),
      parentCommentId:
          (parentRaw == null || parentRaw.isEmpty) ? null : parentRaw,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'postId': postId,
      'authorId': authorId,
      'authorName': authorName,
      'authorPhotoUrl': authorPhotoUrl,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'editedAt': editedAt?.toIso8601String(),
      'likeCount': likeCount,
      'likedBy': likedBy,
      'reactions': reactions.map((r) => r.toMap()).toList(),
      'parentCommentId': parentCommentId,
    };
  }

  Comment copyWith({
    String? content,
    DateTime? updatedAt,
    DateTime? editedAt,
    List<ReactionSummary>? reactions,
  }) {
    return Comment(
      id: id,
      postId: postId,
      authorId: authorId,
      authorName: authorName,
      authorPhotoUrl: authorPhotoUrl,
      content: content ?? this.content,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      editedAt: editedAt ?? this.editedAt,
      likeCount: likeCount,
      likedBy: likedBy,
      reactions: reactions ?? this.reactions,
      parentCommentId: parentCommentId,
    );
  }

  Comment copyWithReactions(List<ReactionSummary> next) =>
      copyWith(reactions: next);

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    final raw = value.toString();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}
