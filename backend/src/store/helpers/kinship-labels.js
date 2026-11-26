const {
  buildSortedIdKey,
  extractSurnameFromName,
  genderAwareWord,
  getMapSetValues,
  hasMapSetValue,
  isFemaleGender,
  isMaleGender,
  isUnionRelationType,
  normalizeParentSetType,
  relationTypeForPerson,
} = require("./relation-utils");

function describeDirectRelationLabel({
  relationType,
  gender = "unknown",
  parentSetType = "biological",
  unionStatus = null,
}) {
  let normalizedRelationType = String(relationType || "").trim().toLowerCase();
  const normalizedParentSetType = normalizeParentSetType(parentSetType);
  // B2: статус союза 'past' на примитивном spouse/partner → метка
  // бывшего союза (тип в пикере остаётся текущим; «бывший» — свойство
  // союза). ended_by_death НЕ превращаем в «бывший»: смерть завершает
  // союз, но по-русски это не «расстались». ex_spouse/ex_partner и так
  // попадут в нужную ветку switch.
  if (String(unionStatus || "").trim().toLowerCase() === "past") {
    if (normalizedRelationType === "spouse") {
      normalizedRelationType = "ex_spouse";
    } else if (normalizedRelationType === "partner") {
      normalizedRelationType = "ex_partner";
    }
  }

  if (normalizedRelationType === "parent") {
    if (normalizedParentSetType === "adoptive") {
      return "Приемный родитель";
    }
    if (normalizedParentSetType === "guardian") {
      return "Опекун";
    }
    if (normalizedParentSetType === "foster") {
      return "Приемный родитель";
    }
    if (normalizedParentSetType === "step") {
      return genderAwareWord(gender, {
        male: "Отчим",
        female: "Мачеха",
        neutral: "Сводный родитель",
      });
    }
    return genderAwareWord(gender, {
      male: "Отец",
      female: "Мать",
      neutral: "Родитель",
    });
  }

  if (normalizedRelationType === "child") {
    if (normalizedParentSetType === "adoptive") {
      return "Приемный ребенок";
    }
    if (normalizedParentSetType === "guardian") {
      return "Подопечный";
    }
    if (normalizedParentSetType === "foster") {
      return "Приемный ребенок";
    }
    if (normalizedParentSetType === "step") {
      return genderAwareWord(gender, {
        male: "Пасынок",
        female: "Падчерица",
        neutral: "Сводный ребенок",
      });
    }
    return genderAwareWord(gender, {
      male: "Сын",
      female: "Дочь",
      neutral: "Ребенок",
    });
  }

  switch (normalizedRelationType) {
    case "sibling":
      return genderAwareWord(gender, {
        male: "Брат",
        female: "Сестра",
        neutral: "Сиблинг",
      });
    case "spouse":
      return genderAwareWord(gender, {
        male: "Муж",
        female: "Жена",
        neutral: "Супруг",
      });
    case "partner":
      return "Партнер";
    case "ex_spouse":
      return genderAwareWord(gender, {
        male: "Бывший муж",
        female: "Бывшая жена",
        neutral: "Бывший супруг",
      });
    case "ex_partner":
      return genderAwareWord(gender, {
        male: "Бывший партнёр",
        female: "Бывшая партнёрша",
        neutral: "Бывший партнёр",
      });
    case "friend":
      return "Друг";
    case "stepparent":
      return genderAwareWord(gender, {
        male: "Отчим",
        female: "Мачеха",
        neutral: "Сводный родитель",
      });
    case "stepchild":
      return genderAwareWord(gender, {
        male: "Пасынок",
        female: "Падчерица",
        neutral: "Сводный ребенок",
      });
    case "grandparent":
      return genderAwareWord(gender, {
        male: "Дедушка",
        female: "Бабушка",
        neutral: "Прародитель",
      });
    case "grandchild":
      return genderAwareWord(gender, {
        male: "Внук",
        female: "Внучка",
        neutral: "Внук/внучка",
      });
    case "uncle":
      return genderAwareWord(gender, {
        male: "Дядя",
        female: "Тетя",
        neutral: "Дядя/тетя",
      });
    case "aunt":
      return genderAwareWord(gender, {
        male: "Дядя",
        female: "Тетя",
        neutral: "Дядя/тетя",
      });
    case "nephew":
    case "niece":
    case "nibling":
      return genderAwareWord(gender, {
        male: "Племянник",
        female: "Племянница",
        neutral: "Племянник/племянница",
      });
    case "cousin":
      return genderAwareWord(gender, {
        male: "Двоюродный брат",
        female: "Двоюродная сестра",
        neutral: "Двоюродный родственник",
      });
    case "parentInLaw":
      return genderAwareWord(gender, {
        male: "Родитель супруга",
        female: "Родительница супруга",
        neutral: "Родитель супруга",
      });
    case "childInLaw":
      return genderAwareWord(gender, {
        male: "Зять",
        female: "Невестка",
        neutral: "Родня по браку",
      });
    case "siblingInLaw":
      return genderAwareWord(gender, {
        male: "Брат супруга",
        female: "Сестра супруга",
        neutral: "Сиблинг супруга",
      });
    case "inlaw":
      return "Родня по браку";
    case "colleague":
      return "Коллега";
    default:
      return "Родственник";
  }
}

