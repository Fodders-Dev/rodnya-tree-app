import '../../models/family_person.dart';

/// Step 2 selection-mode capability: services that can copy a set
/// of persons across trees in a single call AND bridge any
/// relations that should travel with them implement this.
///
/// Bulk-import preserves identity (same `identityId` across trees),
/// inherits person fields from the source (name / photo / dates /
/// gender — anything the legacy `mergePersonDataFromSource` path
/// already forwards) and bridges any source relation whose
/// endpoints can both be resolved on target — either because they
/// were just imported, or because target already has someone with
/// the same `identityId` (the user themselves being the canonical
/// case: their card on the target tree picks up the partner /
/// child / parent edge to the freshly-imported relative).
abstract class BulkImportCapableFamilyTreeService {
  /// Returns the list of persons that landed (skips duplicates) +
  /// the relations that were bridged. Throws on auth / network
  /// errors so the caller can surface a snackbar with retry copy.
  Future<BulkImportResult> bulkImportPersonsToTree({
    required String sourceTreeId,
    required String targetTreeId,
    required List<String> sourcePersonIds,
  });
}

/// Server response shape for the bulk-import endpoint. Persons are
/// the new (or existing-via-identity) target rows; bridgedRelations
/// are the relations that were created or short-circuited as
/// already-existing on target. Counts on the toolbar / snackbar
/// derive from these lists.
class BulkImportResult {
  const BulkImportResult({
    required this.persons,
    required this.bridgedRelationCount,
  });

  /// Persons that the server inserted into the target tree (or
  /// an empty list if every selection was already present via
  /// identity). The frontend uses `length` to render the
  /// "Добавлено: N" snackbar.
  final List<FamilyPerson> persons;

  /// Number of relations the server bridged. Currently no caller
  /// needs the full list — only the count for the snackbar — so
  /// the API stays minimal until a real consumer shows up.
  final int bridgedRelationCount;
}
