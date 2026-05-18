const fs = require("node:fs/promises");
const path = require("node:path");
const crypto = require("node:crypto");

const SNAPSHOT_COLLECTION_KEYS = [
  "users",
  "sessions",
  "trees",
  "persons",
  "personIdentities",
  "circles",
  "circleMembers",
  "relations",
  "chats",
  "chatDrafts",
  "chatPins",
  "messages",
  "relationRequests",
  "treeInvitations",
  "notifications",
  "posts",
  "stories",
  "comments",
  "reports",
  "blocks",
  "pushDevices",
  "pushDeliveries",
  // Phase 3.1 collections — counted in summaries so
  // operational tooling (logging, dry-run reports, snapshot
  // diff'ing) can tell at a glance whether the graph mirror
  // is keeping pace with the legacy side.
  "graphPersons",
  "graphRelations",
  "branches",
  "branchPersonViews",
  "graphPersonEditGrants",
  "identityFieldConflicts",
  // Phase 3.6 hard-delete audit log. Counted в snapshot summaries
  // чтобы операционная log показывала backlog audit-записей
  // (sanity check для 90-day prune cycle).
  "hardDeleteAudit",
];

const MIME_TYPES_BY_EXTENSION = new Map([
  [".aac", "audio/aac"],
  [".avif", "image/avif"],
  [".gif", "image/gif"],
  [".heic", "image/heic"],
  [".heif", "image/heif"],
  [".jpeg", "image/jpeg"],
  [".jpg", "image/jpeg"],
  [".json", "application/json"],
  [".m4a", "audio/mp4"],
  [".mov", "video/quicktime"],
  [".mp3", "audio/mpeg"],
  [".mp4", "video/mp4"],
  [".oga", "audio/ogg"],
  [".ogg", "audio/ogg"],
  [".pdf", "application/pdf"],
  [".png", "image/png"],
  [".svg", "image/svg+xml"],
  [".txt", "text/plain; charset=utf-8"],
  [".wav", "audio/wav"],
  [".webm", "video/webm"],
  [".webp", "image/webp"],
]);

function summarizeSnapshot(snapshot) {
  return Object.fromEntries(
    SNAPSHOT_COLLECTION_KEYS.map((key) => [
      key,
      Array.isArray(snapshot?.[key]) ? snapshot[key].length : 0,
    ]),
  );
}

function formatSnapshotSummary(summary) {
  return SNAPSHOT_COLLECTION_KEYS.map((key) => `${key}=${summary[key] || 0}`).join(
    ", ",
  );
}

function stableSerialize(value) {
  if (Array.isArray(value)) {
    return `[${value.map((entry) => stableSerialize(entry)).join(",")}]`;
  }
  if (value && typeof value === "object") {
    const keys = Object.keys(value).sort((left, right) =>
      left.localeCompare(right),
    );
    return `{${keys
      .map((key) => `${JSON.stringify(key)}:${stableSerialize(value[key])}`)
      .join(",")}}`;
  }
  return JSON.stringify(value);
}

function hashSnapshot(snapshot) {
  return crypto
    .createHash("sha256")
    .update(stableSerialize(snapshot))
    .digest("hex");
}

function normalizeNullableString(value) {
  const normalized = String(value || "").trim();
  return normalized ? normalized : null;
}

function normalizeIdList(value) {
  return Array.from(
    new Set(
      (Array.isArray(value) ? value : [])
        .map((entry) => normalizeNullableString(entry))
        .filter(Boolean),
    ),
  ).sort((left, right) => left.localeCompare(right));
}

