/// A Phase 1.3 edit-time conflict: identity propagation tried to
/// overwrite a field on a person that the user had locally edited
/// since the last sync. The propagator skipped the overwrite and
/// recorded the divergence; the user resolves it later via
/// [resolveIdentityConflict] with `keep` (target wins) or
/// `overwrite` (source wins).
///
/// Surfaced on the canvas as a small ⚠️ dot on the affected card —
/// passive nudge, no modal interruption (mirrors the Phase 1.2 💡
/// indicator's design intent).
class IdentityFieldConflict {
  const IdentityFieldConflict({
    required this.id,
    required this.identityId,
    required this.sourcePersonId,
    required this.sourceTreeId,
    required this.targetPersonId,
    required this.targetTreeId,
    required this.field,
    required this.sourceValue,
    required this.targetValue,
    required this.createdAt,
    this.updatedAt,
    this.resolvedAt,
    this.resolvedBy,
  });

  final String id;
  final String identityId;
  final String sourcePersonId;
  final String sourceTreeId;
  final String targetPersonId;
  final String targetTreeId;

  /// The single canonical field that diverged (e.g. "name",
  /// "birthDate", "photoUrl"). Always one of
  /// `_identityPropagationFields` on the backend.
  final String field;

  /// What the source side now holds — what propagation would have
  /// written if there had been no local edit. Type matches the
  /// backing field: scalar for most, list for `photoGallery`.
  final dynamic sourceValue;

  /// What the target side currently holds — the user's local edit
  /// that the propagator declined to overwrite.
  final dynamic targetValue;

  final String createdAt;
  final String? updatedAt;
  final String? resolvedAt;
  final String? resolvedBy;

  bool get isResolved => resolvedAt != null && resolvedAt!.isNotEmpty;

  factory IdentityFieldConflict.fromJson(Map<String, dynamic> json) {
    return IdentityFieldConflict(
      id: (json['id'] ?? '').toString(),
      identityId: (json['identityId'] ?? '').toString(),
      sourcePersonId: (json['sourcePersonId'] ?? '').toString(),
      sourceTreeId: (json['sourceTreeId'] ?? '').toString(),
      targetPersonId: (json['targetPersonId'] ?? '').toString(),
      targetTreeId: (json['targetTreeId'] ?? '').toString(),
      field: (json['field'] ?? '').toString(),
      sourceValue: json['sourceValue'],
      targetValue: json['targetValue'],
      createdAt: (json['createdAt'] ?? '').toString(),
      updatedAt: json['updatedAt']?.toString(),
      resolvedAt: json['resolvedAt']?.toString(),
      resolvedBy: json['resolvedBy']?.toString(),
    );
  }
}
