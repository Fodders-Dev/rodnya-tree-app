// Ship Q4a frontend (2026-05-28, Ship 31): deleted post DTO.
//
// Mirror backend `mapDeletedPost` (deleted-posts-routes.js:24).
// Snapshot carries full post state — UI reads content + media + dates
// directly. Comments + reaction snapshots opaque (server restores them).

class DeletedPost {
  const DeletedPost({
    required this.id,
    required this.originalPostId,
    required this.treeId,
    required this.snapshot,
    required this.deletedAt,
    this.deletedByUserId,
    required this.hardDeleteScheduledAt,
    required this.earliestHardDelete,
    this.restoredAt,
    this.restoredByUserId,
  });

  final String id;
  final String originalPostId;
  final String treeId;
  final Map<String, dynamic> snapshot;
  final String deletedAt;
  final String? deletedByUserId;
  final String hardDeleteScheduledAt;
  final String earliestHardDelete;
  final String? restoredAt;
  final String? restoredByUserId;

  /// Preview text (first 100 chars из content для list rendering).
  String get bodyPreview {
    final raw = snapshot['content'];
    if (raw is! String) return 'Удалённая публикация';
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Удалённая публикация (без текста)';
    return trimmed.length > 100
        ? '${trimmed.substring(0, 100)}…'
        : trimmed;
  }

  /// Первое медиа image URL для thumbnail если есть.
  String? get firstImageUrl {
    final raw = snapshot['imageUrls'];
    if (raw is List && raw.isNotEmpty) {
      final first = raw.first;
      if (first is String && first.trim().isNotEmpty) return first.trim();
    }
    return null;
  }

  bool isFloorPassed(DateTime now) {
    final ts = DateTime.tryParse(earliestHardDelete);
    if (ts == null) return true;
    return ts.isBefore(now);
  }

  int daysUntilHardDelete(DateTime now) {
    final ts = DateTime.tryParse(hardDeleteScheduledAt);
    if (ts == null) return 0;
    final diff = ts.difference(now).inDays;
    return diff < 0 ? 0 : diff;
  }

  factory DeletedPost.fromJson(Map<String, dynamic> json) {
    return DeletedPost(
      id: (json['id'] ?? '').toString(),
      originalPostId: (json['originalPostId'] ?? '').toString(),
      treeId: (json['treeId'] ?? '').toString(),
      snapshot: json['snapshot'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['snapshot'] as Map)
          : const <String, dynamic>{},
      deletedAt: (json['deletedAt'] ?? '').toString(),
      deletedByUserId: _nullableString(json['deletedByUserId']),
      hardDeleteScheduledAt:
          (json['hardDeleteScheduledAt'] ?? '').toString(),
      earliestHardDelete: (json['earliestHardDelete'] ?? '').toString(),
      restoredAt: _nullableString(json['restoredAt']),
      restoredByUserId: _nullableString(json['restoredByUserId']),
    );
  }
}

String? _nullableString(Object? raw) {
  if (raw == null) return null;
  final s = raw.toString();
  if (s.isEmpty || s == 'null') return null;
  return s;
}