function backfillPersonIdentities(
  snapshot,
  {
    idFactory = () => crypto.randomUUID(),
    now = () => new Date().toISOString(),
  } = {},
) {
  const target = snapshot && typeof snapshot === "object" ? snapshot : {};
  const persons = Array.isArray(target.persons) ? target.persons : [];
  const rawIdentities = Array.isArray(target.personIdentities)
    ? target.personIdentities
    : [];
  const beforeHash = hashSnapshot({
    persons,
    personIdentities: rawIdentities,
  });
  const timestamp = now();
  const identitiesById = new Map();
  let createdCount = 0;
  let linkedPersonCount = 0;

  target.persons = persons;

  function upsertIdentity(rawIdentity = {}, fallbackId = null) {
    const identityId =
      normalizeNullableString(rawIdentity?.id) ||
      normalizeNullableString(fallbackId) ||
      normalizeNullableString(idFactory());
    if (!identityId) {
      return null;
    }

    const existing = identitiesById.get(identityId);
    const nextPersonIds = normalizeIdList([
      ...normalizeIdList(existing?.personIds),
      ...normalizeIdList(rawIdentity?.personIds),
    ]);

    if (existing) {
      identitiesById.set(identityId, {
        ...existing,
        ...rawIdentity,
        id: identityId,
        userId:
          normalizeNullableString(existing.userId) ||
          normalizeNullableString(rawIdentity?.userId),
        personIds: nextPersonIds,
        createdAt: existing.createdAt || rawIdentity?.createdAt || timestamp,
        updatedAt: rawIdentity?.updatedAt || existing.updatedAt || timestamp,
      });
      return identitiesById.get(identityId);
    }

    const identity = {
      ...rawIdentity,
      id: identityId,
      userId: normalizeNullableString(rawIdentity?.userId),
      personIds: nextPersonIds,
      createdAt: rawIdentity?.createdAt || timestamp,
      updatedAt: rawIdentity?.updatedAt || timestamp,
    };
    identitiesById.set(identityId, identity);
    return identity;
  }

  for (const identity of rawIdentities) {
    upsertIdentity(identity);
  }

  const identityIdByPersonId = new Map();
  for (const identity of identitiesById.values()) {
    for (const personId of normalizeIdList(identity.personIds)) {
      if (!identityIdByPersonId.has(personId)) {
        identityIdByPersonId.set(personId, identity.id);
      }
    }
  }

  for (const person of persons) {
    if (!person || typeof person !== "object") {
      continue;
    }

    const personId = normalizeNullableString(person.id);
    if (!personId) {
      continue;
    }

    const existingIdentityId =
      normalizeNullableString(person.identityId) ||
      identityIdByPersonId.get(personId) ||
      null;
    let identity = existingIdentityId
      ? identitiesById.get(existingIdentityId)
      : null;

    if (!identity) {
      identity = upsertIdentity(
        {
          id: existingIdentityId || undefined,
          personIds: [personId],
        },
        existingIdentityId,
      );
      createdCount += 1;
    }

    if (!identity) {
      continue;
    }

    if (person.identityId !== identity.id) {
      person.identityId = identity.id;
      linkedPersonCount += 1;
    }

    const nextPersonIds = normalizeIdList([
      ...(identity.personIds || []),
      personId,
    ]);
    if (nextPersonIds.length !== normalizeIdList(identity.personIds).length) {
      linkedPersonCount += 1;
    }
    identity.personIds = nextPersonIds;
  }

  target.personIdentities = Array.from(identitiesById.values())
    .map((identity) => ({
      ...identity,
      id: normalizeNullableString(identity.id),
      userId: normalizeNullableString(identity.userId),
      personIds: normalizeIdList(identity.personIds),
      createdAt: identity.createdAt || timestamp,
      updatedAt: identity.updatedAt || timestamp,
    }))
    .filter(
      (identity) =>
        identity.id &&
        (identity.userId ||
          (Array.isArray(identity.personIds) && identity.personIds.length > 0)),
    );

  const afterHash = hashSnapshot({
    persons: target.persons,
    personIdentities: target.personIdentities,
  });

  return {
    snapshot: target,
    changed: beforeHash !== afterHash,
    createdCount,
    linkedPersonCount,
  };
}

