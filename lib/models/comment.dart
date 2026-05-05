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

  Comment({
    required this.id,
    required this.postId,
    required this.authorId,
    this.authorName,
    String? authorPhotoUrl,
    required this.content,
    required this.createdAt,
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
      'likeCount': likeCount,
      'likedBy': likedBy,
      'reactions': reactions.map((r) => r.toMap()).toList(),
      'parentCommentId': parentCommentId,
    };
  }

  Comment copyWithReactions(List<ReactionSummary> next) {
    return Comment(
      id: id,
      postId: postId,
      authorId: authorId,
      authorName: authorName,
      authorPhotoUrl: authorPhotoUrl,
      content: content,
      createdAt: createdAt,
      likeCount: likeCount,
      likedBy: likedBy,
      reactions: next,
      parentCommentId: parentCommentId,
    );
  }
}