function buildPathSummary(pathPersonIds, peopleById) {
  const labels = (Array.isArray(pathPersonIds) ? pathPersonIds : [])
    .map((personId) => {
      const person = peopleById.get(personId);
      return String(person?.name || "").trim() || personId;
    })
    .filter(Boolean);
  return labels.join(" -> ");
}

function collectAncestorDepths(startPersonId, parentsByChild) {
  const depths = new Map();
  const queue = [{personId: startPersonId, depth: 0}];

  while (queue.length > 0) {
    const current = queue.shift();
    if (!current) {
      continue;
    }
    const previousDepth = depths.get(current.personId);
    if (previousDepth !== undefined && previousDepth <= current.depth) {
      continue;
    }
    depths.set(current.personId, current.depth);
    for (const parentId of parentsByChild.get(current.personId) || []) {
      queue.push({
        personId: parentId,
        depth: current.depth + 1,
      });
    }
  }

  return depths;
}

function ordinalCousinLabel(degree) {
  switch (degree) {
    case 1:
      return "Двоюродный";
    case 2:
      return "Троюродный";
    case 3:
      return "Четвероюродный";
    default:
      return "Дальний";
  }
}

function ordinalCousinPrefix(degree, gender) {
  switch (degree) {
    case 1:
      return genderAwareWord(gender, {
        male: "Двоюродный",
        female: "Двоюродная",
        neutral: "Двоюродный",
      });
    case 2:
      return genderAwareWord(gender, {
        male: "Троюродный",
        female: "Троюродная",
        neutral: "Троюродный",
      });
    case 3:
      return genderAwareWord(gender, {
        male: "Четвероюродный",
        female: "Четвероюродная",
        neutral: "Четвероюродный",
      });
    default:
      return genderAwareWord(gender, {
        male: "Дальний",
        female: "Дальняя",
        neutral: "Дальний",
      });
  }
}

function buildAncestorLabel(depth, gender) {
  if (depth === 1) {
    return genderAwareWord(gender, {
      male: "Отец",
      female: "Мать",
      neutral: "Родитель",
    });
  }
  if (depth === 2) {
    return genderAwareWord(gender, {
      male: "Дедушка",
      female: "Бабушка",
      neutral: "Прародитель",
    });
  }
  if (depth === 3) {
    return genderAwareWord(gender, {
      male: "Прадедушка",
      female: "Прабабушка",
      neutral: "Предок",
    });
  }
  return "Предок";
}

function buildDescendantLabel(depth, gender) {
  if (depth === 1) {
    return genderAwareWord(gender, {
      male: "Сын",
      female: "Дочь",
      neutral: "Ребенок",
    });
  }
  if (depth === 2) {
    return genderAwareWord(gender, {
      male: "Внук",
      female: "Внучка",
      neutral: "Внук/внучка",
    });
  }
  if (depth === 3) {
    return genderAwareWord(gender, {
      male: "Правнук",
      female: "Правнучка",
      neutral: "Правнук/правнучка",
    });
  }
  return "Потомок";
}

function buildUncleAuntLabel(gender, prefix = null) {
  const value = genderAwareWord(gender, {
    male: "дядя",
    female: "тетя",
    neutral: "дядя/тетя",
  });
  if (!prefix) {
    return value.charAt(0).toUpperCase() + value.slice(1);
  }
  return `${prefix} ${value}`.trim();
}

function buildNephewNieceLabel(gender, prefix = null) {
  const value = genderAwareWord(gender, {
    male: "племянник",
    female: "племянница",
    neutral: "племянник/племянница",
  });
  if (!prefix) {
    return value.charAt(0).toUpperCase() + value.slice(1);
  }
  return `${prefix} ${value}`.trim();
}

