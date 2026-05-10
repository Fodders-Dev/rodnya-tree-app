import '../models/edit_grant.dart';
import '../models/visibility_choice.dart';

/// Phase 3.4 (PHASE-3.4-UI-PROPOSAL §3.1): capability mixin для
/// всех graph-person owner-model endpoints (Phase 3.2 + 3.4-prep
/// commit'ы). Service implements это, и UI получает единый surface
/// для visibility toggle + grants CRUD + grants list.
///
/// Как и [IdentityConflictsCapableFamilyTreeService] — host
/// service implements optional. Старый backend без 3.2/3.4-prep
/// вернёт 404 на эти endpoints; UI gracefully скрывает controls
/// (visibility section / access screen).
abstract class GraphPersonAccessCapableFamilyTreeService {
  /// GET /v1/graph-persons/:id (visibility-gated). Для UI который
  /// рендерит visibility toggle — показать current state radio'у.
  /// Возвращает `null` если viewer не имеет access (404/403).
  Future<GraphPersonAccessSnapshot?> getGraphPersonAccessSnapshot({
    required String graphPersonId,
  });

  /// PATCH /v1/graph-persons/:id/visibility (owner-only). Ставит
  /// `visibilityOverride: true` независимо от value (юзер
  /// осознанно подтвердил выбор).
  Future<GraphPersonVisibility> setGraphPersonVisibility({
    required String graphPersonId,
    required VisibilityChoice choice,
  });

  /// DELETE /v1/graph-persons/:id/visibility-override (owner-only).
  /// Сбрасывает override → effective visibility снова определяется
  /// auto-resolution (deceased + 100 years → public).
  Future<GraphPersonVisibility> clearGraphPersonVisibilityOverride({
    required String graphPersonId,
  });

  /// POST /v1/graph-persons/:id/grants (owner-only). Idempotent —
  /// если active grant с таким (granteeUserId, scope) уже есть,
  /// возвращает existing row.
  Future<EditGrant> addGraphPersonGrant({
    required String graphPersonId,
    required String granteeUserId,
    required EditGrantScope scope,
  });

  /// DELETE /v1/graph-persons/:id/grants/:grantId (owner-only).
  /// Sets `revokedAt` = now, не drop row (audit trail).
  /// Idempotent — повторный revoke не меняет timestamp.
  Future<EditGrant> revokeGraphPersonGrant({
    required String graphPersonId,
    required String grantId,
  });

  /// GET /v1/graph-persons/:id/grants (owner-only). Возвращает
  /// все grants на this graphPerson (active + revoked, для audit).
  Future<List<EditGrant>> listGraphPersonGrants({
    required String graphPersonId,
  });

  /// GET /v1/me/edit-grants. Active + revoked-since-30d grants
  /// для viewer'а (incoming side).
  Future<List<EditGrant>> listMyEditGrants();

  /// GET /v1/me/issued-grants. Active + revoked-since-30d grants
  /// выписанные viewer'ом (outgoing side, Phase 3.4-prep).
  Future<List<EditGrant>> listMyIssuedGrants();
}
