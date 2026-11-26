const path = require("node:path");
const crypto = require("node:crypto");
const {
  GRAPH_PERSON_CANONICAL_FIELDS,
  buildGraphRelationDedupKey,
} = require("../../migration-utils");
const {
  CONNECTED_VISIBILITY_MAX_HOPS,
  IDENTITY_PROPAGATION_FIELDS,
  VALID_INCLUDE_RULE_TYPES,
} = require("../constants");
const {
  applyCanonicalProfileToPerson,
  applyIncludeRulesToBranch,
  buildCanonicalPersonView,
  buildUsersByIdMap,
  normalizeNullableString,
  nowIso,
  upsertPersonAttributesForPerson,
  valuesEqualForPropagation,
} = require("../helpers");

module.exports = {
  _propagateIdentityFields(db, sourcePerson, previousSourcePerson, actorId) {
    const identityId = normalizeNullableString(sourcePerson?.identityId);
    if (!identityId) return [];

    // Find sibling person records that share this identityId.
    // Excludes the source itself (we just updated it) and any
    // record that's somehow tagged with the identityId but lives
    // in the same tree+id (defensive — shouldn't exist after
    // _reconcilePersonIdentities, but a malformed import could).
    const linked = db.persons.filter(
      (entry) =>
        entry.identityId === identityId &&
        !(entry.treeId === sourcePerson.treeId && entry.id === sourcePerson.id),
    );
    if (linked.length === 0) return [];

    if (!Array.isArray(db.identityFieldConflicts)) {
      db.identityFieldConflicts = [];
    }

    const propagated = [];
    const fields = IDENTITY_PROPAGATION_FIELDS;
    const nowTs = nowIso();

    for (const linkedPerson of linked) {
      const previousLinked = structuredClone(linkedPerson);
      let anyChange = false;

      // Per-target snapshot of "what this propagator last wrote
      // here". First propagation populates it; subsequent passes
      // diff `current vs lastWritten` to tell apart "still our
      // value, just out-of-date" (overwrite freely) from "user
      // locally edited this between propagations" (conflict, do
      // NOT clobber). See Phase 1.3 RFC §1.3.
      if (
        !linkedPerson.lastPropagatedFields ||
        typeof linkedPerson.lastPropagatedFields !== "object"
      ) {
        linkedPerson.lastPropagatedFields = {};
      }

      for (const field of fields) {
        const sourceValue = sourcePerson[field];
        const linkedValue = linkedPerson[field];
        if (valuesEqualForPropagation(field, linkedValue, sourceValue)) {
          // Values already match — no overwrite needed. But we
          // still stamp the snapshot if absent, so a future
          // local edit on the target followed by a divergent
          // source update lands in the conflict path instead of
          // a silent overwrite (snapshotPresent would otherwise
          // stay false on this field forever).
          if (
            !Object.prototype.hasOwnProperty.call(
              linkedPerson.lastPropagatedFields,
              field,
            )
          ) {
            linkedPerson.lastPropagatedFields[field] = structuredClone(
              sourceValue,
            );
          }
          continue;
        }

        // Conflict detection only kicks in AFTER the snapshot is
        // present — before that we can't distinguish "different
        // initial values" from "local edit". `hasOwnProperty`
        // keeps a deliberately-stamped null/undefined from being
        // treated as unset.
        const snapshotPresent = Object.prototype.hasOwnProperty.call(
          linkedPerson.lastPropagatedFields,
          field,
        );
        const lastWritten = linkedPerson.lastPropagatedFields[field];
        const localEdit =
          snapshotPresent &&
          !valuesEqualForPropagation(field, linkedValue, lastWritten);
        if (localEdit) {
          // The user already resolved this exact (sourceValue,
          // targetValue) pair earlier with `keep` — honor it and
          // leave the divergence in place silently. Without this
          // mute-check, every later propagation pass would
          // resurface the same conflict the user dismissed.
          const muted = db.identityFieldConflicts.find(
            (entry) =>
              entry.resolvedAt &&
              entry.targetPersonId === linkedPerson.id &&
              entry.targetTreeId === linkedPerson.treeId &&
              entry.field === field &&
              valuesEqualForPropagation(
                field,
                entry.sourceValue,
                sourceValue,
              ) &&
              valuesEqualForPropagation(
                field,
                entry.targetValue,
                linkedValue,
              ),
          );
          if (muted) {
            continue;
          }

          // Refresh an existing open row for the same
          // (target, field) rather than appending a duplicate —
          // /conflicts stays clean if propagation runs many
          // times before the user resolves.
          const existing = db.identityFieldConflicts.find(
            (entry) =>
              !entry.resolvedAt &&
              entry.targetPersonId === linkedPerson.id &&
              entry.targetTreeId === linkedPerson.treeId &&
              entry.field === field,
          );
          if (existing) {
            existing.identityId = identityId;
            existing.sourcePersonId = sourcePerson.id;
            existing.sourceTreeId = sourcePerson.treeId;
            existing.sourceValue = structuredClone(sourceValue);
            existing.targetValue = structuredClone(linkedValue);
            existing.updatedAt = nowTs;
          } else {
            db.identityFieldConflicts.push({
              id: crypto.randomUUID(),
              identityId,
              sourcePersonId: sourcePerson.id,
              sourceTreeId: sourcePerson.treeId,
              targetPersonId: linkedPerson.id,
              targetTreeId: linkedPerson.treeId,
              field,
              sourceValue: structuredClone(sourceValue),
              targetValue: structuredClone(linkedValue),
              createdAt: nowTs,
              updatedAt: nowTs,
              resolvedAt: null,
              resolvedBy: null,
            });
          }
          continue;
        }

        linkedPerson[field] = structuredClone(sourceValue);
        linkedPerson.lastPropagatedFields[field] = structuredClone(sourceValue);
        anyChange = true;
      }
      if (!anyChange) continue;
      linkedPerson.updatedAt = nowTs;
      // Make sure the linked tree's last-modified timestamp also
      // moves so the Flutter client knows to refetch its data.
      const linkedTree = db.trees.find(
        (entry) => entry.id === linkedPerson.treeId,
      );
      if (linkedTree) {
        linkedTree.updatedAt = nowTs;
      }
      this._appendTreeChangeRecord(db, {
        treeId: linkedPerson.treeId,
        actorId,
        type: "person.updated",
        personId: linkedPerson.id,
        details: {
          before: previousLinked,
          after: structuredClone(linkedPerson),
          // Audit hint: each propagated tree's change-log shows
          // where the update came from. Crucial for debugging
          // ("why did mom's birth date change in this tree?
          // I didn't touch it — oh, came from the other tree").
          identityPropagation: {
            sourceTreeId: sourcePerson.treeId,
            sourcePersonId: sourcePerson.id,
            sourceVersionAt: sourcePerson.updatedAt,
            previousSourceUpdatedAt: previousSourcePerson?.updatedAt,
          },
        },
      });
      upsertPersonAttributesForPerson(db, linkedPerson, actorId);
      propagated.push({
        treeId: linkedPerson.treeId,
        personId: linkedPerson.id,
      });
      // graphPerson sync is handled centrally by _write →
      // _syncGraphFromLegacy; no need to mirror here.
    }
    return propagated;
  },

  // `index` — обязательные Map-индексы из _buildGraphSyncIndex
  // (SPEED-9 A). Единственный caller — _syncGraphFromLegacy; индексы
  // мутируются здесь же (push нового graphPerson/view, новый
  // legacyPersonId в existing graphPerson), чтобы следующий person в
  // ТОМ ЖЕ проходе увидел изменение — как видел бы живой `.find()`.
  _syncPersonToGraph(db, legacyPerson, index) {
    if (!legacyPerson) return;
    if (!Array.isArray(db.graphPersons)) db.graphPersons = [];
    if (!Array.isArray(db.branchPersonViews)) db.branchPersonViews = [];
    if (!Array.isArray(db.branches)) db.branches = [];

    const identityId = normalizeNullableString(legacyPerson.identityId);
    if (!identityId) {
      // After Phase 0 backfill every legacy person has an identityId.
      // Hitting this branch means we're mid-creation BEFORE
      // _reconcilePersonIdentities ran; the caller will re-sync after
      // that step.
      return;
    }

    let graphPerson = index.graphPersonsById.get(identityId);
    if (!graphPerson) {
      graphPerson = {
        id: identityId,
        createdBy: legacyPerson.creatorId || null,
        createdAt: legacyPerson.createdAt,
        updatedAt: legacyPerson.updatedAt,
        version: 0,
        deletedAt: null,
        // Phase 3.1 (DECISIONS.md ответ C): 30-day soft-delete
        // window, set on soft-delete, cleared on undo. Hard-delete
        // background job (Phase 3.6) will pick up rows whose
        // hardDeleteScheduledAt < now.
        hardDeleteScheduledAt: null,
        deletedByUserId: null,
        mergedInto: null,
        userId: legacyPerson.userId || null,
        legacyPersonIds: [legacyPerson.id],
        contactPrivacy: "owner-only",
        isPublic: false,
        source: "manual",
        // Phase 3.1 (DECISIONS.md ответ A): default privacy
        // "connected-via-blood-graph" (≤4 hops видят узел). Owner
        // override через UI поднимает до "owner-only" с
        // visibilityOverride=true.
        visibility: "connected-via-blood-graph",
        visibilityOverride: false,
      };
      for (const field of GRAPH_PERSON_CANONICAL_FIELDS) {
        graphPerson[field] = legacyPerson[field] ?? null;
      }
      db.graphPersons.push(graphPerson);
      index.graphPersonsById.set(graphPerson.id, graphPerson);
      if (!index.graphPersonsByLegacyId.has(legacyPerson.id)) {
        index.graphPersonsByLegacyId.set(legacyPerson.id, graphPerson);
      }
    } else {
      let canonicalChanged = false;
      for (const field of GRAPH_PERSON_CANONICAL_FIELDS) {
        const next = legacyPerson[field] ?? null;
        const cur = graphPerson[field] ?? null;
        // JSON-equality covers both scalar fields and the array-
        // shaped photoGallery — we don't need a deep-equal helper.
        if (JSON.stringify(next) !== JSON.stringify(cur)) {
          graphPerson[field] =
            next === null || next === undefined ? null : structuredClone(next);
          canonicalChanged = true;
        }
      }
      if (canonicalChanged) {
        graphPerson.version = (graphPerson.version || 0) + 1;
        graphPerson.updatedAt = legacyPerson.updatedAt;
      }
      if (!Array.isArray(graphPerson.legacyPersonIds)) {
        graphPerson.legacyPersonIds = [];
      }
      if (!graphPerson.legacyPersonIds.includes(legacyPerson.id)) {
        graphPerson.legacyPersonIds.push(legacyPerson.id);
      }
      if (!index.graphPersonsByLegacyId.has(legacyPerson.id)) {
        index.graphPersonsByLegacyId.set(legacyPerson.id, graphPerson);
      }
      if (!graphPerson.userId && legacyPerson.userId) {
        graphPerson.userId = legacyPerson.userId;
      }
      if (graphPerson.deletedAt) {
        // Resurrect — the legacy person came back, so does its
        // canonical node. Most likely path: a soft-delete the user
        // reverted, or a sibling person re-created on another branch.
        graphPerson.deletedAt = null;
        graphPerson.hardDeleteScheduledAt = null;
        graphPerson.deletedByUserId = null;
      }
      // Phase 3.1 lazy-fill: snapshots created before this fix won't
      // carry visibility / hardDeleteScheduledAt. Fill defaults via
      // null-coalescing — if a future admin path sets `visibility:
      // "owner-only"` directly, we MUST NOT clobber that to default.
      // `??=` triggers only on undefined/null; explicit values
      // (including `false` for visibilityOverride) survive.
      graphPerson.visibility ??= "connected-via-blood-graph";
      graphPerson.visibilityOverride ??= false;
      graphPerson.hardDeleteScheduledAt ??= null;
      graphPerson.deletedByUserId ??= null;
    }

    // Per-(branch, person) editorial slot.
    const viewKey = `${legacyPerson.treeId} ${graphPerson.id}`;
    let view = index.branchPersonViewByKey.get(viewKey);
    if (!view) {
      view = {
        id: crypto.randomUUID(),
        branchId: legacyPerson.treeId,
        personId: graphPerson.id,
        label: null,
        photoOverride: null,
        notes: legacyPerson.notes ?? null,
        familySummary: legacyPerson.familySummary ?? null,
        bio: legacyPerson.bio ?? null,
        visibility: legacyPerson.visibility ?? null,
        legacyPersonId: legacyPerson.id,
        createdAt: legacyPerson.createdAt,
        updatedAt: legacyPerson.updatedAt,
      };
      db.branchPersonViews.push(view);
      index.branchPersonViewByKey.set(viewKey, view);
    } else {
      view.notes = legacyPerson.notes ?? null;
      view.familySummary = legacyPerson.familySummary ?? null;
      view.bio = legacyPerson.bio ?? null;
      view.visibility = legacyPerson.visibility ?? null;
      view.updatedAt = legacyPerson.updatedAt;
      if (!view.legacyPersonId) view.legacyPersonId = legacyPerson.id;
    }

    // Auto-extend the branch's manual-include rule. Phase 3.2's
    // wizard will let the user pick richer rule types per branch
    // (blood-from-me, ancestors-of, etc.); for now every legacy
    // tree just becomes a manual-list branch and the rule grows
    // as people get added to the tree.
    const branch = index.branchById.get(legacyPerson.treeId);
    if (branch) {
      if (
        !branch.includeRules ||
        typeof branch.includeRules !== "object"
      ) {
        branch.includeRules = {type: "manual", manualPersonIds: []};
      }
      if (!Array.isArray(branch.includeRules.manualPersonIds)) {
        branch.includeRules.manualPersonIds = [];
      }
      if (!branch.includeRules.manualPersonIds.includes(graphPerson.id)) {
        branch.includeRules.manualPersonIds.push(graphPerson.id);
        branch.updatedAt = legacyPerson.updatedAt;
      }
    }
  },

  _markPersonDeletedInGraph(db, legacyPerson, actorUserId = null) {
    if (!legacyPerson) return;
    if (!Array.isArray(db.graphPersons)) db.graphPersons = [];
    if (!Array.isArray(db.branchPersonViews)) db.branchPersonViews = [];
    if (!Array.isArray(db.branches)) db.branches = [];

    db.branchPersonViews = db.branchPersonViews.filter(
      (v) => v.legacyPersonId !== legacyPerson.id,
    );

    const identityId = normalizeNullableString(legacyPerson.identityId);
    if (!identityId) return;

    // Drop from branch.includeRules ONLY if no other legacy person
    // on the same branch is still tied to the same identity. Several
    // legacy persons sharing an identity on one branch is unusual but
    // possible (e.g. a botched import); we hold the inclusion until
    // the LAST such legacy row is gone.
    const stillOnBranch = (db.persons || []).some(
      (p) =>
        p.id !== legacyPerson.id &&
        p.treeId === legacyPerson.treeId &&
        normalizeNullableString(p.identityId) === identityId,
    );
    if (!stillOnBranch) {
      const branch = db.branches.find((b) => b.id === legacyPerson.treeId);
      if (branch?.includeRules?.manualPersonIds) {
        branch.includeRules.manualPersonIds =
          branch.includeRules.manualPersonIds.filter(
            (gid) => gid !== identityId,
          );
        branch.updatedAt = nowIso();
      }
    }

    // Soft-delete the graphPerson when no legacy row anywhere ties
    // to its identity. Phase 3.1 (DECISIONS.md ответ C): hard-delete
    // is deferred to a 30-day window — `hardDeleteScheduledAt` is
    // set now+30d so the future Phase 3.6 background job can pick
    // up rows past their window. Undo flips both deletedAt and
    // hardDeleteScheduledAt back to null (handled in _syncPersonToGraph
    // resurrect path).
    const stillReferenced = (db.persons || []).some(
      (p) =>
        p.id !== legacyPerson.id &&
        normalizeNullableString(p.identityId) === identityId,
    );
    if (!stillReferenced) {
      const graphPerson = db.graphPersons.find((g) => g.id === identityId);
      if (graphPerson && !graphPerson.deletedAt) {
        const deletedTs = nowIso();
        graphPerson.deletedAt = deletedTs;
        const expirationDate = new Date(Date.parse(deletedTs));
        expirationDate.setUTCDate(expirationDate.getUTCDate() + 30);
        graphPerson.hardDeleteScheduledAt = expirationDate.toISOString();
        graphPerson.deletedByUserId =
          normalizeNullableString(actorUserId) || null;
      }
    }
  },

  // `index` — обязательные Map-индексы из _buildGraphSyncIndex
  // (SPEED-9 A). personsById/graphPersonsByLegacyId заменяют два
  // прежних .find() по db.persons/db.graphPersons.
  _resolveGraphPersonIdForLegacy(db, legacyPersonId, index) {
    if (!legacyPersonId) return null;
    const legacyPerson = index.personsById.get(legacyPersonId);
    if (legacyPerson) {
      const identityId = normalizeNullableString(legacyPerson.identityId);
      if (identityId) return identityId;
    }
    // Person already deleted — fall back to a stale lookup through
    // existing graph rows so callers still operating on a relation
    // mid-cleanup don't get null.
    const fromGraph = index.graphPersonsByLegacyId.get(legacyPersonId);
    return fromGraph ? fromGraph.id : null;
  },

  _syncRelationToGraph(db, legacyRelation, index) {
    if (!legacyRelation) return;
    if (!Array.isArray(db.graphRelations)) db.graphRelations = [];
    const p1g = this._resolveGraphPersonIdForLegacy(
      db,
      legacyRelation.person1Id,
      index,
    );
    const p2g = this._resolveGraphPersonIdForLegacy(
      db,
      legacyRelation.person2Id,
      index,
    );
    if (!p1g || !p2g) return;

    const dedupKey = buildGraphRelationDedupKey(p1g, p2g, legacyRelation);
    // Тот же приоритет, что и у прежнего .find(): точное совпадение
    // по legacyRelationId — раньше, дедуп по ключу — fallback (для
    // валидных данных, которые эти же функции и поддерживают,
    // legacyRelationId принадлежит не более чем одному graphRelation
    // и dedup-ключ не более чем одному graphRelation — коллизия
    // порядка между двумя РАЗНЫМИ записями не возникает).
    let graphRelation = index.graphRelationsByLegacyId.get(legacyRelation.id);
    if (!graphRelation) {
      graphRelation = index.graphRelationsByDedupKey.get(dedupKey);
    }

    const nowTs = nowIso();
    if (!graphRelation) {
      graphRelation = {
        id: legacyRelation.id,
        person1Id: p1g,
        person2Id: p2g,
        relation1to2: legacyRelation.relation1to2,
        relation2to1: legacyRelation.relation2to1,
        isConfirmed: legacyRelation.isConfirmed === true,
        createdBy: legacyRelation.createdBy || null,
        createdAt: legacyRelation.createdAt || nowTs,
        updatedAt: legacyRelation.updatedAt || nowTs,
        version: 0,
        deletedAt: null,
        marriageDate: legacyRelation.marriageDate || null,
        divorceDate: legacyRelation.divorceDate || null,
        customRelationLabel1to2:
          legacyRelation.customRelationLabel1to2 || null,
        customRelationLabel2to1:
          legacyRelation.customRelationLabel2to1 || null,
        parentSetId: legacyRelation.parentSetId || null,
        parentSetType: legacyRelation.parentSetType || null,
        isPrimaryParentSet:
          typeof legacyRelation.isPrimaryParentSet === "boolean"
            ? legacyRelation.isPrimaryParentSet
            : null,
        unionId: legacyRelation.unionId || null,
        unionType: legacyRelation.unionType || null,
        unionStatus: legacyRelation.unionStatus || null,
        legacyRelationIds: [legacyRelation.id],
        legacyTreeIds: legacyRelation.treeId ? [legacyRelation.treeId] : [],
      };
      db.graphRelations.push(graphRelation);
      index.graphRelationsByLegacyId.set(legacyRelation.id, graphRelation);
      index.graphRelationsByDedupKey.set(dedupKey, graphRelation);
      return;
    }

    // relation1to2/relation2to1 входят в dedup-ключ и МОГУТ меняться
    // ниже — если тип связи поменялся, следующая relation в этом же
    // проходе, которая должна была бы задедуплицироваться в эту же
    // graphRelation, обязана найти её по НОВОМУ ключу (раньше .find()
    // просто пересчитывал ключ заново на каждый вызов).
    const previousDedupKey = buildGraphRelationDedupKey(
      graphRelation.person1Id,
      graphRelation.person2Id,
      graphRelation,
    );

    graphRelation.relation1to2 = legacyRelation.relation1to2;
    graphRelation.relation2to1 = legacyRelation.relation2to1;
    graphRelation.isConfirmed = legacyRelation.isConfirmed === true;
    graphRelation.updatedAt = legacyRelation.updatedAt || nowTs;
    graphRelation.marriageDate = legacyRelation.marriageDate || null;
    graphRelation.divorceDate = legacyRelation.divorceDate || null;
    graphRelation.customRelationLabel1to2 =
      legacyRelation.customRelationLabel1to2 || null;
    graphRelation.customRelationLabel2to1 =
      legacyRelation.customRelationLabel2to1 || null;
    graphRelation.parentSetId = legacyRelation.parentSetId || null;
    graphRelation.parentSetType = legacyRelation.parentSetType || null;
    graphRelation.isPrimaryParentSet =
      typeof legacyRelation.isPrimaryParentSet === "boolean"
        ? legacyRelation.isPrimaryParentSet
        : null;
    graphRelation.unionId = legacyRelation.unionId || null;
    graphRelation.unionType = legacyRelation.unionType || null;
    graphRelation.unionStatus = legacyRelation.unionStatus || null;
    if (graphRelation.deletedAt) graphRelation.deletedAt = null;
    if (!Array.isArray(graphRelation.legacyRelationIds)) {
      graphRelation.legacyRelationIds = [];
    }
    if (!graphRelation.legacyRelationIds.includes(legacyRelation.id)) {
      graphRelation.legacyRelationIds.push(legacyRelation.id);
    }
    if (!Array.isArray(graphRelation.legacyTreeIds)) {
      graphRelation.legacyTreeIds = [];
    }
    if (
      legacyRelation.treeId &&
      !graphRelation.legacyTreeIds.includes(legacyRelation.treeId)
    ) {
      graphRelation.legacyTreeIds.push(legacyRelation.treeId);
    }
    graphRelation.version = (graphRelation.version || 0) + 1;

    // Индекс — на случай, если legacyRelation.id раньше указывал на
    // dedup-путь (не был в graphRelationsByLegacyId), и на случай,
    // если relation1to2/relation2to1 поменялись и dedup-ключ сдвинулся.
    index.graphRelationsByLegacyId.set(legacyRelation.id, graphRelation);
    const updatedDedupKey = buildGraphRelationDedupKey(
      graphRelation.person1Id,
      graphRelation.person2Id,
      graphRelation,
    );
    if (
      updatedDedupKey !== previousDedupKey &&
      index.graphRelationsByDedupKey.get(previousDedupKey) === graphRelation
    ) {
      index.graphRelationsByDedupKey.delete(previousDedupKey);
    }
    index.graphRelationsByDedupKey.set(updatedDedupKey, graphRelation);
  },

  // SPEED-12: db — опциональный уже прочитанный снимок (GET
  // /v1/graph/relation передаёт один и тот же readSharedSnapshot()
  // сюда и в findGraphPersonById/previewGraphPersonsByIds — раньше
  // маршрут делал 5 независимых _read() на один HTTP-запрос).
  async findBloodRelation({
    fromGraphPersonId,
    toGraphPersonId,
    maxDepth = 10,
    db: prefetchedDb = null,
  }) {
    const db = prefetchedDb || (await this.readSharedSnapshot());
    return this._findBloodRelationBetween(
      db,
      fromGraphPersonId,
      toGraphPersonId,
      {maxDepth},
    );
  },

  // Preview shape for the chain returned by `/v1/graph/relation`.
  // Only the bare minimum — name + photo + dates — so the client
  // can render a relationship-path strip without leaking editorial
  // fields from non-accessible branches.
  // SPEED-12: db — опциональный уже прочитанный снимок, см.
  // findBloodRelation выше. _userCanSeeGraphPerson read-only.
  async previewGraphPersonsByIds(
    graphPersonIds,
    {viewerUserId = null, db: prefetchedDb = null} = {},
  ) {
    const db = prefetchedDb || (await this.readSharedSnapshot());
    const ids = Array.isArray(graphPersonIds) ? graphPersonIds : [];
    const normalizedViewer = normalizeNullableString(viewerUserId);
    return ids.map((id) => {
      const graphPerson = (db.graphPersons || []).find((g) => g.id === id);
      if (!graphPerson || graphPerson.deletedAt) {
        return {
          id,
          name: null,
          gender: null,
          birthDate: null,
          deathDate: null,
          photoUrl: null,
        };
      }
      // Phase 3.2: chain hydration (BFS, /v1/graph/relation,
      // future /v1/me/extended-family) — каждый node идёт через
      // visibility gate. Hidden node возвращается с пустыми
      // canonical полями + `hidden: true`, чтобы UI знал «здесь
      // звено есть, но имя не показано». Chain shape сохраняется,
      // BFS-степень всё ещё считается — это всё, что нужно для
      // «троюродная сестра через скрытого предка».
      if (
        normalizedViewer &&
        !this._userCanSeeGraphPerson(db, graphPerson, normalizedViewer)
      ) {
        return {
          id: graphPerson.id,
          name: null,
          gender: null,
          birthDate: null,
          deathDate: null,
          photoUrl: null,
          hidden: true,
        };
      }
      return {
        id: graphPerson.id,
        name: graphPerson.name,
        gender: graphPerson.gender,
        birthDate: graphPerson.birthDate,
        deathDate: graphPerson.deathDate,
        photoUrl:
          graphPerson.primaryPhotoUrl || graphPerson.photoUrl || null,
      };
    });
  },

  // Resolve a legacy person id to its canonical graphPerson row.
  // Returns null when the legacy person doesn't exist or its
  // graphPerson has been soft-deleted. Used by route gates that
  // need to call _userCanEditGraphPerson on a (treeId, personId)
  // pair from the URL.
  // SPEED-12: prefetchedDb — опциональный уже прочитанный снимок
  // (requireGraphPersonEdit/identity-routes GET передают req.storeSnapshot
  // или readSharedSnapshot(), чтобы не читать блоб ещё раз). Read-only.
  async findGraphPersonByLegacy(legacyPersonId, prefetchedDb = null) {
    const normalizedId = normalizeNullableString(legacyPersonId);
    if (!normalizedId) return null;
    const db = prefetchedDb || (await this.readSharedSnapshot());
    const legacyPerson = (db.persons || []).find(
      (entry) => entry.id === normalizedId,
    );
    const identityId = legacyPerson
      ? normalizeNullableString(legacyPerson.identityId)
      : null;

    let graphPerson = identityId
      ? (db.graphPersons || []).find((g) => g.id === identityId)
      : null;

    if (!graphPerson) {
      // Edge case: legacy row exists but graphPerson hasn't been
      // synced yet (e.g. first read after a fresh migration). Falling
      // back to a `legacyPersonIds` reverse lookup keeps gates
      // working until the next _syncPersonToGraph pass.
      graphPerson = (db.graphPersons || []).find(
        (g) =>
          Array.isArray(g.legacyPersonIds) &&
          g.legacyPersonIds.includes(normalizedId),
      );
    }
    return graphPerson ? structuredClone(graphPerson) : null;
  },

  // SPEED-12: prefetchedDb — см. findGraphPersonByLegacy выше;
  // GET /v1/graph/relation резолвит два graphPerson подряд и хочет
  // один и тот же снимок на оба вызова вместо двух readSharedSnapshot().
  async findGraphPersonById(graphPersonId, prefetchedDb = null) {
    const normalizedId = normalizeNullableString(graphPersonId);
    if (!normalizedId) return null;
    const db = prefetchedDb || (await this.readSharedSnapshot());
    const graphPerson = (db.graphPersons || []).find(
      (entry) => entry.id === normalizedId,
    );
    return graphPerson ? structuredClone(graphPerson) : null;
  },

  async addGraphPersonGrant({
    graphPersonId,
    grantorUserId,
    granteeUserId,
    scope,
  }) {
    const normalizedScope = String(scope || "").trim();
    if (!["edit", "merge-consent", "soft-delete"].includes(normalizedScope)) {
      throw new Error("INVALID_SCOPE");
    }
    const normalizedGraphPersonId = normalizeNullableString(graphPersonId);
    const normalizedGrantor = normalizeNullableString(grantorUserId);
    const normalizedGrantee = normalizeNullableString(granteeUserId);
    if (!normalizedGraphPersonId || !normalizedGrantor || !normalizedGrantee) {
      throw new Error("INVALID_INPUT");
    }
    if (normalizedGrantor === normalizedGrantee) {
      throw new Error("SELF_GRANT");
    }
    const db = await this._read();
    const graphPerson = (db.graphPersons || []).find(
      (entry) => entry.id === normalizedGraphPersonId,
    );
    if (!graphPerson || graphPerson.deletedAt) return null;

    const owner = this._graphPersonOwnerUserId(graphPerson);
    if (owner !== normalizedGrantor) {
      throw new Error("NOT_OWNER");
    }

    if (!Array.isArray(db.graphPersonEditGrants)) {
      db.graphPersonEditGrants = [];
    }

    // Idempotency: re-issuing an active grant on the same triple
    // returns the existing row. A revoked row with the same triple
    // is left alone (audit trail) and a fresh row gets pushed.
    const activeExisting = db.graphPersonEditGrants.find(
      (entry) =>
        entry.graphPersonId === normalizedGraphPersonId &&
        entry.granteeUserId === normalizedGrantee &&
        entry.scope === normalizedScope &&
        !entry.revokedAt,
    );
    if (activeExisting) {
      return {grant: structuredClone(activeExisting), created: false};
    }

    const grant = {
      id: crypto.randomUUID(),
      graphPersonId: normalizedGraphPersonId,
      grantorUserId: normalizedGrantor,
      granteeUserId: normalizedGrantee,
      scope: normalizedScope,
      grantedAt: nowIso(),
      revokedAt: null,
      origin: "owner-grant",
    };
    db.graphPersonEditGrants.push(grant);
    await this._write(db);
    return {grant: structuredClone(grant), created: true};
  },

  async revokeGraphPersonGrant({graphPersonId, grantId, actorUserId}) {
    const normalizedGraphPersonId = normalizeNullableString(graphPersonId);
    const normalizedGrantId = normalizeNullableString(grantId);
    const normalizedActor = normalizeNullableString(actorUserId);
    if (!normalizedGraphPersonId || !normalizedGrantId || !normalizedActor) {
      return null;
    }
    const db = await this._read();
    const graphPerson = (db.graphPersons || []).find(
      (entry) => entry.id === normalizedGraphPersonId,
    );
    if (!graphPerson) return null;

    const owner = this._graphPersonOwnerUserId(graphPerson);
    if (owner !== normalizedActor) {
      throw new Error("NOT_OWNER");
    }

    if (!Array.isArray(db.graphPersonEditGrants)) {
      db.graphPersonEditGrants = [];
    }
    const grant = db.graphPersonEditGrants.find(
      (entry) =>
        entry.id === normalizedGrantId &&
        entry.graphPersonId === normalizedGraphPersonId,
    );
    if (!grant) return null;

    if (grant.revokedAt) {
      // Idempotent — already revoked, no rewrite of the timestamp.
      return structuredClone(grant);
    }
    grant.revokedAt = nowIso();
    await this._write(db);
    return structuredClone(grant);
  },

  async listGraphPersonGrants({graphPersonId, viewerUserId}) {
    const normalizedGraphPersonId = normalizeNullableString(graphPersonId);
    const normalizedViewer = normalizeNullableString(viewerUserId);
    if (!normalizedGraphPersonId || !normalizedViewer) return null;
    const db = await this._read();
    const graphPerson = (db.graphPersons || []).find(
      (entry) => entry.id === normalizedGraphPersonId,
    );
    if (!graphPerson) return null;

    const owner = this._graphPersonOwnerUserId(graphPerson);
    if (owner !== normalizedViewer) {
      throw new Error("NOT_OWNER");
    }
    return (db.graphPersonEditGrants || [])
      .filter((entry) => entry.graphPersonId === normalizedGraphPersonId)
      .map((entry) => structuredClone(entry));
  },

  // Phase 3.4-prep (Q4): edit branch.includeRules с owner-only check.
  // Used by PATCH /v1/trees/:treeId/include-rules. Отдельный store
  // entry-point чтобы UI не лазил через generic updateTree (которого
  // нет — tree updates идут через _syncTreeToBranch + create flow).
  async updateBranchIncludeRules({treeId, rules, actorUserId}) {
    const normalizedTreeId = normalizeNullableString(treeId);
    const normalizedActor = normalizeNullableString(actorUserId);
    if (!normalizedTreeId || !normalizedActor) return null;
    const db = await this._read();
    const tree = (db.trees || []).find((entry) => entry.id === normalizedTreeId);
    if (!tree) return null;
    if (tree.creatorId !== normalizedActor) {
      throw new Error("NOT_OWNER");
    }
    if (!rules || typeof rules !== "object") {
      throw new Error("INVALID_RULES");
    }
    const requestedType = String(rules.type || "").trim();
    if (!VALID_INCLUDE_RULE_TYPES.has(requestedType)) {
      throw new Error("INVALID_RULE_TYPE");
    }

    // Sync first — гарантируем что branch row существует.
    this._syncTreeToBranch(db, tree);
    const branch = (db.branches || []).find(
      (entry) => entry.id === normalizedTreeId,
    );
    if (!branch) return null;

    const changed = applyIncludeRulesToBranch(branch, rules);
    if (changed) {
      branch.updatedAt = nowIso();
      tree.updatedAt = branch.updatedAt;
      await this._write(db);
    }
    return structuredClone(branch);
  },

  // Phase 3.4-prep (Q4 warning preview): возвращает counts ДО и
  // ПОСЛЕ применения новых rules БЕЗ commit'а. Helps UX warn'нуть
  // юзера «X родственников появятся, Y исчезнут» перед apply.
  async previewBranchIncludeRules({treeId, rules, viewerUserId}) {
    const normalizedTreeId = normalizeNullableString(treeId);
    const normalizedViewer = normalizeNullableString(viewerUserId);
    if (!normalizedTreeId || !normalizedViewer) return null;
    if (!rules || typeof rules !== "object") {
      throw new Error("INVALID_RULES");
    }
    const requestedType = String(rules.type || "").trim();
    if (!VALID_INCLUDE_RULE_TYPES.has(requestedType)) {
      throw new Error("INVALID_RULE_TYPE");
    }
    const db = await this._read();
    const branch = (db.branches || []).find(
      (entry) => entry.id === normalizedTreeId,
    );
    if (!branch) return null;
    if (
      branch.ownerId !== normalizedViewer &&
      !(Array.isArray(branch.memberIds) && branch.memberIds.includes(normalizedViewer))
    ) {
      throw new Error("FORBIDDEN");
    }

    const beforeSet = this._buildBranchVisiblePersonIds(
      db,
      branch,
      normalizedViewer,
    );

    // Симулируем новый branch через deep-clone и apply (без write'а).
    const previewBranch = structuredClone(branch);
    applyIncludeRulesToBranch(previewBranch, rules);
    const afterSet = this._buildBranchVisiblePersonIds(
      db,
      previewBranch,
      normalizedViewer,
    );

    const added = [...afterSet].filter((id) => !beforeSet.has(id));
    const removed = [...beforeSet].filter((id) => !afterSet.has(id));

    return {
      addedCount: added.length,
      removedCount: removed.length,
      totalBeforeCount: beforeSet.size,
      totalAfterCount: afterSet.size,
    };
  },

  // ─── Phase 4: extended network slice ────────────────────────────
  //
  // BFS slice от self-node viewer'а через blood adjacency. Каждый
  // потенциальный target gate'ится через `_userCanSeeGraphPerson`
  // (privacy fence — Phase 3.1 invariant, не relax'ается). graphRelations
  // включаются только когда **оба** endpoints в slice — никаких
  // «public node как портал» leak'ов (DECISIONS.md 2026-05-12 Q1.A).
  //
  // ownerMap **sparse**: содержит только узлы где owner !== viewer
  // (foreign nodes). 90%+ узлов typical viewer'а — own; sparse pattern
  // экономит payload + memory на клиенте (DECISIONS.md 2026-05-12,
  // nice-to-have #1).
  //
  // Slice cap = 1000 persons (Phase 4 DECISIONS Q5.A). Если BFS hit
  // cap — truncate + `stats.capReached: true` для UX hint'а.
  //
  // maxHops clamp 2..4 на route layer'е (см. tree-routes.js); store
  // doubles down defensively (`max(2, min(4, value))`) на случай
  // прямого invocation'а с тестов.
  async getExtendedNetworkSlice({
    viewerUserId,
    treeId,
    maxHops = 4,
    includeAnonymous = true,
    branchIds = null,
    sliceCap = 1000,
  } = {}) {
    const normalizedViewer = normalizeNullableString(viewerUserId);
    const normalizedTree = normalizeNullableString(treeId);
    if (!normalizedViewer || !normalizedTree) {
      return null;
    }
    // Server-side clamp под privacy fence (Q6.A: slider 2..4).
    const fence = CONNECTED_VISIBILITY_MAX_HOPS;
    let clampedMaxHops = Number.isFinite(Number(maxHops))
      ? Math.floor(Number(maxHops))
      : fence;
    clampedMaxHops = Math.max(2, Math.min(fence, clampedMaxHops));

    const db = await this._read();
    const tree = (db.trees || []).find((t) => t.id === normalizedTree);
    if (!tree) return null;

    // Tree membership check: viewer должен быть либо creator'ом
    // либо иметь хотя бы один person'а в этом дереве (Phase 3.2
    // owner-model). Если нет — endpoint вернёт 403.
    const treePersons = (db.persons || []).filter(
      (p) => p.treeId === normalizedTree && !p.deletedAt,
    );
    const isCreator = tree.creatorId === normalizedViewer;
    const isMember = treePersons.some((p) => p.userId === normalizedViewer);
    if (!isCreator && !isMember) {
      return {error: "NOT_TREE_MEMBER"};
    }

    // BFS roots: все persons моей tree → их identityId. Так slice
    // включает «моё дерево полностью» + соседей через identity граф.
    const myIdentityIds = new Set();
    for (const person of treePersons) {
      const identityId = normalizeNullableString(person.identityId);
      if (identityId) myIdentityIds.add(identityId);
    }
    if (myIdentityIds.size === 0) {
      // Свежее дерево, viewer ещё не добавил себя — пустой slice.
      return {
        graphPersons: [],
        graphRelations: [],
        branchMembership: {},
        ownerMap: {},
        viewerSelfGraphPersonId: null,
        stats: {
          totalCount: 0,
          myCount: 0,
          extendedCount: 0,
          anonymousCount: 0,
          maxHopsReached: false,
          capReached: false,
        },
      };
    }

    // Optional branch filter: если caller передал branchIds, только
    // identity'ы из этих веток считаем «моими» (для tree roots).
    const filteredBranchIds = Array.isArray(branchIds)
      ? new Set(
          branchIds
            .map((b) => normalizeNullableString(b))
            .filter((b) => b !== null),
        )
      : null;
    // На текущей schema'е branches mirror trees 1:1; branchIds filter
    // — placeholder для post-Phase-4.1 cross-branch filtering. v1
    // ignored unless explicitly matches treeId.
    if (
      filteredBranchIds !== null &&
      filteredBranchIds.size > 0 &&
      !filteredBranchIds.has(normalizedTree)
    ) {
      return {
        graphPersons: [],
        graphRelations: [],
        branchMembership: {},
        ownerMap: {},
        viewerSelfGraphPersonId: null,
        stats: {
          totalCount: 0,
          myCount: 0,
          extendedCount: 0,
          anonymousCount: 0,
          maxHopsReached: false,
          capReached: false,
        },
      };
    }

    const effectiveSliceCap = Number.isFinite(Number(sliceCap))
      ? Math.max(1, Math.floor(Number(sliceCap)))
      : 1000;
    const adjacency = this._buildBloodAdjacency(db);
    const visited = new Map(); // graphPersonId → hop distance
    const queue = [];
    let capReached = false;
    // Cap check на initial roots — если у viewer'а tree персон больше
    // чем cap, мы должны это поймать ДО BFS expansion'а. Иначе initial
    // visited.size может превысить cap молча.
    for (const rootId of myIdentityIds) {
      if (visited.size >= effectiveSliceCap) {
        capReached = true;
        break;
      }
      visited.set(rootId, 0);
      queue.push({id: rootId, depth: 0});
    }

    let maxHopsReached = false;

    while (queue.length > 0) {
      const current = queue.shift();
      if (current.depth >= clampedMaxHops) {
        maxHopsReached = true;
        continue;
      }
      const neighbors = adjacency.get(current.id) || [];
      for (const {neighbor} of neighbors) {
        if (visited.has(neighbor)) continue;
        if (visited.size >= effectiveSliceCap) {
          capReached = true;
          break;
        }
        visited.set(neighbor, current.depth + 1);
        queue.push({id: neighbor, depth: current.depth + 1});
      }
      if (capReached) break;
    }

    // Privacy gate per-target. Apply ПОСЛЕ BFS чтобы adjacency
    // traversal остался дешёвым; gate отсеивает hidden targets как
    // финальный filter. (Альтернатива — гейтить inside BFS — даёт
    // меньше work, но edge case: viewer self-node остаётся в slice
    // даже если по какой-то причине not seen by him — defensive.)
    const allowedIds = new Set();
    const graphPersonsOut = [];
    const ownerMapOut = {};
    let anonymousCount = 0;
    let myCount = 0;

    for (const [graphPersonId, hopDistance] of visited.entries()) {
      const graphPerson = (db.graphPersons || []).find(
        (g) => g.id === graphPersonId && !g.deletedAt,
      );
      if (!graphPerson) continue;
      // Privacy fence applied per-target-node (Q1.B). Self-node viewer'а
      // всегда allowed (owner === viewer); reused gate consistent с
      // другими read paths.
      if (!this._userCanSeeGraphPerson(db, graphPerson, normalizedViewer)) {
        continue;
      }
      // Skip anonymous nodes если includeAnonymous=false.
      const owner = this._graphPersonOwnerUserId(graphPerson);
      const isAnonymous = !graphPerson.userId;
      if (isAnonymous && !includeAnonymous) continue;

      allowedIds.add(graphPersonId);
      graphPersonsOut.push({
        id: graphPerson.id,
        name: graphPerson.name || null,
        gender: graphPerson.gender || null,
        birthDate: graphPerson.birthDate || null,
        deathDate: graphPerson.deathDate || null,
        photoUrl: graphPerson.photoUrl || null,
        isAlive: graphPerson.isAlive !== false,
        hopDistance,
      });
      if (isAnonymous) anonymousCount += 1;
      if (owner === normalizedViewer) {
        myCount += 1;
      } else {
        // Sparse ownerMap: только foreign nodes.
        ownerMapOut[graphPerson.id] = {
          userId: owner,
          displayName: null, // hydrate'ится ниже
          photoUrl: null,
        };
      }
    }

    // Hydrate owner displayNames + photo (только для foreign nodes).
    const foreignOwnerIds = new Set();
    for (const entry of Object.values(ownerMapOut)) {
      if (entry.userId) foreignOwnerIds.add(entry.userId);
    }
    for (const ownerUserId of foreignOwnerIds) {
      const user = (db.users || []).find((u) => u.id === ownerUserId);
      if (!user) continue;
      const profile = user.profile || {};
      for (const entry of Object.values(ownerMapOut)) {
        if (entry.userId === ownerUserId) {
          entry.displayName = profile.displayName || user.email || null;
          entry.photoUrl = profile.photoUrl || null;
        }
      }
    }

    // graphRelations: только когда оба endpoints in allowed set.
    const graphRelationsOut = [];
    for (const relation of db.graphRelations || []) {
      if (!relation || relation.deletedAt) continue;
      if (
        allowedIds.has(relation.person1Id) &&
        allowedIds.has(relation.person2Id)
      ) {
        graphRelationsOut.push({
          id: relation.id,
          person1Id: relation.person1Id,
          person2Id: relation.person2Id,
          relation1to2: relation.relation1to2,
          relation2to1: relation.relation2to1,
        });
      }
    }

    // branchMembership: для каждого graphPersonId — список trees, где
    // он представлен через persons.identityId. Это даёт UI'ю signal
    // «этот узел также есть в ветке X».
    const branchMembershipOut = {};
    for (const graphPersonId of allowedIds) {
      const branches = new Set();
      for (const person of db.persons || []) {
        if (
          person.identityId === graphPersonId &&
          !person.deletedAt &&
          person.treeId
        ) {
          branches.add(person.treeId);
        }
      }
      if (branches.size > 0) {
        branchMembershipOut[graphPersonId] = Array.from(branches);
      }
    }

    // Phase 4 chunk 4a: viewer self-node id для UI lazy-fetch
    // relation-to-me (через /v1/graph/relation). Single deterministic
    // value — слой DTO не делает client-side filter through
    // graphPersons. May be null если viewer не имеет claimed
    // identity (edge case — anonymous tester либо account без
    // self-node ещё не создан).
    const viewerSelfGraphPersonId =
        this._selfGraphPersonIdForUser(db, normalizedViewer);

    return {
      graphPersons: graphPersonsOut,
      graphRelations: graphRelationsOut,
      branchMembership: branchMembershipOut,
      ownerMap: ownerMapOut,
      viewerSelfGraphPersonId,
      stats: {
        totalCount: graphPersonsOut.length,
        myCount,
        extendedCount: graphPersonsOut.length - myCount,
        anonymousCount,
        maxHopsReached,
        capReached,
      },
    };
  },

  async setGraphPersonVisibility({
    graphPersonId,
    visibility,
    actorUserId,
  }) {
    if (
      !["owner-only", "connected-via-blood-graph", "public"].includes(
        String(visibility || "").trim(),
      )
    ) {
      throw new Error("INVALID_VISIBILITY");
    }
    const normalizedGraphPersonId = normalizeNullableString(graphPersonId);
    const normalizedActor = normalizeNullableString(actorUserId);
    if (!normalizedGraphPersonId || !normalizedActor) return null;
    const db = await this._read();
    const graphPerson = (db.graphPersons || []).find(
      (entry) => entry.id === normalizedGraphPersonId,
    );
    if (!graphPerson || graphPerson.deletedAt) return null;

    const owner = this._graphPersonOwnerUserId(graphPerson);
    if (owner !== normalizedActor) {
      throw new Error("NOT_OWNER");
    }
    graphPerson.visibility = visibility;
    graphPerson.visibilityOverride = true;
    graphPerson.updatedAt = nowIso();
    await this._write(db);
    return structuredClone(graphPerson);
  },

  async clearGraphPersonVisibilityOverride({
    graphPersonId,
    actorUserId,
  }) {
    const normalizedGraphPersonId = normalizeNullableString(graphPersonId);
    const normalizedActor = normalizeNullableString(actorUserId);
    if (!normalizedGraphPersonId || !normalizedActor) return null;
    const db = await this._read();
    const graphPerson = (db.graphPersons || []).find(
      (entry) => entry.id === normalizedGraphPersonId,
    );
    if (!graphPerson || graphPerson.deletedAt) return null;

    const owner = this._graphPersonOwnerUserId(graphPerson);
    if (owner !== normalizedActor) {
      throw new Error("NOT_OWNER");
    }
    graphPerson.visibilityOverride = false;
    graphPerson.updatedAt = nowIso();
    await this._write(db);
    return structuredClone(graphPerson);
  },

  // Bulk visibility check: для list-cross-tree-results (search,
  // identity-suggestions). Фильтрует persons по
  // `_userCanSeeGraphPerson`. Persons без graphPerson (mid-sync
  // edge case) — оставляем (fail-open до следующего sync'а).
  // Возвращает только legacy persons, которые viewer может видеть.
  // Один _read() на whole list — без N+1 на каждый person (caller
  // может передать уже прочитанный db третьим аргументом, чтобы не
  // читать блоб ещё раз, если он и так только что читал его сам —
  // см. identity-suggestions хендлер в tree-routes.js).
  //
  // SPEED-8d: сам _userCanSeeGraphPerson для visibility="connected-
  // via-blood-graph" (дефолт) резолвит viewer'а через
  // _selfGraphPersonIdForUser (линейный проход по users+graphPersons)
  // и гоняет BFS с ПЕРЕСБОРКОЙ adjacency из db.graphRelations с нуля
  // на каждый вызов. viewer и db внутри ОДНОГО вызова этого фильтра
  // не меняются, а количество вызовов — до `limit` (identity-
  // suggestions) целей, так что раньше на каждый ответ endpoint'а
  // могла приходиться до `limit` полных пересборок графа родства.
  // Здесь оба считаются один раз (adjacency — лениво, только если
  // хотя бы один person реально дошёл до blood-graph ветки) и
  // передаются через `context` дальше без изменения результата
  // _userCanSeeGraphPerson — она документированно детерминирована
  // по (db, graphPerson, viewerUserId) и не зависит от identity
  // объекта adjacency-мапы, лишь бы содержимое было тем же.
  async filterLegacyPersonsByGraphVisibility(
    persons,
    viewerUserId,
    prefetchedDb = null,
  ) {
    if (!Array.isArray(persons) || persons.length === 0) return [];
    const normalizedViewer = normalizeNullableString(viewerUserId);
    if (!normalizedViewer) return [];
    const db = prefetchedDb || (await this._read());
    const graphPersonsByIdentity = new Map(
      (db.graphPersons || []).map((entry) => [entry.id, entry]),
    );
    const graphPersonsByLegacy = new Map();
    for (const entry of db.graphPersons || []) {
      for (const legacyId of entry.legacyPersonIds || []) {
        graphPersonsByLegacy.set(legacyId, entry);
      }
    }
    const store = this;
    const viewerSelfGraphPersonId = store._selfGraphPersonIdForUser(
      db,
      normalizedViewer,
    );
    // Ленивая сборка: если ни один person не доходит до blood-graph
    // ветки (все — owner/granted/public/pre-sync), adjacency вообще
    // не строится, как и раньше.
    let cachedAdjacency = null;
    const visibilityContext = {
      viewerSelfGraphPersonId,
      get adjacency() {
        if (!cachedAdjacency) {
          cachedAdjacency = store._buildBloodAdjacency(db);
        }
        return cachedAdjacency;
      },
    };
    return persons.filter((person) => {
      const identityId = normalizeNullableString(person?.identityId);
      const graphPerson =
        (identityId && graphPersonsByIdentity.get(identityId)) ||
        graphPersonsByLegacy.get(person?.id) ||
        null;
      if (!graphPerson) return true; // Pre-sync — fail-open.
      return this._userCanSeeGraphPerson(
        db,
        graphPerson,
        normalizedViewer,
        visibilityContext,
      );
    });
  },

  _markRelationDeletedInGraph(db, legacyRelation) {
    if (!legacyRelation) return;
    if (!Array.isArray(db.graphRelations)) db.graphRelations = [];
    const target = db.graphRelations.find(
      (entry) =>
        Array.isArray(entry.legacyRelationIds) &&
        entry.legacyRelationIds.includes(legacyRelation.id),
    );
    if (!target) return;
    target.legacyRelationIds = target.legacyRelationIds.filter(
      (rid) => rid !== legacyRelation.id,
    );
    if (legacyRelation.treeId) {
      const stillUsed = (db.relations || []).some(
        (r) =>
          target.legacyRelationIds.includes(r.id) &&
          r.treeId === legacyRelation.treeId,
      );
      if (!stillUsed) {
        target.legacyTreeIds = target.legacyTreeIds.filter(
          (tid) => tid !== legacyRelation.treeId,
        );
      }
    }
    if (target.legacyRelationIds.length === 0 && !target.deletedAt) {
      target.deletedAt = nowIso();
    }
  },

  // ответ A.1: visibility derive — поле в БД не пересчитывается
  // background job'ом. Auto-public для исторических узлов
  // (isAlive=false + birthYear < now-100) применяется в read path
  // если owner НЕ выставил `visibilityOverride: true`. Stored
  // `visibility` остаётся «connected-via-blood-graph» — старение
  // само переключает effective без backfill.
  _effectiveGraphPersonVisibility(graphPerson) {
    if (!graphPerson) return "owner-only";
    const stored = graphPerson.visibility || "connected-via-blood-graph";
    if (graphPerson.visibilityOverride === true) {
      return stored;
    }
    if (graphPerson.isAlive === false) {
      const birthYear = parseInt(
        String(graphPerson.birthDate || "").slice(0, 4),
        10,
      );
      if (Number.isFinite(birthYear)) {
        const yearsAgo = new Date().getFullYear() - birthYear;
        if (yearsAgo > 100) return "public";
      }
    }
    return stored;
  },

  // ответ D: вычисление актуального set'а graphPerson IDs внутри
  // branch'а с учётом includeRules.type. Phase 3.1 поддерживает
  // все четыре типа; UI wizard для не-manual типов прилетит в
  // Phase 6.4. До тех пор миграция оставляет все existing
  // branches с type=manual (см. buildBranchFromTree).
  _buildBranchVisiblePersonIds(db, branch, viewerUserId) {
    if (!branch) return new Set();
    const rules = branch.includeRules || {
      type: "manual",
      manualPersonIds: [],
    };
    const maxHops = Number.isFinite(rules.maxHops) ? rules.maxHops : 5;

    switch (rules.type) {
      case "manual":
        return new Set(
          (rules.manualPersonIds || []).filter(Boolean),
        );

      case "blood-from-me": {
        const selfId = this._selfGraphPersonIdForUser(db, viewerUserId);
        if (!selfId) return new Set();
        return this._collectBloodPersonsWithinHops(db, selfId, maxHops);
      }

      case "descendants-of": {
        const anchor = normalizeNullableString(rules.anchorPersonId);
        if (!anchor) return new Set();
        return this._collectDescendantsWithinHops(db, anchor, maxHops);
      }

      case "ancestors-of": {
        const anchor = normalizeNullableString(rules.anchorPersonId);
        if (!anchor) return new Set();
        return this._collectAncestorsWithinHops(db, anchor, maxHops);
      }

      default:
        // Unknown type — empty set, не падать. Логируем для
        // observability на случай если UI отправил мусорный rules
        // (i18n strings, опечатки, etc.).
        return new Set();
    }
  },

  // BFS наружу по обеим сторонам кровных рёбер (parent/child/sibling)
  // — нужно для blood-from-me: попадают и предки, и потомки, и
  // siblings и их потомки в пределах N hops. То есть всё, что в
  // твоём кровном круге не дальше maxHops.
  _collectBloodPersonsWithinHops(db, anchorGraphPersonId, maxHops) {
    const result = new Set();
    if (!anchorGraphPersonId) return result;
    const adjacency = this._buildBloodAdjacency(db);
    if (!adjacency.has(anchorGraphPersonId)) {
      // Узел изолированный (нет blood-edges) — branch включает только сам якорь.
      result.add(anchorGraphPersonId);
      return result;
    }
    const queue = [{node: anchorGraphPersonId, depth: 0}];
    const visited = new Set([anchorGraphPersonId]);
    result.add(anchorGraphPersonId);
    while (queue.length) {
      const current = queue.shift();
      if (current.depth >= maxHops) continue;
      const neighbors = adjacency.get(current.node) || [];
      for (const {neighbor} of neighbors) {
        if (visited.has(neighbor)) continue;
        visited.add(neighbor);
        result.add(neighbor);
        queue.push({node: neighbor, depth: current.depth + 1});
      }
    }
    return result;
  },

  _collectDescendantsWithinHops(db, anchorGraphPersonId, maxHops) {
    return this._collectDirectionalWithinHops(
      db,
      anchorGraphPersonId,
      maxHops,
      "child",
    );
  },

  _collectAncestorsWithinHops(db, anchorGraphPersonId, maxHops) {
    return this._collectDirectionalWithinHops(
      db,
      anchorGraphPersonId,
      maxHops,
      "parent",
    );
  },

  // Direction-aware BFS: walks edges where the TARGET role matches
  // direction. _buildBloodAdjacency пишет
  //   adjacency[child] += {neighbor: parent, edgeType: "parent"}
  //   adjacency[parent] += {neighbor: child, edgeType: "child"}
  // direction="child" значит идём вниз по потомкам; "parent" —
  // вверх по предкам. siblings игнорируются (включаем только
  // прямую вертикаль для descendants-of/ancestors-of).
  _collectDirectionalWithinHops(db, anchorGraphPersonId, maxHops, direction) {
    const result = new Set();
    if (!anchorGraphPersonId) return result;
    const adjacency = this._buildBloodAdjacency(db);
    if (!adjacency.has(anchorGraphPersonId)) {
      result.add(anchorGraphPersonId);
      return result;
    }
    const queue = [{node: anchorGraphPersonId, depth: 0}];
    const visited = new Set([anchorGraphPersonId]);
    result.add(anchorGraphPersonId);
    while (queue.length) {
      const current = queue.shift();
      if (current.depth >= maxHops) continue;
      const neighbors = adjacency.get(current.node) || [];
      for (const {neighbor, edgeType} of neighbors) {
        if (edgeType !== direction) continue;
        if (visited.has(neighbor)) continue;
        visited.add(neighbor);
        result.add(neighbor);
        queue.push({node: neighbor, depth: current.depth + 1});
      }
    }
    return result;
  },

  // ── Phase 3.1d: graph-first read helper ─────────────────────────────
  // Resolves a legacy-shape person record by reading from
  // graphPersons + branchPersonViews + tree first, falling back
  // to the legacy persons collection when graph data is missing
  // (e.g. row hasn't been synced yet, or migration hasn't run).
  // Returns null if no data exists for this (branch, personId).
  //
  // The shape returned is the same as the legacy `db.persons[i]`
  // record so callers and downstream `mapPerson` see no change in
  // payload structure. The values, however, come from the graph
  // side — once we drop the legacy collection in 3.4 this helper
  // simply stops touching `db.persons`.
  // SPEED-10: `index` — опциональные карты, построенные ОДИН раз вызывающим
  // циклом (см. _buildPersonGraphIndex), вместо четырёх .find() по
  // db.persons/db.graphPersons/db.branchPersonViews/db.users на КАЖДОГО
  // person. getTreeGraphSnapshot зовёт это для всех person'ов дерева —
  // было O(persons_в_дереве × (persons+graphPersons+views+users)_всего),
  // см. docs/speed_measurement.md SPEED-10. `legacyPerson` — сам person,
  // если он у вызывающего уже под рукой (снимает и первый .find()).
  // Без `index`/`legacyPerson` — прежнее поведение (findPerson/
  // findPersonByUserId/getPersonDossier — одиночные вызовы, строить
  // индекс ради одного person незачем).
  _buildPersonViewFromGraph(db, branchId, legacyPersonId, {
    index = null,
    legacyPerson: prefetchedLegacyPerson = null,
  } = {}) {
    const legacyPerson = prefetchedLegacyPerson || (db.persons || []).find(
      (p) => p.id === legacyPersonId && p.treeId === branchId,
    );
    if (!legacyPerson) return null;

    const identityId = normalizeNullableString(legacyPerson.identityId);
    const graphPerson = identityId
      ? (index
          ? index.graphPersonsById.get(identityId) || null
          : (db.graphPersons || []).find(
              (g) => g.id === identityId && !g.deletedAt,
            ))
      : null;

    if (!graphPerson) {
      // No graph row yet — happens during the boot window before
      // _syncGraphFromLegacy fires, or for a person whose
      // identityId backfill hasn't completed. Falling back to the
      // legacy record keeps the API working in those edge cases.
      return buildCanonicalPersonView(db, legacyPerson, {
        usersById: index?.usersById,
      });
    }

    const view = index
      ? index.branchPersonViewByKey.get(`${branchId} ${graphPerson.id}`) || null
      : (db.branchPersonViews || []).find(
          (v) => v.branchId === branchId && v.personId === graphPerson.id,
        );

    // Compose: legacy record as the base (carries firstName /
    // lastName / middleName / details / lastPropagatedFields and
    // any other field the graph layer doesn't own yet), then
    // override the canonical fields from graphPerson and the
    // editorial fields from branchPersonView. Output is shape-
    // compatible with the legacy `mapPerson` consumer.
    const personView = structuredClone(legacyPerson);
    for (const field of GRAPH_PERSON_CANONICAL_FIELDS) {
      if (graphPerson[field] !== undefined) {
        personView[field] =
          graphPerson[field] === null
            ? null
            : structuredClone(graphPerson[field]);
      }
    }
    if (view) {
      personView.notes = view.notes ?? personView.notes ?? null;
      personView.familySummary =
        view.familySummary ?? personView.familySummary ?? null;
      personView.bio = view.bio ?? personView.bio ?? null;
      if (view.visibility !== undefined && view.visibility !== null) {
        personView.visibility = view.visibility;
      }
    }

    if (!personView.userId) return personView;
    const user = index
      ? index.usersById.get(String(personView.userId || "").trim()) || null
      : db.users.find((entry) => entry.id === personView.userId);
    if (!user?.profile) return personView;
    return applyCanonicalProfileToPerson(personView, user.profile);
  },

  // SPEED-10: строит один раз карты для _buildPersonViewFromGraph,
  // переиспользуемые на ВСЕХ person'ов одного вызова (сейчас — только
  // getTreeGraphSnapshot). Те же соглашения, что и в _buildGraphSyncIndex
  // (SPEED-9 A): id предполагаются уникальными, forEach-порядок = порядок
  // массива, "последний выигрывает" при дублях — как и обычный .find()
  // на непротиворечивых данных.
  _buildPersonGraphIndex(db) {
    const graphPersonsById = new Map();
    for (const graphPerson of db.graphPersons || []) {
      if (graphPerson.deletedAt) continue;
      graphPersonsById.set(graphPerson.id, graphPerson);
    }
    const branchPersonViewByKey = new Map();
    for (const view of db.branchPersonViews || []) {
      branchPersonViewByKey.set(`${view.branchId} ${view.personId}`, view);
    }
    return {
      graphPersonsById,
      branchPersonViewByKey,
      usersById: buildUsersByIdMap(db),
    };
  },

  // SPEED-9 A: строит все индексы ОДИН раз на весь проход
  // `_syncGraphFromLegacy`, вместо того чтобы `_syncPersonToGraph`/
  // `_syncRelationToGraph`/`_resolveGraphPersonIdForLegacy` делали
  // линейный `.find()` по db.graphPersons/db.branchPersonViews/
  // db.branches/db.persons/db.graphRelations на КАЖДОГО person и
  // КАЖДУЮ relation (было O(persons×graphPersons +
  // relations×(graphRelations+persons)) ≈ O(N²) над ГЛОБАЛЬНЫМИ
  // коллекциями — измерено docs/speed_measurement.md SPEED-9: 136 мс
  // при 1240 persons, 560 мс при 2480).
  //
  // Карты МУТИРУЮТСЯ теми же helper'ами по ходу прохода (push нового
  // graphPerson/view/graphRelation, обновление dedup-ключа при смене
  // типа отношения) — это обязательно, чтобы воспроизвести поведение
  // живого `.find()` по массиву: он видел бы изменения, сделанные
  // РАНЕЕ в этом же проходе (пример — тест "collapses identity-
  // linked legacy persons across two trees onto one graphPerson":
  // второй person с тем же identityId должен найти graphPerson,
  // созданный первым в ЭТОМ ЖЕ вызове _syncGraphFromLegacy).
  //
  // Вызывается ПОСЛЕ цикла _syncTreeToBranch (тот может создавать
  // новые db.branches) и ДО циклов по persons/relations — иначе
  // branchById не увидел бы свежесозданные branch-строки.
  _buildGraphSyncIndex(db) {
    const graphPersonsById = new Map();
    const graphPersonsByLegacyId = new Map();
    for (const graphPerson of db.graphPersons) {
      graphPersonsById.set(graphPerson.id, graphPerson);
      if (Array.isArray(graphPerson.legacyPersonIds)) {
        for (const legacyId of graphPerson.legacyPersonIds) {
          // Первое совпадение по порядку массива — как и вернул бы
          // .find(); при корректных (не повреждённых) данных
          // legacyPersonId принадлежит не более чем одному graphPerson.
          if (!graphPersonsByLegacyId.has(legacyId)) {
            graphPersonsByLegacyId.set(legacyId, graphPerson);
          }
        }
      }
    }

    const branchPersonViewByKey = new Map();
    for (const view of db.branchPersonViews) {
      branchPersonViewByKey.set(`${view.branchId} ${view.personId}`, view);
    }

    const branchById = new Map();
    for (const branch of db.branches) {
      branchById.set(branch.id, branch);
    }

    const personsById = new Map();
    for (const person of db.persons || []) {
      personsById.set(person.id, person);
    }

    const graphRelationsByLegacyId = new Map();
    const graphRelationsByDedupKey = new Map();
    for (const graphRelation of db.graphRelations) {
      if (Array.isArray(graphRelation.legacyRelationIds)) {
        for (const legacyId of graphRelation.legacyRelationIds) {
          if (!graphRelationsByLegacyId.has(legacyId)) {
            graphRelationsByLegacyId.set(legacyId, graphRelation);
          }
        }
      }
      const key = buildGraphRelationDedupKey(
        graphRelation.person1Id,
        graphRelation.person2Id,
        graphRelation,
      );
      if (!graphRelationsByDedupKey.has(key)) {
        graphRelationsByDedupKey.set(key, graphRelation);
      }
    }

    return {
      graphPersonsById,
      graphPersonsByLegacyId,
      branchPersonViewByKey,
      branchById,
      personsById,
      graphRelationsByLegacyId,
      graphRelationsByDedupKey,
    };
  },

  // Aggregate full-scan helper. Walks the legacy collections and
  // brings the graph side into sync with whatever's currently
  // there. Idempotent — every step is a no-op when its row is
  // already up-to-date — so calling it on every _read and every
  // _write keeps the graph eventually consistent without wiring
  // a sync into each of the 30+ write paths individually.
  //
  // SPEED-9 A (05.09.2026): раньше комментарий здесь утверждал
  // O(persons + relations + trees) — это было НЕВЕРНО: три вложенных
  // .find()-скана без индексов внутри _syncPersonToGraph/
  // _syncRelationToGraph/_resolveGraphPersonIdForLegacy давали
  // фактически O(N²) (см. docs/speed_measurement.md SPEED-9, замер
  // bench_sync_scaling.js: 1240→2480 persons даёт ×4.1 времени —
  // учебный квадрат). _buildGraphSyncIndex выше строит Map-индексы
  // один раз на проход, так что теперь это ДЕЙСТВИТЕЛЬНО
  // O(persons + relations + trees). Комментарий про Phase 3.4
  // остаётся: CURRENT-PHASE.md явно держит graph-слой (не
  // депрекейтить), так что эта функция никуда не денется.
  _syncGraphFromLegacy(db) {
    if (!db || typeof db !== "object") return;
    if (!Array.isArray(db.graphPersons)) db.graphPersons = [];
    if (!Array.isArray(db.branchPersonViews)) db.branchPersonViews = [];
    if (!Array.isArray(db.branches)) db.branches = [];
    if (!Array.isArray(db.graphRelations)) db.graphRelations = [];

    const trees = Array.isArray(db.trees) ? db.trees : [];
    const persons = Array.isArray(db.persons) ? db.persons : [];
    const relations = Array.isArray(db.relations) ? db.relations : [];

    for (const tree of trees) {
      this._syncTreeToBranch(db, tree);
    }

    // Индексы строятся ПОСЛЕ _syncTreeToBranch (мог создать новые
    // db.branches) и ДО persons/relations — см. _buildGraphSyncIndex.
    const graphSyncIndex = this._buildGraphSyncIndex(db);

    const liveLegacyPersonIds = new Set();
    const liveIdentityIds = new Set();
    for (const person of persons) {
      liveLegacyPersonIds.add(person.id);
      const identityId = normalizeNullableString(person.identityId);
      if (identityId) liveIdentityIds.add(identityId);
      this._syncPersonToGraph(db, person, graphSyncIndex);
    }

    const liveRelationIds = new Set();
    for (const relation of relations) {
      liveRelationIds.add(relation.id);
      this._syncRelationToGraph(db, relation, graphSyncIndex);
    }

    // Drop branchPersonViews whose legacyPersonId is gone — the
    // person was hard-deleted before the graph caught up, so the
    // view is meaningless. (Soft-deletes leave the legacy person
    // in place; we don't reach this branch in that path.)
    db.branchPersonViews = db.branchPersonViews.filter(
      (view) =>
        !view.legacyPersonId || liveLegacyPersonIds.has(view.legacyPersonId),
    );

    // Soft-delete graphPersons whose identityId is no longer
    // referenced by any legacy person. (And clear deletedAt for
    // ones that came back — handled in _syncPersonToGraph already,
    // but a fresh data file might land in a state where the legacy
    // row exists but the graphPerson is stamped deleted.)
    for (const graphPerson of db.graphPersons) {
      if (liveIdentityIds.has(graphPerson.id)) {
        if (graphPerson.deletedAt) graphPerson.deletedAt = null;
        continue;
      }
      if (!graphPerson.deletedAt) {
        graphPerson.deletedAt = nowIso();
      }
    }

    // SPEED-16: trim graphPerson.legacyPersonIds — drop ids that no
    // longer exist in db.persons. Mirrors the legacyRelationIds trim
    // below. `_syncPersonToGraph` only ever PUSHES into this array
    // (dedup on push, never prunes on delete), so on prod a single
    // long-lived graphPerson with `userId` set had accumulated 1364
    // dead legacy ids — 53 KB on one row, none resolving to a live
    // person, and periodically "resurrected" by smoke traffic
    // (re-created legacy person under the same identity) only to be
    // re-tombstoned, which is why the hard-delete job never got a
    // stable target to sweep it.
    //
    // Unlike legacyRelationIds this intentionally does NOT gate
    // deletedAt/version/updatedAt or any owner-set field (visibility,
    // visibilityOverride, contactPrivacy, isPublic, mergedInto) — the
    // identityId-keyed soft-delete/restore loop just above already
    // owns the lifecycle decision (a graphPerson stays alive as long
    // as ANY live person still carries its identityId == graphPerson.id,
    // independent of how many legacy records ever fed it — see the
    // "20 records on prod" multi-branch identity case). This trim is
    // pure storage hygiene on the array, nothing else.
    //
    // Consumers checked — none depend on a DEAD legacy id surviving:
    //   - `_buildGraphSyncIndex`'s graphPersonsByLegacyId map (feeds
    //     `_resolveGraphPersonIdForLegacy` for relation resolution)
    //     is built at the TOP of THIS SAME pass, before this trim
    //     runs — every lookup this pass needed already happened
    //     against the untrimmed array. Trimming now only shapes what
    //     the NEXT pass's index sees.
    //   - `findGraphPersonByLegacy`'s legacyPersonIds fallback only
    //     fires for an id that resolved to a row in db.persons (i.e.
    //     still live) — a dead id can never reach that branch.
    //   - `filterLegacyPersonsByGraphVisibility`'s graphPersonsByLegacy
    //     map (~14109) is only ever queried with ids drawn from the
    //     (live) `persons` argument it's given.
    for (const graphPerson of db.graphPersons) {
      if (!Array.isArray(graphPerson.legacyPersonIds)) {
        graphPerson.legacyPersonIds = [];
      }
      const filtered = graphPerson.legacyPersonIds.filter((pid) =>
        liveLegacyPersonIds.has(pid),
      );
      if (filtered.length !== graphPerson.legacyPersonIds.length) {
        graphPerson.legacyPersonIds = filtered;
      }
    }

    // Trim branch.includeRules.manualPersonIds: if a legacy person
    // got deleted, its identity is no longer on this branch and the
    // inclusion list shouldn't claim it. Mirrors the per-branch
    // membership rebuild in _markPersonDeletedInGraph but for the
    // full-scan path.
    const identitiesByBranch = new Map();
    for (const person of persons) {
      const identityId = normalizeNullableString(person.identityId);
      if (!identityId) continue;
      if (!identitiesByBranch.has(person.treeId)) {
        identitiesByBranch.set(person.treeId, new Set());
      }
      identitiesByBranch.get(person.treeId).add(identityId);
    }
    for (const branch of db.branches) {
      const ids = branch.includeRules?.manualPersonIds;
      if (!Array.isArray(ids)) continue;
      const allowed = identitiesByBranch.get(branch.id);
      if (!allowed) {
        // Branch with no live persons — drop all manual entries.
        if (ids.length > 0) {
          branch.includeRules.manualPersonIds = [];
        }
        continue;
      }
      branch.includeRules.manualPersonIds = ids.filter((gid) =>
        allowed.has(gid),
      );
    }

    // Trim graphRelation.legacyRelationIds: drop ones that no
    // longer exist in db.relations. If the list goes empty, mark
    // the canonical edge deleted.
    for (const graphRelation of db.graphRelations) {
      if (!Array.isArray(graphRelation.legacyRelationIds)) {
        graphRelation.legacyRelationIds = [];
      }
      const filtered = graphRelation.legacyRelationIds.filter((rid) =>
        liveRelationIds.has(rid),
      );
      if (filtered.length !== graphRelation.legacyRelationIds.length) {
        graphRelation.legacyRelationIds = filtered;
      }
      if (filtered.length === 0 && !graphRelation.deletedAt) {
        graphRelation.deletedAt = nowIso();
      } else if (filtered.length > 0 && graphRelation.deletedAt) {
        // Re-attached after delete — clear the tombstone.
        graphRelation.deletedAt = null;
      }
    }

    // Drop branches whose legacy tree was deleted entirely.
    const liveTreeIds = new Set(trees.map((t) => t.id));
    for (const branch of db.branches) {
      if (!liveTreeIds.has(branch.id) && !branch.deletedAt) {
        branch.deletedAt = nowIso();
      }
    }
  },
};
