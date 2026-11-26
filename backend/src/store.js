const fs = require("node:fs/promises");
const {describeMessagePreview} = require("./chat-utils");
const {
  backfillPersonIdentities,
  migrateTreesToGraphAndBranches,
} = require("./migration-utils");
const path = require("node:path");
const crypto = require("node:crypto");
const helpers = require("./store/helpers");
const {
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
} = require("./store/constants");
const {
  normalizeDbState,
  nowIso,
  createTreeChangeRecord,
  stripTreeChangeRecordDetails,
  isHardDeleteAuditEntryExpired,
  normalizeStoredCall,
  deepFreezeState,
  deriveSessionPublicId,
  isCallTerminalState,
  ensureCirclesForAllTrees,
} = helpers;
const articlesMediaMethods = require("./store/domains/articles-media");
const authUsersMethods = require("./store/domains/auth-users");
const callsMethods = require("./store/domains/calls");
const chatsMethods = require("./store/domains/chats");
const circlesMethods = require("./store/domains/circles");
const graphVisibilityMethods = require("./store/domains/graph-visibility");
const identityMergeMethods = require("./store/domains/identity-merge");
const maintenanceMethods = require("./store/domains/maintenance");
const notificationsSafetyMethods = require("./store/domains/notifications-safety");
const onboardingRequestsMethods = require("./store/domains/onboarding-requests");
const personsTreesMethods = require("./store/domains/persons-trees");
const postsCommentsMethods = require("./store/domains/posts-comments");
const relationsMethods = require("./store/domains/relations");
const semyiMethods = require("./store/domains/semyi");
const storiesGatheringsPollsMethods = require("./store/domains/stories-gatherings-polls");

class FileStore {
  constructor(dataPath) {
    this.dataPath = dataPath;
    this.storageMode = "file-store";
    this.storageTarget = dataPath;
    this._writeQueue = Promise.resolve();
    // Serializes the WHOLE read-modify-write of every _mutate() call so no two
    // mutations interleave (store-wide lost-update fix). Distinct from
    // _writeQueue, which only serializes the persist half.
    this._mutateQueue = Promise.resolve();
    this._sessionTouchCache = new Map();
    this._sessionCache = new Map();
    this._userCache = new Map();
    this._onboardingIncompleteCache = new Map();
    this._initializePromise = null;
  }

  async initialize() {
    if (!this._initializePromise) {
      this._initializePromise = this._initializeFileStore();
    }
    return this._initializePromise;
  }

  async _initializeFileStore() {
    await fs.mkdir(path.dirname(this.dataPath), {recursive: true});

    try {
      await fs.access(this.dataPath);
    } catch {
      await fs.writeFile(
        this.dataPath,
        JSON.stringify(EMPTY_DB, null, 2),
        "utf8",
      );
      return;
    }

    const raw = await fs.readFile(this.dataPath, "utf8");
    const parsed = JSON.parse(raw);
    const normalized = normalizeDbState(parsed);
    const migration = backfillPersonIdentities(normalized);
    const migratedSnapshot = migration.snapshot;
    // Phase 3.1: one-shot trees → graph + branches migration.
    // Idempotent (skips on `migrationStatus.treesToGraph ===
    // "complete"`), so re-runs after the initial fill are free.
    // Fires AFTER backfillPersonIdentities so every person has an
    // identityId and the graph rows can dedupe by it. The legacy
    // collections stay in place — Phase 3.1c will wire reads/
    // writes to the graph behind the existing /v1/trees/:treeId
    // routes; until then this just stages the data side ready
    // for the next layer.
    const graphMigration = migrateTreesToGraphAndBranches(migratedSnapshot);
    const defaultCirclesChanged = ensureCirclesForAllTrees(migratedSnapshot);
    if (
      migration.changed ||
      defaultCirclesChanged ||
      graphMigration.changed
    ) {
      const directoryPath = path.dirname(this.dataPath);
      const tempPath = path.join(
        directoryPath,
        `${path.basename(this.dataPath)}.${crypto.randomUUID()}.tmp`,
      );
      await fs.writeFile(
        tempPath,
        JSON.stringify(migratedSnapshot, null, 2),
        "utf8",
      );
      await fs.rename(tempPath, this.dataPath);
    }
  }

  async healthCheck() {
    await this.initialize();
    await fs.access(path.dirname(this.dataPath));
  }

