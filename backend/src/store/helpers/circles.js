const crypto = require("node:crypto");
const {
  backfillPersonIdentities,
} = require("../../migration-utils");
const {
  AUTO_CIRCLE_KINDS,
} = require("../constants");
const {
  addMapSetValue,
  buildSortedIdKey,
  childIdFromRelation,
  isSpouseLikeRelation,
  parentIdFromRelation,
  sameNormalizedIds,
} = require("./relation-utils");
const {
  normalizeNullableString,
  normalizeParticipantIds,
  nowIso,
} = require("./utils");

function defaultCircleId(treeId, kind) {
  return `circle:${treeId}:${kind}`;
}

function normalizeCircleKind(kind) {
  const normalizedKind = String(kind || "custom").trim().toLowerCase();
  if (
    normalizedKind === "all_tree" ||
    normalizedKind === "favorites" ||
    AUTO_CIRCLE_KINDS.has(normalizedKind)
  ) {
    return normalizedKind;
  }
  return "custom";
}

function isAutoCircleKind(kind) {
  return AUTO_CIRCLE_KINDS.has(normalizeCircleKind(kind));
}

function autoCircleId({treeId, kind, anchorPersonId = null, anchorPersonIds = []}) {
  const normalizedKind = normalizeCircleKind(kind);
  if (normalizedKind === "descendants_of" || normalizedKind === "ancestors_of") {
    return `circle:${treeId}:${normalizedKind}:${normalizeNullableString(anchorPersonId)}`;
  }
  if (normalizedKind === "pair") {
    return `circle:${treeId}:pair:${buildSortedIdKey(anchorPersonIds)}`;
  }
  return defaultCircleId(treeId, normalizedKind);
}

function createCircleRecord({
  treeId,
  name,
  description = null,
  kind = "custom",
  createdBy = null,
  id = null,
  anchorPersonId = null,
  anchorPersonIds = [],
}) {
  const normalizedKind = normalizeCircleKind(kind);
  const normalizedAnchorPersonId = normalizeNullableString(anchorPersonId);
  const normalizedAnchorPersonIds = normalizeParticipantIds(anchorPersonIds);
  const timestamp = nowIso();
  return {
    id:
      normalizeNullableString(id) ||
      (normalizedKind === "custom"
        ? crypto.randomUUID()
        : autoCircleId({
            treeId,
            kind: normalizedKind,
            anchorPersonId: normalizedAnchorPersonId,
            anchorPersonIds: normalizedAnchorPersonIds,
          })),
    treeId,
    kind: normalizedKind,
    name:
      String(
        name ||
          (normalizedKind === "favorites"
            ? "Избранные"
            : normalizedKind === "all_tree"
              ? "Всё дерево"
              : "Новый круг"),
      ).trim() || "Новый круг",
    description: normalizeNullableString(description),
    createdBy: normalizeNullableString(createdBy),
    isSystem: normalizedKind !== "custom",
    anchorPersonId: normalizedAnchorPersonId,
    anchorPersonIds: normalizedAnchorPersonIds,
    createdAt: timestamp,
    updatedAt: timestamp,
  };
}

function ensureDefaultCirclesForTree(db, treeOrTreeId) {
  const tree =
    typeof treeOrTreeId === "string"
      ? db.trees.find((entry) => entry.id === treeOrTreeId)
      : treeOrTreeId;
  const treeId = normalizeNullableString(tree?.id || treeOrTreeId);
  if (!treeId) {
    return {changed: false, allTreeCircle: null, favoritesCircle: null};
  }

  db.circles = Array.isArray(db.circles) ? db.circles : [];
  db.circleMembers = Array.isArray(db.circleMembers) ? db.circleMembers : [];

  let changed = false;
  let allTreeCircle = db.circles.find(
    (entry) => entry.treeId === treeId && entry.kind === "all_tree",
  );
  if (!allTreeCircle) {
    allTreeCircle = createCircleRecord({
      treeId,
      kind: "all_tree",
      name: "Всё дерево",
      createdBy: tree?.creatorId || null,
      id: defaultCircleId(treeId, "all_tree"),
    });
    db.circles.push(allTreeCircle);
    changed = true;
  }

  let favoritesCircle = db.circles.find(
    (entry) => entry.treeId === treeId && entry.kind === "favorites",
  );
  if (!favoritesCircle) {
    favoritesCircle = createCircleRecord({
      treeId,
      kind: "favorites",
      name: "Избранные",
      createdBy: tree?.creatorId || null,
      id: defaultCircleId(treeId, "favorites"),
    });
    db.circles.push(favoritesCircle);
    changed = true;
  }

  return {changed, allTreeCircle, favoritesCircle};
}