// ── Phase 3.1: trees → graph + branches migration ───────────────────
// Walks the legacy `trees` / `persons` / `relations` /
// `personIdentities` collections and builds a parallel set of
// `graphPersons` / `graphRelations` / `branches` / `branchPersonViews`
// rows that represent the same data under the unified-graph model.
//
// CONTRACT
// • Idempotent: re-running on a snapshot that already has
//   `migrationStatus.treesToGraph === "complete"` returns
//   {changed: false} without touching any collection.
// • Non-destructive: the legacy collections are NOT modified or
//   removed. The Phase 3.1c back-compat layer reads from / writes
//   to BOTH old and new until 3.4 ships and we can drop the legacy
//   side. Old clients keep working in the meantime.
// • Reversible: a failure mid-run leaves
//   `migrationStatus.treesToGraph` unset; the next run re-builds
//   from scratch (graphPersons etc. are wiped first).
//
// MAPPING
//   PersonIdentity (with N linked persons) → 1 graphPerson
//   person without identity                → 1 graphPerson
//   tree                                   → 1 branch
//   relation                               → 1 graphRelation
//                                            (dedup by canonical
//                                             pair+type — same human
//                                             pair on different trees
//                                             collapses to one edge)
//   per-(tree, person) editorial fields    → 1 branchPersonView
//                                            (notes / familySummary /
//                                             bio / visibility /
//                                             per-branch label)

const GRAPH_PERSON_CANONICAL_FIELDS = Object.freeze([
  "name",
  "maidenName",
  "gender",
  "birthDate",
  "deathDate",
  "isAlive",
  "birthPlace",
  "deathPlace",
  "photoUrl",
  "primaryPhotoUrl",
  "photoGallery",
]);

// Phase 3.1 (DECISIONS.md ответ B): canonical graphPerson строится
// по принципу highest-completeness wins per-field, не record-уровня.
// Старая `pickCanonicalPerson` (claimed user → updatedAt fallback)
// теряла данные: если user-claim'енный record был заполнен меньше,
// чем «чужая» копия с большим количеством полей, мы намеренно брали
// менее полную запись. Ответ B: для каждого field отдельно берём
// source с наибольшим completeness; все divergent values записываем
// в `identityFieldConflicts` (та самая Phase 1.3 коллекция) с
// `resolvedAt: null` и `origin: "migration"` — пользователь решит
// через тот же ⚠️ UI.

function migrationFieldsEqual(field, leftValue, rightValue) {
  // photoGallery — массив объектов с url'ами. Сравниваем JSON-strings
  // как в `_syncPersonToGraph` / `valuesEqualForPropagation`, чтобы
  // migration и runtime propagation оценивали "то же или нет"
  // одинаково.
  if (field === "photoGallery") {
    return JSON.stringify(leftValue ?? []) === JSON.stringify(rightValue ?? []);
  }
  return leftValue === rightValue;
}

function migrationCompletenessScore(value) {
  if (value == null) return 0;
  if (typeof value === "string") return value.trim().length;
  if (Array.isArray(value)) return value.length;
  if (typeof value === "object") {
    return Object.keys(value).length;
  }
  // boolean / number — non-null beats null but all carry equal weight.
  return 1;
}

function migrationFieldIsNonEmpty(value) {
  if (value == null) return false;
  if (typeof value === "string") return value.trim() !== "";
  if (Array.isArray(value)) return value.length > 0;
  return true;
}

