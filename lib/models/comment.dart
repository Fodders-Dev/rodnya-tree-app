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

  String? get authorPhotoUrl => _authorPhotoUrl;

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
  })  : _authorPhotoUrl = UrlUtils.normalizeImageUrl(authorPhotoUrl),
        reactions = reactions ?? const <ReactionSummary>[];

  factory Comment.fromJson(Map<String, dynamic> json) {
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
    );
  }
}
