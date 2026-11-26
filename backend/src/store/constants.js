const {
  migrateTreesToGraphAndBranches,
} = require("../migration-utils");

const PROFILE_CONTRIBUTION_POLICIES = new Set([
  "disabled",
  "suggestions",
]);

const PROFILE_SUGGESTION_FIELDS = Object.freeze([
  "firstName",
  "lastName",
  "middleName",
  "maidenName",
  "photoUrl",
  "gender",
  "birthDate",
  "birthPlace",
  "countryName",
  "city",
  "bio",
  "familyStatus",
  "aboutFamily",
  "education",
  "work",
  "hometown",
  "languages",
  "values",
  "religion",
  "interests",
]);

const EMPTY_DB = {
  users: [],
  sessions: [],
  authHandoffs: [],
  passwordResetTokens: [],
  // Phase 1.2 voltage-indicator matcher: per-user records of
  // suggestion dismissals so the 💡 indicator doesn't keep
  // re-suggesting pairs the user already said "no, these are
  // different people" about.
  dismissedIdentitySuggestions: [],
  // Phase 1.3 edit-time conflict surfacing: rows recorded by
  // `_propagateIdentityFields` when it would have overwritten a
  // value the user had locally edited on the target tree
  // between propagations. The user resolves each row via
  // /v1/trees/:treeId/conflicts/:conflictId/resolve as either
  // `keep` (target wins, source change ignored on this side)
  // or `overwrite` (source wins, target overwritten).
  identityFieldConflicts: [],
  // Phase 3.1 unified-graph collections. The legacy trees /
  // persons / relations are kept as the read source until the
  // back-compat layer is wired in 3.1c — these new collections
  // are populated by the one-shot migration in
  // migration-utils.migrateTreesToGraphAndBranches and serve as
  // the source of truth from then on.
  // graphPersons: one node per real human, identity-merged from
  //   the legacy persons + personIdentities pair. Carries the
  //   canonical identity-propagation fields (name, dates, photo).
  // graphRelations: deduplicated parent/child/spouse edges
  //   between graphPersons (legacy per-tree duplicates collapsed
  //   to one row per canonical pair+type).
  // branches: per-user filter slice over the graph + automatic
  //   social circle for the per-branch feed. Replaces the legacy
  //   `trees` notion of "container of people" with "named view
  //   over the global graph". `legacyTreeId` keeps the back-
  //   reference so existing /v1/trees/:treeId routes can resolve
  //   the matching branch.
  // branchPersonViews: per-(branch, person) editorial annotation
  //   — notes / familySummary / bio / visibility / per-branch
  //   label override. Splits "what is this human" (graphPerson)
  //   from "how does this branch present them" (this row).
  graphPersons: [],
  graphRelations: [],
  branches: [],
  branchPersonViews: [],
  // Phase 3.1 owner-model: explicit grants from a graphPerson's
  // owner to other users for `edit` / `merge-consent` / `soft-delete`
  // scopes. Default: only the owner (graphPerson.userId or
  // graphPerson.createdBy) can mutate. Auto-extension by hops was
  // explicitly rejected in DECISIONS.md (2026-05-10 ответ C) — every
  // additional editor has to be granted access by the owner.
  graphPersonEditGrants: [],
  // One-shot migration ledger: tracks which schema migrations have
  // already run so re-reads on startup don't redo idempotent work.
  // Phase 3.1 sets `treesToGraph: "complete-v2"` once the new
  // per-field highest-completeness migration has built the graph
  // collections from the legacy ones. The legacy "complete" value
  // marks an old v1 migration whose canonical-picking was record-
  // level (claimed user → updatedAt); v1 snapshots get re-built
  // automatically on next startup so they pick up the new logic.
  migrationStatus: {},
  trees: [],
  // Phase B (federated семьи): 5 collections per ENTITY-DESIGN.md.
  // `семьи` (singular: семья) — explicit group entity wrapping a tree
  // с multi-member roles (owner/editor/viewer). One-tree-per-семья
  // invariant per ENTITY-DESIGN §3.1. Per-семья membership table —
  // source of truth для access control, replaces tree.memberIds[] +
  // tree.creatorId как primary mechanism (legacy fields preserved
  // через dual-write compat shim в Week 3).
  // Hidden persons — per-user opaque filter, не mutates tree.
  // Invitations + browse tokens mirror Phase 6.5 kinshipChecks state
  // machine pattern.
  semyi: [],
  semyaMembers: [],
  semyaMemberHiddenPersons: [],
  semyaInvitations: [],
  semyaBrowseTokens: [],
  persons: [],
  // Ship Q4a (2026-05-28): soft-delete snapshot collection. Path 2
  // from PHASE-Q4A-SOFT-DELETE-DESIGN (ec12804) — separate
  // collection чтобы 95 db.persons read sites остаются untouched
  // by construction. Hard-delete job sweeps этот set per
  // hardDeleteScheduledAt + earliestHardDelete (3h floor) gates.
  deletedPersons: [],
  // Ship Q4a (2026-05-28, Ship 30b): same pattern для posts.
  // Snapshot captures post + comments + reactions для full restore.
  deletedPosts: [],
  // Profile Phase 1 (2026-05-28): article-style biography entity.
  // One row per person — ordered content blocks (paragraph / header /
  // photo / gallery / audio / quote / divider). Separate collection
  // (NOT a person field) — keeps existing 95 db.persons read sites
  // untouched. Per-block authorUserId = multi-author attribution;
  // full history reuses treeChangeRecords (type `article.*`). Media
  // referenced by url (no media table — mirrors photoGallery).
  profileArticles: [],
  personIdentities: [],
  personAttributes: [],
  circles: [],
  circleMembers: [],
  mergeProposals: [],
  identityClaims: [],
  relations: [],
  chats: [],
  chatDrafts: [],
  chatPins: [],
  calls: [],
  messages: [],
  messageReactions: [],
  relationRequests: [],
  // Phase 6 BFS «мы родственники?» bilateral consent flow.
  // Different semantic от relationRequests (invite-to-tree).
  // DECISIONS.md 2026-05-13: kinshipChecks naming + state-based
  // idempotency.
  kinshipChecks: [],
  // «Спросить историю» MVP-1 (STORY-REQUEST-MVP1-BRIEF.md §1): просьба
  // задать вопрос родному → ответ ложится блоком в статью героя. Pending
  // → answered | declined | expired | revoked, 30d TTL (лениво при
  // чтении, как kinshipChecks). Десятки записей — коллекция живёт в
  // блобе, не в отдельной таблице.
  storyRequests: [],
  // Phase 6 wizard progress per-user. State-based idempotency
  // gate для /onboarding/seed.
  onboardingStates: [],
  treeInvitations: [],
  treeChangeRecords: [],
  notifications: [],
  posts: [],
  // Phase E1: «Встреча» (Gathering) — family event invitations. Mirrors
  // posts (circle-on-tree audience, multi-branch fan-out). RSVP rows
  // land here in E3; create+delete only in E1.
  gatherings: [],
  // Phase E4: «Опрос» (Poll) — mirrors gatherings (same audience model);
  // carries options + per-user responses (votes).
  polls: [],
  stories: [],
  comments: [],
  postReactions: [],
  postCommentReactions: [],
  storyReactions: [],
  reports: [],
  blocks: [],
  profileContributions: [],
  pushDevices: [],
  pushDeliveries: [],
  clientDiagnostics: [],
  // Phase 3.6: audit log для hard-delete background job. Каждая запись
  // фиксирует physically deleted entity (entityType, entityId,
  // deletedAt, scheduledAt, hardDeletedAt, runId). Self-prune: записи
  // старше 90 дней удаляются тем же job на следующем runs (DECISIONS.md
  // 2026-05-18 «Phase 3.6 hard-delete background job»).
  hardDeleteAudit: [],
  // Last successful (non-dry, non-paused) run timestamp. Persisted
  // чтобы `setInterval` пережил backend restarts: startup checks
  // elapsed since `hardDeleteLastRunAt`, schedules catch-up через
  // 60s если interval уже истёк. `null` = job ни разу не успешно
  // не отработал на этом state.
  hardDeleteLastRunAt: null,
};

