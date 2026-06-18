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

  app.get("/v1/admin/client-diagnostics", requireAuth, async (req, res) => {
    if (!requireAdmin(req, res)) {
      return;
    }

    const diagnostics = await store.listClientDiagnostics({
      type: req.query?.type,
      userId: req.query?.userId,
      limit: req.query?.limit,
    });

    res.json({diagnostics});
  });

  // Whitelist of statuses an admin can write into a report. Anything
  // outside this set is rejected so the field can't be used as a free-
  // form text payload — moderators sometimes copy-paste 64KB triage
  // notes into the wrong field, and downstream UI keys hard off the
  // status string.
  const allowedReportStatuses = new Set([
    "resolved",
    "dismissed",
    "investigating",
  ]);

  app.post("/v1/admin/reports/:reportId/resolve", requireAuth, async (req, res) => {
    if (!requireAdmin(req, res)) {
      return;
    }

    const rawStatus = String(req.body?.status || "resolved").trim();
    const status = rawStatus.length === 0 ? "resolved" : rawStatus;
    if (!allowedReportStatuses.has(status)) {
      res.status(400).json({
        message:
            `Недопустимый status. Разрешены: ${[...allowedReportStatuses].join(", ")}`,
      });
      return;
    }

    // Cap resolution note to keep DB row size bounded. 4 KB is plenty
    // for any human-written triage paragraph; anything beyond is
    // either accidental paste of a chat history or deliberate abuse.
    const rawNote = req.body?.resolutionNote;
    let resolutionNote = null;
    if (rawNote != null) {
      const noteString = String(rawNote);
      if (noteString.length > 4096) {
        res.status(400).json({
          message: "resolutionNote слишком длинный (максимум 4096 символов).",
        });
        return;
      }
      // Strip ASCII control chars (CR/LF/NUL/...) so the note can't
      // break log lines or downstream tooling that splits on \n.
      // eslint-disable-next-line no-control-regex
      resolutionNote = noteString.replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, "");
    }

    const report = await store.resolveReport({
      reportId: req.params.reportId,
      resolvedBy: req.auth.user.id,
      status,
      resolutionNote,
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