  async _read() {
    await this.initialize();
    await this._writeQueue;
    const raw = await fs.readFile(this.dataPath, "utf8");
    const parsed = JSON.parse(raw);
    const normalized = normalizeDbState(parsed);
    // Phase 3.1c: keep the graph mirror eventually consistent
    // with the legacy collections without wiring sync into every
    // write path. Idempotent — no-op once the graph already
    // matches the legacy side.
    this._syncGraphFromLegacy(normalized);
    return normalized;
  }

  async _write(data) {
    // Same sync pass as _read, but on the OUT-bound side: ensures
    // the data we're about to persist already has graph rows that
    // mirror the legacy mutation the caller just made. Without
    // this, the next process boot would read a snapshot whose
    // graph is one step behind the legacy state.
    this._syncGraphFromLegacy(data);
    this._writeQueue = this._writeQueue.then(async () => {
      // store-race guard: read the freshest persisted calls INSIDE this
      // serialized write link (all prior writes have landed) and keep any
      // terminal call terminal — see _preserveTerminalCalls.
      try {
        const currentRaw = await fs.readFile(this.dataPath, "utf8");
        this._preserveTerminalCalls(data, JSON.parse(currentRaw)?.calls);
      } catch (_) {
        // First write / missing file — nothing persisted to preserve.
      }
      const directoryPath = path.dirname(this.dataPath);
      const tempPath = path.join(
        directoryPath,
        `${path.basename(this.dataPath)}.${crypto.randomUUID()}.tmp`,
      );

      await fs.writeFile(tempPath, JSON.stringify(data, null, 2), "utf8");
      await fs.rename(tempPath, this.dataPath);
    });
    return this._writeQueue;
  }

  // SPEED-11: read-only snapshot for GET routes that used to call _read()
  // just to hand the result straight to a store method as `prefetchedDb`
  // (see requireTreeAccess in app.js — SPEED-9 B introduced that pattern).
  // FileStore has no version-keyed cache (PostgresStore overrides this to
  // actually skip the structuredClone on a cache hit — see there for the
  // real payoff); here it's just _read() + freeze, so tests and local/dev
  // (file-store mode) get the SAME contract — frozen, no `sessions` — as
  // prod, without a store-specific branch in callers.
  async readSharedSnapshot() {
    const state = await this._read();
    deepFreezeState(state);
    return this._buildSharedSnapshotView(state);
  }

  // SPEED-11: wraps an already-frozen db snapshot for read-only, cross-
  // request sharing. Every top-level collection is exposed by reference
  // (safe — `state` is frozen) EXCEPT `sessions`: that collection is a
  // point-in-time snapshot taken when the cache was filled, never refreshed
  // for a cache HIT (PostgresStore's per-request session projection query is
  // exactly what this method exists to skip) — so silently handing it out
  // would serve stale-or-wrong session data to whoever reads db.sessions.
  // Fail loud instead: callers that need sessions must go through
  // findSession/findUserBySessionToken/etc., which query the projection
  // table directly (Postgres) or _read() honestly (FileStore).
  _buildSharedSnapshotView(state) {
    const shared = {...state};
    delete shared.sessions;
    Object.defineProperty(shared, "sessions", {
      enumerable: true,
      configurable: false,
      get() {
        throw new Error(
          "readSharedSnapshot(): shared snapshot has no sessions — use " +
            "findSession/findUserBySessionToken/store session methods instead of db.sessions (SPEED-11)",
        );
      },
    });
    return Object.freeze(shared);
  }

