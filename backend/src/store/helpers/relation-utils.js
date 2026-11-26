const {
  BLOOD_PARENT_SET_TYPES,
  PARENT_SET_TYPES,
  UNION_STATUSES,
  UNION_TYPES,
} = require("../constants");
const {
  normalizeNullableString,
  normalizeOptionalIsoTimestamp,
  normalizeParticipantIds,
} = require("./utils");

// ── Phase 4: blood-relation classification ────────────────────────────
// `parent` / `child` / `sibling` are the three edges the BFS engine
// walks to find consanguinity paths. step-/adopted-/in-law variants
// are NOT blood — they connect family but not DNA — and are
// deliberately excluded so "найти родство" stays meaningful.
function canonicalBloodType(rawType) {
  switch (String(rawType || "").toLowerCase().trim()) {
    case "parent":
      return "parent";
    case "child":
      return "child";
    case "sibling":
      return "sibling";
    default:
      return null;
  }
}

// Mirror of a blood type — used when one side of a legacy relation
// row was stored without a relation2to1 value. The existing tree
// code in `_buildBranchVisiblePersonIds` (line ~12420) does the
// same fallback via `relationMirror`; doing it here keeps the
// blood-graph in sync with what the rest of the backend already
// considers "family" for that record.
function mirrorBloodType(rawType) {
  const canonical = canonicalBloodType(rawType);
  if (canonical === "parent") return "child";
  if (canonical === "child") return "parent";
  if (canonical === "sibling") return "sibling";
  return null;
}

// Russian relationship label generator. Takes the edge sequence
// produced by the BFS (e.g. ["parent","sibling","child"]) and the
// target person's gender, returns a human label + degree. Handles
// the common direct-line / sibling / cousin patterns; falls back
// to a neutral "родственник" for shapes we don't classify yet
// (zigzag paths through marriage etc., though the engine doesn't
// produce those today since spouse edges aren't in the graph).
function describeBloodRelation(edges, gender) {
  // Edge semantics: each edge label is the role of the TARGET side
  // (the person we're walking TO).
  // - "parent" edge means I went TO a parent (going UP — towards
  //   ancestor).
  // - "child" edge means I went TO a child (going DOWN — towards
  //   descendant).
  // - "sibling" edge stays lateral.
  // Matches the convention in _buildBranchVisiblePersonIds.
  let up = 0;
  let hasSibling = false;
  let down = 0;
  let i = 0;
  while (i < edges.length && edges[i] === "parent") {
    up++;
    i++;
  }
  if (i < edges.length && edges[i] === "sibling") {
    hasSibling = true;
    i++;
  }
  while (i < edges.length && edges[i] === "child") {
    down++;
    i++;
  }
  if (i !== edges.length) {
    // Unusual shape — e.g. child-parent-child traversal that
    // would imply spouse edges. We don't traverse those, but
    // be defensive in case future code surfaces such paths.
    return {label: "Родственник", degree: edges.length};
  }

  const isFemale = String(gender || "").toLowerCase() === "female";

  // Direct ancestor line.
  if (!hasSibling && down === 0 && up > 0) {
    if (up === 1) return {label: isFemale ? "мама" : "папа", degree: 1};
    if (up === 2) return {label: isFemale ? "бабушка" : "дедушка", degree: 2};
    if (up === 3)
      return {label: isFemale ? "прабабушка" : "прадедушка", degree: 3};
    const prefix = "пра".repeat(up - 2);
    return {
      label: `${prefix}${isFemale ? "бабушка" : "дедушка"}`,
      degree: up,
    };
  }

  // Direct descendant line.
  if (!hasSibling && up === 0 && down > 0) {
    if (down === 1) return {label: isFemale ? "дочь" : "сын", degree: 1};
    if (down === 2)
      return {label: isFemale ? "внучка" : "внук", degree: 2};
    if (down === 3)
      return {label: isFemale ? "правнучка" : "правнук", degree: 3};
    const prefix = "пра".repeat(down - 2);
    return {
      label: `${prefix}${isFemale ? "внучка" : "внук"}`,
      degree: down,
    };
  }

  // Pure sibling.
  if (hasSibling && up === 0 && down === 0) {
    return {label: isFemale ? "сестра" : "брат", degree: 1};
  }

  // Sibling-of-ancestor: uncle / aunt and their elders.
  if (hasSibling && up >= 1 && down === 0) {
    if (up === 1) return {label: isFemale ? "тётя" : "дядя", degree: 2};
    if (up === 2) {
      return {
        label: isFemale ? "двоюродная бабушка" : "двоюродный дедушка",
        degree: 3,
      };
    }
    const prefix = "пра".repeat(up - 1);
    return {
      label: `${prefix}${isFemale ? "тётя" : "дядя"}`,
      degree: up + 1,
    };
  }

  // Descendant-of-sibling: nephew / niece and their juniors.
  if (hasSibling && up === 0 && down >= 1) {
    if (down === 1) {
      return {label: isFemale ? "племянница" : "племянник", degree: 2};
    }
    if (down === 2) {
      return {
        label: isFemale ? "внучатая племянница" : "внучатый племянник",
        degree: 3,
      };
    }
    const prefix = "пра".repeat(down - 1);
    return {
      label: `${prefix}${isFemale ? "племянница" : "племянник"}`,
      degree: down + 1,
    };
  }

  // Cousin family: ancestor → sibling → descendant.
  if (hasSibling && up >= 1 && down >= 1) {
    const cousinDegree = Math.min(up, down);
    const removed = Math.abs(up - down);
    const cousinPrefixOptions = [
      "двоюродный",
      "троюродный",
      "четвероюродный",
      "пятиюродный",
      "шестиюродный",
    ];
    const cousinPrefix =
      cousinPrefixOptions[cousinDegree - 1] || `${cousinDegree + 1}-юродный`;
    if (removed === 0) {
      return {
        label: `${cousinPrefix} ${isFemale ? "сестра" : "брат"}`,
        degree: up + down + 1,
      };
    }
    if (up > down) {
      return {
        label: `${cousinPrefix} ${isFemale ? "тётя" : "дядя"}`,
        degree: up + down + 1,
      };
    }
    return {
      label: `${cousinPrefix} ${isFemale ? "племянница" : "племянник"}`,
      degree: up + down + 1,
    };
  }

  return {label: "Родственник", degree: edges.length};
}