function buildGrandUncleAuntLabel(gender) {
  return genderAwareWord(gender, {
    male: "Двоюродный дедушка",
    female: "Двоюродная бабушка",
    neutral: "Двоюродный дедушка/бабушка",
  });
}

function buildGrandNephewNieceLabel(gender) {
  return genderAwareWord(gender, {
    male: "Внучатый племянник",
    female: "Внучатая племянница",
    neutral: "Внучатый племянник/племянница",
  });
}

function buildCousinOlderGenerationLabel(cousinDegree, gender) {
  const prefix = ordinalCousinPrefix(cousinDegree, gender);
  return genderAwareWord(gender, {
    male: `${prefix} дядя`,
    female: `${prefix} тетя`,
    neutral: `${prefix} дядя/тетя`,
  });
}

function buildCousinYoungerGenerationLabel(cousinDegree, gender) {
  const prefix = ordinalCousinPrefix(cousinDegree, gender);
  return genderAwareWord(gender, {
    male: `${prefix} племянник`,
    female: `${prefix} племянница`,
    neutral: `${prefix} племянник/племянница`,
  });
}

function buildBloodRelationshipLabel({
  viewerDepth,
  targetDepth,
  targetGender,
}) {
  if (viewerDepth === 0 && targetDepth === 0) {
    return "Это вы";
  }

  if (targetDepth === 0 && viewerDepth > 0) {
    return buildAncestorLabel(viewerDepth, targetGender);
  }

  if (viewerDepth === 0 && targetDepth > 0) {
    return buildDescendantLabel(targetDepth, targetGender);
  }

  if (viewerDepth === 1 && targetDepth === 1) {
    return genderAwareWord(targetGender, {
      male: "Брат",
      female: "Сестра",
      neutral: "Сиблинг",
    });
  }

  if (viewerDepth === 1 && targetDepth === 2) {
    return genderAwareWord(targetGender, {
      male: "Племянник",
      female: "Племянница",
      neutral: "Племянник/племянница",
    });
  }

  if (viewerDepth === 1 && targetDepth === 3) {
    return buildGrandNephewNieceLabel(targetGender);
  }

  if (viewerDepth === 2 && targetDepth === 1) {
    return buildUncleAuntLabel(targetGender);
  }

  if (viewerDepth === 3 && targetDepth === 1) {
    return buildGrandUncleAuntLabel(targetGender);
  }

  if (viewerDepth > 1 && targetDepth > 1) {
    const cousinDegree = Math.min(viewerDepth, targetDepth) - 1;
    const removed = Math.abs(viewerDepth - targetDepth);
    if (removed === 0) {
      return `${ordinalCousinPrefix(cousinDegree, targetGender)} ${genderAwareWord(targetGender, {
        male: "брат",
        female: "сестра",
        neutral: "родственник",
      })}`.trim();
    }
    if (removed === 1) {
      if (viewerDepth < targetDepth) {
        return buildCousinYoungerGenerationLabel(cousinDegree, targetGender);
      }
      return buildCousinOlderGenerationLabel(cousinDegree, targetGender);
    }
  }

  return "Кровный родственник";
}

function computeBloodRelationshipDescriptor(
  viewerPersonId,
  targetPersonId,
  bloodParentsByChild,
  peopleById,
) {
  if (!viewerPersonId || !targetPersonId) {
    return null;
  }

  const viewerAncestors = collectAncestorDepths(viewerPersonId, bloodParentsByChild);
  const targetAncestors = collectAncestorDepths(targetPersonId, bloodParentsByChild);
  let bestMatch = null;

  for (const [ancestorId, viewerDepth] of viewerAncestors.entries()) {
    if (!targetAncestors.has(ancestorId)) {
      continue;
    }
    const targetDepth = targetAncestors.get(ancestorId);
    const candidate = {
      ancestorId,
      viewerDepth,
      targetDepth,
      totalDepth: viewerDepth + targetDepth,
      maxDepth: Math.max(viewerDepth, targetDepth),
    };
    if (
      !bestMatch ||
      candidate.totalDepth < bestMatch.totalDepth ||
      (candidate.totalDepth === bestMatch.totalDepth &&
        candidate.maxDepth < bestMatch.maxDepth)
    ) {
      bestMatch = candidate;
    }
  }

  if (!bestMatch) {
    return null;
  }

  const target = peopleById.get(targetPersonId);
  return {
    ancestorId: bestMatch.ancestorId,
    isBlood: true,
    label: buildBloodRelationshipLabel({
      viewerDepth: bestMatch.viewerDepth,
      targetDepth: bestMatch.targetDepth,
      targetGender: target?.gender,
    }),
    viewerDepth: bestMatch.viewerDepth,
    targetDepth: bestMatch.targetDepth,
  };
}