  // Atomic read-modify-write. Serializes the ENTIRE read → mutate → write of
  // every mutation through a dedicated lock (_mutateQueue) so two concurrent
  // mutations can never interleave — closing the whole-document lost-update
  // where a stale snapshot's write clobbers a field it never saw (the
  // store-wide race the per-field _preserveTerminalCalls guard only patched for
  // terminal calls). It REUSES _read()/_write() (so PostgresStore inherits it
  // unchanged, with its own overrides handling snapshot/projection/cache), and
  // simply prevents interleaving:
  //   - the lock guarantees this mutation's _read() sees the previous
  //     mutation's already-persisted _write();
  //   - _read()/_write() await _writeQueue/_stateWriteQueue, NOT _mutateQueue,
  //     so there is no circular wait / deadlock.
  // `applyFn(data, skip)` mutates `data` in place and returns the method's
  // result. It MUST be pure in-memory — it must NOT call _read/_write/_mutate
  // itself. On a read-only / not-found / no-op path it should `return skip(x)`
  // instead of `return x`: that returns `x` WITHOUT persisting, so those
  // early-returns stay pure reads exactly as they were before the migration
  // (no redundant whole-document write, and — importantly on Postgres — no new
  // write-layer failure surface on a path the old code never wrote on, e.g. an
  // already-terminal call handled by applyCallWebhook). Forgetting `skip` only
  // costs a redundant idempotent write, never a lost update (fail-safe). If
  // applyFn throws, nothing is persisted and the error propagates; the fresh
  // read on the next mutation discards the aborted in-memory changes.
  async _mutate(applyFn) {
    if (!this._mutateQueue) {
      this._mutateQueue = Promise.resolve();
    }
    const run = this._mutateQueue.then(async () => {
      const data = await this._read();
      let shouldWrite = true;
      const skip = (value) => {
        shouldWrite = false;
        return value;
      };
      const result = await applyFn(data, skip);
      if (shouldWrite) {
        await this._write(data);
      }
      return result;
    });
    // Keep the lock chained even if applyFn/persist rejects, so later mutations
    // serialize after this link instead of inheriting a rejected promise.
    this._mutateQueue = run.then(
      () => undefined,
      () => undefined,
    );
    return run;
  }

  // Test/shutdown hook: drain every mutation/persist already enqueued before
  // the caller tears down the process/dataPath (e.g. a test deleting its
  // tempDir). `_mutate`/`_write` are fire-and-forget from route handlers'
  // point of view (send/push dispatch replies BEFORE the blob write lands),
  // so a snapshot-then-await of `_mutateQueue` can miss work appended WHILE
  // we're waiting — that's exactly what caused the Windows ENOTEMPTY flake
  // (rm() walks a directory that gains a fresh `*.tmp` from an in-flight
  // _write mid-delete). Loop until a full await cycle appends nothing new,
  // i.e. the queue reference is stable — only then is the store quiescent.
  // Purely additive: reads existing fields, calls nothing that isn't already
  // called by normal mutation traffic, so it changes no production timing.
  async close() {
    let previous = null;
    let current = this._mutateQueue;
    while (current !== previous) {
      previous = current;
      await current;
      current = this._mutateQueue;
    }
  }

  _preserveTerminalCalls(data, currentCalls) {
    if (!Array.isArray(data?.calls) || data.calls.length === 0) {
      return;
    }
    if (!Array.isArray(currentCalls) || currentCalls.length === 0) {
      return;
    }
    const terminalById = new Map();
    for (const call of currentCalls) {
      if (call && isCallTerminalState(String(call.state || ""))) {
        terminalById.set(String(call.id || ""), call);
      }
    }
    if (terminalById.size === 0) {
      return;
    }
    for (let index = 0; index < data.calls.length; index += 1) {
      const call = data.calls[index];
      const terminal = terminalById.get(String(call?.id || ""));
      if (terminal && !isCallTerminalState(String(call?.state || ""))) {
        data.calls[index] = terminal;
      }
    }
  }

  _rememberSession(session) {
    const normalizedToken = String(session?.token || "").trim();
    if (!normalizedToken) {
      return;
    }
    this._sessionCache.set(normalizedToken, structuredClone(session));
  }

  _forgetSession(token) {
    const normalizedToken = String(token || "").trim();
    if (!normalizedToken) {
      return;
    }
    this._sessionCache.delete(normalizedToken);
    this._sessionTouchCache.delete(normalizedToken);
  }

  _rememberUser(user) {
    const normalizedUserId = String(user?.id || "").trim();
    if (!normalizedUserId) {
      return;
    }
    this._userCache.set(normalizedUserId, cloneUserWithAuthState(user));
  }