function sameNormalizedIds(left, right) {
  const normalizedLeft = normalizeParticipantIds(left);
  const normalizedRight = normalizeParticipantIds(right);
  if (normalizedLeft.length !== normalizedRight.length) {
    return false;
  }

  return normalizedLeft.every((value, index) => value === normalizedRight[index]);
}

function isSpouseLikeRelation(relation) {
  return (
    relation?.relation1to2 === "spouse" ||
    relation?.relation2to1 === "spouse" ||
    relation?.relation1to2 === "partner" ||
    relation?.relation2to1 === "partner"
  );
}

function parentIdFromRelation(relation) {
  if (
    relation?.relation1to2 === "parent" ||
    relation?.relation2to1 === "child"
  ) {
    return relation.person1Id;
  }
  if (
    relation?.relation2to1 === "parent" ||
    relation?.relation1to2 === "child"
  ) {
    return relation.person2Id;
  }
  return null;
}

function childIdFromRelation(relation) {
  if (
    relation?.relation1to2 === "parent" ||
    relation?.relation2to1 === "child"
  ) {
    return relation.person2Id;
  }
  if (
    relation?.relation2to1 === "parent" ||
    relation?.relation1to2 === "child"
  ) {
    return relation.person1Id;
  }
  return null;
}

function buildSortedIdKey(values) {
  return (Array.isArray(values) ? values : [])
    .map((value) => String(value || "").trim())
    .filter(Boolean)
    .sort((left, right) => left.localeCompare(right))
    .join(":");
}

function extractSurnameFromName(name) {
  const parts = String(name || "")
    .trim()
    .split(/\s+/)
    .filter(Boolean);
  if (parts.length === 0) {
    return null;
  }
  return parts[0];
}

function normalizeParentSetType(value) {
  const normalized = String(value || "").trim().toLowerCase();
  return PARENT_SET_TYPES.has(normalized) ? normalized : "biological";
}

function isBloodParentSetType(value) {
  return BLOOD_PARENT_SET_TYPES.has(normalizeParentSetType(value));
}

function normalizeUnionType(value, {relationType = null} = {}) {
  const normalized = String(value || "").trim().toLowerCase();
  if (UNION_TYPES.has(normalized)) {
    return normalized;
  }

  const normalizedRelationType = String(relationType || "")
    .trim()
    .toLowerCase();
  if (normalizedRelationType === "spouse" || normalizedRelationType === "ex_spouse") {
    return "spouse";
  }
  if (normalizedRelationType === "partner" || normalizedRelationType === "ex_partner") {
    return "partner";
  }
  if (normalizedRelationType === "friend") {
    return "friend";
  }

  return "other";
}

function normalizeUnionStatus(value, {relationType = null, divorceDate = null} = {}) {
  const normalized = String(value || "").trim().toLowerCase();
  if (UNION_STATUSES.has(normalized)) {
    return normalized;
  }

  const normalizedRelationType = String(relationType || "")
    .trim()
    .toLowerCase();
  if (
    normalizedRelationType === "ex_spouse" ||
    normalizedRelationType === "ex_partner" ||
    normalizeOptionalIsoTimestamp(divorceDate)
  ) {
    return "past";
  }

  return "current";
}

function relationTypeForPerson(relation, personId) {
  const normalizedPersonId = String(personId || "").trim();
  if (!normalizedPersonId) {
    return null;
  }
  if (String(relation?.person1Id || "").trim() === normalizedPersonId) {
    return String(relation?.relation1to2 || "").trim() || null;
  }
  if (String(relation?.person2Id || "").trim() === normalizedPersonId) {
    return String(relation?.relation2to1 || "").trim() || null;
  }
  return null;
}

