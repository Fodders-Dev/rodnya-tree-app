const crypto = require("node:crypto");

function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function buildTelegramIdentityFromAuth(authData) {
  return {
    provider: "telegram",
    providerUserId: String(authData.id),
    displayName: [
      authData.first_name,
      authData.last_name,
    ].map((value) => String(value || "").trim()).filter(Boolean).join(" "),
    metadata: {
      username: authData.username || null,
      photoUrl: authData.photo_url || null,
      authDate: authData.auth_date || null,
    },
  };
}

function renderTelegramLoginPage({botUsername, authUrl}) {
  return `<!DOCTYPE html>
<html lang="ru">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Вход через Telegram</title>
    <style>
      body {
        margin: 0;
        min-height: 100vh;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        background: linear-gradient(180deg, #eaf5f2 0%, #f8faf8 100%);
        display: grid;
        place-items: center;
        color: #163229;
      }
      .card {
        width: min(92vw, 420px);
        background: rgba(255,255,255,0.92);
        border-radius: 28px;
        padding: 28px;
        box-shadow: 0 20px 60px rgba(16, 61, 51, 0.16);
      }
      h1 { margin: 0 0 12px; font-size: 28px; }
      p { margin: 0 0 20px; line-height: 1.5; color: #446158; }
    </style>
  </head>
  <body>
    <div class="card">
      <h1>Вход через Telegram</h1>
      <p>Подтвердите аккаунт в Telegram. Если Telegram уже привязан к Родне, вход завершится автоматически.</p>
      <script async src="https://telegram.org/js/telegram-widget.js?22"
        data-telegram-login="${escapeHtml(botUsername)}"
        data-size="large"
        data-radius="18"
        data-auth-url="${escapeHtml(authUrl)}"
        data-request-access="write">
      </script>
    </div>
  </body>
</html>`;
}