function collectBloodSiblingIds(personId, bloodParentsByChild, bloodChildrenByParent) {
  const siblingIds = new Set();
  for (const parentId of getMapSetValues(bloodParentsByChild, personId)) {
    for (const childId of getMapSetValues(bloodChildrenByParent, parentId)) {
      if (childId !== personId) {
        siblingIds.add(childId);
      }
    }
  }
  return Array.from(siblingIds);
}

function collectKnownSiblingIds(
  personId,
  bloodParentsByChild,
  bloodChildrenByParent,
  siblingsByPerson,
) {
  const siblingIds = new Set(
    collectBloodSiblingIds(personId, bloodParentsByChild, bloodChildrenByParent),
  );
  for (const siblingId of getMapSetValues(siblingsByPerson, personId)) {
    if (siblingId !== personId) {
      siblingIds.add(siblingId);
    }
  }
  return Array.from(siblingIds);
}

function buildParentInLawLabel({spouseGender, targetGender}) {
  if (isFemaleGender(spouseGender)) {
    return genderAwareWord(targetGender, {
      male: "Тесть",
      female: "Теща",
      neutral: "Родитель жены",
    });
  }
  if (isMaleGender(spouseGender)) {
    return genderAwareWord(targetGender, {
      male: "Свекор",
      female: "Свекровь",
      neutral: "Родитель мужа",
    });
  }
  return genderAwareWord(targetGender, {
    male: "Родитель супруга",
    female: "Родительница супруга",
    neutral: "Родитель супруга",
  });
}

function buildSiblingInLawLabel({spouseGender, targetGender}) {
  if (isFemaleGender(spouseGender)) {
    return genderAwareWord(targetGender, {
      male: "Шурин",
      female: "Свояченица",
      neutral: "Родня жены",
    });
  }
  if (isMaleGender(spouseGender)) {
    return genderAwareWord(targetGender, {
      male: "Деверь",
      female: "Золовка",
      neutral: "Родня мужа",
    });
  }
  return genderAwareWord(targetGender, {
    male: "Брат супруга",
    female: "Сестра супруга",
    neutral: "Сиблинг супруга",
  });
}

function buildChildInLawLabel(targetGender) {
  return genderAwareWord(targetGender, {
    male: "Зять",
    female: "Невестка",
    neutral: "Родня по браку",
  });
}

function buildMatchmakerLabel(targetGender) {
  return genderAwareWord(targetGender, {
    male: "Сват",
    female: "Сватья",
    neutral: "Сват",
  });
}

function buildAffinalInheritedLabel(baseLabel, targetGender) {
  const normalizedLabel = String(baseLabel || "").trim().toLowerCase();
  if (!normalizedLabel) {
    return null;
  }
  if (
    normalizedLabel === "дядя" ||
    normalizedLabel === "тетя" ||
    normalizedLabel.startsWith("двоюродный дяд") ||
    normalizedLabel.startsWith("двоюродная тет")
  ) {
    if (normalizedLabel.startsWith("двоюрод")) {
      return buildCousinOlderGenerationLabel(1, targetGender);
    }
    return buildUncleAuntLabel(targetGender);
  }
  if (
    normalizedLabel.startsWith("двоюродный дед") ||
    normalizedLabel.startsWith("двоюродная баб")
  ) {
    return buildGrandUncleAuntLabel(targetGender);
  }
  return null;
}