function pickCanonicalFieldsAndCollectConflicts({
  linkedPersons,
  identityId,
  timestamp,
  idFactory,
}) {
  const canonical = {};
  const conflicts = [];

  for (const field of GRAPH_PERSON_CANONICAL_FIELDS) {
    // Сужаем до non-empty кандидатов и сортируем по completeness.
    // Ties ломаются by updatedAt (свежее > старое) — без этого
    // итератор массива стабильно даёт первый в файле, и реран
    // мог бы поменять «победителя» из-за reorder в JSONB.
    const ranked = linkedPersons
      .map((person) => ({person, value: person[field]}))
      .filter((entry) => migrationFieldIsNonEmpty(entry.value))
      .sort((a, b) => {
        const scoreDiff =
          migrationCompletenessScore(b.value) -
          migrationCompletenessScore(a.value);
        if (scoreDiff !== 0) return scoreDiff;
        const aTs = String(a.person?.updatedAt || a.person?.createdAt || "");
        const bTs = String(b.person?.updatedAt || b.person?.createdAt || "");
        const tsDiff = bTs.localeCompare(aTs);
        if (tsDiff !== 0) return tsDiff;
        // Tertiary: lex order by person.id. Without this, equal
        // completeness AND equal timestamp leaves the order to
        // Array.prototype.sort stability — deterministic on Node ≥ 12
        // but only for the same input order, which the JSONB
        // serialization isn't required to guarantee. Explicit ID
        // breaker makes migration output stable across reorderings.
        return String(a.person?.id || "").localeCompare(
          String(b.person?.id || ""),
        );
      });

    if (ranked.length === 0) {
      canonical[field] = null;
      continue;
    }

    const winner = ranked[0];
    canonical[field] =
      winner.value === undefined ? null : structuredClone(winner.value);

    // Каждый отличающийся from-canonical value → conflict row.
    // Дубликаты с тем же значением (cross-tree picker уже
    // распространил это поле) — не считаем конфликтом.
    for (const loser of ranked.slice(1)) {
      if (migrationFieldsEqual(field, winner.value, loser.value)) continue;
      conflicts.push({
        id: idFactory(),
        identityId,
        // Source = «откуда взяли winner-value»; target = тот legacy
        // person, чью локальную запись мы НЕ затёрли.
        sourcePersonId: winner.person.id,
        sourceTreeId: winner.person.treeId,
        targetPersonId: loser.person.id,
        targetTreeId: loser.person.treeId,
        field,
        sourceValue: structuredClone(winner.value),
        targetValue: structuredClone(loser.value),
        createdAt: timestamp,
        updatedAt: timestamp,
        resolvedAt: null,
        resolvedBy: null,
        // Маркер «родился из migration», не Phase 1.1 runtime
        // propagation. Помогает observability и (если когда-то
        // понадобится) фильтровать UI на «свежие правки» vs
        // «migration-time» конфликты.
        origin: "migration",
      });
    }
  }

  return {canonical, conflicts};
}

function buildGraphPersonRow({
  canonical,
  identityId,
  linkedPersons,
  timestamp,
}) {
  // userId — берём первый non-null среди linked. Поскольку identity
  // привязана к одному user-аккаунту максимум (см. _ensureUserIdentity),
  // первый-же ненулевой совпадёт с identity.userId если она такая есть.
  const linkedUserId = linkedPersons.find((p) => p.userId)?.userId || null;

  const earliestCreatedAt =
    linkedPersons
      .map((p) => p.createdAt)
      .filter(Boolean)
      .sort((left, right) => String(left).localeCompare(String(right)))[0] ||
    timestamp;
  const latestUpdatedAt =
    linkedPersons
      .map((p) => p.updatedAt)
      .filter(Boolean)
      .sort((left, right) => String(right).localeCompare(String(left)))[0] ||
    timestamp;

  const creator =
    linkedPersons.map((p) => p.creatorId).filter(Boolean)[0] || null;

  const graphPerson = {
    id: identityId,
    createdBy: creator,
    createdAt: earliestCreatedAt,
    updatedAt: latestUpdatedAt,
    version: 0,
    deletedAt: null,
    // Phase 3.1 (DECISIONS.md ответ C): 30-day soft-delete window.
    // Set on soft-delete, drives the future hard-delete background
    // job (Phase 3.6); on undo it gets cleared back to null.
    hardDeleteScheduledAt: null,
    deletedByUserId: null,
    mergedInto: null,
    userId: linkedUserId,
    legacyPersonIds: linkedPersons.map((p) => p.id),
    isPublic: false,
    source: "manual",
    contactPrivacy: "owner-only",
    // Phase 3.1 (DECISIONS.md ответ A): privacy escape hatch.
    // Default — "connected-via-blood-graph" (≤ MAX_BLOOD_HOPS видят
    // узел). Auto-resolution в read path лечит deceased + >100 лет
    // в "public"; owner override — visibilityOverride=true.
    visibility: "connected-via-blood-graph",
    visibilityOverride: false,
  };

  for (const field of GRAPH_PERSON_CANONICAL_FIELDS) {
    graphPerson[field] = canonical?.[field] ?? null;
  }
  return graphPerson;
}

