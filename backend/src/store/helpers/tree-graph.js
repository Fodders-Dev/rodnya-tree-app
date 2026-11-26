const path = require("node:path");
const {
  VALID_INCLUDE_RULE_TYPES,
} = require("../constants");
const {
  buildBranchLabel,
  buildFamilyUnitLabel,
  buildPathSummary,
  buildSparsePathRelationshipDescriptor,
  computeAffinityRelationshipDescriptor,
  computeBloodRelationshipDescriptor,
  describeDirectRelationLabel,
} = require("./kinship-labels");
const {
  composeDisplayNameFromProfile,
  normalizeIsoDate,
  normalizePersonPhotoGallery,
} = require("./persons-auth");
const {
  buildUsersByIdMap,
} = require("./reactions");
const {
  addMapSetValue,
  buildSortedIdKey,
  childIdFromRelation,
  getMapSetValues,
  hasMapSetValue,
  isBloodDirectRelationType,
  isBloodParentSetType,
  isUnionRelation,
  normalizeParentSetType,
  normalizeUnionStatus,
  normalizeUnionType,
  parentIdFromRelation,
  relationCustomLabelForPerson,
  relationTypeForPerson,
} = require("./relation-utils");
const {
  normalizeNullableString,
  nowIso,
} = require("./utils");

function buildLinkedPersonCanonicalPatchFromProfile(profile = {}) {
  const displayName = composeDisplayNameFromProfile(profile);
  const photoState = normalizePersonPhotoGallery([], {
    photoUrl: profile.photoUrl,
    primaryPhotoUrl: profile.photoUrl,
  });

  return {
    name: displayName || null,
    maidenName: normalizeNullableString(profile.maidenName),
    photoUrl: photoState.photoUrl,
    primaryPhotoUrl: photoState.primaryPhotoUrl,
    gender: String(profile.gender || "unknown").trim() || "unknown",
    birthDate: normalizeIsoDate(profile.birthDate),
    birthPlace: normalizeNullableString(profile.birthPlace),
  };
}

function applyIncludeRulesToBranch(branch, incoming) {
  if (!branch || !incoming || typeof incoming !== "object") {
    return false;
  }
  const before = JSON.stringify(branch.includeRules || {});

  if (
    !branch.includeRules ||
    typeof branch.includeRules !== "object"
  ) {
    branch.includeRules = {
      type: "manual",
      manualPersonIds: [],
      anchorPersonId: null,
      maxHops: 5,
    };
  }
  const next = branch.includeRules;

  // Type validation (DECISIONS.md 2026-05-10 fix-1):
  //   - missing / null / empty → silent default (caller relies on
  //     existing type, или `_syncTreeToBranch` initialize'нул "manual").
  //     Это backward-compat для legacy callers без includeRules.
  //   - explicit non-empty но не-allowed → throw INVALID_RULE_TYPE.
  //     Malformed value = client-bug, должен surface'иться 400'ой,
  //     не silent fallback'ом.
  if (incoming.type !== undefined && incoming.type !== null) {
    const requestedType = String(incoming.type).trim();
    if (requestedType !== "") {
      if (!VALID_INCLUDE_RULE_TYPES.has(requestedType)) {
        throw new Error("INVALID_RULE_TYPE");
      }
      next.type = requestedType;
    }
  }

  if (incoming.anchorPersonId === null) {
    next.anchorPersonId = null;
  } else if (typeof incoming.anchorPersonId === "string") {
    const trimmed = incoming.anchorPersonId.trim();
    next.anchorPersonId = trimmed || null;
  }

  // maxHops — continuous int с clamp 1..20 (не throw на out-of-range,
  // в отличие от type). DECISIONS.md fix-2: out-of-range — это
  // valid input behavior, не client-bug; sanity-bound и идём дальше.
  if (Number.isFinite(incoming.maxHops)) {
    const clamped = Math.max(1, Math.min(20, Math.floor(incoming.maxHops)));
    next.maxHops = clamped;
  } else if (next.maxHops === undefined || next.maxHops === null) {
    next.maxHops = 5;
  }

  if (Array.isArray(incoming.manualPersonIds)) {
    next.manualPersonIds = Array.from(
      new Set(incoming.manualPersonIds.filter(Boolean)),
    );
  } else if (!Array.isArray(next.manualPersonIds)) {
    next.manualPersonIds = [];
  }

  return JSON.stringify(next) !== before;
}

function applyCanonicalProfileToPerson(person, profile = {}, {
  touchUpdatedAt = true,
  // `additive: true` — никогда не перезатирать уже существующие поля
  // person (name, gender, birthDate, ...). Только заполнять пустые.
  // Используется при `linkPersonToUser`, чтобы вход нового юзера в
  // чужой существующий слот в дереве НЕ переписывал генеалогические
  // данные, проставленные владельцем дерева.
  //
  // Bug-репорт: «приглашённый Степа стал отцом, фото мамы». Корень —
  // ссылка-приглашение указывала на мамин personId, мамин слот не
  // имел userId, linkPersonToUser принял его, и без additive — затёр
  // мамино имя на «Моздуков Степка» и её гендер на male, из-за чего
  // движок отношений переписал её роль с «Мама» на «Папа». Photo
  // выжило случайно — у Степы в профиле не было своего фото.
  //
  // `additive: false` (по умолчанию для совместимости с
  // buildCanonicalPersonView) — старое поведение полного оверлея,
  // нужно для render-only вызовов на клонированных person'ах.
  additive = false,
} = {}) {
  if (!person || !profile || typeof profile !== "object") {
    return person;
  }

  const patch = buildLinkedPersonCanonicalPatchFromProfile(profile);
  const fillIfEmpty = (current, candidate) => {
    if (!additive) return candidate;
    const trimmed = current === null || current === undefined
      ? ""
      : String(current).trim();
    if (trimmed.length > 0) return current;
    return candidate;
  };

  if (patch.name) {
    person.name = fillIfEmpty(person.name, patch.name);
  }
  person.maidenName = fillIfEmpty(person.maidenName, patch.maidenName);
  if (patch.photoUrl) {
    person.photoUrl = fillIfEmpty(person.photoUrl, patch.photoUrl);
    person.primaryPhotoUrl = fillIfEmpty(
      person.primaryPhotoUrl,
      patch.primaryPhotoUrl,
    );
  }
  person.gender = fillIfEmpty(person.gender, patch.gender);
  person.birthDate = fillIfEmpty(person.birthDate, patch.birthDate);
  person.birthPlace = fillIfEmpty(person.birthPlace, patch.birthPlace);
  if (touchUpdatedAt) {
    person.updatedAt = nowIso();
  }
  return person;
}

