import '../utils/date_parser.dart';
import '../utils/url_utils.dart';
import 'post.dart';

enum StoryType { text, image, video }

class Story {
  Story({
    required this.id,
    required this.treeId,
    required this.authorId,
    this.authorName = 'Аноним',
    String? authorPhotoUrl,
    required this.type,
    this.text,
    String? mediaUrl,
    String? thumbnailUrl,
    required this.createdAt,
    DateTime? updatedAt,
    required this.expiresAt,
    List<String>? viewedBy,
    this.isPublic = false,
    this.scopeType = TreeContentScopeType.wholeTree,
    List<String>? anchorPersonIds,
  })  : _authorPhotoUrl = UrlUtils.normalizeImageUrl(authorPhotoUrl),
        _mediaUrl = UrlUtils.normalizeImageUrl(mediaUrl),
        _thumbnailUrl = UrlUtils.normalizeImageUrl(thumbnailUrl),
        updatedAt = updatedAt ?? createdAt,
        viewedBy = viewedBy ?? const <String>[],
        anchorPersonIds = anchorPersonIds ?? const <String>[];

  final String id;
  final String treeId;
  final String authorId;
  final String authorName;
  final String? _authorPhotoUrl;
  final StoryType type;
  final String? text;
  final String? _mediaUrl;
  final String? _thumbnailUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime expiresAt;
  final List<String> viewedBy;
  final bool isPublic;
  final TreeContentScopeType scopeType;
  final List<String> anchorPersonIds;

  String? get authorPhotoUrl => _authorPhotoUrl;
  String? get mediaUrl => _mediaUrl;
  String? get thumbnailUrl => _thumbnailUrl;
  String? get familyTreeId => treeId;
  bool get hasMedia => mediaUrl != null && mediaUrl!.isNotEmpty;
  bool get hasText => (text ?? '').trim().isNotEmpty;
  bool get isVisual => type == StoryType.image || type == StoryType.video;

  factory Story.fromJson(Map<String, dynamic> json) {
    return Story(
      id: json['id']?.toString() ?? '',
      treeId:
          json['treeId']?.toString() ?? json['familyTreeId']?.toString() ?? '',
      authorId: json['authorId']?.toString() ?? '',
      authorName: json['authorName']?.toString().trim().isNotEmpty == true
          ? json['authorName'].toString().trim()
          : 'Аноним',
      authorPhotoUrl: json['authorPhotoUrl']?.toString() ??
          json['authorPhotoURL']?.toString(),
      type: storyTypeFromString(json['type']?.toString()),
      text: json['text']?.toString(),
      mediaUrl: json['mediaUrl']?.toString(),
      thumbnailUrl: json['thumbnailUrl']?.toString(),
      createdAt: parseDateTimeRequired(json['createdAt']),
      updatedAt:
          parseDateTime(json['updatedAt']) ?? parseDateTime(json['createdAt']),
      expiresAt: parseDateTimeRequired(json['expiresAt']),
      viewedBy: (json['viewedBy'] as List<dynamic>? ?? const <dynamic>[])
          .map((entry) => entry.toString())
          .toList(),
      isPublic: json['isPublic'] == true,
      scopeType: _scopeTypeFromString(json['scopeType']?.toString()),
      anchorPersonIds:
          (json['anchorPersonIds'] as List<dynamic>? ?? const <dynamic>[])
              .map((entry) => entry.toString())
              .toList(),
    );
  }

  factory Story.fromFirestore(dynamic doc) {
    final data = (doc.data() as Map<String, dynamic>? ?? <String, dynamic>{});
    return Story.fromJson(<String, dynamic>{
      'id': doc.id,
      ...data,
    });
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'treeId': treeId,
      'familyTreeId': treeId,
      'authorId': authorId,
      'authorName': authorName,
      'authorPhotoUrl': authorPhotoUrl,
      'type': storyTypeToString(type),
      'text': text,
      'mediaUrl': mediaUrl,
      'thumbnailUrl': thumbnailUrl,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'viewedBy': viewedBy,
      'isPublic': isPublic,
      'scopeType': _scopeTypeToString(scopeType),
      'anchorPersonIds': anchorPersonIds,
    };
  }

  Map<String, dynamic> toMap() => toJson();

  Story copyWith({
    String? id,
    String? treeId,
    String? authorId,
    String? authorName,
    String? authorPhotoUrl,
    StoryType? type,
    String? text,
    String? mediaUrl,
    String? thumbnailUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? expiresAt,
    List<String>? viewedBy,
    bool? isPublic,
    TreeContentScopeType? scopeType,
    List<String>? anchorPersonIds,
  }) {
    return Story(
      id: id ?? this.id,
      treeId: treeId ?? this.treeId,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      authorPhotoUrl: authorPhotoUrl ?? this.authorPhotoUrl,
      type: type ?? this.type,
      text: text ?? this.text,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      viewedBy: viewedBy ?? this.viewedBy,
      isPublic: isPublic ?? this.isPublic,
      scopeType: scopeType ?? this.scopeType,
      anchorPersonIds: anchorPersonIds ?? this.anchorPersonIds,
    );
  }

  bool isViewedBy(String userId) => viewedBy.contains(userId);

  bool isExpired({DateTime? now}) => (now ?? DateTime.now()).isAfter(expiresAt);

  static StoryType storyTypeFromString(String? value) {
    switch (value) {
      case 'image':
        return StoryType.image;
      case 'video':
        return StoryType.video;
      default:
        return StoryType.text;
    }
  }

  static String storyTypeToString(StoryType type) {
    switch (type) {
      case StoryType.image:
        return 'image';
      case StoryType.video:
        return 'video';
      case StoryType.text:
        return 'text';
    }
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