function registerTelegramAuthRoutes(
  app,
  {
    store,
    config,
    requireAuth,
    resolvePublicApiUrl,
    resolvePublicAppUrl,
    authResponse,
  },
) {
  function verifyTelegramLoginPayload(query) {
    if (!config.telegramLoginEnabled) {
      throw new Error("TELEGRAM_LOGIN_DISABLED");
    }

    const hash = String(query?.hash || "").trim();
    const authDate = Number(query?.auth_date || 0);
    const telegramUserId = String(query?.id || "").trim();
    if (!hash || !telegramUserId || !Number.isFinite(authDate) || authDate <= 0) {
      throw new Error("INVALID_TELEGRAM_PAYLOAD");
    }

    const nowSeconds = Math.floor(Date.now() / 1000);
    if (Math.abs(nowSeconds - authDate) > 10 * 60) {
      throw new Error("TELEGRAM_AUTH_EXPIRED");
    }

    const signedFields = new Set([
      "auth_date",
      "first_name",
      "id",
      "last_name",
      "photo_url",
      "username",
    ]);
    const dataCheckString = Object.entries(query || {})
      .filter(([key, value]) =>
        signedFields.has(key) &&
        value !== undefined &&
        value !== null &&
        String(value).trim() !== "",
      )
      .sort(([leftKey], [rightKey]) => leftKey.localeCompare(rightKey))
      .map(([key, value]) => `${key}=${value}`)
      .join("\n");

    const secretKey = crypto
      .createHash("sha256")
      .update(config.telegramBotToken, "utf8")
      .digest();
    const computedHash = crypto
      .createHmac("sha256", secretKey)
      .update(dataCheckString, "utf8")
      .digest("hex");

    const providedHashBuffer = Buffer.from(hash, "hex");
    const computedHashBuffer = Buffer.from(computedHash, "hex");
    if (
      providedHashBuffer.length !== computedHashBuffer.length ||
      !crypto.timingSafeEqual(providedHashBuffer, computedHashBuffer)
    ) {
      throw new Error("INVALID_TELEGRAM_SIGNATURE");
    }

    return {
      id: telegramUserId,
      first_name: query.first_name ? String(query.first_name) : "",
      last_name: query.last_name ? String(query.last_name) : "",
      username: query.username ? String(query.username) : "",
      photo_url: query.photo_url ? String(query.photo_url) : "",
      auth_date: authDate,
    };
  }

  function telegramAuthRedirectUrl(code, {intent = "login"} = {}) {
    const query = new URLSearchParams({
      telegramAuthCode: code,
      ...(intent === "link" ? {telegramIntent: "link"} : {}),
    });
    return `${resolvePublicAppUrl()}/#/login?${query.toString()}`;
  }

  app.get("/v1/auth/telegram/start", async (req, res) => {
    if (!config.telegramLoginEnabled) {
      res.status(503).send("Telegram login is not configured.");
      return;
    }

    const callbackUrl = `${resolvePublicApiUrl(req).replace(/\/$/, "")}/v1/auth/telegram/callback`;
    res.setHeader("cache-control", "no-store");
    res.type("html").send(
      renderTelegramLoginPage({
        botUsername: config.telegramBotUsername,
        authUrl: callbackUrl,
      }),
    );
  });

  app.get("/v1/auth/telegram/callback", async (req, res) => {
    try {
      const intent = String(req.query?.intent || "").trim().toLowerCase() === "link"
        ? "link"
        : "login";
      const telegramAuth = verifyTelegramLoginPayload(req.query || {});
      const telegramIdentity = buildTelegramIdentityFromAuth(telegramAuth);
      const linkedUser = await store.findUserByAuthIdentity(
        telegramIdentity.provider,
        telegramIdentity.providerUserId,
      );

      if (linkedUser) {
        if (intent === "link") {
          const authHandoff = await store.createAuthHandoff({
            type: "telegram_auth_result",
            userId: linkedUser.id,
            payload: {
              status: "already_linked",
              message:
                "Этот Telegram уже привязан к аккаунту Родни. Если это ваш аккаунт, входите через Telegram с экрана входа.",
            },
          });
          res.redirect(302, telegramAuthRedirectUrl(authHandoff.code, {intent}));
          return;
        }

        const refreshedUser = await store.linkAuthIdentity(
          linkedUser.id,
          telegramIdentity,
        );
        const sessionTokens = await store.createSession(refreshedUser.id);
        const authHandoff = await store.createAuthHandoff({
          type: "telegram_auth_result",
          userId: refreshedUser.id,
          payload: {
            status: "authenticated",
            auth: authResponse(refreshedUser, sessionTokens),
          },
        });
        res.redirect(302, telegramAuthRedirectUrl(authHandoff.code, {intent}));
        return;
      }

      const pendingLinkHandoff = await store.createAuthHandoff({
        type: "telegram_pending_link",
        payload: {
          telegramIdentity,
          telegramProfile: {
            id: telegramAuth.id,
            firstName: telegramAuth.first_name || "",
            lastName: telegramAuth.last_name || "",
            username: telegramAuth.username || "",
            photoUrl: telegramAuth.photo_url || "",
          },
        },
      });

      const authHandoff = await store.createAuthHandoff({
        type: "telegram_auth_result",
        payload: {
          status: "pending_link",
          linkCode: pendingLinkHandoff.code,
          telegramProfile: {
            firstName: telegramAuth.first_name || "",
            lastName: telegramAuth.last_name || "",
            username: telegramAuth.username || "",
            photoUrl: telegramAuth.photo_url || "",
          },
          message:
            "Telegram подтверждён. Теперь войдите в существующий аккаунт Родни, чтобы привязать Telegram и не создать дубль.",
        },
      });

      res.redirect(302, telegramAuthRedirectUrl(authHandoff.code, {intent}));
    } catch (error) {
      console.error("[backend] telegram auth callback failed", error);
      const appUrl = resolvePublicAppUrl();
      const normalizedMessage = (() => {
        switch (error?.message) {
          case "TELEGRAM_LOGIN_DISABLED":
            return "Telegram login is not configured";
          case "INVALID_TELEGRAM_SIGNATURE":
            return "Не удалось проверить подпись Telegram";
          case "TELEGRAM_AUTH_EXPIRED":
            return "Telegram login устарел. Повторите попытку.";
          default:
            return "Не удалось завершить вход через Telegram";
        }
      })();
      res.redirect(
        302,
        `${appUrl}/#/login?telegramAuthError=${encodeURIComponent(normalizedMessage)}`,
      );
    }
  });

  app.post("/v1/auth/telegram/exchange", async (req, res) => {
    const code = String(req.body?.code || "").trim();
    if (!code) {
      res.status(400).json({message: "Нужен code"});
      return;
    }

    const handoff = await store.consumeAuthHandoff(code, {
      type: "telegram_auth_result",
    });
    if (!handoff) {
      res.status(404).json({message: "Telegram handoff не найден или уже использован"});
      return;
    }

    res.json(handoff.payload || {});
  });

  app.post("/v1/auth/telegram/link", requireAuth, async (req, res) => {
    const code = String(req.body?.code || "").trim();
    if (!code) {
      res.status(400).json({message: "Нужен code"});
      return;
    }

    const handoff = await store.consumeAuthHandoff(code, {
      type: "telegram_pending_link",
    });
    if (!handoff) {
      res.status(404).json({message: "Telegram link code не найден или уже использован"});
      return;
    }

    try {
      const updatedUser = await store.linkAuthIdentity(
        req.auth.user.id,
        handoff.payload?.telegramIdentity || {},
      );
      res.json({
        ok: true,
        user: {
          id: updatedUser.id,
          identityId: updatedUser.identityId || null,
          email: updatedUser.email,
          providerIds: updatedUser.providerIds || ["password"],
        },
      });
    } catch (error) {
      if (error?.message === "AUTH_IDENTITY_ALREADY_LINKED") {
        res.status(409).json({
          message:
            "Этот Telegram уже привязан к другому аккаунту Родни.",
        });
        return;
      }
      if (error?.message === "AUTH_PROVIDER_ALREADY_LINKED_FOR_USER") {
        res.status(409).json({
          message:
            "К этому аккаунту уже привязан другой Telegram. Сначала отвяжите его или используйте уже связанный вход.",
        });
        return;
      }
      if (error?.message === "INVALID_AUTH_IDENTITY") {
        res.status(400).json({message: "Некорректные данные Telegram identity"});
        return;
      }
      throw error;
    }
  });
}

module.exports = {
  registerTelegramAuthRoutes,
};