// SPEED-10: `usersById` — опциональная карта id→user (buildUsersByIdMap),
// построенная ОДИН раз вызывающим циклом (listPersons и т.п.), вместо
// db.users.find(...) на КАЖДОГО person — было O(persons_в_дереве ×
// users_всего) на listPersons, см. docs/speed_measurement.md SPEED-10.
// Без параметра — прежнее поведение, честный .find() (searchPersonsForUser
// и fallback внутри _buildPersonViewFromGraph зовут одиночно, карту строить
// ради одного person незачем).
function buildCanonicalPersonView(db, person, {
  touchUpdatedAt = false,
  usersById = null,
} = {}) {
  const personView = structuredClone(person);
  if (!personView?.userId) {
    return personView;
  }

  const user = usersById
    ? usersById.get(String(personView.userId || "").trim())
    : db.users.find((entry) => entry.id === personView.userId);
  if (!user?.profile) {
    return personView;
  }

  return applyCanonicalProfileToPerson(personView, user.profile, {
    touchUpdatedAt,
  });
}

function buildBranchVisiblePersonIds(persons, relations, branchRootPersonId) {
  const normalizedRootId = String(branchRootPersonId || "").trim();
  if (!normalizedRootId) {
    return new Set();
  }
  const treeId = Array.isArray(persons) && persons.length > 0 ? persons[0]?.treeId : null;
  if (!treeId) {
    return new Set([normalizedRootId]);
  }
  const snapshot = buildTreeGraphSnapshot({
    treeId,
    persons,
    relations,
    viewerPersonId: null,
  });
  const branchBlock = chooseBranchBlockForPerson(snapshot, normalizedRootId);
  return new Set(branchBlock?.memberPersonIds || [normalizedRootId]);
}

function comparePathCost(left, right) {
  if (!left && !right) {
    return 0;
  }
  if (!left) {
    return 1;
  }
  if (!right) {
    return -1;
  }
  if (left.nonBlood !== right.nonBlood) {
    return left.nonBlood - right.nonBlood;
  }
  if (left.length !== right.length) {
    return left.length - right.length;
  }
  return left.pastUnion - right.pastUnion;
}

function buildTraversalGraph(relations) {
  const adjacency = new Map();
  const parentsByChild = new Map();
  const bloodParentsByChild = new Map();
  const childrenByParent = new Map();
  const bloodChildrenByParent = new Map();
  const currentUnionPartnersByPerson = new Map();
  const anyUnionPartnersByPerson = new Map();
  const siblingsByPerson = new Map();
  const directRelations = new Map();

  for (const relation of Array.isArray(relations) ? relations : []) {
    const pairKey = buildSortedIdKey([relation.person1Id, relation.person2Id]);
    if (pairKey) {
      directRelations.set(pairKey, relation);
    }

    const parentId = parentIdFromRelation(relation);
    const childId = childIdFromRelation(relation);
    if (parentId && childId) {
      addMapSetValue(parentsByChild, childId, parentId);
      addMapSetValue(childrenByParent, parentId, childId);
      if (isBloodParentSetType(relation.parentSetType)) {
        addMapSetValue(bloodParentsByChild, childId, parentId);
        addMapSetValue(bloodChildrenByParent, parentId, childId);
      }
      if (!adjacency.has(parentId)) {
        adjacency.set(parentId, []);
      }
      if (!adjacency.has(childId)) {
        adjacency.set(childId, []);
      }
      adjacency.get(parentId).push({
        toId: childId,
        kind: "child",
        isBlood: isBloodParentSetType(relation.parentSetType),
        isPast: false,
      });
      adjacency.get(childId).push({
        toId: parentId,
        kind: "parent",
        isBlood: isBloodParentSetType(relation.parentSetType),
        isPast: false,
      });
    }

    if (isUnionRelation(relation)) {
      const normalizedUnionStatus = normalizeUnionStatus(relation.unionStatus, {
        relationType: relation.relation1to2 || relation.relation2to1,
        divorceDate: relation.divorceDate,
      });
      const isPast = normalizedUnionStatus !== "current";
      addMapSetValue(anyUnionPartnersByPerson, relation.person1Id, relation.person2Id);
      addMapSetValue(anyUnionPartnersByPerson, relation.person2Id, relation.person1Id);
      if (!isPast) {
        addMapSetValue(currentUnionPartnersByPerson, relation.person1Id, relation.person2Id);
        addMapSetValue(currentUnionPartnersByPerson, relation.person2Id, relation.person1Id);
      }
      if (!adjacency.has(relation.person1Id)) {
        adjacency.set(relation.person1Id, []);
      }
      if (!adjacency.has(relation.person2Id)) {
        adjacency.set(relation.person2Id, []);
      }
      adjacency.get(relation.person1Id).push({
        toId: relation.person2Id,
        kind: "union",
        isBlood: false,
        isPast,
      });
      adjacency.get(relation.person2Id).push({
        toId: relation.person1Id,
        kind: "union",
        isBlood: false,
        isPast,
      });
    }

    if (
      String(relation.relation1to2 || "").trim().toLowerCase() === "sibling" &&
      String(relation.relation2to1 || "").trim().toLowerCase() === "sibling"
    ) {
      addMapSetValue(siblingsByPerson, relation.person1Id, relation.person2Id);
      addMapSetValue(siblingsByPerson, relation.person2Id, relation.person1Id);
      if (!adjacency.has(relation.person1Id)) {
        adjacency.set(relation.person1Id, []);
      }
      if (!adjacency.has(relation.person2Id)) {
        adjacency.set(relation.person2Id, []);
      }
      adjacency.get(relation.person1Id).push({
        toId: relation.person2Id,
        kind: "sibling",
        isBlood: true,
        isPast: false,
      });
      adjacency.get(relation.person2Id).push({
        toId: relation.person1Id,
        kind: "sibling",
        isBlood: true,
        isPast: false,
      });
    }
  }

  return {
    adjacency,
    parentsByChild,
    bloodParentsByChild,
    childrenByParent,
    bloodChildrenByParent,
    currentUnionPartnersByPerson,
    anyUnionPartnersByPerson,
    siblingsByPerson,
    directRelations,
  };
}