function buildBranchFromTree(tree, manualPersonIds) {
  return {
    id: tree.id, // reuse treeId so /v1/trees/:treeId/* keep resolving.
    ownerId: tree.creatorId,
    name: tree.name,
    description: tree.description || "",
    isPrivate: tree.isPrivate !== false,
    kind: tree.kind || "family",
    includeRules: {
      // Manual is the safest default for migrated branches —
      // preserves exactly the set of people the tree had. Users
      // can switch to "blood-from-me" / "descendants-of" /
      // "ancestors-of" later via the Phase 6.4 branch wizard, at
      // which point `anchorPersonId` and `maxHops` get filled in.
      // Phase 3.1 (DECISIONS.md ответ D): default maxHops = 5 for
      // future blood-rule branches; carried on every includeRules
      // shape so the helper doesn't have to special-case absence.
      type: "manual",
      manualPersonIds: Array.from(new Set(manualPersonIds)).filter(Boolean),
      anchorPersonId: null,
      maxHops: 5,
    },
    memberIds: Array.isArray(tree.memberIds)
      ? [...tree.memberIds]
      : Array.isArray(tree.members)
          ? [...tree.members]
          : [],
    publicSlug: tree.publicSlug || null,
    isCertified: tree.isCertified === true,
    certificationNote: tree.certificationNote || null,
    legacyTreeId: tree.id,
    deletedAt: null,
    createdAt: tree.createdAt,
    updatedAt: tree.updatedAt,
  };
}

function buildGraphRelationDedupKey(person1Id, person2Id, relation) {
  // Order pair canonically so an A→B edge and the B→A inverse
  // end up on the same key (relation1to2 and relation2to1 are
  // already symmetric metadata, but we sort anyway).
  const [first, second] = [person1Id, person2Id].sort();
  return `${first}|${second}|${relation.relation1to2 || ""}|${relation.relation2to1 || ""}`;
}

// Phase 3.1: ledger key for the per-field highest-completeness
// migration. `complete` (v1) marked the old record-level canonical
// picking; v1 snapshots get rebuilt automatically on the next
// startup so they pick up the new logic plus the new schema fields
// (visibility, hardDeleteScheduledAt, …). DECISIONS.md 2026-05-10
// fixes "re-run целиком" as the cutover strategy — incremental
// patching was rejected because complete-v2 didn't yet exist and
// no real runtime state had accumulated on top of v1.
const TREES_TO_GRAPH_LEDGER_V2 = "complete-v2";
const TREES_TO_GRAPH_LEDGER_V1 = "complete";

