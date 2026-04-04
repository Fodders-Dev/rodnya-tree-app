import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/url_utils.dart';

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
  }) : _authorPhotoUrl = UrlUtils.normalizeImageUrl(authorPhotoUrl);

  factory Comment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Comment(
      id: doc.id,
      postId: data['postId'] ?? '',
      authorId: data['authorId'] ?? '',
      authorName: data['authorName'],
      authorPhotoUrl: data['authorPhotoUrl'],
      content: data['content'] ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      likeCount: data['likeCount'] ?? 0,
      likedBy:
          data['likedBy'] != null ? List<String>.from(data['likedBy']) : [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'postId': postId,
      'authorId': authorId,
      'authorName': authorName,
      'authorPhotoUrl': authorPhotoUrl,
      'content': content,
      'createdAt': Timestamp.fromDate(createdAt),
      'likeCount': likeCount,
      'likedBy': likedBy,
    };
  }
}
