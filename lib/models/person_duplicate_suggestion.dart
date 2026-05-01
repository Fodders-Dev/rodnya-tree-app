import 'family_person.dart';

class PersonDuplicateSuggestion {
  const PersonDuplicateSuggestion({
    required this.id,
    required this.treeId,
    required this.personA,
    required this.personB,
    required this.score,
    required this.confidence,
    required this.reasons,
  });

  final String id;
  final String treeId;
  final FamilyPerson personA;
  final FamilyPerson personB;
  final double score;
  final String confidence;
  final List<String> reasons;

  bool involves(String personId) =>
      personA.id == personId || personB.id == personId;

  FamilyPerson otherPersonFor(String personId) =>
      personA.id == personId ? personB : personA;

  factory PersonDuplicateSuggestion.fromJson(Map<String, dynamic> json) {
    final personAJson = json['personA'] is Map<String, dynamic>
        ? json['personA'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final personBJson = json['personB'] is Map<String, dynamic>
        ? json['personB'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final personAId = personAJson['id']?.toString() ?? '';
    final personBId = personBJson['id']?.toString() ?? '';

    return PersonDuplicateSuggestion(
      id: json['id']?.toString() ?? '',
      treeId: json['treeId']?.toString() ?? '',
      personA: FamilyPerson.fromMap(personAJson, personAId),
      personB: FamilyPerson.fromMap(personBJson, personBId),
      score: double.tryParse(json['score']?.toString() ?? '') ?? 0,
      confidence: json['confidence']?.toString() ?? 'medium',
      reasons: (json['reasons'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => value.toString())
          .where((value) => value.trim().isNotEmpty)
          .toList(growable: false),
    );
  }
}