function migrateTreesToGraphAndBranches(
  snapshot,
  {
    now = () => new Date().toISOString(),
    idFactory = () => crypto.randomUUID(),
  } = {},
) {
  const target = snapshot && typeof snapshot === "object" ? snapshot : {};
  const status =
    target.migrationStatus && typeof target.migrationStatus === "object"
      ? target.migrationStatus
      : {};
  target.migrationStatus = status;

  // v2 already done → no-op. v1 — rebuild from scratch.
  if (status.treesToGraph === TREES_TO_GRAPH_LEDGER_V2) {
    return {snapshot: target, changed: false, summary: null};
  }

  const wasV1 = status.treesToGraph === TREES_TO_GRAPH_LEDGER_V1;

  const persons = Array.isArray(target.persons) ? target.persons : [];
  const personIdentities = Array.isArray(target.personIdentities)
    ? target.personIdentities
    : [];
  const relations = Array.isArray(target.relations) ? target.relations : [];
  const trees = Array.isArray(target.trees) ? target.trees : [];
  const posts = Array.isArray(target.posts) ? target.posts : [];

  const timestamp = now();

  // Wipe any partial state from a previous failed run before
  // rebuilding — guarantees the migration is reproducible. On a
  // v1→v2 rerun this also clears stale graph rows that picked
  // canonical fields by record-level (claimed user → updatedAt) so
  // the new per-field logic gets a clean slate.
  const graphPersons = [];
  const graphRelations = [];
  const branches = [];
  const branchPersonViews = [];

  // identityFieldConflicts is a Phase 1.3 collection that's also
  // used at runtime by `_propagateIdentityFields` to surface
  // edit-time divergences. On rerun we drop ONLY the rows we
  // ourselves wrote (origin === "migration"); runtime rows stay
  // so users don't lose unresolved Phase 1.3 conflicts they were
  // about to handle.
  if (Array.isArray(target.identityFieldConflicts)) {
    target.identityFieldConflicts = target.identityFieldConflicts.filter(
      (entry) => entry?.origin !== "migration",
    );
  } else {
    target.identityFieldConflicts = [];
  }

  // ── 1. PersonIdentity → graphPerson (one row per real human) ──
  const personIdToGraphId = new Map();
  let identitiesWithLinkedPersons = 0;
  for (const identity of personIdentities) {
    const identityId = normalizeNullableString(identity?.id);
    if (!identityId) continue;
    const linkedPersons = persons.filter(
      (entry) => normalizeNullableString(entry.identityId) === identityId,
    );
    if (linkedPersons.length === 0) continue;
    identitiesWithLinkedPersons += 1;

    const {canonical, conflicts} = pickCanonicalFieldsAndCollectConflicts({
      linkedPersons,
      identityId,
      timestamp,
      idFactory,
    });

    target.identityFieldConflicts.push(...conflicts);

    // Stamp lastPropagatedFields на каждом legacy person — без
    // этого Phase 1.1 _propagateIdentityFields на первом edit
    // после migration увидел бы «локальная правка» (т.к.
    // snapshot отсутствует) и выкинул ложный конфликт. Stamp
    // canonical-value на ВСЕ linked-records, потому что
    // canonical = «то, что graphPerson сейчас держит», и
    // следующий runtime propagation должен mirror этого.
    for (const person of linkedPersons) {
      if (
        !person.lastPropagatedFields ||
        typeof person.lastPropagatedFields !== "object"
      ) {
        person.lastPropagatedFields = {};
      }
      for (const field of GRAPH_PERSON_CANONICAL_FIELDS) {
        person.lastPropagatedFields[field] =
          canonical[field] === undefined ? null : structuredClone(canonical[field]);
      }
    }

    const graphPerson = buildGraphPersonRow({
      canonical,
      identityId,
      linkedPersons,
      timestamp,
    });
    graphPersons.push(graphPerson);
    for (const linked of linkedPersons) {
      personIdToGraphId.set(linked.id, graphPerson.id);
    }
  }

  // ── 2. Persons without identity → 1:1 graphPerson ──
  let personsWithoutIdentity = 0;
  for (const person of persons) {
    if (personIdToGraphId.has(person.id)) continue;
    personsWithoutIdentity += 1;
    const newId = idFactory();
    // Single-source canonical — нет divergent values, конфликтов
    // не пишем. lastPropagatedFields всё равно ставим, чтобы при
    // дальнейшем cross-tree picking this person стал sourceFor
    // identity propagation без ложного first-pass конфликта.
    if (
      !person.lastPropagatedFields ||
      typeof person.lastPropagatedFields !== "object"
    ) {
      person.lastPropagatedFields = {};
    }
    const canonical = {};
    for (const field of GRAPH_PERSON_CANONICAL_FIELDS) {
      const value = person[field];
      canonical[field] =
        value === undefined ? null : structuredClone(value);
      person.lastPropagatedFields[field] = canonical[field];
    }
    const graphPerson = buildGraphPersonRow({
      canonical,
      identityId: newId,
      linkedPersons: [person],
      timestamp,
    });
    graphPersons.push(graphPerson);
    personIdToGraphId.set(person.id, graphPerson.id);
  }

  // ── 3. trees → branches with manualPersons rule ──
  const treeIdToBranchId = new Map();
  for (const tree of trees) {
    const treePersons = persons.filter((p) => p.treeId === tree.id);
    const manualPersonIds = treePersons
      .map((p) => personIdToGraphId.get(p.id))
      .filter(Boolean);
    const branch = buildBranchFromTree(tree, manualPersonIds);
    branches.push(branch);
    treeIdToBranchId.set(tree.id, branch.id);
  }

  // ── 4. relations → graphRelations (dedup by canonical pair+type) ──
  const relationKeySeen = new Map(); // key → graphRelation index
  let droppedOrphanRelations = 0;
  for (const relation of relations) {
    const p1g = personIdToGraphId.get(relation.person1Id);
    const p2g = personIdToGraphId.get(relation.person2Id);
    if (!p1g || !p2g) {
      droppedOrphanRelations += 1;
      continue; // orphan — drop silently.
    }
    const key = buildGraphRelationDedupKey(p1g, p2g, relation);
    const seenIndex = relationKeySeen.get(key);
    if (seenIndex !== undefined) {
      const existing = graphRelations[seenIndex];
      existing.legacyRelationIds.push(relation.id);
      if (relation.treeId) existing.legacyTreeIds.push(relation.treeId);
      continue;
    }
    const graphRelation = {
      id: relation.id, // reuse for back-compat
      person1Id: p1g,
      person2Id: p2g,
      relation1to2: relation.relation1to2,
      relation2to1: relation.relation2to1,
      isConfirmed: relation.isConfirmed === true,
      createdBy: relation.createdBy || null,
      createdAt: relation.createdAt || timestamp,
      updatedAt: relation.updatedAt || timestamp,
      version: 0,
      deletedAt: null,
      marriageDate: relation.marriageDate || null,
      divorceDate: relation.divorceDate || null,
      customRelationLabel1to2: relation.customRelationLabel1to2 || null,
      customRelationLabel2to1: relation.customRelationLabel2to1 || null,
      parentSetId: relation.parentSetId || null,
      parentSetType: relation.parentSetType || null,
      isPrimaryParentSet:
        typeof relation.isPrimaryParentSet === "boolean"
          ? relation.isPrimaryParentSet
          : null,
      unionId: relation.unionId || null,
      unionType: relation.unionType || null,
      unionStatus: relation.unionStatus || null,
      legacyRelationIds: [relation.id],
      legacyTreeIds: relation.treeId ? [relation.treeId] : [],
    };
    relationKeySeen.set(key, graphRelations.length);
    graphRelations.push(graphRelation);
  }

  // ── 5. per-(tree, person) editorial fields → branchPersonViews ──
  for (const person of persons) {
    const branchId = treeIdToBranchId.get(person.treeId);
    if (!branchId) continue;
    const personId = personIdToGraphId.get(person.id);
    if (!personId) continue;
    const view = {
      id: idFactory(),
      branchId,
      personId,
      label: null,
      photoOverride: null,
      notes: person.notes ?? null,
      familySummary: person.familySummary ?? null,
      bio: person.bio ?? null,
      visibility: person.visibility ?? null,
      legacyPersonId: person.id,
      createdAt: person.createdAt || timestamp,
      updatedAt: person.updatedAt || timestamp,
    };
    branchPersonViews.push(view);
  }

  // ── 6. Posts get back-compat branchIds ──
  // Phase 3.4 will switch UI to surface this directly. For now we
  // just stamp it so feed queries can move to the new field
  // without back-fill churn later. `treeId` stays in place for
  // legacy callers.
  for (const post of posts) {
    if (Array.isArray(post.branchIds) && post.branchIds.length > 0) continue;
    if (post.treeId && treeIdToBranchId.has(post.treeId)) {
      post.branchIds = [treeIdToBranchId.get(post.treeId)];
    }
  }

  // ── 7. Pre-flight count check (DECISIONS.md 2026-05-10
  // nice-to-have). Перед write проверяем что invariants
  // выполнены: каждый identity-with-linked → один graphPerson;
  // каждый person-без-identity → ещё один graphPerson; каждый
  // tree → одна branch; relations с обеих сторон в graph
  // соответствуют либо новому row, либо merged-into duplicate
  // (legacyRelationIds покрывают всё, что не orphan'ы). Любое
  // расхождение — abort с явной ошибкой, без write. Это
  // страховка от тихого data loss при будущих изменениях
  // canonical-picking логики.
  const expectedGraphPersonCount =
    identitiesWithLinkedPersons + personsWithoutIdentity;
  if (graphPersons.length !== expectedGraphPersonCount) {
    throw new Error(
      `migrateTreesToGraphAndBranches pre-flight: graphPersons.length=${graphPersons.length}, expected ${expectedGraphPersonCount} (=${identitiesWithLinkedPersons} identities + ${personsWithoutIdentity} orphans). Aborting before write.`,
    );
  }
  if (branches.length !== trees.length) {
    throw new Error(
      `migrateTreesToGraphAndBranches pre-flight: branches.length=${branches.length}, expected ${trees.length}. Aborting before write.`,
    );
  }
  const totalLegacyRelationsInGraph = graphRelations.reduce(
    (acc, entry) => acc + (entry.legacyRelationIds || []).length,
    0,
  );
  const expectedLegacyRelationsInGraph =
    relations.length - droppedOrphanRelations;
  if (totalLegacyRelationsInGraph !== expectedLegacyRelationsInGraph) {
    throw new Error(
      `migrateTreesToGraphAndBranches pre-flight: graphRelations cover ${totalLegacyRelationsInGraph} legacy relation ids, expected ${expectedLegacyRelationsInGraph} (=${relations.length} input - ${droppedOrphanRelations} orphans). Aborting before write.`,
    );
  }

  target.graphPersons = graphPersons;
  target.graphRelations = graphRelations;
  target.branches = branches;
  target.branchPersonViews = branchPersonViews;
  if (!Array.isArray(target.graphPersonEditGrants)) {
    target.graphPersonEditGrants = [];
  }
  status.treesToGraph = TREES_TO_GRAPH_LEDGER_V2;
  status.treesToGraphAt = timestamp;
  if (wasV1) {
    // Stash for observability — useful when post-cutover monitoring
    // wants to know which snapshots were rebuilt vs. fresh.
    status.treesToGraphRebuiltFromV1At = timestamp;
  }

  const summary = {
    legacyPersonCount: persons.length,
    graphPersonCount: graphPersons.length,
    legacyRelationCount: relations.length,
    graphRelationCount: graphRelations.length,
    branchCount: branches.length,
    branchPersonViewCount: branchPersonViews.length,
    migrationConflictCount: target.identityFieldConflicts.filter(
      (entry) => entry?.origin === "migration",
    ).length,
    droppedOrphanRelationCount: droppedOrphanRelations,
    rebuiltFromV1: wasV1,
  };

  return {snapshot: target, changed: true, summary};
}

