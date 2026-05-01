import '../../models/person_duplicate_suggestion.dart';

abstract class IdentityDuplicateCapableFamilyTreeService {
  Future<List<PersonDuplicateSuggestion>> getDuplicateSuggestions(
    String treeId,
  );
}
