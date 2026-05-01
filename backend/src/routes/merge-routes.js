function registerMergeRoutes(app, {store, requireAuth}) {
  app.get("/v1/merge-proposals/pending", requireAuth, async (req, res) => {
    const requestedLimit = Number(req.query.limit || 50);
    const proposals = await store.listPendingMergeProposalsForUser(
      req.auth.user.id,
      {
        limit: Number.isFinite(requestedLimit) ? requestedLimit : 50,
      },
    );
    res.json({proposals});
  });

  app.post(
    "/v1/merge-proposals/:proposalId/review",
    requireAuth,
    async (req, res) => {
      const reviewed = await store.reviewMergeProposal({
        proposalId: req.params.proposalId,
        reviewerUserId: req.auth.user.id,
        decision: req.body?.decision,
        reason: req.body?.reason,
      });
      if (reviewed === null) {
        res.status(404).json({message: "Предложение не найдено"});
        return;
      }
      if (reviewed === false) {
        res.status(403).json({message: "Нет доступа к этому предложению"});
        return;
      }
      res.json({proposal: reviewed});
    },
  );
}

module.exports = {
  registerMergeRoutes,
};