function ensureDefaultCirclesForAllTrees(db) {
  let changed = false;
  for (const tree of Array.isArray(db.trees) ? db.trees : []) {
    const result = ensureDefaultCirclesForTree(db, tree);
    changed = changed || result.changed;
  }
  return changed;
}

function normalizeCircleMemberIdentityIds(db, treeId, identityIds = []) {
  const allowedIdentityIds = new Set(
    (Array.isArray(db.persons) ? db.persons : [])
      .filter((person) => person.treeId === treeId)
      .map((person) => normalizeNullableString(person.identityId))
      .filter(Boolean),
  );
  return Array.from(
    new Set(
      (Array.isArray(identityIds) ? identityIds : [])
        .map((value) => normalizeNullableString(value))
        .filter((value) => value && allowedIdentityIds.has(value)),
    ),
  );
}

function circlePersonDisplayName(person) {
  return String(person?.name || "").trim() || "Без имени";
}

function collectReachablePersonIds(startPersonId, adjacency) {
  const start = normalizeNullableString(startPersonId);
  if (!start) {
    return new Set();
  }

  const result = new Set([start]);
  const queue = [start];
  while (queue.length > 0) {
    const current = queue.shift();
    for (const next of adjacency.get(current) || []) {
      if (result.has(next)) {
        continue;
      }
      result.add(next);
      queue.push(next);
    }
  }
  return result;
}

// Авто-кругам от бэкфилла идентичностей нужно одно: identityId у людей ЭТОГО
// дерева (membership кругов считается по person.identityId). Сам
// backfillPersonIdentities хэширует ВСЕ persons+identities базы (stableSerialize
// + sha256, дважды) — вызываемый на каждое дерево из ensureCirclesForAllTrees
// он давал 77% CPU GET /posts при неизменных данных. Поэтому зовём его только
// когда у дерева реально есть человек без идентичности.
function treeHasPersonsWithoutIdentity(db, treeId) {
  return (Array.isArray(db.persons) ? db.persons : []).some(
    (person) =>
      person.treeId === treeId && !normalizeNullableString(person.identityId),
  );
}

// SPEED-13: тот же приём, что treeHasPersonsWithoutIdentity (SPEED-8c), но
// БЕЗ фильтра по дереву — merge-proposals кросс-древесные
// (_ensureCrossTreeMergeProposals сверяет stewardPersons ПРОТИВ db.persons
// ВСЕЙ базы, не одного дерева), поэтому гейту нужна глобальная проверка.
// backfillPersonIdentities (внутри _reconcilePersonIdentities) хэширует ВСЕ
// persons+personIdentities базы дважды (before/after stableSerialize+sha256)
// — на проде, где все persons уже с identityId, это ~47% self-time
// GET /v1/merge-proposals/pending на КАЖДЫЙ вызов при неизменных данных
// (docs/speed_measurement.md SPEED-10/SPEED-12 профиль). Как и у
// treeHasPersonsWithoutIdentity, гейт смотрит ТОЛЬКО на присутствие
// identityId — не на согласованность personIdentities[].personIds с ним
// (тот же принятый риск, см. SPEED-12 «Что НЕ переведено»).
function dbHasPersonsWithoutIdentity(db) {
  return (Array.isArray(db.persons) ? db.persons : []).some(
    (person) => !normalizeNullableString(person.identityId),
  );
}

function identityIdsForPersonIds(db, treeId, personIds) {
  const personsById = new Map(
    (Array.isArray(db.persons) ? db.persons : [])
      .filter((person) => person.treeId === treeId)
      .map((person) => [person.id, person]),
  );
  const identityIds = normalizeParticipantIds(personIds)
    .map((personId) => normalizeNullableString(personsById.get(personId)?.identityId))
    .filter(Boolean);
  return normalizeCircleMemberIdentityIds(db, treeId, identityIds);
}

