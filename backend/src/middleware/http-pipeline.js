const express = require("express");
const cors = require("cors");
const crypto = require("node:crypto");

function registerCoreHttpMiddleware(app, {config, normalizedRuntimeInfo = {}}) {
  app.set("trust proxy", 1);
  app.use(cors({origin: config.corsOrigin}));
  app.use((req, res, next) => {
    const forwardedRequestId = String(req.get("x-request-id") || "").trim();
    req.requestId = forwardedRequestId || crypto.randomUUID();
    req.startedAt = Date.now();
    res.setHeader("x-request-id", req.requestId);
    // Authed API responses must never be cached by any upstream (proxy / CDN /
    // browser). Without this, a shared cache could serve a stale GET /v1/chats
    // — the suspected cause of a group's updated photoUrl missing from the chat
    // list while the details endpoint returned it fresh. The backend serves
    // only dynamic, per-user API data, so a blanket no-store is safe.
    res.setHeader("Cache-Control", "no-store");
    if (normalizedRuntimeInfo?.releaseLabel) {
      res.setHeader("x-rodnya-release", normalizedRuntimeInfo.releaseLabel);
    }
    next();
  });
  app.use((req, res, next) => {
    const pathName = req.path || req.originalUrl || "/";
    if (pathName === "/health" || pathName === "/ready") {
      next();
      return;
    }

    const startedAt = Date.now();
    res.on("finish", () => {
      const durationMs = Date.now() - startedAt;
      // S1: медленные ответы (>500ms) — warning с маршрутом, чтобы
      // «быстро» было числом, а не мнением.
      const isSlow = durationMs >= 500;
      const shouldLog =
        res.statusCode >= 400 ||
        req.method !== "GET" ||
        isSlow ||
        pathName.startsWith("/v1/admin/");
      if (!shouldLog) {
        return;
      }

      const payload = JSON.stringify({
        requestId: req.requestId,
        method: req.method,
        path: pathName,
        statusCode: res.statusCode,
        durationMs,
        ip: req.ip,
      });
      if (isSlow) {
        console.warn("[backend] slow-request", payload);
        return;
      }
      console.log("[backend] request", payload);
    });
    next();
  });
}

function registerJsonBodyParser(app) {
  // Some legacy/mobile clients still send JSON literal `null` on bodyless POSTs
  // such as like/view/read actions. Accept it and let handlers validate fields.
  // Бинарный PUT /v1/media/object обязан пройти МИМО json-парсера при
  // любом Content-Type: иначе application/json-тело перехватывается здесь
  // (до requireAuth и rate-limit), а SyntaxError улетает в глобальный
  // error-handler — 500 без токена и «Пустое тело» для легитимного клиента
  // с кривым заголовком (ревью бинарной загрузки, P1).
  const jsonBodyParser = express.json({limit: "50mb", strict: false});
  app.use((req, res, next) => {
    if (req.path.replace(/\/+$/, "") === "/v1/media/object") {
      next();
      return;
    }
    jsonBodyParser(req, res, next);
  });
}

function registerHealthRoutes(app, {buildStatusPayload, ensureReady}) {
  app.get("/health", async (req, res) => {
    res.json(
      buildStatusPayload("ok", {
        requestId: req.requestId,
      }),
    );
  });

  app.get("/ready", async (req, res) => {
    try {
      await ensureReady();
      res.json(
        buildStatusPayload("ready", {
          requestId: req.requestId,
        }),
      );
    } catch (error) {
      res.status(503).json({
        ...buildStatusPayload("not_ready", {
          requestId: req.requestId,
          ready: false,
          message: "Backend storage paths are not accessible",
        }),
        errorCode: String(error?.code || error?.message || "NOT_READY"),
      });
    }
  });

}

function registerErrorHandlers(app, {runtimeInfo = null}) {
  app.use((req, res) => {
    res.status(404).json({
      message: "Route not found",
      requestId: req.requestId,
    });
  });

  app.use((error, req, res, next) => {
    if (typeof runtimeInfo?.captureError === "function") {
      runtimeInfo.captureError("express", error, {
        requestId: req.requestId,
        method: req.method,
        path: req.originalUrl || req.path || "/",
      });
    }
    console.error(
      "[backend] unhandled-error",
      JSON.stringify({
        requestId: req.requestId,
        method: req.method,
        path: req.originalUrl || req.path || "/",
        name: error?.name || "Error",
        message: error?.message || String(error),
        stack: error?.stack || null,
      }),
    );

    if (res.headersSent) {
      next(error);
      return;
    }

    res.status(500).json({
      message: "Внутренняя ошибка backend",
      requestId: req.requestId,
    });
  });

}

module.exports = {
  registerCoreHttpMiddleware,
  registerJsonBodyParser,
  registerHealthRoutes,
  registerErrorHandlers,
};
