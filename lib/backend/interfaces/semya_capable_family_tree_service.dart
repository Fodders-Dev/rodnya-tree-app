import '../models/semya.dart';

/// Phase B Ship FE1: capability mixin для семя read endpoints.
///
/// Implementation lives в [CustomApiFamilyTreeService]. Caps detection
/// `is SemyaCapableFamilyTreeService` returns false на older backends
/// без Phase B endpoints → UI hides семя switcher и falls back на
/// legacy tree provider (default OFF до Week 8 production rollout).
///
/// Methods return `null` либо empty list on network failure (graceful
/// degradation) — controller surface'ит generic «попробуйте позже»
/// rather than crashing UI. Known error codes throw [SemyaError]
/// чтобы UI мог render targeted copy (e.g. SEMYA_NOT_FOUND, NOT_OWNER).
///
/// Ship FE1 — read-only methods. Mutation endpoints (create/update/
/// delete, membership, invitations, pull-person, browse, hide filter)
/// come в later FE ships, each extending этот interface либо separate
/// capability mixin.
abstract class SemyaCapableFamilyTreeService {
  /// `GET /v1/me/semya`. Returns caller's семья (active membership
  /// only — soft-deleted семьи excluded).
  ///
  /// Empty list = caller has no семя yet (либо production migration
  /// не ran для этого user). UI shows «У вас пока нет семьи» empty
  /// state с CTA для create flow (FE2 scope).
  Future<List<Semya>> listMySemya();

  /// `GET /v1/semya/:id`. Returns combined семя metadata + caller's
  /// membership row. Permission gate (`requireSemyaAccess` viewer+)
  /// enforced server-side — returns null если 403/404.
  ///
  /// Soft-deleted семьи treated как not-found (404 in backend).
  ///
  /// Throws [SemyaError] для:
  ///   - SEMYA_NOT_FOUND (id mismatch либо soft-deleted)
  ///   - FORBIDDEN (caller not member)
  Future<SemyaDetails?> findSemyaById(String semyaId);
}
