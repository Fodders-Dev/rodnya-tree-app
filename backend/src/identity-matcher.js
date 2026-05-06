function normalizeNullableString(value) {
  const normalized = String(value || "").trim();
  return normalized ? normalized : null;
}

function normalizeName(value) {
  const normalized = String(value || "")
    .trim()
    .toLowerCase()
    .replace(/ё/g, "е")
    .replace(/[^a-zа-я0-9\s-]/gi, " ")
    .replace(/\s+/g, " ");
  return normalized || null;
}

function normalizeNameTokens(value) {
  const normalized = normalizeName(value);
  if (!normalized) {
    return [];
  }
  return Array.from(new Set(normalized.split(/\s+/).filter(Boolean))).sort(
    (left, right) => left.localeCompare(right),
  );
}

function normalizeIsoDate(value) {
  const rawValue = String(value || "").trim();
  if (!rawValue) {
    return null;
  }
  const parsed = new Date(rawValue);
  if (Number.isNaN(parsed.getTime())) {
    return null;
  }
  return parsed.toISOString().slice(0, 10);
}

function normalizedBirthYear(value) {
  const date = normalizeIsoDate(value);
  return date ? date.slice(0, 4) : null;
}

function sameKnownValue(left, right) {
  const normalizedLeft = normalizeNullableString(left);
  const normalizedRight = normalizeNullableString(right);
  return normalizedLeft && normalizedRight && normalizedLeft === normalizedRight;
}

function tokenSimilarity(leftTokens, rightTokens) {
  if (leftTokens.length === 0 || rightTokens.length === 0) {
    return 0;
  }
  const rightSet = new Set(rightTokens);
  const sharedCount = leftTokens.filter((token) => rightSet.has(token)).length;
  return sharedCount / Math.max(leftTokens.length, rightTokens.length);
}

function scorePersonPair(left, right) {
  const leftName = normalizeName(left?.name);
  const rightName = normalizeName(right?.name);
  const leftTokens = normalizeNameTokens(left?.name);
  const rightTokens = normalizeNameTokens(right?.name);
  const reasons = [];
  let score = 0;

  if (leftName && rightName && leftName === rightName) {
    score += 0.62;
    reasons.push("Совпадает ФИО");
  } else {
    const similarity = tokenSimilarity(leftTokens, rightTokens);
    if (similarity >= 0.85 && Math.min(leftTokens.length, rightTokens.length) >= 2) {
      score += 0.42;
      reasons.push("Очень похожее имя");
    } else if (
      similarity >= 0.7 &&
      Math.min(leftTokens.length, rightTokens.length) >= 2
    ) {
      score += 0.28;
      reasons.push("Похожее имя");
    }
  }

  const leftBirthDate = normalizeIsoDate(left?.birthDate);
  const rightBirthDate = normalizeIsoDate(right?.birthDate);
  if (leftBirthDate && rightBirthDate && leftBirthDate === rightBirthDate) {
    score += 0.28;
    reasons.push("Совпадает дата рождения");
  } else if (sameKnownValue(normalizedBirthYear(left?.birthDate), normalizedBirthYear(right?.birthDate))) {
    score += 0.16;
    reasons.push("Совпадает год рождения");
  }

  if (
    sameKnownValue(left?.gender, right?.gender) &&
    String(left?.gender || "").trim() !== "unknown"
  ) {
    score += 0.05;
    reasons.push("Совпадает пол");
  }

  if (sameKnownValue(left?.birthPlace, right?.birthPlace)) {
    score += 0.06;
    reasons.push("Совпадает место рождения");
  }

  if (sameKnownValue(normalizeIsoDate(left?.deathDate), normalizeIsoDate(right?.deathDate))) {
    score += 0.04;
    reasons.push("Совпадает дата смерти");
  }

  const hasStrongNameSignal =
    leftName && rightName && (leftName === rightName || tokenSimilarity(leftTokens, rightTokens) >= 0.85);
  const hasBiographicalSignal =
    leftBirthDate ||
    rightBirthDate ||
    normalizeNullableString(left?.birthPlace) ||
    normalizeNullableString(right?.birthPlace);

  if (!hasStrongNameSignal || !hasBiographicalSignal) {
    return null;
  }

  if (score < 0.78) {
    return null;
  }

  return {
    score: Math.min(0.99, Number(score.toFixed(2))),
    reasons,
  };
}

