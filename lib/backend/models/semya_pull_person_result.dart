import '../../models/family_person.dart';

/// Ship FE5 (2026-05-26): результат POST /v1/semya/:targetSemyaId/
/// pull-person (backend Ship 6, eba1a25). Backend бэжет bulkImport
/// + identity link создание + tree_mutated dispatch.
///
/// `person` — imported (либо existing twin при idempotent re-pull)
/// row в target tree. `relations` — bridging rows бэкенд создал для
/// linkage. UI typically refreshes target tree вместо использования
/// relations directly.
class SemyaPullPersonResult {
  const SemyaPullPersonResult({
    required this.person,
    required this.targetSemyaId,
    required this.sourceSemyaId,
    required this.sourcePersonId,
  });

  /// Pulled person row (имя/dates/photo). `null` would indicate
  /// бэkend returned empty persons list — caller treats as soft
  /// failure (unlikely, но defensive).
  final FamilyPerson? person;

  final String targetSemyaId;
  final String sourceSemyaId;
  final String sourcePersonId;

  factory SemyaPullPersonResult.fromJson(Map<String, dynamic> json) {
    final personRaw = json['person'];
    FamilyPerson? person;
    if (personRaw is Map<String, dynamic>) {
      final id = personRaw['id']?.toString() ?? '';
      if (id.isNotEmpty) {
        person = FamilyPerson.fromMap(personRaw, id);
      }
    }
    return SemyaPullPersonResult(
      person: person,
      targetSemyaId: (json['targetSemyaId'] ?? '').toString(),
      sourceSemyaId: (json['sourceSemyaId'] ?? '').toString(),
      sourcePersonId: (json['sourcePersonId'] ?? '').toString(),
    );
  }
}
