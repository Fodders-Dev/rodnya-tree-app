function registerAdminRoutes(
  app,
  {store, requireAuth, requireAdmin, buildStatusPayload, mapReport},
) {
  app.get("/v1/admin/runtime", requireAuth, async (req, res) => {
    if (!requireAdmin(req, res)) {
      return;
    }

    res.json(
      buildStatusPayload("ok", {
        requestId: req.requestId,
      }),
    );
  });

  app.get("/v1/admin/reports", requireAuth, async (req, res) => {
    if (!requireAdmin(req, res)) {
      return;
    }

    const status = String(req.query?.status || "").trim() || null;
    const reports = await store.listReports({status});
    const mappedReports = [];
    for (const report of reports) {
      const reporter = await store.findUserById(report.reporterId);
      mappedReports.push(mapReport(report, reporter));
    }

    res.json({
      reports: mappedReports,
    });
  });

  app.post("/v1/admin/reports/:reportId/resolve", requireAuth, async (req, res) => {
    if (!requireAdmin(req, res)) {
      return;
    }

    const status = String(req.body?.status || "resolved").trim() || "resolved";
    const report = await store.resolveReport({
      reportId: req.params.reportId,
      resolvedBy: req.auth.user.id,
      status,
      resolutionNote: req.body?.resolutionNote,
    });
    if (!report) {
      res.status(404).json({message: "Жалоба не найдена"});
      return;
    }

    const reporter = await store.findUserById(report.reporterId);
    res.json({
      report: mapReport(report, reporter),
    });
  });
}

module.exports = {
  registerAdminRoutes,
};