function buildAutoCircleSpec({
  db,
  treeId,
  kind,
  name,
  description,
  personIds,
  anchorPersonId = null,
  anchorPersonIds = [],
  createdBy = null,
}) {
  const normalizedKind = normalizeCircleKind(kind);
  const normalizedPersonIds = normalizeParticipantIds(personIds);
  if (!isAutoCircleKind(normalizedKind) || normalizedPersonIds.length < 2) {
    return null;
  }

  const normalizedAnchorPersonId = normalizeNullableString(anchorPersonId);
  const normalizedAnchorPersonIds = normalizeParticipantIds(anchorPersonIds);
  const id = autoCircleId({
    treeId,
    kind: normalizedKind,
    anchorPersonId: normalizedAnchorPersonId,
    anchorPersonIds: normalizedAnchorPersonIds,
  });
  const identityIds = identityIdsForPersonIds(db, treeId, normalizedPersonIds);
  if (identityIds.length === 0) {
    return null;
  }

  return {
    id,
    treeId,
    kind: normalizedKind,
    name,
    description,
    personIds: normalizedPersonIds,
    identityIds,
    anchorPersonId: normalizedAnchorPersonId,
    anchorPersonIds: normalizedAnchorPersonIds,
    createdBy,
  };
}

function buildAutoCircleSpecsForTree(db, tree) {
  const treeId = normalizeNullableString(tree?.id || tree);
  if (!treeId) {
    return new Map();
  }

  const persons = (Array.isArray(db.persons) ? db.persons : []).filter(
    (person) => person.treeId === treeId,
  );
  const personsById = new Map(persons.map((person) => [person.id, person]));
  const treeRelations = (Array.isArray(db.relations) ? db.relations : []).filter(
    (relation) => relation.treeId === treeId,
  );
  const childrenByParentId = new Map();
  const parentsByChildId = new Map();

  for (const relation of treeRelations) {
    const parentId = parentIdFromRelation(relation);
    const childId = childIdFromRelation(relation);
    if (!personsById.has(parentId) || !personsById.has(childId)) {
      continue;
    }
    addMapSetValue(childrenByParentId, parentId, childId);
    addMapSetValue(parentsByChildId, childId, parentId);
  }

  const specs = new Map();
  const addSpec = (spec) => {
    if (spec) {
      specs.set(spec.id, spec);
    }
  };

  for (const person of persons) {
    const descendants = collectReachablePersonIds(person.id, childrenByParentId);
    if (descendants.size > 1) {
      addSpec(
        buildAutoCircleSpec({
          db,
          treeId,
          kind: "descendants_of",
          name: `Ветка: ${circlePersonDisplayName(person)}`,
          description: "Автоматически: человек и его потомки",
          personIds: Array.from(descendants),
          anchorPersonId: person.id,
          createdBy: tree.creatorId || null,
        }),
      );
    }

    const ancestors = collectReachablePersonIds(person.id, parentsByChildId);
    if (ancestors.size > 1) {
      addSpec(
        buildAutoCircleSpec({
          db,
          treeId,
          kind: "ancestors_of",
          name: `Предки: ${circlePersonDisplayName(person)}`,
          description: "Автоматически: человек и его предки",
          personIds: Array.from(ancestors),
          anchorPersonId: person.id,
          createdBy: tree.creatorId || null,
        }),
      );
    }
  }

  for (const relation of treeRelations) {
    if (!isSpouseLikeRelation(relation)) {
      continue;
    }
    const left = personsById.get(relation.person1Id);
    const right = personsById.get(relation.person2Id);
    if (!left || !right) {
      continue;
    }

    const pairPersonIds = new Set([left.id, right.id]);
    for (const candidate of treeRelations) {
      const parentId = parentIdFromRelation(candidate);
      const childId = childIdFromRelation(candidate);
      if (pairPersonIds.has(parentId) && personsById.has(childId)) {
        pairPersonIds.add(childId);
      }
    }

    const anchorPersonIds = normalizeParticipantIds([left.id, right.id]);
    addSpec(
      buildAutoCircleSpec({
        db,
        treeId,
        kind: "pair",
        name: `${circlePersonDisplayName(left)} + ${circlePersonDisplayName(right)}`,
        description: "Автоматически: пара и дети",
        personIds: Array.from(pairPersonIds),
        anchorPersonIds,
        createdBy: tree.creatorId || null,
      }),
    );
  }

  return specs;
}

