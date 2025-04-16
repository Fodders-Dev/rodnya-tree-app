import 'package:cloud_firestore/cloud_firestore.dart';

class Post {
  final String id;
  final String treeId;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;
  final String content;
  final List<String>? imageUrls;
  final DateTime createdAt;
  final List<String> likedBy; // Список user ID
  final int commentCount;
  final bool isPublic;

  // Геттер для удобства
  int get likeCount => likedBy.length;

  Post({
    required this.id,
    required this.treeId,
    required this.authorId,
    required this.authorName,
    this.authorPhotoUrl,
    required this.content,
    this.imageUrls,
    required this.createdAt,
    List<String>? likedBy, // Делаем nullable для удобства в fromFirestore
    this.commentCount = 0,
    this.isPublic = false,
  }) : likedBy = likedBy ?? []; // Инициализируем пустым списком, если null

  factory Post.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Post(
      id: doc.id,
      treeId: data['treeId'] ?? '',
      authorId: data['authorId'] ?? '',
      authorName: data['authorName'] ?? 'Аноним',
      authorPhotoUrl: data['authorPhotoUrl'] as String?,
      content: data['content'] ?? '',
      imageUrls: (data['imageUrls'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      likedBy: (data['likedBy'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      commentCount: data['commentCount'] ?? 0,
      isPublic: data['isPublic'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'treeId': treeId,
      'authorId': authorId,
      'authorName': authorName,
      'authorPhotoUrl': authorPhotoUrl,
      'content': content,
      'imageUrls': imageUrls,
      'createdAt': Timestamp.fromDate(createdAt),
      'likedBy': likedBy,
      'commentCount': commentCount,
      'isPublic': isPublic,
    };
  }
} 