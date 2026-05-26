import '../models/semya.dart';
import '../models/semya_browse_token.dart';
import '../models/semya_invitation.dart';
import '../models/semya_pull_person_result.dart';

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

  /// Ship FE2 (2026-05-26): `GET /v1/semya/:id/memberships`. Returns
  /// list of all member rows для этой семя — used by SemyaDetailsScreen
  /// для render members list. Permission gate viewer+ (same as findSemyaById).
  ///
  /// Returns empty list при graceful failures (network, 403/404 → caller
  /// can fall back на empty state). Throws [SemyaError] only когда
  /// server returns structured domain error.
  Future<List<SemyaMembership>> listMembershipsForSemya(String semyaId);

  /// Ship FE3 (2026-05-26): `POST /v1/semya/:id/invitation`. Creates
  /// pending invitation для recipient (email либо phone — userId not
  /// surfaced UI-side в этом ship). Idempotent на (semyaId + recipient).
  ///
  /// Returns invitation including `token` (capability for accept flow).
  /// Permission: owner либо editor с invite-grant. Backend rejects
  /// otherwise via 403.
  ///
  /// Throws [SemyaError] для: ALREADY_MEMBER (409), RECIPIENT_NOT_FOUND
  /// (404), SEMYA_NOT_FOUND (404), INVALID_PARAMS (400), FORBIDDEN (403).
  Future<SemyaInvitation> createInvitation({
    required String semyaId,
    required SemyaRole role,
    String? recipientEmail,
    String? recipientPhone,
    String? recipientUserId,
  });

  /// Ship FE3: `GET /v1/semya/:id/invitations`. Returns all invitations
  /// для семя (статусы pending/accepted/revoked/expired mixed) — caller
  /// filters per UI needs.
  ///
  /// Permission: viewer+ (member access). Returns empty list при network
  /// failure либо 403/404.
  Future<List<SemyaInvitation>> listInvitationsForSemya(String semyaId);

  /// Ship FE3: `DELETE /v1/semya/:id/invitation/:invitationId`. Revokes
  /// pending invitation. Only inviter либо semya owner can revoke.
  ///
  /// Returns updated invitation (status='revoked'). Throws [SemyaError]
  /// для: NOT_INVITER_OR_OWNER (403), INVITATION_NOT_FOUND (404),
  /// INVITATION_NOT_PENDING (409 — терминальный state).
  Future<SemyaInvitation> revokeInvitation({
    required String semyaId,
    required String invitationId,
  });

  /// Ship FE3: `POST /v1/invitation/:token/accept`. Accepts invitation
  /// via token (capability). Atomic accept + membership creation.
  ///
  /// Throws [SemyaError] для: INVITATION_NOT_FOUND (404),
  /// INVITATION_NOT_PENDING (409 — already accepted/revoked/expired),
  /// WRONG_RECIPIENT (403 — token addressed к different user),
  /// SEMYA_NOT_FOUND (404).
  Future<SemyaInvitationAcceptResult> acceptInvitation(String token);

  /// Ship FE5 (2026-05-26): `POST /v1/semya/:targetSemyaId/pull-person`.
  /// Copies person из source семья к caller's target семья. Backend wraps
  /// bulkImportPersonsToTree (Ship 6) — identity-aware dedup means
  /// re-pull of same person returns existing twin (idempotent).
  ///
  /// Permissions: caller must be editor+ в target семя AND any-role
  /// member of source семя. Backend independently enforces.
  ///
  /// Throws [SemyaError] для:
  ///   • INVALID_INPUT (400 — missing IDs либо source == target)
  ///   • FORBIDDEN (403 — no source membership либо no target editor)
  ///   • SEMYA_NOT_FOUND (404 — source семя deleted либо missing)
  ///   • PERSON_NOT_FOUND (404 — source person не в source tree)
  ///
  /// Response includes pulled person row + new relations created
  /// via bulk import. Caller typically discards relations и refreshes
  /// target tree view.
  Future<SemyaPullPersonResult> pullPersonToSemya({
    required String targetSemyaId,
    required String sourceSemyaId,
    required String sourcePersonId,
  });

  /// Ship FE6a (2026-05-26): `POST /v1/semya/:id/browse-token`. Creates
  /// shareable read-only capability link к семя's tree. Owner либо
  /// editor-с-grant only (backend enforces). Default expiresInDays=30
  /// (server-side cap 90).
  ///
  /// Plaintext secret leaks ONCE — caller must surface immediately
  /// в share UI без persistence.
  ///
  /// Throws [SemyaError] для: FORBIDDEN (403 — no role либо grant),
  /// SEMYA_NOT_FOUND (404), INVALID_INPUT (400).
  Future<SemyaBrowseToken> createBrowseToken({
    required String semyaId,
    int? expiresInDays,
  });

  /// Ship FE6a (2026-05-26): `GET /v1/browse/:token`. Resolves token
  /// → семя + tree summary с persons/relations (read-only, privacy-
  /// filtered). NO auth required — token само is capability.
  ///
  /// Persons returned с minimal fields: name, maidenName, gender,
  /// birthDate, deathDate, identityId. Photos / bio / sensitive
  /// attributes intentionally omitted (privacy boundary).
  ///
  /// Throws [SemyaError] для: TOKEN_NOT_FOUND (404), TOKEN_REVOKED
  /// (410), TOKEN_EXPIRED (410), SEMYA_NOT_FOUND (404), TREE_NOT_FOUND
  /// (404).
  Future<BrowsedSemyaTree> fetchBrowseTree(String token);

  /// Ship FE6b (2026-05-26): `GET /v1/semya/:id/browse-tokens`. Returns
  /// active + expired + revoked browse tokens для семя (server includes
  /// all statuses; frontend filters/styles per status).
  ///
  /// Permission: viewer+ (member access — backend enforces). UI gates
  /// section render на canInvite separately (UX choice).
  ///
  /// Plaintext token secret NOT included (security: leaks ONCE на
  /// create). Каждая row carries computed status field.
  ///
  /// Returns empty list при graceful failures (network, 403/404).
  Future<List<SemyaBrowseTokenSummary>> listBrowseTokens({
    required String semyaId,
  });

  /// Ship FE6b (2026-05-26): `DELETE /v1/semya/:id/browse-token/:tokenId`.
  /// Revokes browse token. Backend permission: семя owner (any token) либо
  /// token creator (own tokens). Frontend gates revoke button accordingly.
  ///
  /// Throws [SemyaError] для: NOT_CREATOR_OR_OWNER (403),
  /// TOKEN_NOT_FOUND (404), TOKEN_ALREADY_REVOKED (409),
  /// INVALID_TOKEN_ID (400).
  Future<SemyaBrowseTokenSummary> revokeBrowseToken({
    required String semyaId,
    required String tokenId,
  });
}
