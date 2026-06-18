const {enforceTextLimit} = require("../input-guards");

function sanitizeDiagnosticValue(value, depth = 0) {
  if (depth > 6) {
    return "[depth-limit]";
  }
  if (value === null || value === undefined) {
    return null;
  }
  if (typeof value === "string") {
    return value.length > 8000 ? `${value.slice(0, 8000)}…` : value;
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return value;
  }
  if (Array.isArray(value)) {
    return value
      .slice(0, 500)
      .map((entry) => sanitizeDiagnosticValue(entry, depth + 1));
  }
  if (typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value)
        .slice(0, 200)
        .map(([key, entry]) => [
          String(key).slice(0, 120),
          sanitizeDiagnosticValue(entry, depth + 1),
        ]),
    );
  }
  return String(value);
}

function registerDiagnosticsRoutes(app, {store, requireAuth, logger = console}) {
  app.post("/v1/diagnostics/client-events", requireAuth, async (req, res) => {
    const typeGuard = enforceTextLimit(req.body?.type, {
      max: 80,
      allowEmpty: false,
      allowMultiline: false,
      fieldName: "type",
    });
    if (!typeGuard.ok) {
      res.status(typeGuard.status).json({message: typeGuard.message});
      return;
    }

    const messageGuard = enforceTextLimit(req.body?.message, {
      max: 1000,
      allowEmpty: true,
      allowMultiline: true,
      fieldName: "message",
    });
    if (!messageGuard.ok) {
      res.status(messageGuard.status).json({message: messageGuard.message});
      return;
    }

    const event = await store.createClientDiagnostic({
      userId: req.auth.user.id,
      sessionId: req.auth.session?.id || null,
      type: typeGuard.value,
      message: messageGuard.value,
      platform: sanitizeDiagnosticValue(req.body?.platform),
      appVersion: sanitizeDiagnosticValue(req.body?.appVersion),
      context: sanitizeDiagnosticValue(req.body?.context || {}),
      error: sanitizeDiagnosticValue(req.body?.error),
      stackTrace: sanitizeDiagnosticValue(req.body?.stackTrace),
    });

    logger.warn?.("[client-diagnostic]", {
      id: event.id,
      userId: event.userId,
      type: event.type,
      message: event.message,
    });

    res.status(202).json({eventId: event.id});
  });
}

module.exports = {
  registerDiagnosticsRoutes,
};