const SESSION_TOUCH_MIN_INTERVAL_MS = 60_000;

const AUTO_CIRCLE_KINDS = new Set([
  "descendants_of",
  "ancestors_of",
  "pair",
]);

const PARENT_SET_TYPES = new Set([
  "biological",
  "adoptive",
  "foster",
  "guardian",
  "step",
  "unknown",
]);

const BLOOD_PARENT_SET_TYPES = new Set(["biological", "unknown"]);

const UNION_TYPES = new Set([
  "spouse",
  "partner",
  "friend",
  "single",
  "other",
]);

const UNION_STATUSES = new Set(["current", "past", "ended_by_death"]);

// Phase 3.4-prep (DECISIONS.md 2026-05-10 Q3/Q4): валидирует и
// применяет incoming `includeRules` поверх существующих rules
// branch'а. Не перетирает manualPersonIds на blood/descendants/
// ancestors (stash для возможного rollback на manual). Validation:
//   - type ∈ {manual, blood-from-me, descendants-of, ancestors-of}
//   - maxHops 1..20 (default 5 если invalid/missing)
//   - anchorPersonId — string или null
// Возвращает true если что-то реально изменилось, false если no-op.
const VALID_INCLUDE_RULE_TYPES = new Set([
  "manual",
  "blood-from-me",
  "descendants-of",
  "ancestors-of",
]);

