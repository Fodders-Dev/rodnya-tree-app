import '../models/cross_tree_person_suggestion.dart';

/// Capability interface for the Phase 0 cross-tree person picker.
/// Implemented by [CustomApiFamilyTreeService] and any test fake;
/// the add-relative screen tests for this with `is`-check, so a
/// service that doesn't implement it just doesn't show the picker.
///
/// Phase 1+ may grow this with a richer canonical-PersonIdentity
/// view; the picker only needs the lightweight summary today.
abstract class CrossTreePersonSearchCapableFamilyTreeService {
  Future<List<CrossTreePersonSuggestion>> searchPersonsAcrossOwnTrees({
    required String query,
    String? excludeTreeId,
    int limit = 20,
  });
}
