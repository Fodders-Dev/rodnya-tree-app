// Ship Q4a frontend (2026-05-28, Ship 31): deleted person DTO.
//
// Mirror backend `mapDeletedPerson` (deleted-persons-routes.js:27).
// Snapshot is JSON map preserved verbatim — frontend reads name +
// photoUrl + birthDate fields directly. NOT typed FamilyPerson to
// avoid coupling — schema may evolve independently.

class DeletedPerson {
  const DeletedPerson({
    required this.id,
    required this.originalPersonId,
    required this.treeId,
    this.semyaId,
    required this.snapshot,
    required this.deletedAt,
    this.deletedByUserId,
    required this.hardDeleteScheduledAt,
    required this.earliestHardDelete,
    this.restoredAt,
    this.restoredByUserId,
  });

  final String id;
  final String originalPersonId;
  final String treeId;
  final String? semyaId;
  final Map<String, dynamic> snapshot;
  final String deletedAt;
  final String? deletedByUserId;
  final String hardDeleteScheduledAt;
  final String earliestHardDelete;
  final String? restoredAt;
  final String? restoredByUserId;

  /// Display name из snapshot. Falls back если name absent.
  String get displayName {
    final raw = snapshot['name'];
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    return 'Удалённая карточка';
  }

  /// Photo URL для avatar render если есть.
  String? get photoUrl {
    final raw = snapshot['photoUrl'];
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    return null;
  }

  /// True когда earliestHardDelete passed — manual «Удалить навсегда»
  /// available. До этого момента 3h floor блокирует button.
  bool isFloorPassed(DateTime now) {
    final ts = DateTime.tryParse(earliestHardDelete);
    if (ts == null) return true;
    return ts.isBefore(now);
  }

  /// Дней до автоматического hard-delete.
  int daysUntilHardDelete(DateTime now) {
    final ts = DateTime.tryParse(hardDeleteScheduledAt);
    if (ts == null) return 0;
    final diff = ts.difference(now).inDays;
    return diff < 0 ? 0 : diff;
  }

  factory DeletedPerson.fromJson(Map<String, dynamic> json) {
    return DeletedPerson(
      id: (json['id'] ?? '').toString(),
      originalPersonId: (json['originalPersonId'] ?? '').toString(),
      treeId: (json['treeId'] ?? '').toString(),
      semyaId: _nullableString(json['semyaId']),
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
