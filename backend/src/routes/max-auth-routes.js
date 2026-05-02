const {parseMaxStartParam} = require("../max-auth");

function buildMaxIdentityFromLaunch(launchData) {
  const user = launchData?.user && typeof launchData.user === "object"
    ? launchData.user
    : {};
  const providerUserId = String(user?.id || "").trim();
  if (!providerUserId) {
    throw new Error("MAX_USER_INFO_INVALID");
  }

  return {
    provider: "max",
    providerUserId,
    displayName: [
      String(user?.first_name || "").trim(),
      String(user?.last_name || "").trim(),
    ].filter(Boolean).join(" ") || String(user?.username || "").trim() || null,
    metadata: {
      firstName: String(user?.first_name || "").trim() || null,
      lastName: String(user?.last_name || "").trim() || null,
      username: String(user?.username || "").trim() || null,
      photoUrl: String(user?.photo_url || "").trim() || null,
      languageCode: String(user?.language_code || "").trim() || null,
      authDate: launchData?.authDate || null,
    },
  };
}

function registerMaxAuthRoutes(
  app,
  {
    store,
    requireAuth,
    maxAuthClient,
    resolvePublicAppUrl,
    authResponse,
    readDeviceContext = () => ({}),
  },
) {
  function maxAuthRedirectUrl(code, {intent = "login"} = {}) {
    const query = new URLSearchParams({
      maxAuthCode: code,
      ...(intent === "link" ? {maxIntent: "link"} : {}),
    });
    return `${resolvePublicAppUrl()}/#/login?${query.toString()}`;
  }

  app.get("/v1/auth/max/start", async (req, res) => {
    if (!maxAuthClient.isEnabled) {
      res.status(503).send("MAX login is not configured.");
      return;
    }

    const intent = String(req.query?.intent || "").trim().toLowerCase() === "link"
      ? "link"
      : "login";
    const authFlowHandoff = await store.createAuthHandoff({
      type: "max_auth_flow",
      payload: {intent},
    });

    res.setHeader("cache-control", "no-store");
    res.redirect(
      302,
      maxAuthClient.buildStartUrl({
        intent,
        flowCode: authFlowHandoff.code,
      }),
    );
  });

  app.post("/v1/auth/max/complete", async (req, res) => {
    try {
      if (!maxAuthClient.isEnabled) {
        throw new Error("MAX_AUTH_NOT_CONFIGURED");
      }

      const launchData = maxAuthClient.verifyInitData(
        String(req.body?.initData || "").trim(),
      );
      const {intent, flowCode} = parseMaxStartParam(launchData.startParam);
      const authFlowHandoff = await store.consumeAuthHandoff(flowCode, {
        type: "max_auth_flow",
      });
      if (!authFlowHandoff) {
        throw new Error("MAX_AUTH_STATE_INVALID");
      }

      const effectiveIntent = String(authFlowHandoff.payload?.intent || "").trim().toLowerCase() === "link"
        ? "link"
        : intent;
      const maxIdentity = buildMaxIdentityFromLaunch(launchData);
      const linkedUser = await store.findUserByAuthIdentity(
        maxIdentity.provider,
        maxIdentity.providerUserId,
      );

      if (linkedUser) {
        if (effectiveIntent === "link") {
          const authHandoff = await store.createAuthHandoff({
            type: "max_auth_result",
            userId: linkedUser.id,
            payload: {
              status: "already_linked",
              message:
                "Этот MAX уже привязан к аккаунту Родни. Если это ваш аккаунт, входите через MAX с экрана входа.",
            },
          });
          res.json({
            ok: true,
            redirectUrl: maxAuthRedirectUrl(authHandoff.code, {
              intent: effectiveIntent,
            }),
            status: "already_linked",
            handoffCode: authHandoff.code,
          });
          return;
        }

        const refreshedUser = await store.linkAuthIdentity(
          linkedUser.id,
          maxIdentity,
        );
        const sessionTokens = await store.createSession(
          refreshedUser.id,
          readDeviceContext(req),
        );
        const authHandoff = await store.createAuthHandoff({
          type: "max_auth_result",
          userId: refreshedUser.id,
          payload: {
            status: "authenticated",
            auth: authResponse(refreshedUser, sessionTokens),
          },
        });
        res.json({
          ok: true,
          redirectUrl: maxAuthRedirectUrl(authHandoff.code, {
            intent: effectiveIntent,
          }),
          status: "authenticated",
          handoffCode: authHandoff.code,
        });
        return;
      }

      const maxProfile = {
        firstName: maxIdentity.metadata?.firstName || "",
        lastName: maxIdentity.metadata?.lastName || "",
        username: maxIdentity.metadata?.username || "",
        photoUrl: maxIdentity.metadata?.photoUrl || "",
      };
      const pendingLinkHandoff = await store.createAuthHandoff({
        type: "max_pending_link",
        payload: {
          maxIdentity,
          maxProfile,
        },
      });
      const authHandoff = await store.createAuthHandoff({
        type: "max_auth_result",
        payload: {
          status: "pending_link",
          linkCode: pendingLinkHandoff.code,
          maxProfile,
          message:
            "MAX подтверждён. Теперь войдите или создайте аккаунт Родни, и мы привяжем MAX без дубля профиля.",
        },
      });
      res.json({
        ok: true,
        redirectUrl: maxAuthRedirectUrl(authHandoff.code, {
          intent: effectiveIntent,
        }),
        status: "pending_link",
        handoffCode: authHandoff.code,
      });
    } catch (error) {
      const normalizedMessage = (() => {
        switch (error?.message) {
          case "MAX_AUTH_NOT_CONFIGURED":
            return "MAX login пока не настроен";
          case "MAX_INIT_DATA_REQUIRED":
          case "MAX_INIT_DATA_INVALID":
          case "MAX_INIT_DATA_DUPLICATE_KEYS":
          case "MAX_INIT_DATA_HASH_REQUIRED":
          case "MAX_INIT_DATA_SIGNATURE_INVALID":
            return "Не удалось проверить подпись MAX";
          case "MAX_INIT_DATA_AUTH_DATE_INVALID":
          case "MAX_INIT_DATA_EXPIRED":
            return "MAX login устарел. Повторите попытку.";
          case "MAX_AUTH_STATE_INVALID":
          case "MAX_AUTH_START_PARAM_INVALID":
            return "MAX login устарел. Запустите flow ещё раз из Родни.";
          default:
            return "Не удалось завершить вход через MAX";
        }
      })();
      const statusCode =
        error?.message === "MAX_AUTH_NOT_CONFIGURED"
          ? 503
          : error?.message === "MAX_AUTH_STATE_INVALID"
            ? 410
            : 401;
      res.status(statusCode).json({
        message: normalizedMessage,
        errorCode: String(error?.message || "MAX_AUTH_FAILED"),
      });
    }
  });

  app.post("/v1/auth/max/exchange", async (req, res) => {
    const code = String(req.body?.code || "").trim();
    if (!code) {
      res.status(400).json({message: "Нужен code"});
      return;
    }

    const handoff = await store.consumeAuthHandoff(code, {
      type: "max_auth_result",
    });
    if (!handoff) {
      res.status(404).json({message: "MAX handoff не найден или уже использован"});
      return;
    }

    res.json(handoff.payload || {});
  });

  app.post("/v1/auth/max/link", requireAuth, async (req, res) => {
    const code = String(req.body?.code || "").trim();
    if (!code) {
      res.status(400).json({message: "Нужен code"});
      return;
    }

    const handoff = await store.consumeAuthHandoff(code, {
      type: "max_pending_link",
    });
    if (!handoff) {
      res.status(404).json({message: "MAX link code не найден или уже использован"});
      return;
    }

    try {
      const updatedUser = await store.linkAuthIdentity(
        req.auth.user.id,
        handoff.payload?.maxIdentity || {},
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
          message: "Этот MAX уже привязан к другому аккаунту Родни.",
        });
        return;
      }
      if (error?.message === "AUTH_PROVIDER_ALREADY_LINKED_FOR_USER") {
        res.status(409).json({
          message:
            "К этому аккаунту уже привязан другой MAX. Сначала отвяжите его или используйте уже связанный вход.",
        });
        return;
      }
      if (error?.message === "INVALID_AUTH_IDENTITY") {
        res.status(400).json({message: "Некорректные данные MAX identity"});
        return;
      }
      throw error;
    }
  });
}

module.exports = {
  registerMaxAuthRoutes,
};