  _forgetUser(userId) {
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) {
      return;
    }
    this._userCache.delete(normalizedUserId);
    this._onboardingIncompleteCache.delete(normalizedUserId);
  }

  _appendTreeChangeRecord(db, {
    treeId,
    actorId = null,
    type,
    personId = null,
    personIds = [],
    relationId = null,
    mediaId = null,
    details = {},
  }) {
    const record = createTreeChangeRecord({
      treeId,
      actorId,
      type,
      personId,
      personIds,
      relationId,
      mediaId,
      details,
    });
    db.treeChangeRecords.push(record);
    return record;
  }

  // ── SPEED-8b: хуки над журналом изменений и аудитом hard-delete ──────
  // На FileStore коллекции живут в блобе — хуки правят массивы на месте.
  // PostgresStore держит их в таблицах и переопределяет хуки: массивы в
  // блобе после миграции пусты, а табличная часть операции уходит в очередь,
  // которую применяет _write (хуки зовутся из _mutate-applyFn — там нельзя
  // await'ить SQL).
  _rewriteTreeChangeRecordsForMerge(db, {
    treeId,
    duplicatePersonId,
    preferredPersonId,
  }) {
    for (const record of db.treeChangeRecords || []) {
      if (record.treeId !== treeId) {
        continue;
      }
      if (record.personId === duplicatePersonId) {
        record.personId = preferredPersonId;
      }
      record.personIds = normalizeParticipantIds(
        (record.personIds || []).map((personId) =>
          personId === duplicatePersonId ? preferredPersonId : personId,
        ),
      );
    }
  }

  _pseudonymizeTreeChangeActor(db, userId) {
    for (const record of db.treeChangeRecords || []) {
      if (record.actorId === userId) {
        record.actorId = "deleted-user";
        record.actorName = null;
      }
    }
  }

  /// Срезает before/after/mergedFrom у НЕ-article записей старше cutoffTs
  /// (сама запись остаётся — таймлайн цел). Возвращает число затронутых.
  _stripTreeChangeDetails(db, {cutoffTs, dryRun = false}) {
    let stripped = 0;
    for (const record of db.treeChangeRecords || []) {
      if (stripTreeChangeRecordDetails(record, {cutoffTs, dryRun})) {
        stripped += 1;
      }
    }
    return stripped;
  }

  /// Аудит hard-delete: записи старше cutoffTs выбывают. Возвращает
  /// {surviving, pruned}; при dryRun ничего не меняет, только считает.
  _pruneHardDeleteAudit(db, {cutoffTs, dryRun = false}) {
    const existing = Array.isArray(db.hardDeleteAudit) ? db.hardDeleteAudit : [];
    const surviving = [];
    let pruned = 0;
    for (const entry of existing) {
      if (isHardDeleteAuditEntryExpired(entry, cutoffTs)) {
        pruned += 1;
        if (dryRun) surviving.push(entry);
      } else {
        surviving.push(entry);
      }
    }
    return {surviving, pruned};
  }

  // Phase B Ship 6: public wrapper для route-layer additive audit
  // entries (e.g. person.pulled-from-semya). Existing pattern —
  // change records appended inside store mutation methods. Когда
  // change source = composite route (pull = bulkImport + audit +
  // notify), route нужен hook без re-walking entire mutation flow.
  async appendTreeChangeRecord({
    treeId,
    actorId = null,
    type,
    personId = null,
    personIds = [],
    relationId = null,
    mediaId = null,
    details = {},
  }) {
    if (!treeId || typeof treeId !== "string") {
      throw new Error("INVALID_TREE_ID");
    }
    if (!type || typeof type !== "string") {
      throw new Error("INVALID_TYPE");
    }
    const db = await this._read();
    const record = this._appendTreeChangeRecord(db, {
      treeId,
      actorId,
      type,
      personId,
      personIds,
      relationId,
      mediaId,
      details,
    });
    await this._write(db);
    return structuredClone(record);
  }

  static get _maxLoginFailuresBeforeLockout() {
    return MAX_LOGIN_FAILURES_BEFORE_LOCKOUT;
  }

  static get _loginLockoutDurationMs() {
    return LOGIN_LOCKOUT_DURATION_MS;
  }

  static get _passwordResetTokenTtlMs() {
    return PASSWORD_RESET_TOKEN_TTL_MS;
  }

  static get _passwordResetMinIssueIntervalMs() {
    return PASSWORD_RESET_MIN_ISSUE_INTERVAL_MS;
  }

  static get _identityPropagationFields() {
    return IDENTITY_PROPAGATION_FIELDS;
  }

  static get _connectedVisibilityMaxHops() {
    return CONNECTED_VISIBILITY_MAX_HOPS;
  }

  static get _sensitiveAttributeFields() {
    return SENSITIVE_ATTRIBUTE_FIELDS;
  }

  static isSensitiveAttributeField(field) {
    return isSensitiveAttributeField(field);
  }

  static get _kinshipCheckTtlMs() {
    return KINSHIP_CHECK_TTL_MS;
  }

  static get _kinshipRejectionCooldownMs() {
    return KINSHIP_REJECTION_COOLDOWN_MS;
  }

  static get _storyRequestTtlMs() {
    return STORY_REQUEST_TTL_MS;
  }

  static get _storyRequestMaxPendingPerInitiator() {
    return STORY_REQUEST_MAX_PENDING_PER_INITIATOR;
  }
}

