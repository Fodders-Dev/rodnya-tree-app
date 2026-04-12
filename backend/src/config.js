const path = require("node:path");

function createConfig() {
  const webPushPublicKey = String(
    process.env.LINEAGE_WEB_PUSH_PUBLIC_KEY || "",
  ).trim();
  const webPushPrivateKey = String(
    process.env.LINEAGE_WEB_PUSH_PRIVATE_KEY || "",
  ).trim();
  const webPushSubject = String(
    process.env.LINEAGE_WEB_PUSH_SUBJECT || "https://rodnya-tree.ru",
  ).trim();
  const rustorePushProjectId = String(
    process.env.LINEAGE_RUSTORE_PUSH_PROJECT_ID || "",
  ).trim();
  const rustorePushServiceToken = String(
    process.env.LINEAGE_RUSTORE_PUSH_SERVICE_TOKEN || "",
  ).trim();
  const rustorePushApiBaseUrl = String(
    process.env.LINEAGE_RUSTORE_PUSH_API_BASE_URL ||
      "https://vkpns.rustore.ru",
  ).trim();
  const adminEmails = String(
    process.env.LINEAGE_BACKEND_ADMIN_EMAILS || "",
  )
    .split(",")
    .map((value) => value.trim().toLowerCase())
    .filter(Boolean);
  const rateLimitWindowMs = Number(
    process.env.LINEAGE_RATE_LIMIT_WINDOW_MS || 60_000,
  );
  const defaultRateLimitMax = Number(
    process.env.LINEAGE_RATE_LIMIT_DEFAULT_MAX || 600,
  );
  const authRateLimitMax = Number(
    process.env.LINEAGE_RATE_LIMIT_AUTH_MAX || 30,
  );
  const mutationRateLimitMax = Number(
    process.env.LINEAGE_RATE_LIMIT_MUTATION_MAX || 180,
  );
  const uploadRateLimitMax = Number(
    process.env.LINEAGE_RATE_LIMIT_UPLOAD_MAX || 40,
  );
  const safetyRateLimitMax = Number(
    process.env.LINEAGE_RATE_LIMIT_SAFETY_MAX || 20,
  );
  const storageBackend = String(
    process.env.LINEAGE_BACKEND_STORAGE || "file",
  )
    .trim()
    .toLowerCase();
  const mediaBackend = String(
    process.env.LINEAGE_MEDIA_BACKEND || "local",
  )
    .trim()
    .toLowerCase();
  const s3ForcePathStyle = String(
    process.env.LINEAGE_S3_FORCE_PATH_STYLE || "true",
  )
    .trim()
    .toLowerCase() !== "false";

  return {
    port: Number(process.env.PORT || 8080),
    corsOrigin: process.env.LINEAGE_BACKEND_CORS_ORIGIN || "*",
    dataPath:
      process.env.LINEAGE_BACKEND_DATA_PATH ||
      path.join(__dirname, "..", "data", "dev-db.json"),
    mediaRootPath:
      process.env.LINEAGE_BACKEND_MEDIA_ROOT ||
      path.join(__dirname, "..", "data", "uploads"),
    mediaBackend,
    mediaPublicBaseUrl:
      process.env.LINEAGE_MEDIA_PUBLIC_BASE_URL ||
      process.env.LINEAGE_S3_PUBLIC_BASE_URL ||
      "",
    publicApiUrl:
      process.env.LINEAGE_PUBLIC_API_URL || "",
    publicAppUrl:
      process.env.LINEAGE_PUBLIC_APP_URL || "https://rodnya-tree.ru",
    postgresUrl:
      process.env.LINEAGE_POSTGRES_URL || process.env.DATABASE_URL || "",
    postgresSchema: process.env.LINEAGE_POSTGRES_SCHEMA || "public",
    postgresStateTable:
      process.env.LINEAGE_POSTGRES_STATE_TABLE || "lineage_state",
    postgresStateRowId:
      process.env.LINEAGE_POSTGRES_STATE_ROW_ID || "default",
    s3Endpoint: process.env.LINEAGE_S3_ENDPOINT || "",
    s3Region: process.env.LINEAGE_S3_REGION || "ru-msk",
    s3Bucket: process.env.LINEAGE_S3_BUCKET || "",
    s3AccessKeyId: process.env.LINEAGE_S3_ACCESS_KEY_ID || "",
    s3SecretAccessKey: process.env.LINEAGE_S3_SECRET_ACCESS_KEY || "",
    s3ForcePathStyle,
    s3Prefix: process.env.LINEAGE_S3_PREFIX || "lineage",
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
  };
}

module.exports = {
  createConfig,
};