function buildBestPathIndex(startPersonId, adjacency) {
  const costs = new Map();
  const pathCounts = new Map();
  const predecessors = new Map();
  costs.set(startPersonId, {
    nonBlood: 0,
    length: 0,
    pastUnion: 0,
  });
  pathCounts.set(startPersonId, 1);
  const pending = [{
    personId: startPersonId,
    cost: {
      nonBlood: 0,
      length: 0,
      pastUnion: 0,
    },
  }];

  while (pending.length > 0) {
    pending.sort((left, right) => comparePathCost(left.cost, right.cost));
    const current = pending.shift();
    if (!current) {
      continue;
    }
    const previousBest = costs.get(current.personId);
    if (previousBest && comparePathCost(current.cost, previousBest) > 0) {
      continue;
    }

    for (const edge of adjacency.get(current.personId) || []) {
      const nextCost = {
        nonBlood: current.cost.nonBlood + (edge.isBlood ? 0 : 1),
        length: current.cost.length + 1,
        pastUnion: current.cost.pastUnion + (edge.isPast ? 1 : 0),
      };
      const existingCost = costs.get(edge.toId);
      const comparison = comparePathCost(nextCost, existingCost);
      if (comparison < 0 || existingCost === undefined) {
        costs.set(edge.toId, nextCost);
        if (edge.toId !== startPersonId) {
          predecessors.set(edge.toId, current.personId);
        }
        pathCounts.set(edge.toId, pathCounts.get(current.personId) || 1);
        pending.push({
          personId: edge.toId,
          cost: nextCost,
        });
      } else if (comparison === 0) {
        pathCounts.set(
          edge.toId,
          (pathCounts.get(edge.toId) || 0) + (pathCounts.get(current.personId) || 1),
        );
      }
    }
  }

  return {
    costs,
    pathCounts,
    predecessors,
  };
}

function reconstructPersonPath(targetPersonId, predecessors) {
  const path = [];
  const seen = new Set();
  let currentId = targetPersonId;
  while (currentId && !seen.has(currentId)) {
    path.unshift(currentId);
    seen.add(currentId);
    currentId = predecessors.get(currentId);
  }
  return path;
}

function normalizeTreeGraph(treeId, persons = [], relations = []) {
  const normalizedPeople = (Array.isArray(persons) ? persons : [])
    .filter((person) => person.treeId === treeId)
    .map((person) => structuredClone(person));
  const normalizedRelations = (Array.isArray(relations) ? relations : [])
    .filter((relation) => relation.treeId === treeId)
    .map((relation) => {
      const normalizedRelation = structuredClone(relation);
      const normalizedParentId = parentIdFromRelation(normalizedRelation);
      const normalizedChildId = childIdFromRelation(normalizedRelation);
      if (normalizedParentId && normalizedChildId) {
        normalizedRelation.parentSetType = normalizeParentSetType(
          normalizedRelation.parentSetType,
        );
        normalizedRelation.parentSetId =
          normalizeNullableString(normalizedRelation.parentSetId) || null;
        normalizedRelation.isPrimaryParentSet =
          normalizedRelation.isPrimaryParentSet !== false;
      } else {
        normalizedRelation.parentSetType = null;
        normalizedRelation.parentSetId = null;
        normalizedRelation.isPrimaryParentSet = null;
      }

      if (isUnionRelation(normalizedRelation)) {
        const relationType =
          normalizedRelation.relation1to2 || normalizedRelation.relation2to1;
        normalizedRelation.unionType = normalizeUnionType(
          normalizedRelation.unionType,
          {relationType},
        );
        normalizedRelation.unionStatus = normalizeUnionStatus(
          normalizedRelation.unionStatus,
          {
            relationType,
            divorceDate: normalizedRelation.divorceDate,
          },
        );
        normalizedRelation.unionId =
          normalizeNullableString(normalizedRelation.unionId) ||
          `union:${treeId}:${buildSortedIdKey([
            normalizedRelation.person1Id,
            normalizedRelation.person2Id,
          ])}:${normalizedRelation.unionType}:${normalizedRelation.unionStatus}`;
      } else {
        normalizedRelation.unionType = null;
        normalizedRelation.unionStatus = null;
        normalizedRelation.unionId = null;
      }

      return normalizedRelation;
    });

  const relationGroups = new Map();
  for (const relation of normalizedRelations) {
    const childId = childIdFromRelation(relation);
    if (!childId) {
      continue;
    }
    const groupKey = `${childId}:${relation.parentSetType}`;
    if (!relationGroups.has(groupKey)) {
      relationGroups.set(groupKey, []);
    }
    relationGroups.get(groupKey).push(relation);
  }

  for (const [groupKey, groupRelations] of relationGroups.entries()) {
    const [childId, parentSetType] = groupKey.split(":");
    const explicitIds = Array.from(
      new Set(
        groupRelations
          .map((relation) => normalizeNullableString(relation.parentSetId))
          .filter(Boolean),
      ),
    );

    if (explicitIds.length === 0) {
      const uniqueParentIds = Array.from(
        new Set(groupRelations.map((relation) => parentIdFromRelation(relation)).filter(Boolean)),
      );
      if (uniqueParentIds.length <= 2) {
        const sharedId = `ps:${treeId}:${childId}:${parentSetType}:primary`;
        for (const relation of groupRelations) {
          relation.parentSetId = sharedId;
          relation.isPrimaryParentSet = true;
        }
      } else {
        let index = 0;
        for (const relation of groupRelations) {
          index += 1;
          relation.parentSetId = `ps:${treeId}:${childId}:${parentSetType}:${index}`;
          relation.isPrimaryParentSet = index === 1;
        }
      }
      continue;
    }

    const primaryId =
      groupRelations.find((relation) => relation.isPrimaryParentSet)?.parentSetId ||
      explicitIds[0];
    const primaryParentIds = new Set(
      groupRelations
        .filter((relation) => relation.parentSetId === primaryId)
        .map((relation) => parentIdFromRelation(relation))
        .filter(Boolean),
    );
    let generatedIndex = explicitIds.length;
    for (const relation of groupRelations) {
      if (relation.parentSetId) {
        relation.isPrimaryParentSet = relation.parentSetId === primaryId;
        continue;
      }
      const parentId = parentIdFromRelation(relation);
      if (primaryParentIds.has(parentId) || primaryParentIds.size < 2) {
        relation.parentSetId = primaryId;
        relation.isPrimaryParentSet = true;
        if (parentId) {
          primaryParentIds.add(parentId);
        }
      } else {
        generatedIndex += 1;
        relation.parentSetId =
          `ps:${treeId}:${childId}:${parentSetType}:${generatedIndex}`;
        relation.isPrimaryParentSet = false;
      }
    }
  }

  return {
    people: normalizedPeople,
    relations: normalizedRelations,
  };
}

