const path = require("node:path");

function readEnvValue(...keys) {
  for (const key of keys) {
    const value = process.env[key];
    if (typeof value === "string" && value.trim()) {
      return value.trim();
    }
  }

  return "";
}

function legacyEnvKey(key) {
  if (typeof key !== "string" || !key.startsWith("RODNYA_")) {
    return key;
  }

  return `LINEAGE_${key.slice("RODNYA_".length)}`;
}

function readEnvAlias(key, ...extraKeys) {
  const keys = [key];
  const legacyKey = legacyEnvKey(key);
  if (legacyKey && legacyKey !== key) {
    keys.push(legacyKey);
  }

  keys.push(...extraKeys);
  return readEnvValue(...keys);
}

function readEnvNumber(fallback, ...keys) {
  const rawValue = readEnvValue(...keys);
  if (rawValue) {
    return Number(rawValue);
  }

  return Number(fallback);
}

function readEnvBool(fallback, ...keys) {
  const rawValue = readEnvValue(...keys);
  if (!rawValue) {
    return Boolean(fallback);
  }
  const normalized = rawValue.trim().toLowerCase();
  if (normalized === "true" || normalized === "1" || normalized === "yes") {
    return true;
  }
  if (normalized === "false" || normalized === "0" || normalized === "no") {
    return false;
  }
  return Boolean(fallback);
}