async function walkFiles(rootPath) {
  const entries = await fs.readdir(rootPath, {withFileTypes: true});
  const nestedPaths = [];

  for (const entry of entries) {
    const resolvedPath = path.join(rootPath, entry.name);
    if (entry.isDirectory()) {
      nestedPaths.push(...(await walkFiles(resolvedPath)));
      continue;
    }
    if (entry.isFile()) {
      nestedPaths.push(resolvedPath);
    }
  }

  return nestedPaths;
}

async function collectLocalMediaObjects(rootPath) {
  const normalizedRootPath = path.resolve(rootPath);
  const absoluteFilePaths = await walkFiles(normalizedRootPath);

  return Promise.all(
    absoluteFilePaths.map(async (absolutePath) => {
      const relativePath = path
        .relative(normalizedRootPath, absolutePath)
        .replace(/\\/g, "/");
      const [bucket, ...restParts] = relativePath.split("/").filter(Boolean);
      if (!bucket || restParts.length === 0) {
        throw new Error(
          `Unexpected media layout for ${absolutePath}. Expected <bucket>/<path>.`,
        );
      }

      const stat = await fs.stat(absolutePath);
      return {
        absolutePath,
        bucket,
        relativePath: restParts.join("/"),
        sizeBytes: stat.size,
      };
    }),
  );
}

function inferMediaContentType(filePath) {
  const extension = path.extname(String(filePath || "")).trim().toLowerCase();
  return MIME_TYPES_BY_EXTENSION.get(extension) || "application/octet-stream";
}

function formatBytes(sizeBytes) {
  if (!Number.isFinite(sizeBytes) || sizeBytes < 1024) {
    return `${Math.max(0, Number(sizeBytes) || 0)} B`;
  }
  const units = ["KB", "MB", "GB", "TB"];
  let value = sizeBytes / 1024;
  let index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index += 1;
  }
  return `${value.toFixed(1)} ${units[index]}`;
}

module.exports = {
  GRAPH_PERSON_CANONICAL_FIELDS,
  SNAPSHOT_COLLECTION_KEYS,
  backfillPersonIdentities,
  buildGraphRelationDedupKey,
  collectLocalMediaObjects,
  formatBytes,
  formatSnapshotSummary,
  hashSnapshot,
  inferMediaContentType,
  migrateTreesToGraphAndBranches,
  summarizeSnapshot,
};