function buildDisplayTreeRelations(treeId, relations = []) {
  const normalizedRelations = (Array.isArray(relations) ? relations : []).map((relation) =>
    structuredClone(relation),
  );
  const anyUnionPartnersByPerson = new Map();
  const primaryParentGroups = new Map();
  const childIdsByParentAndType = new Map();
  const existingParentRelationKeys = new Set();

  for (const relation of normalizedRelations) {
    if (isUnionRelation(relation)) {
      addMapSetValue(anyUnionPartnersByPerson, relation.person1Id, relation.person2Id);
      addMapSetValue(anyUnionPartnersByPerson, relation.person2Id, relation.person1Id);
    }

    const parentId = parentIdFromRelation(relation);
    const childId = childIdFromRelation(relation);
    if (!parentId || !childId) {
      continue;
    }
    const normalizedParentSetType = normalizeParentSetType(relation.parentSetType);
    existingParentRelationKeys.add(`${parentId}:${childId}:${normalizedParentSetType}`);
    if (relation.isPrimaryParentSet === false || !isBloodParentSetType(normalizedParentSetType)) {
      continue;
    }
    const groupKey = `${childId}:${normalizedParentSetType}`;
    if (!primaryParentGroups.has(groupKey)) {
      primaryParentGroups.set(groupKey, []);
    }
    primaryParentGroups.get(groupKey).push(relation);
    addMapSetValue(
      childIdsByParentAndType,
      `${parentId}:${normalizedParentSetType}`,
      childId,
    );
  }

  const inferredRelations = [];
  for (const groupRelations of primaryParentGroups.values()) {
    const uniqueParentIds = Array.from(
      new Set(groupRelations.map((relation) => parentIdFromRelation(relation)).filter(Boolean)),
    );
    if (uniqueParentIds.length !== 1) {
      continue;
    }

    const knownParentId = uniqueParentIds[0];
    const childId = childIdFromRelation(groupRelations[0]);
    const parentSetType = normalizeParentSetType(groupRelations[0].parentSetType);
    if (!knownParentId || !childId || !parentSetType) {
      continue;
    }

    const candidateSupport = new Map();
    for (const siblingChildId of getMapSetValues(
      childIdsByParentAndType,
      `${knownParentId}:${parentSetType}`,
    )) {
      if (siblingChildId === childId) {
        continue;
      }
      const siblingRelations =
        primaryParentGroups.get(`${siblingChildId}:${parentSetType}`) || [];
      const siblingParentIds = Array.from(
        new Set(
          siblingRelations
            .map((relation) => parentIdFromRelation(relation))
            .filter(Boolean),
        ),
      );
      if (siblingParentIds.length !== 2 || !siblingParentIds.includes(knownParentId)) {
        continue;
      }
      const candidateParentId = siblingParentIds.find((id) => id !== knownParentId);
      if (
        !candidateParentId ||
        !hasMapSetValue(anyUnionPartnersByPerson, knownParentId, candidateParentId)
      ) {
        continue;
      }
      candidateSupport.set(
        candidateParentId,
        (candidateSupport.get(candidateParentId) || 0) + 1,
      );
    }

    if (candidateSupport.size !== 1) {
      continue;
    }
    const [[candidateParentId]] = Array.from(candidateSupport.entries());
    const inferredKey = `${candidateParentId}:${childId}:${parentSetType}`;
    if (existingParentRelationKeys.has(inferredKey)) {
      continue;
    }

    const templateRelation = groupRelations[0];
    inferredRelations.push({
      ...structuredClone(templateRelation),
      id: `inferred:${treeId}:${candidateParentId}:${childId}:${parentSetType}`,
      person1Id: candidateParentId,
      person2Id: childId,
      relation1to2: "parent",
      relation2to1: "child",
      isConfirmed: true,
      customRelationLabel1to2: null,
      customRelationLabel2to1: null,
      parentSetType,
      parentSetId: templateRelation.parentSetId,
      isPrimaryParentSet: true,
      unionType: null,
      unionStatus: null,
      unionId: null,
      inferredDisplayOnly: true,
    });
    existingParentRelationKeys.add(inferredKey);
  }

  return [...normalizedRelations, ...inferredRelations];
}

