// Phase 4: unified-graph routes — "Найти родство" engine and any
// future graph-level queries (consanguinity, public-figure search).
// Sits separately from tree-routes because the queries operate on
// the unified `graphPersons` / `graphRelations` collections rather
// than the legacy per-tree shape.

function registerGraphRoutes(app, {store, requireAuth, mapPerson}) {
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
