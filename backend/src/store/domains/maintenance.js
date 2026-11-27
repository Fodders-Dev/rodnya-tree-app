const path = require("node:path");
const crypto = require("node:crypto");
const {
  isCallTerminalState,
} = require("../helpers");

module.exports = {
  // ── Retention for unbounded LOG / history collections ─────────────
  // These are NOT soft-delete tombstones (that is hardDeleteExpired's
  // job) but append-only logs/history that bloat the whole-document blob.
  // The store rewrites the ENTIRE blob on every write, so persist latency
  // ∝ total blob size — a prod blob measured 8 MB gave ~2.5 s message-send
  // ack, ~1.6 s of it just re-serialising the blob (see
  // docs/speed_measurement.md). Trimming these by age/cap shrinks the blob
  // and speeds up EVERY write app-wide.
  //
  // Mutates `db` in place ONLY when !dryRun; always returns counts so a dry
  // run reports what it WOULD trim. Pure in-memory — no nested store calls
  // (runs inside hardDeleteExpired, which owns the single _read/_write).
  _sweepUnboundedLogs(db, retention = {}, {nowTs, dryRun = false} = {}) {
    const HOUR = 3_600_000;
    const DAY = 86_400_000;
    const counts = {
      callsTerminal: 0,
      pushDeliveries: 0,
      notificationsSilent: 0,
      notificationsRead: 0,
      notificationsUnread: 0,
      treeChangeDetailsStripped: 0,
      storyRequestsTerminal: 0,
      storiesExpiredArchive: 0,
      storyReactionsOrphan: 0,
    };
    const parseTs = (value) => {
      const t = value ? Date.parse(value) : NaN;
      return Number.isFinite(t) ? t : null;
    };
    // A newest-N cap. Returns null for 0 / negative / non-numeric so the cap
    // is DISABLED (matching the "0 disables an individual trim" config
    // contract) instead of slice(0) wiping the whole collection.
    const positiveIntOrNull = (value) => {
      const n = Math.floor(Number(value));
      return Number.isFinite(n) && n > 0 ? n : null;
    };

    // ── db.calls: terminal-only TTL + newest-N cap. Busy calls
    //   (ringing/active) are NEVER trimmed — dropping a live call breaks
    //   busy-detection / resume / join / webhook teardown. The durable
    //   user-facing call log lives in db.messages (call payload), not here.
    const callsTtlMs =
      Math.max(0, Number(retention.callsTerminalHours ?? 24)) * HOUR;
    const callsMax = positiveIntOrNull(retention.callsTerminalMax ?? 500);
    if (Array.isArray(db.calls) && db.calls.length) {
      // null when no parseable timestamp — such a call is never TTL-trimmed
      // (we never delete on an unknown age), only cap-trimmed as oldest.
      const callTs = (c) =>
        parseTs(c.updatedAt) ?? parseTs(c.endedAt) ?? parseTs(c.createdAt);
      const remove = new Set();
      for (const call of db.calls) {
        if (!isCallTerminalState(call.state)) continue; // keep busy calls
        const ts = callTs(call);
        if (callsTtlMs > 0 && ts !== null && nowTs - ts > callsTtlMs) {
          remove.add(call);
        }
      }
      // Cap: among still-surviving terminal calls, keep only newest callsMax.
      // callsMax === null (knob 0 / non-numeric) DISABLES the cap.
      if (callsMax !== null) {
        const survivingTerminal = db.calls
          .filter((c) => isCallTerminalState(c.state) && !remove.has(c))
          .sort((a, b) => (callTs(b) ?? 0) - (callTs(a) ?? 0));
        for (const call of survivingTerminal.slice(callsMax)) remove.add(call);
      }
      counts.callsTerminal = remove.size;
      if (!dryRun && remove.size) {
        db.calls = db.calls.filter((c) => !remove.has(c));
      }
    }

    // ── db.pushDeliveries: pure telemetry log. Age TTL + newest-N cap.
    //   No user feature reads it back (only an ops debug endpoint).
    const pushTtlMs =
      Math.max(0, Number(retention.pushDeliveriesDays ?? 7)) * DAY;
    const pushMax = positiveIntOrNull(retention.pushDeliveriesMax ?? 2000);
    if (Array.isArray(db.pushDeliveries) && db.pushDeliveries.length) {
      const pdTs = (d) => parseTs(d.createdAt) ?? parseTs(d.updatedAt);
      const remove = new Set();
      for (const delivery of db.pushDeliveries) {
        const ts = pdTs(delivery);
        if (pushTtlMs > 0 && ts !== null && nowTs - ts > pushTtlMs) {
          remove.add(delivery);
        }
      }
      // pushMax === null (knob 0 / non-numeric) DISABLES the cap.
      if (pushMax !== null) {
        const surviving = db.pushDeliveries
          .filter((d) => !remove.has(d))
          .sort((a, b) => (pdTs(b) ?? 0) - (pdTs(a) ?? 0));
        for (const delivery of surviving.slice(pushMax)) remove.add(delivery);
      }
      counts.pushDeliveries = remove.size;
      if (!dryRun && remove.size) {
        db.pushDeliveries = db.pushDeliveries.filter((d) => !remove.has(d));
      }
    }

    // ── db.notifications: mixed. The feature shows only the newest ≤50
    //   UNREAD per user, so all three windows sit far past any live item:
    //     • silent:true  (tree_mutated / call_ended pings) — transient,
    //       already delivered via realtime+push → drop after 48h.
    //     • read (readAt set) — no read-history screen re-reads them → 30d.
    //     • unread — stale beyond a year → 365d (generous safety margin).
    const notifSilentMs =
      Math.max(0, Number(retention.notifSilentHours ?? 48)) * HOUR;
    const notifReadMs =
      Math.max(0, Number(retention.notifReadDays ?? 30)) * DAY;
    const notifUnreadMs =
      Math.max(0, Number(retention.notifUnreadDays ?? 365)) * DAY;
    if (Array.isArray(db.notifications) && db.notifications.length) {
      const remove = new Set();
      for (const notif of db.notifications) {
        const createdTs = parseTs(notif.createdAt);
        // Never delete a notification we cannot age (missing/unparseable
        // createdAt) — a live unread item must never be silently removed.
        if (createdTs === null) continue;
        const age = nowTs - createdTs;
        if (notif.silent === true) {
          if (notifSilentMs > 0 && age > notifSilentMs) {
            remove.add(notif);
            counts.notificationsSilent += 1;
          }
        } else if (notif.readAt) {
          // Возраст прочитанного — от readAt (см. Postgres-sweep): иначе
          // массовое «Прочитать всё» отправляло бы старый бэклог под
          // 30-дневное окно в первый же ночной проход.
          const readTs = parseTs(notif.readAt);
          const readAge = readTs === null ? age : nowTs - readTs;
          if (notifReadMs > 0 && readAge > notifReadMs) {
            remove.add(notif);
            counts.notificationsRead += 1;
          }
        } else if (notifUnreadMs > 0 && age > notifUnreadMs) {
          remove.add(notif);
          counts.notificationsUnread += 1;
        }
      }
      if (!dryRun && remove.size) {
        db.notifications = db.notifications.filter((n) => !remove.has(n));
      }
    }

    // ── db.treeChangeRecords: feature-backing HISTORY, but the byte driver
    //   is the full before/after/mergedFrom entity snapshots embedded on
    //   high-churn person.*/relation.* records (3.5 MB in prod). The client
    //   history sheet renders only type + names + timestamps — it NEVER
    //   reads details.before/after — so stripping those heavy keys from old
    //   NON-article records is invisible, KEEPS the record (timeline intact),
    //   and reclaims the bulk. article.* records (biography edit provenance —
    //   family-memory north-star) are left fully intact.
    const treeDetailMs =
      Math.max(0, Number(retention.treeChangeDetailDays ?? 30)) * DAY;
    if (treeDetailMs > 0) {
      counts.treeChangeDetailsStripped += this._stripTreeChangeDetails(db, {
        cutoffTs: nowTs - treeDetailMs,
        dryRun,
      });
    }

    // ── db.storyRequests: terminal-only TTL (STORY-REQUEST-MVP1-BRIEF.md
    //   §2.3). Pending requests are NEVER trimmed here — only their own 30d
    //   lazy expiry (_sweepExpiredStoryRequests) can end one; this sweep
    //   only reclaims already-terminal rows (answered/declined/expired/
    //   revoked) past a separate, longer retention window, mirroring
    //   db.calls' terminal-only TTL above. Age is measured from `updatedAt`
    //   (set on every terminal transition), falling back to `createdAt` for
    //   a hypothetical row that somehow never got one.
    const storyRequestsTtlMs =
      Math.max(0, Number(retention.storyRequestsTerminalDays ?? 90)) * DAY;
    if (
      storyRequestsTtlMs > 0 &&
      Array.isArray(db.storyRequests) &&
      db.storyRequests.length
    ) {
      const remove = new Set();
      for (const request of db.storyRequests) {
        if (request.status === "pending") continue;
        const ts = parseTs(request.updatedAt) ?? parseTs(request.createdAt);
        if (ts !== null && nowTs - ts > storyRequestsTtlMs) {
          remove.add(request);
        }
      }
      counts.storyRequestsTerminal = remove.size;
      if (!dryRun && remove.size) {
        db.storyRequests = db.storyRequests.filter((r) => !remove.has(r));
      }
    }

    // ── db.stories & db.storyReactions: retain expired stories for author archive
    //   up to 365d past expiresAt, and clean orphan reactions.
    const storiesArchiveMs =
      Math.max(0, Number(retention.storiesArchiveDays ?? 365)) * DAY;
    if (storiesArchiveMs > 0 && Array.isArray(db.stories) && db.stories.length) {
      const remove = new Set();
      for (const story of db.stories) {
        const expTs = parseTs(story.expiresAt);
        if (expTs !== null && nowTs - expTs > storiesArchiveMs) {
          remove.add(story);
        }
      }
      counts.storiesExpiredArchive = remove.size;
      if (!dryRun && remove.size) {
        db.stories = db.stories.filter((s) => !remove.has(s));
      }
    }
    if (Array.isArray(db.storyReactions) && db.storyReactions.length) {
      const activeStoryIds = new Set(
        (Array.isArray(db.stories) ? db.stories : [])
          .map((s) => String(s?.id || "").trim())
          .filter(Boolean),
      );
      const orphanReactions = db.storyReactions.filter(
        (r) => !activeStoryIds.has(String(r?.storyId || "").trim()),
      );
      counts.storyReactionsOrphan = orphanReactions.length;
      if (!dryRun && orphanReactions.length > 0) {
        db.storyReactions = db.storyReactions.filter((r) =>
          activeStoryIds.has(String(r?.storyId || "").trim()),
        );
      }
    }

    return counts;
  },

  // ── Phase 3.6: hard-delete background job ─────────────────────────
  // Sweeps physically deleted entries past their retention window:
  //   * `graphPersons`    — Path A explicit `hardDeleteScheduledAt`
  //                         set к deletedAt+30d; Path B
  //                         (`_reconcilePersonIdentities`) leaves null,
  //                         fallback на deletedAt + retentionDays.
  //   * `graphRelations`  — reconciliation tombstones, age-based.
  //   * `branches`        — reconciliation tombstones, age-based.
  //   * `personIdentities` — `_propagateIdentityFields` orphan
  //                          cleanup, age-based.
  //   * `branchPersonViews` — no own `deletedAt`; orphan-cleaned за
  //                            branches/graphPersons удалёнными в same
  //                            run.
  //
  // Hybrid eligibility: explicit `hardDeleteScheduledAt` wins, fallback
  // на `deletedAt + retention`. Backwards-compat с Path A + forward-
  // compat с custom per-entity extensions (e.g. user-requested
  // window).
  //
  // Order (application-level, не FK): leaf first → root last.
  //   `graphRelations` → `branches` → `personIdentities` →
  //   `graphPersons` → `branchPersonViews` (orphans от вышепроцессенных).
  //   Budget cap может halt mid-collection; partial state OK,
  //   reconciliation cleans dangling refs on next state load.
  //
  // Single full-state pass: `_read` → mutate в памяти → `_write`.
  // Atomic per document-storage (FileStore JSON write, PostgresStore
  // single-row UPDATE — all-or-nothing).
  //
  // See DECISIONS.md 2026-05-18 «Phase 3.6 hard-delete background job»
  // для альтернатив (A1 middleware inject отвергнут), rollout
  // sequence (master toggle → first-run-dry → live), risks.
  async hardDeleteExpired({
    now = new Date(),
    retentionDays = 30,
    semyaRetentionDays = Number(process.env.RODNYA_SEMYA_RETENTION_DAYS) || 90,
    auditRetentionDays = 90,
    maxPerRun = 10_000,
    dryRun = false,
    runId = null,
    logRetention = {},
  } = {}) {
    const startedAt = now instanceof Date ? now : new Date(now);
    const startedTs = startedAt.getTime();
    const retentionMs = retentionDays * 86_400_000;
    const semyaRetentionMs = semyaRetentionDays * 86_400_000;
    const auditRetentionMs = auditRetentionDays * 86_400_000;
    const effectiveRunId = runId || crypto.randomUUID();

    // Route the whole read→compute→mutate→write through _mutate so this daily
    // job serializes against every other _mutate writer (message-send, calls,
    // notifications). Otherwise its whole-blob overwrite — built on a snapshot
    // read OUTSIDE the lock — could clobber a message that was concurrently
    // appended + ack'd (the store-wide lost-update the _mutate primitive
    // closes). applyFn is pure in-memory (no awaits / nested store calls);
    // dry-run returns via skip() so it stays a pure read (no write).
    return this._mutate((db, skip) => {
    // Hybrid eligibility: explicit `hardDeleteScheduledAt` wins; иначе
    // age-based fallback (`deletedAt + retention`). Без `deletedAt` —
    // entity не soft-deleted, не eligible.
    const isEligible = (entity) => {
      if (!entity || !entity.deletedAt) return false;
      const explicit = entity.hardDeleteScheduledAt
        ? Date.parse(entity.hardDeleteScheduledAt)
        : NaN;
      const fallback = Date.parse(entity.deletedAt) + retentionMs;
      const scheduledTs = Number.isFinite(explicit) ? explicit : fallback;
      return Number.isFinite(scheduledTs) && scheduledTs < startedTs;
    };

    const isSemyaEligible = (semya) => {
      if (!semya || !semya.deletedAt) return false;
      const explicit = semya.hardDeleteScheduledAt
        ? Date.parse(semya.hardDeleteScheduledAt)
        : NaN;
      const fallback = Date.parse(semya.deletedAt) + semyaRetentionMs;
      const scheduledTs = Number.isFinite(explicit) ? explicit : fallback;
      return Number.isFinite(scheduledTs) && scheduledTs < startedTs;
    };

    const buildAuditEntry = (entityType, entity) => ({
      runId: effectiveRunId,
      entityType,
      entityId: entity.id,
      deletedAt: entity.deletedAt,
      scheduledAt:
        entity.hardDeleteScheduledAt ||
        new Date(Date.parse(entity.deletedAt) + retentionMs).toISOString(),
      hardDeletedAt: startedAt.toISOString(),
    });

    let budget = Math.max(0, Math.floor(maxPerRun));
    const newAuditEntries = [];
    const deletedCounts = {
      graphPersons: 0,
      graphRelations: 0,
      branches: 0,
      personIdentities: 0,
      branchPersonViews: 0,
      // Ship Q4a (2026-05-28): deletedPersons snapshot collection
      // swept by same job. Path 2 architecture (ec12804) — physical
      // erasure after retention + 3h floor (earliestHardDelete).
      deletedPersons: 0,
      // Ship Q4a (2026-05-28, Ship 30b): deletedPosts swept same way.
      deletedPosts: 0,
      semyi: 0,
      auditPruned: 0,
    };
    const sampleIds = {};
    const removeIdsByType = {
      graphRelation: new Set(),
      branch: new Set(),
      personIdentity: new Set(),
      graphPerson: new Set(),
      branchPersonView: new Set(),
    };

    // Explicit map — irregular plurals: branch→branches,
    // personIdentity→personIdentities (naive `${type}s` ломается).
    const collectionKeyByType = {
      graphRelation: "graphRelations",
      branch: "branches",
      personIdentity: "personIdentities",
      graphPerson: "graphPersons",
      branchPersonView: "branchPersonViews",
    };

    const takeEligible = (collection, entityType) => {
      const collectionKey = collectionKeyByType[entityType];
      for (const entity of collection || []) {
        if (budget <= 0) break;
        if (!isEligible(entity)) continue;
        newAuditEntries.push(buildAuditEntry(entityType, entity));
        removeIdsByType[entityType].add(entity.id);
        deletedCounts[collectionKey] += 1;
        if (!sampleIds[entityType]) sampleIds[entityType] = [];
        if (sampleIds[entityType].length < 5) {
          sampleIds[entityType].push(entity.id);
        }
        budget -= 1;
      }
    };

    takeEligible(db.graphRelations, "graphRelation");
    takeEligible(db.branches, "branch");
    takeEligible(db.personIdentities, "personIdentity");
    takeEligible(db.graphPersons, "graphPerson");

    // Ship Q4a (2026-05-28): deletedPersons sweep. Eligible rows:
    //   • restoredAt == null
    //   • hardDeleteScheduledAt < now (per existing isEligible)
    //   • earliestHardDelete < now (3h floor protection — defends
    //     against мисconfigured retention env)
    const removeDeletedPersonIds = new Set();
    for (const row of db.deletedPersons || []) {
      if (budget <= 0) break;
      if (row.restoredAt) continue;
      // Reuse isEligible — deletedPersons rows carry deletedAt +
      // hardDeleteScheduledAt в той же shape as graph entities.
      if (!isEligible(row)) continue;
      // Floor check — never purge before earliestHardDelete.
      if (
        row.earliestHardDelete &&
        Date.parse(row.earliestHardDelete) > startedTs
      ) {
        continue;
      }
      newAuditEntries.push({
        runId: effectiveRunId,
        entityType: "deletedPerson",
        entityId: row.id,
        deletedAt: row.deletedAt,
        scheduledAt: row.hardDeleteScheduledAt,
        hardDeletedAt: startedAt.toISOString(),
      });
      removeDeletedPersonIds.add(row.id);
      deletedCounts.deletedPersons += 1;
      if (!sampleIds.deletedPerson) sampleIds.deletedPerson = [];
      if (sampleIds.deletedPerson.length < 5) {
        sampleIds.deletedPerson.push(row.id);
      }
      budget -= 1;
    }

    // Ship Q4a (2026-05-28, Ship 30b): same sweep для deletedPosts.
    // Identical eligibility logic (3h floor + retention) — copy-paste
    // of persons block. Posts data sleeker (post + comments +
    // reactions snapshot), so physical erasure removes whole row.
    const removeDeletedPostIds = new Set();
    for (const row of db.deletedPosts || []) {
      if (budget <= 0) break;
      if (row.restoredAt) continue;
      if (!isEligible(row)) continue;
      if (
        row.earliestHardDelete &&
        Date.parse(row.earliestHardDelete) > startedTs
      ) {
        continue;
      }
      newAuditEntries.push({
        runId: effectiveRunId,
        entityType: "deletedPost",
        entityId: row.id,
        deletedAt: row.deletedAt,
        scheduledAt: row.hardDeleteScheduledAt,
        hardDeletedAt: startedAt.toISOString(),
      });
      removeDeletedPostIds.add(row.id);
      deletedCounts.deletedPosts += 1;
      if (!sampleIds.deletedPost) sampleIds.deletedPost = [];
      if (sampleIds.deletedPost.length < 5) {
        sampleIds.deletedPost.push(row.id);
      }
      budget -= 1;
    }

    // Wave B1 (P1.2): soft-deleted semyi sweep after 90-day retention.
    const removeSemyaIds = new Set();
    for (const semya of db.semyi || []) {
      if (budget <= 0) break;
      if (!isSemyaEligible(semya)) continue;
      newAuditEntries.push({
        runId: effectiveRunId,
        entityType: "semya",
        entityId: semya.id,
        deletedAt: semya.deletedAt,
        scheduledAt:
          semya.hardDeleteScheduledAt ||
          new Date(Date.parse(semya.deletedAt) + semyaRetentionMs).toISOString(),
        hardDeletedAt: startedAt.toISOString(),
      });
      removeSemyaIds.add(semya.id);
      deletedCounts.semyi += 1;
      if (!sampleIds.semya) sampleIds.semya = [];
      if (sampleIds.semya.length < 5) {
        sampleIds.semya.push(semya.id);
      }
      budget -= 1;
    }

    // Orphan cleanup для branchPersonViews — views ссылающиеся на
    // branches/graphPersons удалёнными в этом run. Views не имеют
    // собственного `deletedAt`, потому отдельный path.
    for (const view of db.branchPersonViews || []) {
      if (budget <= 0) break;
      const isOrphaned =
        removeIdsByType.branch.has(view.branchId) ||
        removeIdsByType.graphPerson.has(view.graphPersonId);
      if (!isOrphaned) continue;
      const viewKey =
        view.id ?? `${view.branchId || ""}:${view.graphPersonId || ""}`;
      newAuditEntries.push({
        runId: effectiveRunId,
        entityType: "branchPersonView",
        entityId: viewKey,
        deletedAt: null,
        scheduledAt: null,
        hardDeletedAt: startedAt.toISOString(),
      });
      removeIdsByType.branchPersonView.add(viewKey);
      deletedCounts.branchPersonViews += 1;
      if (!sampleIds.branchPersonView) sampleIds.branchPersonView = [];
      if (sampleIds.branchPersonView.length < 5) {
        sampleIds.branchPersonView.push(viewKey);
      }
      budget -= 1;
    }

    // Audit prune — entries старше `auditRetentionDays` от now.
    const auditPrune = this._pruneHardDeleteAudit(db, {
      cutoffTs: startedTs - auditRetentionMs,
      dryRun,
    });
    const survivingAudit = auditPrune.surviving;
    deletedCounts.auditPruned += auditPrune.pruned;

    const totalDeleted =
      deletedCounts.graphPersons +
      deletedCounts.graphRelations +
      deletedCounts.branches +
      deletedCounts.personIdentities +
      deletedCounts.branchPersonViews +
      deletedCounts.deletedPersons +
      deletedCounts.deletedPosts +
      deletedCounts.semyi;

    // Retention for unbounded log/history collections (blob-shrink). Mutates
    // db in place when !dryRun; the single _write below persists it alongside
    // the tombstone sweep. Runs regardless of the maxPerRun tombstone budget
    // (its own cheap O(n) filters), so large log collections never starve
    // graph-tombstone cleanup.
    const logCounts = this._sweepUnboundedLogs(db, logRetention, {
      nowTs: startedTs,
      dryRun,
    });

    const finishedAt = new Date();
    const summary = {
      runId: effectiveRunId,
      startedAt: startedAt.toISOString(),
      finishedAt: finishedAt.toISOString(),
      durationMs: finishedAt.getTime() - startedTs,
      dryRun,
      deleted: deletedCounts,
      logRetention: logCounts,
      sampleIds,
      capHit: budget <= 0 && totalDeleted >= Math.max(0, Math.floor(maxPerRun)),
      lastRunAt: dryRun
        ? db.hardDeleteLastRunAt || null
        : startedAt.toISOString(),
    };

    // Dry-run: report counts without persisting. skip() keeps it a pure read
    // (and _sweepUnboundedLogs already no-op'd its own mutations under dryRun).
    if (dryRun) return skip(summary);

    db.graphRelations = (db.graphRelations || []).filter(
      (r) => !removeIdsByType.graphRelation.has(r.id),
    );
    db.branches = (db.branches || []).filter(
      (b) => !removeIdsByType.branch.has(b.id),
    );
    db.personIdentities = (db.personIdentities || []).filter(
      (pi) => !removeIdsByType.personIdentity.has(pi.id),
    );
    db.graphPersons = (db.graphPersons || []).filter(
      (gp) => !removeIdsByType.graphPerson.has(gp.id),
    );
    db.branchPersonViews = (db.branchPersonViews || []).filter((v) => {
      const key = v.id ?? `${v.branchId || ""}:${v.graphPersonId || ""}`;
      return !removeIdsByType.branchPersonView.has(key);
    });
    // Ship Q4a: physically erase deletedPersons rows past retention
    // + floor. Snapshot data permanently gone — recovery impossible
    // beyond этого point.
    db.deletedPersons = (db.deletedPersons || []).filter(
      (r) => !removeDeletedPersonIds.has(r.id),
    );
    // Ship Q4a (Ship 30b): same для deletedPosts.
    db.deletedPosts = (db.deletedPosts || []).filter(
      (r) => !removeDeletedPostIds.has(r.id),
    );
    if (removeSemyaIds.size > 0) {
      db.semyi = (db.semyi || []).filter((s) => !removeSemyaIds.has(s.id));
      db.semyaMembers = (db.semyaMembers || []).filter(
        (m) => !removeSemyaIds.has(m.semyaId),
      );
      db.semyaInvitations = (db.semyaInvitations || []).filter(
        (inv) => !removeSemyaIds.has(inv.semyaId),
      );
      db.semyaBrowseTokens = (db.semyaBrowseTokens || []).filter(
        (t) => !removeSemyaIds.has(t.semyaId),
      );
      db.semyaMemberHiddenPersons = (db.semyaMemberHiddenPersons || []).filter(
        (h) => !removeSemyaIds.has(h.semyaId),
      );
      db.deletedPersons = (db.deletedPersons || []).filter(
        (r) => !r.semyaId || !removeSemyaIds.has(r.semyaId),
      );
      for (const tree of db.trees || []) {
        if (tree.semyaId && removeSemyaIds.has(tree.semyaId)) {
          tree.semyaId = null;
        }
      }
    }
    db.hardDeleteAudit = [...survivingAudit, ...newAuditEntries];
    db.hardDeleteLastRunAt = startedAt.toISOString();
    if (removeSemyaIds.size > 0) {
      Object.defineProperty(summary, "_sweptSemyaIds", {
        value: Array.from(removeSemyaIds),
        enumerable: false,
      });
    }
    return summary;
    });
  },
};