function buildFamilyUnits(treeId, persons = [], relations = []) {
  const normalizedGraph = normalizeTreeGraph(treeId, persons, relations);
  const displayRelations = buildDisplayTreeRelations(
    treeId,
    normalizedGraph.relations,
  );
  const peopleById = new Map(
    normalizedGraph.people.map((person) => [String(person.id || "").trim(), person]),
  );
  const familyUnits = [];
  const representedUnionIds = new Set();
  const parentSetGroups = new Map();

  for (const relation of displayRelations) {
    const parentId = parentIdFromRelation(relation);
    const childId = childIdFromRelation(relation);
    if (!parentId || !childId || !relation.parentSetId) {
      continue;
    }
    if (!parentSetGroups.has(relation.parentSetId)) {
      parentSetGroups.set(relation.parentSetId, {
        id: relation.parentSetId,
        parentSetType: relation.parentSetType,
        isPrimaryParentSet: relation.isPrimaryParentSet !== false,
        adultIds: new Set(),
        childIds: new Set(),
        relationIds: new Set(),
      });
    }
    const group = parentSetGroups.get(relation.parentSetId);
    group.adultIds.add(parentId);
    group.childIds.add(childId);
    group.relationIds.add(relation.id);
    if (relation.isPrimaryParentSet === false) {
      group.isPrimaryParentSet = false;
    }
  }

  const mergedParentFamilyGroups = new Map();

  for (const group of parentSetGroups.values()) {
    const adultIds = Array.from(group.adultIds).sort((left, right) =>
      left.localeCompare(right),
    );
    const childIds = Array.from(group.childIds).sort((left, right) =>
      left.localeCompare(right),
    );
    const matchingUnion = adultIds.length >= 2
      ? displayRelations.find((relation) => {
          return (
            relation.unionId &&
            buildSortedIdKey([relation.person1Id, relation.person2Id]) ===
              buildSortedIdKey(adultIds)
          );
        })
      : null;
    const mergeKey = [
      buildSortedIdKey(adultIds),
      matchingUnion?.unionId || `single:${buildSortedIdKey(adultIds)}`,
      normalizeParentSetType(group.parentSetType),
      group.isPrimaryParentSet ? "primary" : "secondary",
    ].join("|");

    if (!mergedParentFamilyGroups.has(mergeKey)) {
      mergedParentFamilyGroups.set(mergeKey, {
        rootParentSetIds: new Set(),
        adultIds: new Set(),
        childIds: new Set(),
        relationIds: new Set(),
        unionId: matchingUnion?.unionId || null,
        unionType:
          matchingUnion?.unionType || (adultIds.length > 1 ? "other" : "single"),
        unionStatus: matchingUnion?.unionStatus || "current",
        parentSetType: group.parentSetType,
        isPrimaryParentSet: group.isPrimaryParentSet,
      });
    }

    const mergedGroup = mergedParentFamilyGroups.get(mergeKey);
    mergedGroup.rootParentSetIds.add(group.id);
    for (const adultId of adultIds) {
      mergedGroup.adultIds.add(adultId);
    }
    for (const childId of childIds) {
      mergedGroup.childIds.add(childId);
    }
    for (const relationId of group.relationIds) {
      mergedGroup.relationIds.add(relationId);
    }
  }

  for (const mergedGroup of mergedParentFamilyGroups.values()) {
    const adultIds = Array.from(mergedGroup.adultIds).sort((left, right) =>
      left.localeCompare(right),
    );
    const childIds = Array.from(mergedGroup.childIds).sort((left, right) =>
      left.localeCompare(right),
    );
    const relationIds = Array.from(mergedGroup.relationIds).sort((left, right) =>
      left.localeCompare(right),
    );
    const rootParentSetIds = Array.from(mergedGroup.rootParentSetIds).sort(
      (left, right) => left.localeCompare(right),
    );
    const rootParentSetId = rootParentSetIds[0] || null;

    if (mergedGroup.unionId) {
      representedUnionIds.add(mergedGroup.unionId);
    }

    familyUnits.push({
      id:
        rootParentSetIds.length <= 1
          ? `family:${rootParentSetId}`
          : `family:merged:${treeId}:${buildSortedIdKey(rootParentSetIds)}`,
      rootParentSetId,
      adultIds,
      childIds,
      relationIds,
      unionId: mergedGroup.unionId,
      unionType: mergedGroup.unionType,
      unionStatus: mergedGroup.unionStatus,
      parentSetType: mergedGroup.parentSetType,
      isPrimaryParentSet: mergedGroup.isPrimaryParentSet,
      label: buildFamilyUnitLabel({adultIds, peopleById}),
    });
  }

  for (const relation of displayRelations) {
    if (!isUnionRelation(relation) || !relation.unionId) {
      continue;
    }
    if (representedUnionIds.has(relation.unionId)) {
      continue;
    }
    representedUnionIds.add(relation.unionId);
    const adultIds = [relation.person1Id, relation.person2Id].sort((left, right) =>
      left.localeCompare(right),
    );
    familyUnits.push({
      id: `family:${relation.unionId}`,
      rootParentSetId: null,
      adultIds,
      childIds: [],
      relationIds: [relation.id],
      unionId: relation.unionId,
      unionType: relation.unionType,
      unionStatus: relation.unionStatus,
      parentSetType: null,
      isPrimaryParentSet: false,
      label: buildFamilyUnitLabel({adultIds, peopleById}),
    });
  }

  const coveredPersonIds = new Set(
    familyUnits.flatMap((unit) => [...unit.adultIds, ...unit.childIds]),
  );
  for (const person of normalizedGraph.people) {
    if (coveredPersonIds.has(person.id)) {
      continue;
    }
    familyUnits.push({
      id: `family:solo:${person.id}`,
      rootParentSetId: null,
      adultIds: [person.id],
      childIds: [],
      relationIds: [],
      unionId: null,
      unionType: "single",
      unionStatus: "current",
      parentSetType: null,
      isPrimaryParentSet: false,
      label: buildFamilyUnitLabel({
        adultIds: [person.id],
        peopleById,
      }),
    });
  }

  return familyUnits;
}