function computeAffinityRelationshipDescriptor({
  viewerPersonId,
  targetPersonId,
  peopleById,
  parentsByChild,
  childrenByParent,
  bloodParentsByChild,
  bloodChildrenByParent,
  currentUnionPartnersByPerson,
  siblingsByPerson,
}) {
  const viewer = peopleById.get(viewerPersonId);
  const target = peopleById.get(targetPersonId);
  if (!viewer || !target) {
    return null;
  }

  const viewerPartners = getMapSetValues(currentUnionPartnersByPerson, viewerPersonId);
  for (const spouseId of viewerPartners) {
    const spouse = peopleById.get(spouseId);
    if (!spouse) {
      continue;
    }
    if (hasMapSetValue(parentsByChild, spouseId, targetPersonId)) {
      return {
        label: buildParentInLawLabel({
          spouseGender: spouse.gender,
          targetGender: target.gender,
        }),
        isBlood: false,
      };
    }

    const spouseSiblingIds = collectKnownSiblingIds(
      spouseId,
      bloodParentsByChild,
      bloodChildrenByParent,
      siblingsByPerson,
    );
    if (spouseSiblingIds.includes(targetPersonId)) {
      return {
        label: buildSiblingInLawLabel({
          spouseGender: spouse.gender,
          targetGender: target.gender,
        }),
        isBlood: false,
      };
    }

    if (
      hasMapSetValue(childrenByParent, spouseId, targetPersonId) &&
      !hasMapSetValue(childrenByParent, viewerPersonId, targetPersonId)
    ) {
      return {
        label: describeDirectRelationLabel({
          relationType: "stepchild",
          gender: target.gender,
          parentSetType: "step",
        }),
        isBlood: false,
      };
    }

    for (const spouseSiblingId of spouseSiblingIds) {
      const spouseSibling = peopleById.get(spouseSiblingId);
      if (!spouseSibling) {
        continue;
      }
      if (
        hasMapSetValue(currentUnionPartnersByPerson, spouseSiblingId, targetPersonId) &&
        isMaleGender(target.gender) &&
        isFemaleGender(spouseSibling.gender)
      ) {
        return {
          label: "Свояк",
          isBlood: false,
        };
      }
    }
  }

  for (const parentId of getMapSetValues(parentsByChild, viewerPersonId)) {
    if (
      hasMapSetValue(currentUnionPartnersByPerson, parentId, targetPersonId) &&
      !hasMapSetValue(parentsByChild, viewerPersonId, targetPersonId)
    ) {
      return {
        label: describeDirectRelationLabel({
          relationType: "stepparent",
          gender: target.gender,
          parentSetType: "step",
        }),
        isBlood: false,
      };
    }
  }

  for (const childId of getMapSetValues(childrenByParent, viewerPersonId)) {
    if (hasMapSetValue(currentUnionPartnersByPerson, childId, targetPersonId)) {
      return {
        label: buildChildInLawLabel(target.gender),
        isBlood: false,
      };
    }

    for (const childPartnerId of getMapSetValues(currentUnionPartnersByPerson, childId)) {
      if (
        childPartnerId !== viewerPersonId &&
        hasMapSetValue(parentsByChild, childPartnerId, targetPersonId)
      ) {
        return {
          label: buildMatchmakerLabel(target.gender),
          isBlood: false,
        };
      }
    }
  }

  for (const siblingId of collectKnownSiblingIds(
    viewerPersonId,
    bloodParentsByChild,
    bloodChildrenByParent,
    siblingsByPerson,
  )) {
    if (hasMapSetValue(currentUnionPartnersByPerson, siblingId, targetPersonId)) {
      return {
        label: buildChildInLawLabel(target.gender),
        isBlood: false,
      };
    }
  }

  for (const partnerId of getMapSetValues(currentUnionPartnersByPerson, targetPersonId)) {
    const partnerBloodDescriptor = computeBloodRelationshipDescriptor(
      viewerPersonId,
      partnerId,
      bloodParentsByChild,
      peopleById,
    );
    const inheritedLabel = buildAffinalInheritedLabel(
      partnerBloodDescriptor?.label,
      target.gender,
    );
    if (inheritedLabel) {
      return {
        label: inheritedLabel,
        isBlood: false,
      };
    }
  }

  return null;
}

function relationTypeAlongPath(directRelations, fromPersonId, toPersonId) {
  const relation = directRelations.get(buildSortedIdKey([fromPersonId, toPersonId]));
  if (!relation) {
    return null;
  }
  return String(relationTypeForPerson(relation, toPersonId) || "")
    .trim()
    .toLowerCase() || null;
}

