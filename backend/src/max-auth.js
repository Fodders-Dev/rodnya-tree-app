const crypto = require("node:crypto");

const MAX_WEBAPP_SECRET = "WebAppData";
const MAX_AUTH_FLOW_PREFIX = "rodnya";

function normalizeMaxBotUsername(value) {
  return String(value || "").trim().replace(/^@/, "");
}

function buildMaxStartParam({intent = "login", flowCode}) {
  const normalizedIntent =
    String(intent || "").trim().toLowerCase() === "link" ? "link" : "login";
  const normalizedFlowCode = String(flowCode || "")
    .trim()
    .replace(/[^a-z0-9_-]/gi, "");
  if (!normalizedFlowCode) {
    throw new Error("MAX_AUTH_FLOW_CODE_REQUIRED");
  }
  return `${MAX_AUTH_FLOW_PREFIX}-${normalizedIntent}-${normalizedFlowCode}`;
}

function parseMaxStartParam(value) {
  const normalizedValue = String(value || "").trim();
  const match = normalizedValue.match(
    /^rodnya-(login|link)-([a-z0-9_-]+)$/i,
  );
  if (!match) {
    throw new Error("MAX_AUTH_START_PARAM_INVALID");
  }

  return {
    intent: match[1].toLowerCase() === "link" ? "link" : "login",
    flowCode: match[2],
  };
}

function buildMaxMiniAppUrl({botUsername, startParam}) {
  const normalizedBotUsername = normalizeMaxBotUsername(botUsername);
  const normalizedStartParam = String(startParam || "").trim();
  if (!normalizedBotUsername || !normalizedStartParam) {
    throw new Error("MAX_AUTH_NOT_CONFIGURED");
  }
  return `https://max.ru/${encodeURIComponent(normalizedBotUsername)}?startapp=${encodeURIComponent(normalizedStartParam)}`;
}

function parseMaxInitData(initData) {
  const rawValue = String(initData || "").trim();
  if (!rawValue) {
    throw new Error("MAX_INIT_DATA_REQUIRED");
  }

  const pairs = rawValue.split("&").filter(Boolean).map((entry) => {
    const separatorIndex = entry.indexOf("=");
    if (separatorIndex < 0) {
      throw new Error("MAX_INIT_DATA_INVALID");
    }
    const key = decodeURIComponent(entry.slice(0, separatorIndex));
    const value = decodeURIComponent(entry.slice(separatorIndex + 1));
    return [key, value];
  });

  const keyCounts = new Map();
  for (const [key] of pairs) {
    keyCounts.set(key, Number(keyCounts.get(key) || 0) + 1);
  }
  for (const [key, count] of keyCounts.entries()) {
    if (count !== 1) {
      throw new Error("MAX_INIT_DATA_DUPLICATE_KEYS");
    }
  }

  const providedHash = pairs.find(([key]) => key === "hash")?.[1] || "";
  if (!providedHash) {
    throw new Error("MAX_INIT_DATA_HASH_REQUIRED");
  }

  const dataEntries = pairs
    .filter(([key]) => key !== "hash")
    .sort(([leftKey], [rightKey]) => leftKey.localeCompare(rightKey));

  const launchParams = dataEntries
    .map(([key, value]) => `${key}=${value}`)
    .join("\n");

  const values = Object.fromEntries(dataEntries);
  return {
    initData: rawValue,
    providedHash,
    launchParams,
    values,
  };
}

function createMaxAuthClient(config = {}) {
  const botToken = String(config.maxBotToken || "").trim();
  const botUsername = normalizeMaxBotUsername(config.maxBotUsername);

  return {
    isEnabled: Boolean(botToken && botUsername),
    botToken,
    botUsername,
    buildStartUrl({intent = "login", flowCode}) {
      if (!botUsername) {
        throw new Error("MAX_AUTH_NOT_CONFIGURED");
      }
      return buildMaxMiniAppUrl({
        botUsername,
        startParam: buildMaxStartParam({intent, flowCode}),
      });
    },
    verifyInitData(initData) {
      if (!botToken || !botUsername) {
        throw new Error("MAX_AUTH_NOT_CONFIGURED");
      }

      const parsedInitData = parseMaxInitData(initData);
      const secretKey = crypto
        .createHmac("sha256", MAX_WEBAPP_SECRET)
        .update(botToken, "utf8")
        .digest();
      const computedHash = crypto
        .createHmac("sha256", secretKey)
        .update(parsedInitData.launchParams, "utf8")
        .digest("hex");

      const providedHashBuffer = Buffer.from(
        parsedInitData.providedHash,
        "hex",
      );
      const computedHashBuffer = Buffer.from(computedHash, "hex");
      if (
        providedHashBuffer.length !== computedHashBuffer.length ||
        !crypto.timingSafeEqual(providedHashBuffer, computedHashBuffer)
      ) {
        throw new Error("MAX_INIT_DATA_SIGNATURE_INVALID");
      }

      const authDate = Number(parsedInitData.values.auth_date || 0);
      if (!Number.isFinite(authDate) || authDate <= 0) {
        throw new Error("MAX_INIT_DATA_AUTH_DATE_INVALID");
      }
      const nowSeconds = Math.floor(Date.now() / 1000);
      if (Math.abs(nowSeconds - authDate) > 10 * 60) {
        throw new Error("MAX_INIT_DATA_EXPIRED");
      }

      let user = {};
      if (parsedInitData.values.user) {
        try {
          user = JSON.parse(parsedInitData.values.user);
        } catch {
          throw new Error("MAX_INIT_DATA_USER_INVALID");
        }
      }

      return {
        authDate,
        queryId: String(parsedInitData.values.query_id || "").trim() || null,
        startParam: String(parsedInitData.values.start_param || "").trim(),
        user,
        raw: parsedInitData.values,
      };
    },
  };
}

module.exports = {
  createMaxAuthClient,
  parseMaxStartParam,
};
