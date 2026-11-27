const path = require("node:path");
const crypto = require("node:crypto");
const {
  buildDisplayTreeRelations,
  buildSortedIdKey,
  buildTreeGraphSnapshot,
  childIdFromRelation,
  createTreeInvitationRecord,
  describeBloodRelation,
  ensureCirclesForTree,
  isCurrentUnionRelation,
  isUnionRelationType,
  normalizeNullableString,
  normalizeOptionalIsoTimestamp,
  normalizeParentSetType,
  normalizeTreeGraph,
  normalizeUnionStatus,
  normalizeUnionType,
  nowIso,
  parentIdFromRelation,
  relationMirror,
} = require("../helpers");

module.exports = {
  // ── Phase 4: Find Blood Relation (BFS over the unified graph) ──────
  // Walks `graphRelations` looking only at blood-relation edges
  // (parent/child/sibling). Returns the shortest chain of graph
  // persons from `fromId` to `toId`, the edge sequence describing
  // the path, the consanguinity degree, and a Russian label
  // ("троюродная сестра", "прадедушка"). Returns null when no
  // blood path exists within `maxDepth` hops.
  //
  // Why blood-only: spouse/partner/step/adopted edges connect
  // people who share the household but not necessarily DNA. The
  // RFC restricts the "найти родство" feature to the consanguinity
  // graph by design — adding non-blood edges turns the engine
  // into "social distance" rather than "родство".
  // `adjacency` — опциональная предпостроенная карта смежности
  // (SPEED-8d). Без неё поведение не меняется (строим с нуля из db,
  // как раньше); передаётся, когда caller гоняет BFS много раз ПОДРЯД
  // для одного и того же db в рамках одного запроса
  // (filterLegacyPersonsByGraphVisibility на N кандидатов) — без
  // этого каждый вызов пересобирал бы весь граф родства заново.
  _findBloodRelationBetween(
    db,
    fromGraphPersonId,
    toGraphPersonId,
    {maxDepth = 10, adjacency: precomputedAdjacency = null} = {},
  ) {
    if (!fromGraphPersonId || !toGraphPersonId) return null;
    if (fromGraphPersonId === toGraphPersonId) {
      return {
        chain: [fromGraphPersonId],
        edges: [],
        label: "Это вы",
        degree: 0,
      };
    }
    const adjacency = precomputedAdjacency || this._buildBloodAdjacency(db);
    const fromList = adjacency.get(fromGraphPersonId);
    if (!fromList) return null;

    // BFS gives shortest path in an unweighted graph — exactly
    // what we want for "ближайшая степень родства".
    const visited = new Map([[fromGraphPersonId, null]]);
    const queue = [{node: fromGraphPersonId, depth: 0, edges: []}];
    while (queue.length) {
      const current = queue.shift();
      if (current.depth >= maxDepth) continue;
      const neighbors = adjacency.get(current.node) || [];
      for (const {neighbor, edgeType} of neighbors) {
        if (visited.has(neighbor)) continue;
        visited.set(neighbor, {parent: current.node, edgeType});
        if (neighbor === toGraphPersonId) {
          const path = [neighbor];
          const edges = [edgeType];
          let cursor = current.node;
          while (cursor !== fromGraphPersonId) {
            path.push(cursor);
            const back = visited.get(cursor);
            edges.push(back.edgeType);
            cursor = back.parent;
          }
          path.push(fromGraphPersonId);
          path.reverse();
          edges.reverse();
          const targetPerson = (db.graphPersons || []).find(
            (g) => g.id === toGraphPersonId,
          );
          const description = describeBloodRelation(
            edges,
            targetPerson?.gender,
          );
          return {
            chain: path,
            edges,
            label: description.label,
            degree: description.degree,
          };
        }
        queue.push({
          node: neighbor,
          depth: current.depth + 1,
          edges: [...current.edges, edgeType],
        });
      }
    }
    return null;
  },

  async listRelations(treeId) {
    const db = await this._read();
    const treePersons = db.persons.filter((person) => person.treeId === treeId);
    return normalizeTreeGraph(treeId, treePersons, db.relations).relations;
  },

  // SPEED-9 B: db — опциональный уже прочитанный блоб (снимок
  // requireTreeAccess). Без него — собственный _read(), как раньше.
  async getTreeGraphSnapshot(treeId, {viewerUserId = null, db: prefetchedDb = null} = {}) {
    const db = prefetchedDb || (await this._read());
    // Phase 3.1d: every person in the snapshot now flows through
    // the graph-first helper. Helper falls back to the legacy
    // record if graph data is absent, so nothing breaks during
    // the boot window or on a snapshot that hasn't been migrated.
    //
    // SPEED-10: index построен один раз для ВСЕХ person'ов дерева, а
    // person передан напрямую (уже под рукой из фильтра ниже) — было
    // O(persons_в_дереве²) global-scan через четыре .find() внутри
    // _buildPersonViewFromGraph на каждого. См. docs/speed_measurement.md.
    const tree = (db.trees || []).find((entry) => entry.id === treeId) || null;
    const graphIndex = this._buildPersonGraphIndex(db);
    let treePersons = db.persons
      .filter((person) => person.treeId === treeId)
      .map((person) =>
        this._buildPersonViewFromGraph(db, treeId, person.id, {
          index: graphIndex,
          legacyPerson: person,
        }),
      )
      .filter(Boolean);
    if (treePersons.length === 0 && !tree) {
      return null;
    }

    let snapshotRelations = db.relations;
    if (tree?.semyaId && viewerUserId) {
      const hiddenIds = await this.listHiddenPersonIdsForCaller(
        tree.semyaId,
        viewerUserId,
        db,
      );
      if (hiddenIds.length > 0) {
        const hiddenSet = new Set(hiddenIds);
        treePersons = treePersons.filter((p) => !hiddenSet.has(p.id));
        snapshotRelations = db.relations.filter(
          (rel) => !hiddenSet.has(rel.person1Id) && !hiddenSet.has(rel.person2Id),
        );
      }
    }

    const viewerPerson = viewerUserId
      ? treePersons.find((person) => person.userId === viewerUserId)
      : null;

    return buildTreeGraphSnapshot({
      treeId,
      persons: treePersons,
      relations: snapshotRelations,
      viewerPersonId: viewerPerson?.id || null,
    });
  },

  async listTreeChangeRecords(treeId, {
    personId = null,
    type = null,
    actorId = null,
  } = {}) {
    const db = await this._read();
    return db.treeChangeRecords
      .filter((record) => {
        if (record.treeId !== treeId) {
          return false;
        }
        if (personId) {
          const personIds = Array.isArray(record.personIds)
            ? record.personIds
            : [];
          if (record.personId !== personId && !personIds.includes(personId)) {
            return false;
          }
        }
        if (type && record.type !== type) {
          return false;
        }
        if (actorId && record.actorId !== actorId) {
          return false;
        }
        return true;
      })
      .sort((left, right) =>
        String(right.createdAt || "").localeCompare(String(left.createdAt || "")),
      )
      .map((record) => structuredClone(record));
  },

  async upsertRelation({
    treeId,
    person1Id,
    person2Id,
    relation1to2,
    relation2to1,
    customRelationLabel1to2 = undefined,
    customRelationLabel2to1 = undefined,
    isConfirmed = true,
    marriageDate = undefined,
    divorceDate = undefined,
    createdBy = null,
    parentSetId = undefined,
    parentSetType = "biological",
    isPrimaryParentSet = undefined,
    unionId = undefined,
    unionType = undefined,
    unionStatus = undefined,
  }) {
    const db = await this._read();
    const person1Exists = db.persons.some(
      (entry) => entry.id === person1Id && entry.treeId === treeId,
    );
    const person2Exists = db.persons.some(
      (entry) => entry.id === person2Id && entry.treeId === treeId,
    );
    if (!person1Exists || !person2Exists) {
      return null;
    }

    const resolvedRelation2to1 =
      relation2to1 || relationMirror(relation1to2);
    const normalizedRelation1to2 = String(relation1to2 || "other");
    const normalizedRelation2to1 = String(resolvedRelation2to1 || "other");
    const normalizedCustomRelationLabel1to2 =
      customRelationLabel1to2 === undefined
        ? undefined
        : normalizeNullableString(customRelationLabel1to2);
    const normalizedCustomRelationLabel2to1 =
      customRelationLabel2to1 === undefined
        ? undefined
        : normalizeNullableString(customRelationLabel2to1);
    const resolvedMarriageDate =
      marriageDate === undefined
        ? undefined
        : normalizeOptionalIsoTimestamp(marriageDate);
    const resolvedDivorceDate =
      divorceDate === undefined
        ? undefined
        : normalizeOptionalIsoTimestamp(divorceDate);
    const treeRelations = db.relations.filter((entry) => entry.treeId === treeId);
    const findRelationRecord = (leftId, rightId) => {
      return db.relations.find((entry) => {
        return (
          entry.treeId === treeId &&
          ((entry.person1Id === leftId && entry.person2Id === rightId) ||
            (entry.person1Id === rightId && entry.person2Id === leftId))
        );
      });
    };
    const getPrimaryParentRelations = (childId) => {
      return treeRelations.filter((entry) => {
        return (
          childIdFromRelation(entry) === childId &&
          entry.isPrimaryParentSet !== false
        );
      });
    };
    const getCurrentUnionPartners = (personId) => {
      const partnerIds = new Set();
      for (const relation of treeRelations) {
        if (!isCurrentUnionRelation(relation)) {
          continue;
        }
        if (relation.person1Id === personId) {
          partnerIds.add(relation.person2Id);
        } else if (relation.person2Id === personId) {
          partnerIds.add(relation.person1Id);
        }
      }
      return Array.from(partnerIds);
    };

    // Текущие СУПРУГИ/ПАРТНЁРЫ (романтический союз) — для со-родительства.
    // В отличие от getCurrentUnionPartners, исключает friend/other/single:
    // друг/прочий не должен становиться родителем ребёнка (ревью B3 FR2).
    // past/divorced уже отсечены isCurrentUnionRelation (только current).
    const getCurrentSpousePartnerIds = (personId) => {
      const partnerIds = new Set();
      for (const relation of treeRelations) {
        if (!isCurrentUnionRelation(relation)) {
          continue;
        }
        const unionType = normalizeUnionType(relation.unionType, {
          relationType: relation.relation1to2 || relation.relation2to1,
        });
        if (unionType !== "spouse" && unionType !== "partner") {
          continue;
        }
        if (relation.person1Id === personId) {
          partnerIds.add(relation.person2Id);
        } else if (relation.person2Id === personId) {
          partnerIds.add(relation.person1Id);
        }
      }
      return Array.from(partnerIds);
    };

    const normalizedParentId =
      normalizedRelation1to2 === "parent" || normalizedRelation2to1 === "child"
        ? person1Id
        : normalizedRelation1to2 === "child" || normalizedRelation2to1 === "parent"
          ? person2Id
          : null;
    const normalizedChildId =
      normalizedRelation1to2 === "parent" || normalizedRelation2to1 === "child"
        ? person2Id
        : normalizedRelation1to2 === "child" || normalizedRelation2to1 === "parent"
          ? person1Id
          : null;
    const resolvedParentSetType = normalizedParentId
      ? normalizeParentSetType(parentSetType)
      : null;
    let resolvedParentSetId =
      normalizeNullableString(parentSetId) || null;
    let resolvedIsPrimaryParentSet =
      normalizedParentId && isPrimaryParentSet !== false;

    if (normalizedParentId && normalizedChildId && !resolvedParentSetId) {
      const existingParentRelations = treeRelations.filter((entry) => {
        return (
          childIdFromRelation(entry) === normalizedChildId &&
          normalizeParentSetType(entry.parentSetType) === resolvedParentSetType
        );
      });
      const primaryGroupId =
        existingParentRelations.find((entry) => entry.isPrimaryParentSet !== false)
          ?.parentSetId || null;
      const primaryParentIds = new Set(
        existingParentRelations
          .filter((entry) => entry.parentSetId === primaryGroupId)
          .map((entry) => parentIdFromRelation(entry))
          .filter(Boolean),
      );
      if (primaryGroupId && (primaryParentIds.has(normalizedParentId) || primaryParentIds.size < 2)) {
        resolvedParentSetId = primaryGroupId;
        resolvedIsPrimaryParentSet = true;
      } else if (!primaryGroupId) {
        resolvedParentSetId =
          `ps:${treeId}:${normalizedChildId}:${resolvedParentSetType}:primary`;
        resolvedIsPrimaryParentSet = true;
      } else {
        resolvedParentSetId =
          `ps:${treeId}:${normalizedChildId}:${resolvedParentSetType}:${crypto.randomUUID()}`;
        resolvedIsPrimaryParentSet = false;
      }
    }

    const resolvedUnionType = isUnionRelationType(normalizedRelation1to2) ||
        isUnionRelationType(normalizedRelation2to1)
      ? normalizeUnionType(unionType, {
          relationType: normalizedRelation1to2,
        })
      : null;
    const resolvedUnionStatus = resolvedUnionType
      ? normalizeUnionStatus(unionStatus, {
          relationType: normalizedRelation1to2,
          divorceDate: resolvedDivorceDate,
        })
      : null;
    const resolvedUnionId = resolvedUnionType
      ? normalizeNullableString(unionId) ||
        `union:${treeId}:${buildSortedIdKey([person1Id, person2Id])}:${resolvedUnionType}:${resolvedUnionStatus}`
      : null;

    const upsertRawRelation = ({
      leftId,
      rightId,
      leftToRight,
      rightToLeft,
      trackChange = true,
      relationCreatedBy = createdBy,
      rawParentSetId = resolvedParentSetId,
      rawParentSetType = resolvedParentSetType,
      rawIsPrimaryParentSet = resolvedIsPrimaryParentSet,
      rawUnionId = resolvedUnionId,
      rawUnionType = resolvedUnionType,
      rawUnionStatus = resolvedUnionStatus,
      rawMarriageDate = resolvedMarriageDate,
      rawDivorceDate = resolvedDivorceDate,
      rawCustomRelationLabel1to2 = normalizedCustomRelationLabel1to2,
      rawCustomRelationLabel2to1 = normalizedCustomRelationLabel2to1,
    }) => {
      const existingRelation = findRelationRecord(leftId, rightId);
      const timestamp = nowIso();
      if (existingRelation) {
        const previousRelation = structuredClone(existingRelation);
        if (
          existingRelation.person1Id === leftId &&
          existingRelation.person2Id === rightId
        ) {
          existingRelation.relation1to2 = leftToRight;
          existingRelation.relation2to1 = rightToLeft;
          if (rawCustomRelationLabel1to2 !== undefined) {
            existingRelation.customRelationLabel1to2 =
              rawCustomRelationLabel1to2 || null;
          }
          if (rawCustomRelationLabel2to1 !== undefined) {
            existingRelation.customRelationLabel2to1 =
              rawCustomRelationLabel2to1 || null;
          }
        } else {
          existingRelation.relation1to2 = rightToLeft;
          existingRelation.relation2to1 = leftToRight;
          if (rawCustomRelationLabel1to2 !== undefined) {
            existingRelation.customRelationLabel2to1 =
              rawCustomRelationLabel1to2 || null;
          }
          if (rawCustomRelationLabel2to1 !== undefined) {
            existingRelation.customRelationLabel1to2 =
              rawCustomRelationLabel2to1 || null;
          }
        }
        existingRelation.isConfirmed = isConfirmed === true;
        if (rawMarriageDate !== undefined) {
          existingRelation.marriageDate = rawMarriageDate;
        }
        if (rawDivorceDate !== undefined) {
          existingRelation.divorceDate = rawDivorceDate;
        }
        existingRelation.parentSetId = rawParentSetId || null;
        existingRelation.parentSetType = rawParentSetType || null;
        existingRelation.isPrimaryParentSet =
          rawParentSetType ? rawIsPrimaryParentSet !== false : null;
        existingRelation.unionId = rawUnionId || null;
        existingRelation.unionType = rawUnionType || null;
        existingRelation.unionStatus = rawUnionStatus || null;
        existingRelation.updatedAt = timestamp;
        if (trackChange) {
          this._appendTreeChangeRecord(db, {
            treeId,
            actorId: relationCreatedBy,
            type: "relation.updated",
            personIds: [existingRelation.person1Id, existingRelation.person2Id],
            relationId: existingRelation.id,
            details: {
              before: previousRelation,
              after: structuredClone(existingRelation),
            },
          });
        }
        return existingRelation;
      }

      const relation = {
        id: crypto.randomUUID(),
        treeId,
        person1Id: leftId,
        person2Id: rightId,
        relation1to2: leftToRight,
        relation2to1: rightToLeft,
        isConfirmed: isConfirmed === true,
        createdAt: timestamp,
        updatedAt: timestamp,
        createdBy: relationCreatedBy,
        marriageDate: rawMarriageDate ?? null,
        divorceDate: rawDivorceDate ?? null,
        customRelationLabel1to2: rawCustomRelationLabel1to2 || null,
        customRelationLabel2to1: rawCustomRelationLabel2to1 || null,
        parentSetId: rawParentSetId || null,
        parentSetType: rawParentSetType || null,
        isPrimaryParentSet:
          rawParentSetType ? rawIsPrimaryParentSet !== false : null,
        unionId: rawUnionId || null,
        unionType: rawUnionType || null,
        unionStatus: rawUnionStatus || null,
      };
      db.relations.push(relation);
      treeRelations.push(relation);
      if (trackChange) {
        this._appendTreeChangeRecord(db, {
          treeId,
          actorId: relationCreatedBy,
          type: "relation.created",
          personIds: [leftId, rightId],
          relationId: relation.id,
          details: {
            after: structuredClone(relation),
          },
        });
      }
      return relation;
    };

    // B3 (ревью F3): со-родительство достраиваем ТОЛЬКО при создании НОВОГО
    // ребра parent→child. upsertRawRelation матчит по ПАРЕ и обновляет запись
    // на месте — без этой проверки повторное сохранение существующего ребра
    // (idempotent re-POST, правка дат/типа, подтверждение) ретро-линковало бы
    // супруга, появившегося ПОСЛЕ привязки к ребёнку (та же P0-коррапт).
    const mainEdgeExistedBefore = treeRelations.some(
      (entry) =>
        (entry.person1Id === person1Id && entry.person2Id === person2Id) ||
        (entry.person1Id === person2Id && entry.person2Id === person1Id),
    );

    const relation = upsertRawRelation({
      leftId: person1Id,
      rightId: person2Id,
      leftToRight: normalizedRelation1to2,
      rightToLeft: normalizedRelation2to1,
    });

    // B3 (со-родительство, УЗКО — ревью B3): достраиваем второго родителя
    // ТОЛЬКО при явном создании ребра parent→child (мы сейчас внутри его
    // создания) и ТОЛЬКО для набора ЭТОГО ребёнка. НЕ на браке, НЕ задним
    // числом, НЕ по всему дереву.
    //
    // Почему так: данные НЕ отличают «нуклеарная семья сложилась после
    // ребёнка» от «родитель женился повторно на постороннем ребёнку».
    // Прежняя широкая автоматика (срабатывание на браке + tree-wide
    // backfill существующих деревьев) из-за этого корраптила сводные
    // семьи — молча записывала отчима (и даже 'friend'-союз) биологическим
    // родителем ребёнка из ПРОШЛОГО союза. Остальные кейсы (брак после
    // привязки к ребёнку, починка старого дерева) закрываются ручным UI
    // «Добавить второго родителя» — это безопасно (явный выбор человека).
    //
    // Гарды: набор с РОВНО ОДНИМ родителем (только что добавленным); набор
    // биологический (приёмный/опекунский статус персональный, через брак не
    // распространяется); у родителя РОВНО ОДИН текущий СУПРУГ/ПАРТНЁР
    // (романтический союз; friend/other/single и past/divorced исключены —
    // FR2); партнёр ещё не родитель этого ребёнка ни в одном наборе; и ребро
    // parent→child создано ВПЕРВЫЕ (ревью F3 — не на повторном upsert'е).
    if (
      !mainEdgeExistedBefore &&
      normalizedParentId &&
      normalizedChildId &&
      resolvedParentSetId
    ) {
      const groupParentIds = new Set(
        treeRelations
          .filter((entry) => entry.parentSetId === resolvedParentSetId)
          .map((entry) => parentIdFromRelation(entry))
          .filter(Boolean),
      );
      const isBiologicalSet =
        normalizeParentSetType(resolvedParentSetType) === "biological";
      if (groupParentIds.size === 1 && isBiologicalSet) {
        const soleParentId = groupParentIds.values().next().value;
        const currentPartners = getCurrentSpousePartnerIds(soleParentId);
        if (currentPartners.length === 1) {
          const partnerId = currentPartners[0];
          // Партнёр уже родитель этого ребёнка в ЛЮБОМ наборе (в т.ч.
          // намеренно как отчим/step) — не дублируем и не перезаписываем.
          const partnerAlreadyParent = treeRelations.some(
            (entry) =>
              childIdFromRelation(entry) === normalizedChildId &&
              parentIdFromRelation(entry) === partnerId,
          );
          if (!partnerAlreadyParent) {
            upsertRawRelation({
              leftId: partnerId,
              rightId: normalizedChildId,
              leftToRight: "parent",
              rightToLeft: "child",
              trackChange: false,
              rawParentSetId: resolvedParentSetId,
              rawParentSetType: resolvedParentSetType,
              rawIsPrimaryParentSet: resolvedIsPrimaryParentSet,
              rawUnionId: null,
              rawUnionType: null,
              rawUnionStatus: null,
              rawMarriageDate: undefined,
              rawDivorceDate: undefined,
            });
          }
        }
      }
    }

    if (
      normalizedRelation1to2 === "sibling" &&
      normalizedRelation2to1 === "sibling"
    ) {
      const person1Parents = getPrimaryParentRelations(person1Id);
      const person2Parents = getPrimaryParentRelations(person2Id);
      if (person1Parents.length === 0 && person2Parents.length > 0) {
        for (const parentRelation of person2Parents) {
          const sourceParentId = parentIdFromRelation(parentRelation);
          if (!sourceParentId) {
            continue;
          }
          upsertRawRelation({
            leftId: sourceParentId,
            rightId: person1Id,
            leftToRight: "parent",
            rightToLeft: "child",
            trackChange: false,
            rawParentSetId: parentRelation.parentSetId,
            rawParentSetType: normalizeParentSetType(parentRelation.parentSetType),
            rawIsPrimaryParentSet: parentRelation.isPrimaryParentSet !== false,
            rawUnionId: null,
            rawUnionType: null,
            rawUnionStatus: null,
            rawMarriageDate: undefined,
            rawDivorceDate: undefined,
          });
        }
      } else if (person2Parents.length === 0 && person1Parents.length > 0) {
        for (const parentRelation of person1Parents) {
          const sourceParentId = parentIdFromRelation(parentRelation);
          if (!sourceParentId) {
            continue;
          }
          upsertRawRelation({
            leftId: sourceParentId,
            rightId: person2Id,
            leftToRight: "parent",
            rightToLeft: "child",
            trackChange: false,
            rawParentSetId: parentRelation.parentSetId,
            rawParentSetType: normalizeParentSetType(parentRelation.parentSetType),
            rawIsPrimaryParentSet: parentRelation.isPrimaryParentSet !== false,
            rawUnionId: null,
            rawUnionType: null,
            rawUnionStatus: null,
            rawMarriageDate: undefined,
            rawDivorceDate: undefined,
          });
        }
      }
    }

    // B3 (ревью): НЕ материализуем (не персистим) выведенные sibling-родители.
    // Прежде _materializeInferredParentLinks писал их РЕАЛЬНЫМИ biological-
    // записями на КАЖДОЙ мутации, по ВСЕМ деревьям, используя anyUnionParters
    // (любой союз — friend/ex/past), мимо всех B3-гардов: это молча записывало
    // постороннего человека биологическим родителем ребёнка из прошлого союза
    // (та же P0-коррапт сводных семей, второй путь). buildDisplayTreeRelations
    // по-прежнему ВЫВОДИТ их display-only для отрисовки — но мы их не
    // фиксируем как факт (FR4: существующие деревья не правим автоматически).
    const tree = db.trees.find((entry) => entry.id === treeId);
    if (tree) {
      tree.updatedAt = nowIso();
    }
    ensureCirclesForTree(db, treeId);
    await this._write(db);
    return structuredClone(relation);
  },

  async syncUserPhotoToTreePersons(userId, photoUrl) {
    if (!userId || !photoUrl) return;
    const normalizedUrl = String(photoUrl).trim();
    if (!normalizedUrl) return;
    const db = await this._read();
    let changed = false;
    const timestamp = nowIso();
    for (const person of db.persons) {
      if (String(person.userId || "").trim() !== userId) continue;
      const gallery = Array.isArray(person.photoGallery) ? person.photoGallery : [];
      const alreadyPrimaryInGallery = gallery.some(
        (entry) =>
          String(entry?.url || "").trim() === normalizedUrl &&
          entry?.isPrimary === true,
      );
      if (
        String(person.primaryPhotoUrl || "").trim() === normalizedUrl &&
        alreadyPrimaryInGallery
      ) {
        continue;
      }
      person.photoUrl = normalizedUrl;
      person.primaryPhotoUrl = normalizedUrl;
      const alreadyInGallery = gallery.some(
        (entry) => String(entry?.url || "").trim() === normalizedUrl,
      );
      if (!alreadyInGallery) {
        const existing = gallery.map((e) => ({...e, isPrimary: false}));
        person.photoGallery = [
          {
            id: `profile-sync:${userId}:${timestamp}`,
            url: normalizedUrl,
            thumbnailUrl: null,
            type: "image",
            contentType: null,
            caption: null,
            createdAt: timestamp,
            updatedAt: timestamp,
            isPrimary: true,
          },
          ...existing,
        ];
      } else {
        person.photoGallery = gallery.map((e) => ({
          ...e,
          isPrimary: String(e?.url || "").trim() === normalizedUrl,
          updatedAt: timestamp,
        }));
      }
      person.updatedAt = timestamp;
      changed = true;
    }
    if (changed) await this._write(db);
  },

  async deleteRelation(treeId, relationId, actorId = null) {
    const db = await this._read();
    const relation = db.relations.find(
      (entry) => entry.id === relationId && entry.treeId === treeId,
    );
    if (!relation) {
      return null;
    }

    const deletedRelation = structuredClone(relation);
    db.relations = db.relations.filter((entry) => entry.id !== relationId);
    const tree = db.trees.find((entry) => entry.id === treeId);
    if (tree) {
      tree.updatedAt = nowIso();
    }
    this._appendTreeChangeRecord(db, {
      treeId,
      actorId,
      type: "relation.deleted",
      personIds: [relation.person1Id, relation.person2Id],
      relationId,
      details: {
        before: deletedRelation,
      },
    });
    ensureCirclesForTree(db, treeId);
    await this._write(db);
    return deletedRelation;
  },

  async getDirectRelationBetween(treeId, person1Id, person2Id) {
    const db = await this._read();
    const relation = db.relations.find((entry) => {
      return (
        entry.treeId === treeId &&
        ((entry.person1Id === person1Id && entry.person2Id === person2Id) ||
          (entry.person1Id === person2Id && entry.person2Id === person1Id))
      );
    });

    if (!relation) {
      return null;
    }

    if (relation.person1Id === person1Id && relation.person2Id === person2Id) {
      return relation.relation1to2;
    }

    return relation.relation2to1;
  },

  async listOfflineProfilesByCreator(treeId, creatorId) {
    const db = await this._read();
    return db.persons
      .filter(
        (person) =>
          person.treeId === treeId &&
          person.creatorId === creatorId &&
          !person.userId,
      )
      .sort((left, right) =>
        String(left.name || "").localeCompare(String(right.name || "")),
      )
      .map((person) => structuredClone(person));
  },

  async findSpouseId(treeId, personId) {
    const db = await this._read();
    const relation = db.relations.find((entry) => {
      if (entry.treeId !== treeId) {
        return false;
      }

      const involvesPerson =
        entry.person1Id === personId || entry.person2Id === personId;
      const isSpouseRelation =
        entry.relation1to2 === "spouse" ||
        entry.relation2to1 === "spouse" ||
        entry.relation1to2 === "partner" ||
        entry.relation2to1 === "partner";

      return involvesPerson && isSpouseRelation;
    });

    if (!relation) {
      return null;
    }

    return relation.person1Id === personId ? relation.person2Id : relation.person1Id;
  },

  async createRelationRequest({
    treeId,
    senderId,
    recipientId,
    senderToRecipient,
    targetPersonId = null,
    message = null,
  }) {
    const db = await this._read();
    const tree = db.trees.find((entry) => entry.id === treeId);
    if (!tree) {
      return null;
    }

    const sender = db.users.find((entry) => entry.id === senderId);
    const recipient = db.users.find((entry) => entry.id === recipientId);
    if (!sender || !recipient) {
      return undefined;
    }

    if (senderId === recipientId) {
      return false;
    }

    if (targetPersonId) {
      const targetPerson = db.persons.find(
        (entry) => entry.id === targetPersonId && entry.treeId === treeId,
      );
      if (!targetPerson) {
        return "TARGET_PERSON_NOT_FOUND";
      }
    }

    const duplicate = db.relationRequests.find((entry) => {
      return (
        entry.treeId === treeId &&
        entry.senderId === senderId &&
        entry.recipientId === recipientId &&
        entry.status === "pending" &&
        String(entry.targetPersonId || "") === String(targetPersonId || "")
      );
    });
    if (duplicate) {
      return "DUPLICATE";
    }

    const timestamp = nowIso();
    const request = {
      id: crypto.randomUUID(),
      treeId,
      senderId,
      recipientId,
      senderToRecipient: String(senderToRecipient || "other"),
      targetPersonId: targetPersonId || null,
      offlineRelativeId: targetPersonId || null,
      createdAt: timestamp,
      updatedAt: timestamp,
      respondedAt: null,
      status: "pending",
      message: normalizeNullableString(message),
    };

    db.relationRequests.push(request);
    tree.updatedAt = nowIso();
    await this._write(db);
    return structuredClone(request);
  },

  async listRelationRequests({
    treeId = null,
    senderId = null,
    recipientId = null,
    status = null,
  } = {}) {
    const db = await this._read();
    return db.relationRequests
      .filter((entry) => {
        if (treeId && entry.treeId !== treeId) {
          return false;
        }
        if (senderId && entry.senderId !== senderId) {
          return false;
        }
        if (recipientId && entry.recipientId !== recipientId) {
          return false;
        }
        if (status && entry.status !== status) {
          return false;
        }
        return true;
      })
      .sort((left, right) =>
        String(right.createdAt || "").localeCompare(String(left.createdAt || "")),
      )
      .map((entry) => structuredClone(entry));
  },

  async findRelationRequest(requestId) {
    const db = await this._read();
    const request = db.relationRequests.find((entry) => entry.id === requestId);
    return request ? structuredClone(request) : null;
  },

  async respondToRelationRequest(requestId, status) {
    return this._mutate((db, skip) => {
      const request = (Array.isArray(db.relationRequests)
        ? db.relationRequests
        : []
      ).find((entry) => entry.id === requestId);
      if (!request) {
        return skip(null);
      }
      if (request.status !== "pending") {
        return skip({conflict: true, request: structuredClone(request)});
      }

      request.status = String(status || request.status || "pending");
      request.respondedAt = nowIso();
      request.updatedAt = request.respondedAt;
      return {conflict: false, request: structuredClone(request)};
    });
  },

  async createTreeInvitation({
    treeId,
    userId,
    addedBy = null,
    invitedByUserId = null,
    relationToTree = null,
  }) {
    const db = await this._read();
    const tree = db.trees.find((entry) => entry.id === treeId);
    if (!tree) {
      return null;
    }

    const user = db.users.find((entry) => entry.id === userId);
    if (!user) {
      return undefined;
    }

    const inviterId =
      normalizeNullableString(addedBy) ||
      normalizeNullableString(invitedByUserId) ||
      null;

    if (tree.semyaId) {
      const semya = (db.semyi || []).find(
        (entry) => entry.id === tree.semyaId && !entry.deletedAt,
      );
      if (semya) {
        const kickedRow = (db.semyaMembers || []).find(
          (m) =>
            m.semyaId === semya.id &&
            m.userId === userId &&
            Boolean(m.hiddenAt),
        );
        if (kickedRow) {
          const inviterIsOwner = Boolean(
            inviterId &&
              (db.semyaMembers || []).some(
                (m) =>
                  m.semyaId === semya.id &&
                  m.userId === inviterId &&
                  m.role === "owner" &&
                  !m.hiddenAt,
              ),
          );
          if (!inviterIsOwner) {
            return "KICKED_FROM_SEMYA";
          }
        }
      }
    }

    const isMember =
      tree.creatorId === userId ||
      (Array.isArray(tree.memberIds) && tree.memberIds.includes(userId));
    if (isMember) {
      return false;
    }

    const duplicate = db.treeInvitations.find((entry) => {
      return (
        entry.treeId === treeId &&
        entry.userId === userId &&
        entry.role === "pending"
      );
    });
    if (duplicate) {
      return "DUPLICATE";
    }

    const invitation = createTreeInvitationRecord({
      treeId,
      userId,
      addedBy: inviterId,
      relationToTree,
    });
    db.treeInvitations.push(invitation);
    tree.updatedAt = nowIso();
    await this._write(db);
    return structuredClone(invitation);
  },

  async listPendingTreeInvitations(userId) {
    const db = await this._read();
    return db.treeInvitations
      .filter((entry) => entry.userId === userId && entry.role === "pending")
      .sort((left, right) =>
        String(right.addedAt || "").localeCompare(String(left.addedAt || "")),
      )
      .map((entry) => structuredClone(entry));
  },

  async findTreeInvitation(invitationId) {
    const db = await this._read();
    const invitation = db.treeInvitations.find((entry) => entry.id === invitationId);
    return invitation ? structuredClone(invitation) : null;
  },

  async respondToTreeInvitation(invitationId, accept) {
    const db = await this._read();
    const invitationIndex = db.treeInvitations.findIndex(
      (entry) => entry.id === invitationId,
    );
    if (invitationIndex < 0) {
      return null;
    }

    const invitation = db.treeInvitations[invitationIndex];
    const tree = db.trees.find((entry) => entry.id === invitation.treeId);
    if (!tree) {
      return undefined;
    }

    if (accept) {
      tree.memberIds = Array.isArray(tree.memberIds) ? tree.memberIds : [];
      tree.members = Array.isArray(tree.members) ? tree.members : [];
      if (!tree.memberIds.includes(invitation.userId)) {
        tree.memberIds.push(invitation.userId);
      }
      if (!tree.members.includes(invitation.userId)) {
        tree.members.push(invitation.userId);
      }
      const allowUnhide =
        !tree.semyaId ||
        (Boolean(invitation.addedBy) &&
          (db.semyaMembers || []).some(
            (m) =>
              m.semyaId === tree.semyaId &&
              m.userId === invitation.addedBy &&
              m.role === "owner" &&
              !m.hiddenAt,
          ));
      this._ensureSemyaMembershipForLegacyJoin(db, tree, invitation.userId, {
        allowUnhide,
      });
      tree.updatedAt = nowIso();
    }

    db.treeInvitations.splice(invitationIndex, 1);
    await this._write(db);
    return {
      invitation: structuredClone(invitation),
      tree: structuredClone(tree),
      accepted: accept === true,
    };
  },

  _inferRelationPair(relationToMe) {
    switch (relationToMe) {
      case "mother":
      case "father":
        return {relativeToSelf: "parent", selfToRelative: "child"};
      case "sibling":
        return {relativeToSelf: "sibling", selfToRelative: "sibling"};
      case "child":
        return {relativeToSelf: "child", selfToRelative: "parent"};
      case "grandmother":
      case "grandfather":
        return {relativeToSelf: "grandparent", selfToRelative: "grandchild"};
      case "spouse":
        return {relativeToSelf: "spouse", selfToRelative: "spouse"};
      default:
        return null;
    }
  },
};