function findWithinTreeDuplicateCandidates({
  treeId,
  persons,
  limit = 20,
} = {}) {
  const normalizedTreeId = normalizeNullableString(treeId);
  if (!normalizedTreeId || !Array.isArray(persons)) {
    return [];
  }

  const treePersons = persons.filter((person) => {
    return (
      person &&
      typeof person === "object" &&
      person.treeId === normalizedTreeId &&
      normalizeNullableString(person.id) &&
      !normalizeNullableString(person.userId)
    );
  });

  const suggestions = [];
  for (let leftIndex = 0; leftIndex < treePersons.length; leftIndex += 1) {
    for (
      let rightIndex = leftIndex + 1;
      rightIndex < treePersons.length;
      rightIndex += 1
    ) {
      const left = treePersons[leftIndex];
      const right = treePersons[rightIndex];
      if (
        normalizeNullableString(left.identityId) &&
        normalizeNullableString(left.identityId) ===
          normalizeNullableString(right.identityId)
      ) {
        continue;
      }

      const match = scorePersonPair(left, right);
      if (!match) {
        continue;
      }

      const [personA, personB] = [left, right].sort((a, b) =>
        String(a.id).localeCompare(String(b.id)),
      );
      suggestions.push({
        id: `${normalizedTreeId}:${personA.id}:${personB.id}`,
        treeId: normalizedTreeId,
        personA,
        personB,
        score: match.score,
        confidence: match.score >= 0.9 ? "high" : "medium",
        reasons: match.reasons,
      });
    }
  }

  return suggestions
    .sort((left, right) => {
      if (right.score !== left.score) {
        return right.score - left.score;
      }
      return left.id.localeCompare(right.id);
    })
    .slice(0, Math.max(0, Math.min(Number(limit) || 20, 100)));
}

// Phase 1.2 of unified-graph migration: cross-tree identity
// suggestions. For a single source person, score them against
// every person in the user's OTHER accessible trees and return
// medium+high confidence matches that aren't already linked or
// dismissed. Surfaces the user's natural duplicates without
// dragging them through 200 modal popups.
//
// Threshold tuning:
//   * 0.78+ score = surface (mid+high)
//   * < 0.78     = silent, never shown
//   * confidence = "high" when score >= 0.9, "medium" otherwise
// Mirrors within-tree scoring so the user sees consistent
// confidence levels across both surfaces.
function findCrossTreeIdentitySuggestions({
  sourcePerson,
  accessibleTrees,
  persons,
  dismissedTargetPersonIds = new Set(),
  limit = 10,
} = {}) {
  if (!sourcePerson || typeof sourcePerson !== "object") return [];
  if (!Array.isArray(persons) || !Array.isArray(accessibleTrees)) return [];
  const accessibleTreeIds = new Set(
    accessibleTrees.map((tree) => normalizeNullableString(tree?.id)).filter(Boolean),
  );
  const sourceTreeId = normalizeNullableString(sourcePerson.treeId);
  const sourcePersonId = normalizeNullableString(sourcePerson.id);
  if (!sourceTreeId || !sourcePersonId) return [];
  const sourceIdentityId = normalizeNullableString(sourcePerson.identityId);

  const treeNameById = new Map();
  for (const tree of accessibleTrees) {
    if (tree?.id) treeNameById.set(tree.id, tree.name || "");
  }

  const suggestions = [];
  for (const candidate of persons) {
    if (!candidate || typeof candidate !== "object") continue;
    const candidateTreeId = normalizeNullableString(candidate.treeId);
    if (!candidateTreeId || !accessibleTreeIds.has(candidateTreeId)) continue;
    // Skip persons in the source's own tree — within-tree
    // duplicates have their own surface (`/duplicates`).
    if (candidateTreeId === sourceTreeId) continue;
    const candidatePersonId = normalizeNullableString(candidate.id);
    if (!candidatePersonId) continue;
    // Skip if user already dismissed this exact pair.
    if (dismissedTargetPersonIds.has(candidatePersonId)) continue;
    // Skip if already linked via identityId — they're already
    // the "same human" in our model. (Phase 1.1 handles edit
    // propagation; the matcher only surfaces UNlinked candidates.)
    const candidateIdentityId = normalizeNullableString(candidate.identityId);
    if (
      sourceIdentityId &&
      candidateIdentityId &&
      sourceIdentityId === candidateIdentityId
    ) {
      continue;
    }

    const match = scorePersonPair(sourcePerson, candidate);
    if (!match) continue;

    suggestions.push({
      sourcePersonId,
      sourceTreeId,
      targetPersonId: candidatePersonId,
      targetTreeId: candidateTreeId,
      targetTreeName: treeNameById.get(candidateTreeId) || "",
      targetPerson: candidate,
      score: match.score,
      confidence: match.score >= 0.9 ? "high" : "medium",
      reasons: match.reasons,
    });
  }

  return suggestions
    .sort((left, right) => {
      if (right.score !== left.score) return right.score - left.score;
      return left.targetPersonId.localeCompare(right.targetPersonId);
    })
    .slice(0, Math.max(0, Math.min(Number(limit) || 10, 50)));
}

module.exports = {
  findWithinTreeDuplicateCandidates,
  findCrossTreeIdentitySuggestions,
  normalizedBirthYear,
  scorePersonPair,
};