function buildGenerationRows(persons, relations, familyUnits) {
  const normalizedPersons = Array.isArray(persons) ? persons : [];
  const normalizedRelations = Array.isArray(relations) ? relations : [];
  const parentsByChild = new Map();
  const siblingIdsByPerson = new Map();

  for (const relation of normalizedRelations) {
    if (
      String(relation.relation1to2 || "").trim().toLowerCase() === "sibling" &&
      String(relation.relation2to1 || "").trim().toLowerCase() === "sibling"
    ) {
      addMapSetValue(siblingIdsByPerson, relation.person1Id, relation.person2Id);
      addMapSetValue(siblingIdsByPerson, relation.person2Id, relation.person1Id);
    }

    const parentId = parentIdFromRelation(relation);
    const childId = childIdFromRelation(relation);
    if (!parentId || !childId || relation.isPrimaryParentSet === false) {
      continue;
    }
    if (!parentsByChild.has(childId)) {
      parentsByChild.set(childId, new Set());
    }
    parentsByChild.get(childId).add(parentId);
  }

  const levels = new Map();
  const visiting = new Set();
  const resolveLevel = (personId) => {
    if (levels.has(personId)) {
      return levels.get(personId);
    }
    if (visiting.has(personId)) {
      return 0;
    }
    visiting.add(personId);
    const parents = Array.from(parentsByChild.get(personId) || []);
    const level =
      parents.length === 0
        ? 0
        : Math.max(...parents.map((parentId) => resolveLevel(parentId))) + 1;
    visiting.delete(personId);
    levels.set(personId, level);
    return level;
  };

  for (const person of normalizedPersons) {
    resolveLevel(person.id);
  }

  const normalizedFamilyUnits = Array.isArray(familyUnits) ? familyUnits : [];
  const maxIterations = normalizedPersons.length + normalizedFamilyUnits.length + 8;
  let changed = true;
  let iteration = 0;
  while (changed && iteration < maxIterations) {
    changed = false;
    iteration += 1;

    for (const unit of normalizedFamilyUnits) {
      const adultIds = (Array.isArray(unit?.adultIds) ? unit.adultIds : []).filter(Boolean);
      const childIds = (Array.isArray(unit?.childIds) ? unit.childIds : []).filter(Boolean);
      if (adultIds.length === 0 && childIds.length === 0) {
        continue;
      }

      let desiredAdultLevel = null;
      if (childIds.length > 0) {
        desiredAdultLevel = Math.max(
          0,
          Math.min(...childIds.map((personId) => levels.get(personId) ?? 0)) - 1,
        );
      } else if (adultIds.length > 0) {
        desiredAdultLevel = Math.max(
          ...adultIds.map((personId) => levels.get(personId) ?? 0),
        );
      }

      if (desiredAdultLevel !== null) {
        for (const adultId of adultIds) {
          if ((levels.get(adultId) ?? 0) !== desiredAdultLevel) {
            levels.set(adultId, desiredAdultLevel);
            changed = true;
          }
        }
      }

      if (desiredAdultLevel !== null && childIds.length > 0) {
        const desiredChildLevel = desiredAdultLevel + 1;
        for (const childId of childIds) {
          if ((levels.get(childId) ?? 0) !== desiredChildLevel) {
            levels.set(childId, desiredChildLevel);
            changed = true;
          }
        }
      }
    }

    for (const [personId, siblingIds] of siblingIdsByPerson.entries()) {
      const targetLevel = Math.max(
        levels.get(personId) ?? 0,
        ...Array.from(siblingIds).map((siblingId) => levels.get(siblingId) ?? 0),
      );
      if ((levels.get(personId) ?? 0) !== targetLevel) {
        levels.set(personId, targetLevel);
        changed = true;
      }
      for (const siblingId of siblingIds) {
        if ((levels.get(siblingId) ?? 0) !== targetLevel) {
          levels.set(siblingId, targetLevel);
          changed = true;
        }
      }
    }
  }

  const minLevel = Math.min(0, ...Array.from(levels.values()));
  if (minLevel < 0) {
    for (const [personId, level] of levels.entries()) {
      levels.set(personId, level - minLevel);
    }
  }

  const maxLevel = Math.max(0, ...Array.from(levels.values()));
  const rows = [];
  for (let row = 0; row <= maxLevel; row += 1) {
    const personIds = normalizedPersons
      .filter((person) => levels.get(person.id) === row)
      .map((person) => person.id);
    const familyUnitIds = (Array.isArray(familyUnits) ? familyUnits : [])
      .filter((unit) =>
        unit.adultIds.some((personId) => personIds.includes(personId)) ||
        unit.childIds.some((personId) => personIds.includes(personId)),
      )
      .map((unit) => unit.id);
    let label = `Поколение ${row + 1}`;
    if (maxLevel === 0) {
      label = "Семья";
    } else if (row === 0) {
      label = "Старшее поколение";
    } else if (row === maxLevel) {
      label = "Младшее поколение";
    }
    rows.push({
      row,
      label,
      personIds,
      familyUnitIds: Array.from(new Set(familyUnitIds)),
    });
  }

  return rows;
}

function describeParentSetTypeLabelRu(parentSetType) {
  switch (normalizeParentSetType(parentSetType)) {
    case "biological":
      return "биологические родители";
    case "adoptive":
      return "усыновители";
    case "foster":
      return "приемная семья";
    case "guardian":
      return "опекуны";
    case "step":
      return "неродные родители";
    case "unknown":
      return "родители";
    default:
      return "родители";
  }
}

function buildGraphWarnings({
  persons = [],
  relations = [],
  familyUnits = [],
}) {
  const normalizedPersons = Array.isArray(persons) ? persons : [];
  const normalizedRelations = Array.isArray(relations) ? relations : [];
  const normalizedFamilyUnits = Array.isArray(familyUnits) ? familyUnits : [];
  const peopleById = new Map(
    normalizedPersons.map((person) => [String(person.id || "").trim(), person]),
  );
  const warnings = [];
  const emittedWarningIds = new Set();
  const pushWarning = (warning) => {
    const warningId = String(warning?.id || "").trim();
    if (!warningId || emittedWarningIds.has(warningId)) {
      return;
    }
    emittedWarningIds.add(warningId);
    warnings.push({
      id: warningId,
      code: String(warning.code || "").trim() || "graph_warning",
      severity: String(warning.severity || "").trim() || "warning",
      message: String(warning.message || "").trim() || "Дерево требует проверки.",
      hint: normalizeNullableString(warning.hint),
      personIds: Array.from(
        new Set((Array.isArray(warning.personIds) ? warning.personIds : []).filter(Boolean)),
      ),
      familyUnitIds: Array.from(
        new Set(
          (Array.isArray(warning.familyUnitIds) ? warning.familyUnitIds : []).filter(Boolean),
        ),
      ),
      relationIds: Array.from(
        new Set((Array.isArray(warning.relationIds) ? warning.relationIds : []).filter(Boolean)),
      ),
    });
  };

  const primaryParentGroups = new Map();
  for (const relation of normalizedRelations) {
    const parentId = parentIdFromRelation(relation);
    const childId = childIdFromRelation(relation);
    if (!parentId || !childId || relation.isPrimaryParentSet === false) {
      continue;
    }
    const normalizedParentSetType = normalizeParentSetType(relation.parentSetType) || "unknown";
    const normalizedParentSetId =
      normalizeNullableString(relation.parentSetId) ||
      `implicit:${childId}:${normalizedParentSetType}`;
    const groupKey = `${childId}:${normalizedParentSetType}`;
    if (!primaryParentGroups.has(groupKey)) {
      primaryParentGroups.set(groupKey, new Map());
    }
    const groupEntries = primaryParentGroups.get(groupKey);
    if (!groupEntries.has(normalizedParentSetId)) {
      groupEntries.set(normalizedParentSetId, {
        parentIds: new Set(),
        relationIds: new Set(),
      });
    }
    const groupEntry = groupEntries.get(normalizedParentSetId);
    groupEntry.parentIds.add(parentId);
    groupEntry.relationIds.add(relation.id);
  }

  for (const [groupKey, groupEntries] of primaryParentGroups.entries()) {
    if (groupEntries.size <= 1) {
      continue;
    }
    const [childId, parentSetType] = groupKey.split(":");
    const childName =
      peopleById.get(childId)?.name || peopleById.get(childId)?.displayName || childId;
    const allParentIds = [];
    const allRelationIds = [];
    const parentSetIds = new Set(groupEntries.keys());
    for (const entry of groupEntries.values()) {
      allParentIds.push(...Array.from(entry.parentIds));
      allRelationIds.push(...Array.from(entry.relationIds));
    }
    const familyUnitIds = normalizedFamilyUnits
      .filter((unit) => unit.rootParentSetId && parentSetIds.has(unit.rootParentSetId))
      .map((unit) => unit.id);
    pushWarning({
      id: `warning:primary-parent-set:${groupKey}`,
      code: "multiple_primary_parent_sets",
      severity: "warning",
      message: `У ${childName} несколько основных наборов родителей (${describeParentSetTypeLabelRu(
        parentSetType,
      )}).`,
      hint: "Оставьте только один основной набор, а остальные связи переведите в дополнительные.",
      personIds: [childId, ...allParentIds],
      familyUnitIds,
      relationIds: allRelationIds,
    });
  }

  // auto_repaired_parent_link was previously generated for every inferred
  // parent-child link.  The inference itself is correct (we deduce the missing
  // second parent from sibling evidence), so surfacing it as a warning is
  // confusing and actionable only in edge cases.  Users who want to review or
  // override auto-inferred links can do so in the tree editor where all
  // relations are visible.  The warning block is intentionally removed here.

  const pairRelations = new Map();
  for (const relation of normalizedRelations) {
    const leftId = String(relation.person1Id || "").trim();
    const rightId = String(relation.person2Id || "").trim();
    if (!leftId || !rightId) {
      continue;
    }
    const pairKey = buildSortedIdKey([leftId, rightId]);
    if (!pairRelations.has(pairKey)) {
      pairRelations.set(pairKey, []);
    }
    pairRelations.get(pairKey).push(relation);
  }

  const relationCategoryForWarning = (relation) => {
    if (parentIdFromRelation(relation) && childIdFromRelation(relation)) {
      return "parentChild";
    }
    if (isUnionRelation(relation)) {
      return "union";
    }
    if (relation?.relation1to2 === "sibling" || relation?.relation2to1 === "sibling") {
      return "sibling";
    }
    return null;
  };

  for (const [pairKey, pairEntries] of pairRelations.entries()) {
    const categories = new Set(
      pairEntries.map(relationCategoryForWarning).filter(Boolean),
    );
    if (categories.size <= 1) {
      continue;
    }
    const [personAId, personBId] = pairKey.split(":");
    const personAName =
      peopleById.get(personAId)?.name || peopleById.get(personAId)?.displayName || personAId;
    const personBName =
      peopleById.get(personBId)?.name || peopleById.get(personBId)?.displayName || personBId;
    pushWarning({
      id: `warning:conflicting-direct-links:${pairKey}`,
      code: "conflicting_direct_links",
      severity: "warning",
      message: `Между ${personAName} и ${personBName} есть конфликтующие прямые связи.`,
      hint: "Для одной пары людей оставьте только один прямой тип связи: родитель, сиблинг или союз.",
      personIds: [personAId, personBId],
      relationIds: pairEntries.map((relation) => relation.id),
      familyUnitIds: normalizedFamilyUnits
        .filter((unit) =>
          unit.adultIds.includes(personAId) ||
          unit.adultIds.includes(personBId) ||
          unit.childIds.includes(personAId) ||
          unit.childIds.includes(personBId),
        )
        .map((unit) => unit.id),
    });
  }

  return warnings;
}