function createConfig() {
  const dataPath =
    readEnvAlias("RODNYA_BACKEND_DATA_PATH") ||
    path.join(__dirname, "..", "data", "dev-db.json");
  const webPushPublicKey = readEnvAlias("RODNYA_WEB_PUSH_PUBLIC_KEY");
  const webPushPrivateKey = readEnvAlias("RODNYA_WEB_PUSH_PRIVATE_KEY");
  const webPushSubject = String(
    readEnvAlias("RODNYA_WEB_PUSH_SUBJECT") || "https://rodnya-tree.ru",
  ).trim();
  const rustorePushProjectId = readEnvAlias("RODNYA_RUSTORE_PUSH_PROJECT_ID");
  const rustorePushServiceToken = readEnvAlias(
    "RODNYA_RUSTORE_PUSH_SERVICE_TOKEN",
  );
  const rustorePushApiBaseUrl = String(
    readEnvAlias("RODNYA_RUSTORE_PUSH_API_BASE_URL") ||
      "https://vkpns.rustore.ru",
  ).trim();
  const adminEmails = String(
    readEnvAlias("RODNYA_BACKEND_ADMIN_EMAILS") || "",
  )
    .split(",")
    .map((value) => value.trim().toLowerCase())
    .filter(Boolean);
  const rateLimitWindowMs = readEnvNumber(
    60_000,
    "RODNYA_RATE_LIMIT_WINDOW_MS",
    legacyEnvKey("RODNYA_RATE_LIMIT_WINDOW_MS"),
  );
  const defaultRateLimitMax = readEnvNumber(
    600,
    "RODNYA_RATE_LIMIT_DEFAULT_MAX",
    legacyEnvKey("RODNYA_RATE_LIMIT_DEFAULT_MAX"),
  );
  const authRateLimitMax = readEnvNumber(
    30,
    "RODNYA_RATE_LIMIT_AUTH_MAX",
    legacyEnvKey("RODNYA_RATE_LIMIT_AUTH_MAX"),
  );
  const mutationRateLimitMax = readEnvNumber(
    180,
    "RODNYA_RATE_LIMIT_MUTATION_MAX",
    legacyEnvKey("RODNYA_RATE_LIMIT_MUTATION_MAX"),
  );
  const uploadRateLimitMax = readEnvNumber(
    40,
    "RODNYA_RATE_LIMIT_UPLOAD_MAX",
    legacyEnvKey("RODNYA_RATE_LIMIT_UPLOAD_MAX"),
  );
  const safetyRateLimitMax = readEnvNumber(
    20,
    "RODNYA_RATE_LIMIT_SAFETY_MAX",
    legacyEnvKey("RODNYA_RATE_LIMIT_SAFETY_MAX"),
  );
  const storageBackend = String(
    readEnvAlias("RODNYA_BACKEND_STORAGE") || "file",
  )
    .trim()
    .toLowerCase();

  // ── Phase 3.6 hard-delete background job ──────────────────────────
  // Master toggle defaults `false` — code присутствует, но scheduler
  // не register'ится пока explicitly не enabled. Rollout per
  // DECISIONS.md 2026-05-18 «Phase 3.6 hard-delete background job»:
  //   1. Deploy с hardDeleteEnabled=false → verify «disabled» log
  //   2. Set RODNYA_HARD_DELETE_ENABLED=true → restart → 60s first
  //      dry-run (hardDeleteFirstRunDry=true)
  //   3. Review log: counts reasonable + sample IDs + errors empty
  //   4. Set RODNYA_HARD_DELETE_FIRST_RUN_DRY=false → next 24h
  //      cycle live
  const hardDeleteEnabled = readEnvBool(
    false,
    "RODNYA_HARD_DELETE_ENABLED",
  );
  const hardDeleteRetentionDays = readEnvNumber(
    30,
    "RODNYA_HARD_DELETE_RETENTION_DAYS",
  );
  const hardDeleteIntervalHours = readEnvNumber(
    24,
    "RODNYA_HARD_DELETE_INTERVAL_HOURS",
  );
  const hardDeleteDryRun = readEnvBool(
    false,
    "RODNYA_HARD_DELETE_DRY_RUN",
  );
  const hardDeleteFirstRunDry = readEnvBool(
    true,
    "RODNYA_HARD_DELETE_FIRST_RUN_DRY",
  );
  const hardDeletePaused = readEnvBool(
    false,
    "RODNYA_HARD_DELETE_PAUSED",
  );
  const hardDeleteMaxPerRun = readEnvNumber(
    10_000,
    "RODNYA_HARD_DELETE_MAX_PER_RUN",
  );
  const hardDeleteAuditRetentionDays = readEnvNumber(
    90,
    "RODNYA_HARD_DELETE_AUDIT_RETENTION_DAYS",
  );
  const hardDeleteTimeoutMs = readEnvNumber(
    120_000,
    "RODNYA_HARD_DELETE_TIMEOUT_MS",
  );
  const mediaBackend = String(
    readEnvAlias("RODNYA_MEDIA_BACKEND") || "local",
  )
    .trim()
    .toLowerCase();
  const s3ForcePathStyle = String(
    readEnvAlias("RODNYA_S3_FORCE_PATH_STYLE") || "true",
  )
    .trim()
    .toLowerCase() !== "false";
  const telegramBotToken = readEnvAlias("RODNYA_TELEGRAM_BOT_TOKEN");
  const telegramBotUsername = readEnvAlias("RODNYA_TELEGRAM_BOT_USERNAME")
    .trim()
    .replace(/^@/, "");
  const googleWebClientId = readEnvAlias("RODNYA_GOOGLE_WEB_CLIENT_ID");
  const googleAllowedClientIds = String(
    readEnvAlias("RODNYA_GOOGLE_ALLOWED_CLIENT_IDS") || "",
  )
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  const vkWebAppId = readEnvAlias("RODNYA_VK_WEB_APP_ID");
  const vkWebProtectedKey = readEnvAlias("RODNYA_VK_WEB_PROTECTED_KEY");
  const vkAndroidAppId = readEnvAlias("RODNYA_VK_ANDROID_APP_ID");
  const vkAndroidProtectedKey = readEnvAlias(
    "RODNYA_VK_ANDROID_PROTECTED_KEY",
  );
  const maxBotToken = readEnvAlias("RODNYA_MAX_BOT_TOKEN");
  const maxBotUsername = readEnvAlias("RODNYA_MAX_BOT_USERNAME")
    .trim()
    .replace(/^@/, "");
  const liveKitUrl = readEnvAlias("RODNYA_LIVEKIT_URL");
  const liveKitApiKey = readEnvAlias("RODNYA_LIVEKIT_API_KEY");
  const liveKitApiSecret = readEnvAlias("RODNYA_LIVEKIT_API_SECRET");
  const liveKitWebhookKey = readEnvAlias("RODNYA_LIVEKIT_WEBHOOK_KEY");

  // SMTP for transactional email (password reset etc.). Provider is
  // pluggable — UniSender Go in production today (РФ-friendly free
  // tier), but `email-sender.js` only sees these env-derived knobs
  // so swapping providers is a env edit, not a code change.
  //
  // When SMTP_HOST / USER / PASSWORD are not set, `email-sender.js`
  // falls back to a console-logger that prints what it would have
  // sent → keeps dev/CI green and gives developers a copyable reset
  // link in stdout.
  const smtpHost = readEnvAlias("RODNYA_SMTP_HOST");
  const smtpPort = readEnvNumber(
    587,
    "RODNYA_SMTP_PORT",
    legacyEnvKey("RODNYA_SMTP_PORT"),
  );
  const smtpUser = readEnvAlias("RODNYA_SMTP_USER");
  const smtpPassword = process.env.RODNYA_SMTP_PASSWORD || "";
  const smtpSecure = String(
    readEnvAlias("RODNYA_SMTP_SECURE") || "false",
  )
    .trim()
    .toLowerCase();
  const mailFrom = readEnvAlias("RODNYA_MAIL_FROM") || "no-reply@rodnya-tree.ru";
  const mailFromName = readEnvAlias("RODNYA_MAIL_FROM_NAME") || "Родня";
  // UniSender Go HTTPS API. Preferred over SMTP in production —
  // works through outbound 443 which is universally open, even
  // when 587/465/25 are blocked by the VPS provider's anti-spam
  // policy. The API key is the same as RODNYA_SMTP_PASSWORD if you
  // already had SMTP wired up; just rename the env var.
  const unisenderApiKey =
    process.env.RODNYA_UNISENDER_API_KEY || "";
  const unisenderApiBaseUrl =
    readEnvAlias("RODNYA_UNISENDER_API_BASE_URL") ||
    "https://go2.unisender.ru/ru/transactional/api/v1";

  return {
    port: Number(process.env.PORT || 8080),
    corsOrigin: readEnvAlias("RODNYA_BACKEND_CORS_ORIGIN") || "*",
    dataPath,
    mediaRootPath:
      readEnvAlias("RODNYA_BACKEND_MEDIA_ROOT") ||
      path.join(__dirname, "..", "data", "uploads"),
    mediaBackend,
    mediaPublicBaseUrl:
      readEnvAlias("RODNYA_MEDIA_PUBLIC_BASE_URL") ||
      readEnvAlias("RODNYA_S3_PUBLIC_BASE_URL") ||
      "",
    publicApiUrl: readEnvAlias("RODNYA_PUBLIC_API_URL") || "",
    publicAppUrl:
      readEnvAlias("RODNYA_PUBLIC_APP_URL") || "https://rodnya-tree.ru",
    postgresUrl:
      readEnvAlias("RODNYA_POSTGRES_URL", "DATABASE_URL") ||
      process.env.DATABASE_URL ||
      "",
    postgresSchema:
      readEnvAlias("RODNYA_POSTGRES_SCHEMA") || "public",
    postgresStateTable:
      readEnvAlias("RODNYA_POSTGRES_STATE_TABLE") || "rodnya_state",
    postgresStateRowId:
      readEnvAlias("RODNYA_POSTGRES_STATE_ROW_ID") || "default",
    postgresSnapshotCachePath:
      readEnvAlias("RODNYA_POSTGRES_SNAPSHOT_CACHE_PATH") ||
      path.join(path.dirname(dataPath), "postgres-state-cache.json"),
    postgresPoolMax: readEnvNumber(
      64,
      "RODNYA_POSTGRES_POOL_MAX",
      legacyEnvKey("RODNYA_POSTGRES_POOL_MAX"),
    ),
    postgresApplicationName:
      readEnvAlias("RODNYA_POSTGRES_APPLICATION_NAME") || "rodnya_backend",
    s3Endpoint: readEnvAlias("RODNYA_S3_ENDPOINT") || "",
    s3Region: readEnvAlias("RODNYA_S3_REGION") || "ru-msk",
    s3Bucket: readEnvAlias("RODNYA_S3_BUCKET") || "",
    s3AccessKeyId:
      readEnvAlias("RODNYA_S3_ACCESS_KEY_ID") || "",
    s3SecretAccessKey:
      readEnvAlias("RODNYA_S3_SECRET_ACCESS_KEY") || "",
    s3ForcePathStyle,
    s3Prefix: readEnvAlias("RODNYA_S3_PREFIX") || "rodnya",
    telegramBotToken,
    telegramBotUsername,
    telegramLoginEnabled: Boolean(telegramBotToken && telegramBotUsername),
    googleWebClientId,
    googleAllowedClientIds,
    googleAuthEnabled:
      Boolean(googleWebClientId) || googleAllowedClientIds.length > 0,
    vkWebAppId,
    vkWebProtectedKey,
    vkAndroidAppId,
    vkAndroidProtectedKey,
    vkAuthEnabled: Boolean(vkWebAppId),
    maxBotToken,
    maxBotUsername,
    maxAuthEnabled: Boolean(maxBotToken && maxBotUsername),
    liveKitUrl,
    liveKitApiKey,
    liveKitApiSecret,
    liveKitWebhookKey,
    liveKitEnabled: Boolean(liveKitUrl && liveKitApiKey && liveKitApiSecret),
    smtpHost,
    smtpPort,
    smtpUser,
    smtpPassword,
    smtpSecure,
    mailFrom,
    mailFromName,
    smtpEnabled: Boolean(smtpHost && smtpUser && smtpPassword),
    unisenderApiKey,
    unisenderApiBaseUrl,
    unisenderHttpsEnabled: Boolean(unisenderApiKey),
    // True when ANY transport is configured — the email-sender
    // factory falls back to a console logger otherwise. Useful for
    // boot-time logs ("email sending: enabled via https-api").
    emailDeliveryEnabled: Boolean(
      unisenderApiKey || (smtpHost && smtpUser && smtpPassword),
    ),
    webPushPublicKey,
    webPushPrivateKey,
    webPushSubject,
    webPushEnabled: Boolean(webPushPublicKey && webPushPrivateKey),
    rustorePushProjectId,
    rustorePushServiceToken,
    rustorePushApiBaseUrl,
    rustorePushEnabled: Boolean(
      rustorePushProjectId && rustorePushServiceToken,
    ),
    adminEmails,
    rateLimitWindowMs,
    defaultRateLimitMax,
    authRateLimitMax,
    mutationRateLimitMax,
    uploadRateLimitMax,
    safetyRateLimitMax,
    storageBackend,
    hardDeleteEnabled,
    hardDeleteRetentionDays,
    hardDeleteIntervalHours,
    hardDeleteDryRun,
    hardDeleteFirstRunDry,
    hardDeletePaused,
    hardDeleteMaxPerRun,
    hardDeleteAuditRetentionDays,
    hardDeleteTimeoutMs,
  };
}

module.exports = {
  createConfig,
};