function buildSparsePathRelationshipDescriptor({
  targetPersonId,
  primaryPathPersonIds,
  directRelations,
  peopleById,
}) {
  if (!Array.isArray(primaryPathPersonIds) || primaryPathPersonIds.length < 2) {
    return null;
  }

  const target = peopleById.get(String(targetPersonId || "").trim());
  if (!target) {
    return null;
  }

  const edgeTypes = [];
  for (let index = 0; index < primaryPathPersonIds.length - 1; index += 1) {
    const relationType = relationTypeAlongPath(
      directRelations,
      primaryPathPersonIds[index],
      primaryPathPersonIds[index + 1],
    );
    if (!relationType) {
      return null;
    }
    edgeTypes.push(relationType);
  }

  if (edgeTypes.length === 2 && edgeTypes[0] === "parent" && edgeTypes[1] === "sibling") {
    return {
      label: buildUncleAuntLabel(target.gender),
      isBlood: true,
    };
  }

  if (
    edgeTypes.length === 3 &&
    edgeTypes[0] === "parent" &&
    edgeTypes[1] === "sibling" &&
    edgeTypes[2] === "child"
  ) {
    return {
      label: genderAwareWord(target.gender, {
        male: "Двоюродный брат",
        female: "Двоюродная сестра",
        neutral: "Двоюродный родственник",
      }),
      isBlood: true,
    };
  }

  if (
    edgeTypes.length === 2 &&
    edgeTypes[0] === "sibling" &&
    edgeTypes[1] === "child"
  ) {
    return {
      label: buildNephewNieceLabel(target.gender),
      isBlood: true,
    };
  }

  if (
    edgeTypes.length === 3 &&
    edgeTypes[0] === "sibling" &&
    edgeTypes[1] === "child" &&
    edgeTypes[2] === "child"
  ) {
    return {
      label: buildGrandNephewNieceLabel(target.gender),
      isBlood: true,
    };
  }

  if (
    edgeTypes.length === 3 &&
    edgeTypes[0] === "parent" &&
    edgeTypes[1] === "parent" &&
    edgeTypes[2] === "sibling"
  ) {
    return {
      label: buildGrandUncleAuntLabel(target.gender),
      isBlood: true,
    };
  }

  const lastEdgeType = edgeTypes[edgeTypes.length - 1];
  const olderGenerationChain = edgeTypes.slice(0, -1);
  if (
    isUnionRelationType(lastEdgeType) &&
    olderGenerationChain.length >= 2 &&
    olderGenerationChain[olderGenerationChain.length - 1] === "sibling" &&
    olderGenerationChain.slice(0, -1).every((relationType) => relationType === "parent")
  ) {
    const parentDepth = olderGenerationChain.length - 1;
    if (parentDepth === 1) {
      return {
        label: buildUncleAuntLabel(target.gender),
        isBlood: false,
      };
    }
    if (parentDepth === 2) {
      return {
        label: buildGrandUncleAuntLabel(target.gender),
        isBlood: false,
      };
    }
  }

  return null;
}

function buildFamilyUnitLabel({adultIds, peopleById}) {
  const adults = (Array.isArray(adultIds) ? adultIds : [])
    .map((personId) => peopleById.get(personId))
    .filter(Boolean);

  if (adults.length === 0) {
    return "Семья";
  }

  const surnames = Array.from(
    new Set(
      adults
        .map((person) => extractSurnameFromName(person.name))
        .filter(Boolean),
    ),
  );
  if (surnames.length === 1) {
    return `Ветка ${surnames[0]}`;
  }

  if (adults.length === 1) {
    return `Семья ${adults[0].name}`;
  }

  return `Семья ${adults[0].name} и ${adults[1].name}`;
}

function buildBranchLabel({rootUnit, peopleById}) {
  if (!rootUnit) {
    return "Семья";
  }
  return buildFamilyUnitLabel({
    adultIds: rootUnit.adultIds,
    peopleById,
  });
}

module.exports = {
  describeDirectRelationLabel,
  buildPathSummary,
  collectAncestorDepths,
  ordinalCousinLabel,
  ordinalCousinPrefix,
  buildAncestorLabel,
  buildDescendantLabel,
  buildUncleAuntLabel,
  buildNephewNieceLabel,
  buildGrandUncleAuntLabel,
  buildGrandNephewNieceLabel,
  buildCousinOlderGenerationLabel,
  buildCousinYoungerGenerationLabel,
  buildBloodRelationshipLabel,
  computeBloodRelationshipDescriptor,
  collectBloodSiblingIds,
  collectKnownSiblingIds,
  buildParentInLawLabel,
  buildSiblingInLawLabel,
  buildChildInLawLabel,
  buildMatchmakerLabel,
  buildAffinalInheritedLabel,
  computeAffinityRelationshipDescriptor,
  relationTypeAlongPath,
  buildSparsePathRelationshipDescriptor,
  buildFamilyUnitLabel,
  buildBranchLabel,
};
