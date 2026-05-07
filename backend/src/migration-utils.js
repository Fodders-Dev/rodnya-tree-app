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

function pickCanonicalPerson(linkedPersons, identity) {
  // Prefer the person record tied to the identity's claimed user
  // — that's the human's own profile, more likely to have the
  // truest values. Fall back to the most recently updated record.
  const claimedUserId = normalizeNullableString(identity?.userId);
  if (claimedUserId) {
    const claimed = linkedPersons.find(
      (entry) => normalizeNullableString(entry.userId) === claimedUserId,
    );
    if (claimed) return claimed;
  }
  return [...linkedPersons].sort((a, b) => {
    const aTs = String(a?.updatedAt || a?.createdAt || "");
    const bTs = String(b?.updatedAt || b?.createdAt || "");
    return bTs.localeCompare(aTs);
  })[0];
}

function buildGraphPersonFromCanonical(
  canonical,
  identityId,
  linkedPersons,
  timestamp,
) {
  const graphPerson = {
    id: identityId, // reuse identity id so existing identity-keyed
    // references (e.g. messages, mergeProposals) can resolve.
    createdBy: canonical?.creatorId || null,
    createdAt: canonical?.createdAt || timestamp,
    updatedAt: canonical?.updatedAt || timestamp,
    version: 0,
    deletedAt: null,
    mergedInto: null,
    userId: linkedPersons.find((p) => p.userId)?.userId || null,
    legacyPersonIds: linkedPersons.map((p) => p.id),
    // Phase 5 prep: every migrated node starts as private/manual.
    isPublic: false,
    source: "manual",
    // Phase 1.5 / Q5 default: contact fields stay owner-only on
    // living humans. Living/dead is canonical (isAlive); the route
    // layer will gate phone/email reads accordingly.
    contactPrivacy: "owner-only",
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
      // can switch to "blood-from-me" / "descendants-of" later
      // via the branch wizard (Phase 3.2).
      type: "manual",
      manualPersonIds: Array.from(new Set(manualPersonIds)).filter(Boolean),
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

  if (status.treesToGraph === "complete") {
    return {snapshot: target, changed: false, summary: null};
  }

  const persons = Array.isArray(target.persons) ? target.persons : [];
  const personIdentities = Array.isArray(target.personIdentities)
    ? target.personIdentities
    : [];
  const relations = Array.isArray(target.relations) ? target.relations : [];
  const trees = Array.isArray(target.trees) ? target.trees : [];
  const posts = Array.isArray(target.posts) ? target.posts : [];

  const timestamp = now();

  // Wipe any partial state from a previous failed run before
  // rebuilding — guarantees the migration is reproducible.
  const graphPersons = [];
  const graphRelations = [];
  const branches = [];
  const branchPersonViews = [];

  // ── 1. PersonIdentity → graphPerson (one row per real human) ──
  const personIdToGraphId = new Map();
  for (const identity of personIdentities) {
    const identityId = normalizeNullableString(identity?.id);
    if (!identityId) continue;
    const linkedPersons = persons.filter(
      (entry) => normalizeNullableString(entry.identityId) === identityId,
    );
    if (linkedPersons.length === 0) continue;
    const canonical = pickCanonicalPerson(linkedPersons, identity);
    const graphPerson = buildGraphPersonFromCanonical(
      canonical,
      identityId,
      linkedPersons,
      timestamp,
    );
    graphPersons.push(graphPerson);
    for (const linked of linkedPersons) {
      personIdToGraphId.set(linked.id, graphPerson.id);
    }
  }

  // ── 2. Persons without identity → 1:1 graphPerson ──
  for (const person of persons) {
    if (personIdToGraphId.has(person.id)) continue;
    const newId = idFactory();
    const graphPerson = buildGraphPersonFromCanonical(
      person,
      newId,
      [person],
      timestamp,
    );
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
  for (const relation of relations) {
    const p1g = personIdToGraphId.get(relation.person1Id);
    const p2g = personIdToGraphId.get(relation.person2Id);
    if (!p1g || !p2g) continue; // orphan — drop silently.
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

  target.graphPersons = graphPersons;
  target.graphRelations = graphRelations;
  target.branches = branches;
  target.branchPersonViews = branchPersonViews;
  status.treesToGraph = "complete";
  status.treesToGraphAt = timestamp;

  const summary = {
    legacyPersonCount: persons.length,
    graphPersonCount: graphPersons.length,
    legacyRelationCount: relations.length,
    graphRelationCount: graphRelations.length,
    branchCount: branches.length,
    branchPersonViewCount: branchPersonViews.length,
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
  SNAPSHOT_COLLECTION_KEYS,
  backfillPersonIdentities,
  collectLocalMediaObjects,
  formatBytes,
  formatSnapshotSummary,
  hashSnapshot,
  inferMediaContentType,
  migrateTreesToGraphAndBranches,
  summarizeSnapshot,
};
