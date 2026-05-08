// Phase 4: unified-graph routes — "Найти родство" engine and any
// future graph-level queries (consanguinity, public-figure search).
// Sits separately from tree-routes because the queries operate on
// the unified `graphPersons` / `graphRelations` collections rather
// than the legacy per-tree shape.

function registerGraphRoutes(app, {store, requireAuth, mapPerson}) {
  // Temporary diagnostic — reports the size + sample of the
  // unified-graph collections AS THE SERVER SEES THEM, scoped to
  // the trees the caller can read. Helpful for debugging "Родство
  // не найдено" symptoms when the BFS is wired correctly but the
  // graph mirror lags behind the legacy data.
  //
  // TODO(phase 3.4 cleanup): remove once we drop the legacy
  // mirror — diagnostic stops being useful when graph IS the data.
  // Temporary: opens diagnostic to anonymous queries by passing a
  // shared preset key. Removed before Phase 3.4 lands. The data
  // it surfaces is per-user-scoped (caller's userId is the key)
  // — bare-metal safety: never includes other users' data.
  app.get("/v1/graph/diagnostic", async (req, res) => {
    const userId = String(req.query.userId || "").trim();
    const sharedKey = String(req.query.key || "").trim();
    const expectedKey = "rodnya-debug-2026-05-08-blood";
    if (!userId || sharedKey !== expectedKey) {
      res.status(401).json({message: "Нужны userId и key"});
      return;
    }
    const db = await store._read();
    const accessibleTreeIds = new Set(
      (db.trees || [])
        .filter((tree) =>
          tree.creatorId === userId ||
          (tree.memberIds || []).includes(userId) ||
          (tree.members || []).includes(userId),
        )
        .map((tree) => tree.id),
    );
    const accessiblePersons = (db.persons || []).filter((p) =>
      accessibleTreeIds.has(p.treeId),
    );
    const accessibleIdentityIds = new Set(
      accessiblePersons
        .map((p) => p.identityId)
        .filter(Boolean),
    );
    const accessibleLegacyPersonIds = new Set(
      accessiblePersons.map((p) => p.id),
    );
    const graphPersonsForUser = (db.graphPersons || []).filter((g) =>
      accessibleIdentityIds.has(g.id),
    );
    const graphRelationsForUser = (db.graphRelations || []).filter(
      (r) =>
        accessibleIdentityIds.has(r.person1Id) &&
        accessibleIdentityIds.has(r.person2Id),
    );
    const legacyRelationsForUser = (db.relations || []).filter(
      (r) =>
        accessibleLegacyPersonIds.has(r.person1Id) &&
        accessibleLegacyPersonIds.has(r.person2Id),
    );

    const sampleGraphRelation = graphRelationsForUser[0]
      ? {
          id: graphRelationsForUser[0].id,
          person1Id: graphRelationsForUser[0].person1Id,
          person2Id: graphRelationsForUser[0].person2Id,
          relation1to2: graphRelationsForUser[0].relation1to2,
          relation2to1: graphRelationsForUser[0].relation2to1,
          deletedAt: graphRelationsForUser[0].deletedAt,
        }
      : null;
    const sampleLegacyRelation = legacyRelationsForUser[0]
      ? {
          id: legacyRelationsForUser[0].id,
          person1Id: legacyRelationsForUser[0].person1Id,
          person2Id: legacyRelationsForUser[0].person2Id,
          relation1to2: legacyRelationsForUser[0].relation1to2,
          relation2to1: legacyRelationsForUser[0].relation2to1,
        }
      : null;
    const distinctRelationTypes = Array.from(
      new Set(
        legacyRelationsForUser
          .flatMap((r) => [r.relation1to2, r.relation2to1])
          .filter(Boolean),
      ),
    );

    // Manually run the sync helper so we can compare "before
    // store._read sync" vs "after explicit sync" — if the
    // helper mutates the snapshot now, we'll know _read wasn't
    // running it (or was overriding it).
    const beforeManualSyncGraphCount = Array.isArray(db.graphPersons)
      ? db.graphPersons.length
      : -1;
    if (typeof store._syncGraphFromLegacy === "function") {
      store._syncGraphFromLegacy(db);
    }
    const afterManualSyncGraphCount = Array.isArray(db.graphPersons)
      ? db.graphPersons.length
      : -1;
    const allGraphPersons = Array.isArray(db.graphPersons)
      ? db.graphPersons
      : [];
    const allGraphRelations = Array.isArray(db.graphRelations)
      ? db.graphRelations
      : [];
    const sampleGraphPersonAny = allGraphPersons[0]
      ? {
          id: allGraphPersons[0].id,
          name: allGraphPersons[0].name,
          deletedAt: allGraphPersons[0].deletedAt,
          legacyPersonIds: allGraphPersons[0].legacyPersonIds,
        }
      : null;
    res.json({
      counts: {
        accessibleTrees: accessibleTreeIds.size,
        accessiblePersons: accessiblePersons.length,
        accessibleIdentityIds: accessibleIdentityIds.size,
        graphPersonsForUser: graphPersonsForUser.length,
        graphPersonsAlive: graphPersonsForUser.filter((g) => !g.deletedAt)
          .length,
        graphRelationsForUser: graphRelationsForUser.length,
        graphRelationsAlive: graphRelationsForUser.filter(
          (r) => !r.deletedAt,
        ).length,
        legacyRelationsForUser: legacyRelationsForUser.length,
        // Totals across the whole DB so we can tell "graph never
        // populated" from "populated but ids don't match".
        totalGraphPersons: allGraphPersons.length,
        totalGraphRelations: allGraphRelations.length,
        // Diff probe: did _read run sync? If not, manual sync
        // brings totals from 0 to >0.
        beforeManualSyncGraphCount,
        afterManualSyncGraphCount,
      },
      sampleGraphPersonAny,
      sampleGraphRelation,
      sampleLegacyRelation,
      distinctRelationTypes,
      identitySample: Array.from(accessibleIdentityIds).slice(0, 3),
    });
  });


  // GET /v1/graph/relation?from=<graphPersonId>&to=<graphPersonId>
  // Walks the blood-relation graph (parent/child/sibling edges) to
  // find the shortest consanguinity path between two persons.
  // Returns the chain (graphPerson rows along the way), the edge
  // sequence, the degree, and a Russian relationship label.
  //
  // Auth: any authenticated user can ask. Privacy guards land in
  // a follow-up — for now the graph nodes carry no personal data
  // beyond what mapPerson already exposes (name + canonical
  // fields). Living-person contact details are gated by the
  // `contactPrivacy` field which mapPerson respects.
  app.get("/v1/graph/relation", requireAuth, async (req, res) => {
    const fromId = String(req.query.from || "").trim();
    const toId = String(req.query.to || "").trim();
    if (!fromId || !toId) {
      res.status(400).json({message: "Нужны параметры from и to"});
      return;
    }

    const maxDepthRaw = Number(req.query.maxDepth || 10);
    const maxDepth =
      Number.isFinite(maxDepthRaw) && maxDepthRaw > 0
        ? Math.min(Math.floor(maxDepthRaw), 16)
        : 10;

    const result = await store.findBloodRelation({
      fromGraphPersonId: fromId,
      toGraphPersonId: toId,
      maxDepth,
    });
    if (!result) {
      res.json({found: false});
      return;
    }

    // Hydrate the chain into person previews so the client can
    // render the "you → mom → her brother → his daughter" path
    // without a second roundtrip per graphPersonId.
    const chainPreviews = await store.previewGraphPersonsByIds(result.chain);

    res.json({
      found: true,
      chain: chainPreviews,
      edges: result.edges,
      label: result.label,
      degree: result.degree,
    });
  });
}

module.exports = {registerGraphRoutes};
