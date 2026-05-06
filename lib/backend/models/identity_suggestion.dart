import 'cross_tree_person_suggestion.dart';

/// A "voltage indicator" hint surfaced by the backend's matcher
/// for one of the user's persons: another person on a different
/// accessible tree that scores ≥ 0.78 on the identity matcher
/// AND isn't already linked via identityId AND wasn't dismissed.
///
/// The Flutter canvas renders a small 💡 dot on each card whose
/// suggestion list is non-empty; tap → popover → confirm-link or
/// dismiss. Confirm calls `linkIdentity(...)` (Phase 1.1
/// propagation kicks in from there); dismiss persists so the
/// suggestion doesn't keep re-surfacing.
class IdentitySuggestion {
  const IdentitySuggestion({
    required this.sourcePersonId,
    required this.sourceTreeId,
    required this.targetPersonId,
    required this.targetTreeId,
    required this.targetTreeName,
    required this.targetDisplayName,
    required this.score,
    required this.confidence,
    required this.reasons,
    this.targetPhotoUrl,
    this.targetBirthDate,
  });

  final String sourcePersonId;
  final String sourceTreeId;
  final String targetPersonId;
  final String targetTreeId;
  final String targetTreeName;
  final String targetDisplayName;
  final String? targetPhotoUrl;
  final String? targetBirthDate;

  /// 0.78–0.99. Anything below is filtered server-side and never
  /// reaches us.
  final double score;

  /// "high" (score ≥ 0.9) or "medium" (0.78–0.9). The UI uses
  /// this to color the 💡 (high = stronger accent) but doesn't
  /// gate behavior — both confidences require user confirmation.
  final String confidence;

  /// Human-readable evidence ("Совпадает ФИО", "Совпадает дата
  /// рождения", etc.) — surfaced in the popover so the user can
  /// decide whether to link.
  final List<String> reasons;

  factory IdentitySuggestion.fromJson(Map<String, dynamic> json) {
    final target =
        json['targetPerson'] is Map<String, dynamic>
            ? json['targetPerson'] as Map<String, dynamic>
            : const <String, dynamic>{};
    final reasonsRaw = json['reasons'];
    final reasons = reasonsRaw is List
        ? reasonsRaw.map((entry) => entry.toString()).toList(growable: false)
        : const <String>[];
    return IdentitySuggestion(
      sourcePersonId: (json['sourcePersonId'] ?? '').toString(),
      sourceTreeId: (json['sourceTreeId'] ?? '').toString(),
      targetPersonId: (json['targetPersonId'] ?? '').toString(),
      targetTreeId: (json['targetTreeId'] ?? '').toString(),
      targetTreeName: (json['targetTreeName'] ?? '').toString(),
      targetDisplayName: (target['name'] ?? '').toString(),
      targetPhotoUrl:
          (target['primaryPhotoUrl'] ?? target['photoUrl'])?.toString(),
      targetBirthDate: target['birthDate']?.toString(),
      score: (json['score'] is num) ? (json['score'] as num).toDouble() : 0.0,
      confidence: (json['confidence'] ?? 'medium').toString(),
      reasons: reasons,
    );
  }

  /// Convert into the lightweight DTO our cross-tree picker
  /// already knows how to render — useful when the popover
  /// re-uses the picker's row component for visual consistency.
  CrossTreePersonSuggestion toPickerSuggestion() {
    return CrossTreePersonSuggestion(
      id: targetPersonId,
      treeId: targetTreeId,
      treeName: targetTreeName,
      displayName: targetDisplayName,
      photoUrl: targetPhotoUrl,
      birthDate: targetBirthDate,
      gender: 'unknown',
    );
  }
}