function ensureAutoCirclesForTree(db, treeOrTreeId) {
  const tree =
    typeof treeOrTreeId === "string"
      ? db.trees.find((entry) => entry.id === treeOrTreeId)
      : treeOrTreeId;
  const treeId = normalizeNullableString(tree?.id || treeOrTreeId);
  if (!treeId) {
    return {changed: false};
  }

  db.circles = Array.isArray(db.circles) ? db.circles : [];
  db.circleMembers = Array.isArray(db.circleMembers) ? db.circleMembers : [];
  let changed = treeHasPersonsWithoutIdentity(db, treeId)
    ? backfillPersonIdentities(db).changed
    : false;
  const specs = buildAutoCircleSpecsForTree(db, tree);
  const desiredIds = new Set(specs.keys());
  const removedCircleIds = new Set();

  db.circles = db.circles.filter((circle) => {
    if (circle.treeId !== treeId || !isAutoCircleKind(circle.kind)) {
      return true;
    }
    if (desiredIds.has(circle.id)) {
      return true;
    }
    removedCircleIds.add(circle.id);
    changed = true;
    return false;
  });

  if (removedCircleIds.size > 0) {
    db.circleMembers = db.circleMembers.filter(
      (entry) =>
        entry.treeId !== treeId || !removedCircleIds.has(entry.circleId),
    );
  }

  for (const spec of specs.values()) {
    let circle = db.circles.find(
      (entry) => entry.treeId === treeId && entry.id === spec.id,
    );
    if (!circle) {
      circle = createCircleRecord({
        treeId,
        kind: spec.kind,
        name: spec.name,
        description: spec.description,
        createdBy: spec.createdBy,
        id: spec.id,
        anchorPersonId: spec.anchorPersonId,
        anchorPersonIds: spec.anchorPersonIds,
      });
      db.circles.push(circle);
      changed = true;
    } else {
      const timestamp = nowIso();
      const updates = {
        kind: spec.kind,
        name: spec.name,
        description: normalizeNullableString(spec.description),
        createdBy: normalizeNullableString(circle.createdBy || spec.createdBy),
        isSystem: true,
        anchorPersonId: normalizeNullableString(spec.anchorPersonId),
      };
      for (const [key, value] of Object.entries(updates)) {
        if (circle[key] !== value) {
          circle[key] = value;
          changed = true;
          circle.updatedAt = timestamp;
        }
      }
      if (!sameNormalizedIds(circle.anchorPersonIds, spec.anchorPersonIds)) {
        circle.anchorPersonIds = normalizeParticipantIds(spec.anchorPersonIds);
        circle.updatedAt = timestamp;
        changed = true;
      }
    }

    const currentIdentityIds = db.circleMembers
      .filter((entry) => entry.treeId === treeId && entry.circleId === spec.id)
      .map((entry) => normalizeNullableString(entry.identityId))
      .filter(Boolean);
    if (!sameNormalizedIds(currentIdentityIds, spec.identityIds)) {
      const timestamp = nowIso();
      db.circleMembers = db.circleMembers.filter(
        (entry) => !(entry.treeId === treeId && entry.circleId === spec.id),
      );
      for (const identityId of spec.identityIds) {
        db.circleMembers.push({
          id: crypto.randomUUID(),
          treeId,
          circleId: spec.id,
          identityId,
          createdAt: timestamp,
          updatedAt: timestamp,
        });
      }
      circle.updatedAt = timestamp;
      changed = true;
    }
  }

  return {changed};
}

function ensureCirclesForTree(db, treeOrTreeId) {
  const defaults = ensureDefaultCirclesForTree(db, treeOrTreeId);
  const autoCircles = ensureAutoCirclesForTree(db, treeOrTreeId);
  return {
    ...defaults,
    changed: defaults.changed || autoCircles.changed,
  };
}

function ensureCirclesForAllTrees(db) {
  let changed = false;
  for (const tree of Array.isArray(db.trees) ? db.trees : []) {
    const result = ensureCirclesForTree(db, tree);
    changed = changed || result.changed;
  }
  return changed;
}

module.exports = {
  defaultCircleId,
  normalizeCircleKind,
  isAutoCircleKind,
  autoCircleId,
  createCircleRecord,
  ensureDefaultCirclesForTree,
  ensureDefaultCirclesForAllTrees,
  normalizeCircleMemberIdentityIds,
  circlePersonDisplayName,
  collectReachablePersonIds,
  treeHasPersonsWithoutIdentity,
  dbHasPersonsWithoutIdentity,
  identityIdsForPersonIds,
  buildAutoCircleSpec,
  buildAutoCircleSpecsForTree,
  ensureAutoCirclesForTree,
  ensureCirclesForTree,
  ensureCirclesForAllTrees,
};