const PERSON_VISIBILITIES = new Set([
  "private",
  "tree",
  "cross-tree",
  "public",
]);

const PERSON_ATTRIBUTE_FIELDS = Object.freeze([
  "name",
  "photo",
  "birthDate",
  "birthYear",
  "places",
  "contacts",
  "notes",
  "relations",
]);

const SUPPORTED_AUTH_PROVIDERS = new Set([
  "password",
  "google",
  "telegram",
  "vk",
  "max",
]);

const ARTICLE_BLOCK_TYPES = Object.freeze([
  "paragraph",
  "header",
  "photo",
  "gallery",
  "audio",
  "quote",
  "divider",
]);

const MAX_LOGIN_FAILURES_BEFORE_LOCKOUT = 7;
const LOGIN_LOCKOUT_DURATION_MS = 15 * 60 * 1000;
const PASSWORD_RESET_TOKEN_TTL_MS = 24 * 60 * 60 * 1000;
const PASSWORD_RESET_MIN_ISSUE_INTERVAL_MS = 60 * 60 * 1000;
const IDENTITY_PROPAGATION_FIELDS = Object.freeze([
  "name",
  "maidenName",
  "gender",
  "birthDate",
  "birthDatePrecision",
  "deathDate",
  "deathDatePrecision",
  "isAlive",
  "birthPlace",
  "deathPlace",
  "biography",
  "occupation",
  "photoUrl",
  "primaryPhotoUrl",
  "photoGallery",
]);
const CONNECTED_VISIBILITY_MAX_HOPS = 4;
const SENSITIVE_ATTRIBUTE_FIELDS = new Set(["contacts"]);
function isSensitiveAttributeField(field) {
  return SENSITIVE_ATTRIBUTE_FIELDS.has(String(field || ""));
}
const KINSHIP_CHECK_TTL_MS = 14 * 86_400_000;
const KINSHIP_REJECTION_COOLDOWN_MS = 30 * 86_400_000;
const STORY_REQUEST_TTL_MS = 30 * 86_400_000;
const STORY_REQUEST_MAX_PENDING_PER_INITIATOR = 20;

module.exports = {
  PROFILE_CONTRIBUTION_POLICIES,
  PROFILE_SUGGESTION_FIELDS,
  EMPTY_DB,
  SESSION_TOUCH_MIN_INTERVAL_MS,
  AUTO_CIRCLE_KINDS,
  PARENT_SET_TYPES,
  BLOOD_PARENT_SET_TYPES,
  UNION_TYPES,
  UNION_STATUSES,
  VALID_INCLUDE_RULE_TYPES,
  PERSON_VISIBILITIES,
  PERSON_ATTRIBUTE_FIELDS,
  SUPPORTED_AUTH_PROVIDERS,
  ARTICLE_BLOCK_TYPES,
  MAX_LOGIN_FAILURES_BEFORE_LOCKOUT,
  LOGIN_LOCKOUT_DURATION_MS,
  PASSWORD_RESET_TOKEN_TTL_MS,
  PASSWORD_RESET_MIN_ISSUE_INTERVAL_MS,
  IDENTITY_PROPAGATION_FIELDS,
  CONNECTED_VISIBILITY_MAX_HOPS,
  SENSITIVE_ATTRIBUTE_FIELDS,
  isSensitiveAttributeField,
  KINSHIP_CHECK_TTL_MS,
  KINSHIP_REJECTION_COOLDOWN_MS,
  STORY_REQUEST_TTL_MS,
  STORY_REQUEST_MAX_PENDING_PER_INITIATOR,
};