function relationCustomLabelForPerson(relation, personId) {
  const normalizedPersonId = String(personId || "").trim();
  if (!normalizedPersonId) {
    return null;
  }
  if (String(relation?.person1Id || "").trim() === normalizedPersonId) {
    return normalizeNullableString(relation?.customRelationLabel1to2);
  }
  if (String(relation?.person2Id || "").trim() === normalizedPersonId) {
    return normalizeNullableString(relation?.customRelationLabel2to1);
  }
  return null;
}

function isUnionRelationType(relationType) {
  switch (String(relationType || "").trim().toLowerCase()) {
    case "spouse":
    case "partner":
    case "friend":
    case "ex_spouse":
    case "ex_partner":
      return true;
    default:
      return false;
  }
}

function isUnionRelation(relation) {
  return (
    isUnionRelationType(relation?.relation1to2) ||
    isUnionRelationType(relation?.relation2to1)
  );
}

function isBloodDirectRelationType(relationType, parentSetType = null) {
  switch (String(relationType || "").trim().toLowerCase()) {
    case "parent":
    case "child":
      return isBloodParentSetType(parentSetType);
    case "sibling":
    case "cousin":
    case "uncle":
    case "aunt":
    case "nephew":
    case "niece":
    case "nibling":
    case "grandparent":
    case "grandchild":
    case "greatgrandparent":
    case "greatgrandchild":
      return true;
    default:
      return false;
  }
}

function isCurrentUnionRelation(relation) {
  if (!isUnionRelation(relation)) {
    return false;
  }
  return normalizeUnionStatus(relation?.unionStatus, {
    relationType: relation?.relation1to2 || relation?.relation2to1,
    divorceDate: relation?.divorceDate,
  }) === "current";
}

function relationMirror(relationType) {
  switch (String(relationType || "other")) {
    case "parent":
      return "child";
    case "child":
      return "parent";
    case "spouse":
      return "spouse";
    case "partner":
      return "partner";
    case "sibling":
      return "sibling";
    case "cousin":
      return "cousin";
    case "uncle":
      return "nibling";
    case "aunt":
      return "nibling";
    case "nephew":
      return "uncle";
    case "niece":
      return "aunt";
    case "nibling":
      return "uncle";
    case "grandparent":
      return "grandchild";
    case "grandchild":
      return "grandparent";
    case "greatGrandparent":
      return "greatGrandchild";
    case "greatGrandchild":
      return "greatGrandparent";
    case "parentInLaw":
      return "childInLaw";
    case "childInLaw":
      return "parentInLaw";
    case "siblingInLaw":
      return "siblingInLaw";
    case "inlaw":
      return "inlaw";
    case "stepparent":
      return "stepchild";
    case "stepchild":
      return "stepparent";
    case "ex_spouse":
      return "ex_spouse";
    case "ex_partner":
      return "ex_partner";
    case "friend":
      return "friend";
    case "colleague":
      return "colleague";
    default:
      return "other";
  }
}

function genderAwareWord(gender, {
  male,
  female,
  neutral,
}) {
  const normalizedGender = String(gender || "").trim().toLowerCase();
  if (normalizedGender === "male" && male) {
    return male;
  }
  if (normalizedGender === "female" && female) {
    return female;
  }
  return neutral || male || female || "";
}

function normalizeGenderValue(gender) {
  return String(gender || "").trim().toLowerCase();
}

function isMaleGender(gender) {
  return normalizeGenderValue(gender) === "male";
}

function isFemaleGender(gender) {
  return normalizeGenderValue(gender) === "female";
}

function addMapSetValue(map, key, value) {
  const normalizedKey = String(key || "").trim();
  const normalizedValue = String(value || "").trim();
  if (!normalizedKey || !normalizedValue) {
    return;
  }
  if (!map.has(normalizedKey)) {
    map.set(normalizedKey, new Set());
  }
  map.get(normalizedKey).add(normalizedValue);
}

function getMapSetValues(map, key) {
  return Array.from(map.get(String(key || "").trim()) || []);
}

function hasMapSetValue(map, key, value) {
  return Boolean(map.get(String(key || "").trim())?.has(String(value || "").trim()));
}

module.exports = {
  canonicalBloodType,
  mirrorBloodType,
  describeBloodRelation,
  sameNormalizedIds,
  isSpouseLikeRelation,
  parentIdFromRelation,
  childIdFromRelation,
  buildSortedIdKey,
  extractSurnameFromName,
  normalizeParentSetType,
  isBloodParentSetType,
  normalizeUnionType,
  normalizeUnionStatus,
  relationTypeForPerson,
  relationCustomLabelForPerson,
  isUnionRelationType,
  isUnionRelation,
  isBloodDirectRelationType,
  isCurrentUnionRelation,
  relationMirror,
  genderAwareWord,
  normalizeGenderValue,
  isMaleGender,
  isFemaleGender,
  addMapSetValue,
  getMapSetValues,
  hasMapSetValue,
};
