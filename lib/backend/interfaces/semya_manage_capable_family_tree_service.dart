import '../models/semya.dart';

/// Additive capability mixin for managing a [Semya] container (`POST /v1/semya`
/// and `PATCH /v1/semya/:id`) without breaking mocks implementing only
/// [SemyaCapableFamilyTreeService].
abstract class SemyaManageCapableFamilyTreeService {
  Future<Semya> createSemya({
    required String name,
    required String treeId,
    String? description,
  });

  Future<Semya> updateSemya({
    required String semyaId,
    String? name,
    String? description,
  });

  Future<Semya> deleteSemya(String semyaId);

  Future<Semya> restoreSemya(String semyaId);
}