function resolveBranchBlocks(treeId, persons = [], relations = [], familyUnits = null) {
  const normalizedGraph = normalizeTreeGraph(treeId, persons, relations);
  const resolvedFamilyUnits = Array.isArray(familyUnits)
    ? familyUnits
    : buildFamilyUnits(treeId, normalizedGraph.people, normalizedGraph.relations);
  const peopleById = new Map(
    normalizedGraph.people.map((person) => [String(person.id || "").trim(), person]),
  );
  const adultUnitsByPersonId = new Map();

  for (const unit of resolvedFamilyUnits) {
    for (const adultId of unit.adultIds) {
      if (!adultUnitsByPersonId.has(adultId)) {
        adultUnitsByPersonId.set(adultId, []);
      }
      adultUnitsByPersonId.get(adultId).push(unit.id);
    }
  }

  return resolvedFamilyUnits.map((rootUnit) => {
    const visitedUnitIds = new Set([rootUnit.id]);
    const memberPersonIds = new Set([...rootUnit.adultIds, ...rootUnit.childIds]);
    const queue = [rootUnit.id];

    while (queue.length > 0) {
      const currentUnitId = queue.shift();
      const currentUnit = resolvedFamilyUnits.find((unit) => unit.id === currentUnitId);
      if (!currentUnit) {
        continue;
      }
      for (const childId of currentUnit.childIds) {
        memberPersonIds.add(childId);
        for (const descendantUnitId of adultUnitsByPersonId.get(childId) || []) {
          if (visitedUnitIds.has(descendantUnitId)) {
            continue;
          }
          visitedUnitIds.add(descendantUnitId);
          queue.push(descendantUnitId);
          const descendantUnit = resolvedFamilyUnits.find((unit) => unit.id === descendantUnitId);
          for (const adultId of descendantUnit?.adultIds || []) {
            memberPersonIds.add(adultId);
          }
          for (const descendantChildId of descendantUnit?.childIds || []) {
            memberPersonIds.add(descendantChildId);
          }
        }
      }
    }

    return {
      id: `branch:${rootUnit.id}`,
      rootUnitId: rootUnit.id,
      label: buildBranchLabel({rootUnit, peopleById}),
      memberPersonIds: Array.from(memberPersonIds).sort((left, right) =>
        left.localeCompare(right),
      ),
    };
  });
}

function chooseBranchBlockForPerson(snapshot, personId) {
  if (!snapshot || !personId) {
    return null;
  }

  const normalizedPersonId = String(personId || "").trim();
  const familyUnits = Array.isArray(snapshot.familyUnits) ? snapshot.familyUnits : [];
  const branchBlocks = Array.isArray(snapshot.branchBlocks) ? snapshot.branchBlocks : [];
  const candidateUnit =
    familyUnits.find((unit) => unit.adultIds.includes(normalizedPersonId)) ||
    familyUnits.find(
      (unit) =>
        unit.childIds.includes(normalizedPersonId) && unit.isPrimaryParentSet === true,
    ) ||
    familyUnits.find((unit) => unit.childIds.includes(normalizedPersonId)) ||
    familyUnits.find((unit) => unit.adultIds.includes(normalizedPersonId));
  if (!candidateUnit) {
    return null;
  }
  return (
    branchBlocks.find((branchBlock) => branchBlock.rootUnitId === candidateUnit.id) ||
    null
  );
}

