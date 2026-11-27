function registerRateLimitMiddleware(app, {config, rateLimitBackend}) {
  const resolvedRateLimitBackend = rateLimitBackend;
  app.use(async (req, res, next) => {
    const policy = (() => {
      const pathName = req.path || "/";
      // Express матчит роуты нестрого: /v1/media/object/ попадает в тот же
      // хендлер, но строгие === в политике его не видели — запрос уезжал в
      // щедрый mutation-бакет мимо upload-лимита (ревью, P2).
      const normalizedPathName =
        pathName.replace(/\/+/g, "/").replace(/\/+$/, "") || "/";
      if (normalizedPathName === "/health" || normalizedPathName === "/ready") {
        return null;
      }
      if (normalizedPathName.startsWith("/media/")) {
        return null;
      }
      if (normalizedPathName.startsWith("/storage/")) {
        return null;
      }
      if (
        normalizedPathName === "/v1/auth/login" ||
        normalizedPathName === "/v1/auth/register" ||
        normalizedPathName === "/v1/auth/password-reset" ||
        normalizedPathName === "/v1/auth/password-reset/request" ||
        normalizedPathName === "/v1/auth/password-reset/confirm" ||
        normalizedPathName === "/v1/invitations/pending/process" ||
        normalizedPathName === "/v1/auth/refresh" ||
        normalizedPathName === "/v1/auth/qr/start" ||
        normalizedPathName === "/v1/auth/qr/approve" ||
        normalizedPathName === "/v1/auth/qr/poll" ||
        // OAuth code-exchange endpoints — same brute-force surface as
        // /login. An attacker who steals a one-time auth code via a
        // sniffed SMS or phishing link can replay-attempt at the
        // exchange route without ever hitting /login, so they need to
        // sit in the same strict bucket.
        normalizedPathName === "/v1/auth/google" ||
        normalizedPathName === "/v1/auth/vk/exchange" ||
        normalizedPathName === "/v1/auth/telegram/exchange" ||
        normalizedPathName === "/v1/auth/max/exchange" ||
        normalizedPathName === "/v1/auth/change-password" ||
        normalizedPathName.startsWith("/v1/auth/providers/")
      ) {
        return {bucket: "auth", limit: config.authRateLimitMax};
      }
      if (
        normalizedPathName === "/v1/media/upload" ||
        normalizedPathName === "/v1/media/object"
      ) {
        return {bucket: "upload", limit: config.uploadRateLimitMax};
      }
      if (
        normalizedPathName === "/v1/reports" ||
        normalizedPathName.startsWith("/v1/blocks")
      ) {
        return {bucket: "safety", limit: config.safetyRateLimitMax};
      }
      if (/^\/story\/[^/]+$/.test(normalizedPathName)) {
        return {
          bucket: "public_story_read",
          limit: config.publicStoryReadRateLimitMax || 30,
        };
      }
      if (/^\/v1\/invitation\/[^/]+$/.test(normalizedPathName)) {
        return {
          bucket: "public_invitation_read",
          limit: config.publicStoryReadRateLimitMax || 30,
        };
      }
      if (/^\/story\/[^/]+\/(media|answer)$/.test(normalizedPathName)) {
        return {
          bucket: "public_story_write",
          limit: config.publicStoryWriteRateLimitMax || 12,
        };
      }
      if (!["GET", "HEAD", "OPTIONS"].includes(req.method)) {
        return {bucket: "mutation", limit: config.mutationRateLimitMax};
      }
      return {bucket: "default", limit: config.defaultRateLimitMax};
    })();

    if (!policy || !Number.isFinite(policy.limit) || policy.limit <= 0) {
      next();
      return;
    }

    const now = Date.now();
    const windowMs = Number.isFinite(config.rateLimitWindowMs) &&
        config.rateLimitWindowMs > 0
      ? config.rateLimitWindowMs
      : 60_000;
    const actorId = String(req.ip || "unknown").trim() || "unknown";
    const key = `${policy.bucket}:${actorId}`;

    let activeBucket;
    try {
      activeBucket = await resolvedRateLimitBackend.incr(key, windowMs);
    } catch (error) {
      // Backend hiccup (e.g. Redis blip in a future scaled-out
      // deploy) — fail OPEN so we don't 503 every request when the
      // limiter is unavailable. The trade-off is documented:
      // attacker can briefly burst during the outage, which is a
      // better failure mode than denying every legitimate request.
      console.error(
        "[backend] rate-limit backend failure — failing open",
        JSON.stringify({requestId: req.requestId, message: error?.message}),
      );
      next();
      return;
    }

    // Periodic GC sweep — only the in-memory backend exposes the
    // sweepExpired hook. Redis-backed buckets self-expire via TTL.
    if (
      typeof resolvedRateLimitBackend.sweepExpired === "function" &&
      Math.random() < 0.01 &&
      resolvedRateLimitBackend.size > 2000
    ) {
      resolvedRateLimitBackend.sweepExpired(now);
    }

    res.setHeader("x-ratelimit-limit", String(policy.limit));
    res.setHeader(
      "x-ratelimit-remaining",
      String(Math.max(0, policy.limit - activeBucket.count)),
    );
    res.setHeader(
      "x-ratelimit-reset",
      String(Math.ceil(activeBucket.resetAt / 1000)),
    );

    if (activeBucket.count > policy.limit) {
      const retryAfterSeconds = Math.max(
        1,
        Math.ceil((activeBucket.resetAt - now) / 1000),
      );
      res.setHeader("retry-after", String(retryAfterSeconds));
      res.status(429).json({
        message: "Слишком много запросов. Повторите попытку позже.",
        requestId: req.requestId,
      });
      return;
    }

    next();
  });
}

module.exports = {
  registerRateLimitMiddleware,
};