Object.assign(
  FileStore.prototype,
  articlesMediaMethods,
  authUsersMethods,
  callsMethods,
  chatsMethods,
  circlesMethods,
  graphVisibilityMethods,
  identityMergeMethods,
  maintenanceMethods,
  notificationsSafetyMethods,
  onboardingRequestsMethods,
  personsTreesMethods,
  postsCommentsMethods,
  relationsMethods,
  semyiMethods,
  storiesGatheringsPollsMethods,
);

const {
  EMPTY_DB,
  buildCommentReactionNotificationPlan,
  buildCommentReplyNotificationPlan,
  buildPostReactionNotificationPlan,
  buildStoryReactionNotificationPlan,
  computeNotificationCoalesceKey,
  decodeNotificationCursor,
  encodeNotificationCursor,
  createNotificationRecord,
  createPushDeliveryRecord,
  composeDisplayNameFromProfile,
  buildChatSearchSnippet,
  buildTreeGraphSnapshot,
  buildGraphWarnings,
  buildBranchVisiblePersonIds,
  buildPersonRecord,
  buildCallParticipantIdentity,
  chatMessageSearchHaystack,
  cloneUserWithAuthState,
  collectMessageMediaUrls,
  compareChatMessagesDescending,
  createChatDraftRecord,
  createChatPinRecord,
  createChatRecord,
  createPersonIdentityRecord,
  createPostRecord,
  ensureCirclesForTree,
  isExpiredAt,
  isMessageReadByUser,
  normalizeChatMessageCall,
  normalizeChatSearchQuery,
  normalizeNullableString,
  normalizeOptionalIsoTimestamp,
  normalizeReactionEmoji,
  normalizeSessionDeviceContext,
  normalizeParticipantIds,
  normalizePhoneNumber,
  parseCallParticipantIdentity,
  parseDirectParticipantsFromChatId,
  SESSION_TOUCH_MIN_INTERVAL_MS,
  verifyPassword,
} = helpers;

module.exports = {
  EMPTY_DB,
  stripTreeChangeRecordDetails,
  isHardDeleteAuditEntryExpired,
  FileStore,
  buildCommentReactionNotificationPlan,
  buildCommentReplyNotificationPlan,
  buildPostReactionNotificationPlan,
  buildStoryReactionNotificationPlan,
  computeNotificationCoalesceKey,
  decodeNotificationCursor,
  encodeNotificationCursor,
  createNotificationRecord,
  createPushDeliveryRecord,
  composeDisplayNameFromProfile,
  buildChatSearchSnippet,
  buildTreeGraphSnapshot,
  buildGraphWarnings,
  buildBranchVisiblePersonIds,
  buildPersonRecord,
  buildCallParticipantIdentity,
  chatMessageSearchHaystack,
  cloneUserWithAuthState,
  collectMessageMediaUrls,
  compareChatMessagesDescending,
  createChatDraftRecord,
  createChatPinRecord,
  createChatRecord,
  createPersonIdentityRecord,
  createPostRecord,
  createTreeChangeRecord,
  deepFreezeState,
  deriveSessionPublicId,
  describeMessagePreview,
  ensureCirclesForTree,
  isExpiredAt,
  isMessageReadByUser,
  normalizeChatMessageCall,
  normalizeChatSearchQuery,
  normalizeDbState,
  normalizeNullableString,
  normalizeOptionalIsoTimestamp,
  normalizeReactionEmoji,
  normalizeSessionDeviceContext,
  normalizeParticipantIds,
  normalizePhoneNumber,
  normalizeStoredCall,
  nowIso,
  parseCallParticipantIdentity,
  parseDirectParticipantsFromChatId,
  SESSION_TOUCH_MIN_INTERVAL_MS,
  verifyPassword,
};