function computeViewerKinships(treeId, persons = [], relations = [], viewerPersonId = null) {
  const normalizedViewerId = String(viewerPersonId || "").trim();
  if (!normalizedViewerId) {
    return [];
  }

  const normalizedGraph = normalizeTreeGraph(treeId, persons, relations);
  const peopleById = new Map(
    normalizedGraph.people.map((person) => [String(person.id || "").trim(), person]),
  );
  if (!peopleById.has(normalizedViewerId)) {
    return [];
  }

  const traversal = buildTraversalGraph(normalizedGraph.relations);
  const pathIndex = buildBestPathIndex(normalizedViewerId, traversal.adjacency);
  const descriptors = [];

  for (const person of normalizedGraph.people) {
    const personId = String(person.id || "").trim();
    if (!personId) {
      continue;
    }

    if (personId === normalizedViewerId) {
      descriptors.push({
        personId,
        primaryRelationLabel: "Это вы",
        isBlood: true,
        alternatePathCount: 0,
        pathSummary: person.name || personId,
        primaryPathPersonIds: [personId],
      });
      continue;
    }

    const directRelation =
      traversal.directRelations.get(buildSortedIdKey([normalizedViewerId, personId])) || null;
    const bloodDescriptor = computeBloodRelationshipDescriptor(
      normalizedViewerId,
      personId,
      traversal.bloodParentsByChild,
      peopleById,
    );
    const affinityDescriptor = computeAffinityRelationshipDescriptor({
      viewerPersonId: normalizedViewerId,
      targetPersonId: personId,
      peopleById,
      parentsByChild: traversal.parentsByChild,
      childrenByParent: traversal.childrenByParent,
      bloodParentsByChild: traversal.bloodParentsByChild,
      bloodChildrenByParent: traversal.bloodChildrenByParent,
      currentUnionPartnersByPerson: traversal.currentUnionPartnersByPerson,
      siblingsByPerson: traversal.siblingsByPerson,
    });
    let primaryRelationLabel = null;
    let isBlood = false;

    if (directRelation) {
      const customDirectLabel = relationCustomLabelForPerson(directRelation, personId);
      const relationType = relationTypeForPerson(directRelation, personId);
      if (customDirectLabel) {
        primaryRelationLabel = customDirectLabel;
        isBlood = false;
      } else if (relationType && relationType !== "other") {
        const shouldPreferAffinityLabel =
          relationType === "parentInLaw" ||
          relationType === "childInLaw" ||
          relationType === "siblingInLaw" ||
          relationType === "inlaw";
        primaryRelationLabel = shouldPreferAffinityLabel
          ? affinityDescriptor?.label || describeDirectRelationLabel({
              relationType,
              gender: person.gender,
              parentSetType: directRelation.parentSetType,
              unionStatus: directRelation.unionStatus,
            })
          : describeDirectRelationLabel({
              relationType,
              gender: person.gender,
              parentSetType: directRelation.parentSetType,
              // B2: бывший союз → метка «бывший муж/жена» вместо текущей.
              unionStatus: directRelation.unionStatus,
            });
        isBlood = isBloodDirectRelationType(
          relationType,
          directRelation.parentSetType,
        );
      }
    }

    if (!primaryRelationLabel && bloodDescriptor?.label) {
      primaryRelationLabel = bloodDescriptor.label;
      isBlood = bloodDescriptor.isBlood;
    }

    if (!primaryRelationLabel && affinityDescriptor?.label) {
      primaryRelationLabel = affinityDescriptor.label;
      isBlood = false;
    }

    const bestCost = pathIndex.costs.get(personId) || null;
    const primaryPathPersonIds = reconstructPersonPath(
      personId,
      pathIndex.predecessors,
    );
    const alternatePathCount = Math.max(
      0,
      (pathIndex.pathCounts.get(personId) || 1) - 1,
    );
    if (!primaryRelationLabel && primaryPathPersonIds.length > 1) {
      const sparsePathDescriptor = buildSparsePathRelationshipDescriptor({
        targetPersonId: personId,
        primaryPathPersonIds,
        directRelations: traversal.directRelations,
        peopleById,
      });
      if (sparsePathDescriptor?.label) {
        primaryRelationLabel = sparsePathDescriptor.label;
        isBlood = sparsePathDescriptor.isBlood === true;
      }
    }
    if (!primaryRelationLabel && bestCost) {
      primaryRelationLabel =
        bestCost.nonBlood === 0 ? "Кровный родственник" : "Родня по браку";
      isBlood = bestCost.nonBlood === 0;
    }

    if (!primaryRelationLabel) {
      continue;
    }

    descriptors.push({
      personId,
      primaryRelationLabel,
      isBlood,
      alternatePathCount,
      pathSummary: buildPathSummary(primaryPathPersonIds, peopleById),
      primaryPathPersonIds,
    });
  }

  return descriptors;
}

function buildTreeGraphSnapshot({
  treeId,
  persons = [],
  relations = [],
  viewerPersonId = null,
}) {
  const normalizedGraph = normalizeTreeGraph(treeId, persons, relations);
  const displayRelations = buildDisplayTreeRelations(
    treeId,
    normalizedGraph.relations,
  );
  const familyUnits = buildFamilyUnits(
    treeId,
    normalizedGraph.people,
    displayRelations,
  );
  const branchBlocks = resolveBranchBlocks(
    treeId,
    normalizedGraph.people,
    displayRelations,
    familyUnits,
  );
  const generationRows = buildGenerationRows(
    normalizedGraph.people,
    displayRelations,
    familyUnits,
  );
  const warnings = buildGraphWarnings({
    persons: normalizedGraph.people,
    relations: displayRelations,
    familyUnits,
  });

  return {
    treeId,
    viewerPersonId: String(viewerPersonId || "").trim() || null,
    people: normalizedGraph.people,
    relations: displayRelations,
    familyUnits,
    viewerDescriptors: computeViewerKinships(
      treeId,
      normalizedGraph.people,
      displayRelations,
      viewerPersonId,
    ),
    branchBlocks,
    generationRows,
    warnings,
  };
}

module.exports = {
  buildLinkedPersonCanonicalPatchFromProfile,
  applyIncludeRulesToBranch,
  applyCanonicalProfileToPerson,
  buildCanonicalPersonView,
  buildBranchVisiblePersonIds,
  comparePathCost,
  buildTraversalGraph,
  buildBestPathIndex,
  reconstructPersonPath,
  normalizeTreeGraph,
  buildDisplayTreeRelations,
  buildFamilyUnits,
  buildGenerationRows,
  describeParentSetTypeLabelRu,
  buildGraphWarnings,
  resolveBranchBlocks,
  chooseBranchBlockForPerson,
  computeViewerKinships,
  buildTreeGraphSnapshot,
};
