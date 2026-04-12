const fs = require("node:fs/promises");
const path = require("node:path");

const {
  S3Client,
  PutObjectCommand,
  DeleteObjectCommand,
  HeadBucketCommand,
} = require("@aws-sdk/client-s3");

function sanitizeRelativePath(inputValue) {
  const rawValue = String(inputValue || "").trim().replace(/\\/g, "/");
  const normalized = path.posix.normalize(`/${rawValue}`).replace(/^\/+/, "");

  if (!normalized || normalized === "." || normalized.startsWith("..")) {
    throw new Error("INVALID_MEDIA_PATH");
  }

  return normalized;
}

function resolveRequestOrigin(req, config) {
  const configuredOrigin = String(config?.publicApiUrl || "")
    .trim()
    .replace(/\/+$/, "");
  const forwardedProto = String(req?.get?.("x-forwarded-proto") || "")
    .split(",")[0]
    .trim();
  const forwardedHost = String(req?.get?.("x-forwarded-host") || "")
    .split(",")[0]
    .trim();

  return configuredOrigin ||
    `${forwardedProto || req?.protocol || "https"}://${forwardedHost || req?.get?.("host")}`;
}

function encodePathSegments(parts) {
  return parts
    .filter(Boolean)
    .map((segment) => encodeURIComponent(segment))
    .join("/");
}

class LocalMediaStorage {
  constructor({config}) {
    this.config = config;
    this.mediaMode = "local-filesystem";
    this.mediaTarget = config.mediaRootPath;
  }

  async ensureReady() {
    await fs.mkdir(this.config.mediaRootPath, {recursive: true});
    await fs.access(this.config.mediaRootPath);
  }

  resolveMediaFilePath(bucket, relativePath) {
    const safeBucket = sanitizeRelativePath(bucket);
    const safeRelativePath = sanitizeRelativePath(relativePath);
    const rootPath = path.resolve(this.config.mediaRootPath);
    const resolvedPath = path.resolve(rootPath, safeBucket, safeRelativePath);

    if (
      resolvedPath !== rootPath &&
      !resolvedPath.startsWith(`${rootPath}${path.sep}`)
    ) {
      throw new Error("INVALID_MEDIA_PATH");
    }

    return {
      safeBucket,
      safeRelativePath,
      resolvedPath,
    };
  }

  buildPublicUrl(req, bucket, relativePath) {
    const origin = resolveRequestOrigin(req, this.config);
    const encodedPath = encodePathSegments([
      bucket,
      ...String(relativePath || "").split("/"),
    ]);
    return `${origin}/media/${encodedPath}`;
  }

  async saveObject({req, bucket, relativePath, contentType, fileBuffer}) {
    const {safeBucket, safeRelativePath, resolvedPath} = this.resolveMediaFilePath(
      bucket,
      relativePath,
    );

    await fs.mkdir(path.dirname(resolvedPath), {recursive: true});
    await fs.writeFile(resolvedPath, fileBuffer);

    return {
      bucket: safeBucket,
      path: safeRelativePath,
      contentType: contentType ? String(contentType) : null,
      size: fileBuffer.length,
      url: this.buildPublicUrl(req, safeBucket, safeRelativePath),
    };
  }

  async deleteObjectByUrl(urlValue) {
    const url = new URL(urlValue);
    const mediaPrefix = "/media/";
    if (!url.pathname.startsWith(mediaPrefix)) {
      throw new Error("UNSUPPORTED_MEDIA_URL");
    }

    const relativePath = decodeURIComponent(url.pathname.slice(mediaPrefix.length));
    const [bucket, ...restParts] = relativePath.split("/").filter(Boolean);
    const mediaPath = restParts.join("/");
    const {resolvedPath} = this.resolveMediaFilePath(bucket, mediaPath);
    await fs.rm(resolvedPath, {force: true});
  }

  async handleGetRequest(req, res) {
    const requestedPath = String(req.params?.[0] || "").trim();
    const [bucket, ...restParts] = decodeURIComponent(requestedPath)
      .split("/")
      .filter(Boolean);
    const mediaPath = restParts.join("/");
    const {resolvedPath} = this.resolveMediaFilePath(bucket, mediaPath);
    res.sendFile(resolvedPath);
  }
}

class S3MediaStorage {
  constructor({config, client = null}) {
    const bucket = String(config?.s3Bucket || "").trim();
    if (!bucket) {
      throw new Error(
        "LINEAGE_S3_BUCKET is required when LINEAGE_MEDIA_BACKEND=s3",
      );
    }

    this.config = config;
    this.bucket = bucket;
    this.prefix = sanitizeRelativePath(config?.s3Prefix || "lineage");
    this.mediaMode = "s3";
    this.mediaTarget = `${bucket}/${this.prefix}`;
    this._client =
      client ??
      new S3Client({
        region: config.s3Region,
        endpoint: config.s3Endpoint || undefined,
        forcePathStyle: config.s3ForcePathStyle === true,
        credentials:
          config.s3AccessKeyId && config.s3SecretAccessKey
            ? {
                accessKeyId: config.s3AccessKeyId,
                secretAccessKey: config.s3SecretAccessKey,
              }
            : undefined,
      });
  }

  buildObjectKey(bucket, relativePath) {
    const safeBucket = sanitizeRelativePath(bucket);
    const safeRelativePath = sanitizeRelativePath(relativePath);
    return {
      safeBucket,
      safeRelativePath,
      objectKey: `${this.prefix}/${safeBucket}/${safeRelativePath}`,
    };
  }

  buildPublicUrl(bucket, relativePath) {
    const publicBaseUrl = String(this.config.mediaPublicBaseUrl || "").trim();
    const {safeBucket, safeRelativePath, objectKey} = this.buildObjectKey(
      bucket,
      relativePath,
    );

    if (publicBaseUrl) {
      const normalizedBaseUrl = publicBaseUrl.replace(/\/+$/, "");
      return `${normalizedBaseUrl}/${encodePathSegments(objectKey.split("/"))}`;
    }

    if (!this.config.s3Endpoint) {
      throw new Error(
        "LINEAGE_MEDIA_PUBLIC_BASE_URL or LINEAGE_S3_ENDPOINT is required for S3 media URLs",
      );
    }

    const normalizedEndpoint = String(this.config.s3Endpoint).trim().replace(
      /\/+$/,
      "",
    );
    return `${normalizedEndpoint}/${this.bucket}/${encodePathSegments([
      this.prefix,
      safeBucket,
      ...safeRelativePath.split("/"),
    ])}`;
  }

  async ensureReady() {
    await this._client.send(new HeadBucketCommand({Bucket: this.bucket}));
  }

  async saveObject({bucket, relativePath, contentType, fileBuffer}) {
    const {safeBucket, safeRelativePath, objectKey} = this.buildObjectKey(
      bucket,
      relativePath,
    );

    await this._client.send(
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: objectKey,
        Body: fileBuffer,
        ContentType: contentType ? String(contentType) : undefined,
      }),
    );

    return {
      bucket: safeBucket,
      path: safeRelativePath,
      contentType: contentType ? String(contentType) : null,
      size: fileBuffer.length,
      url: this.buildPublicUrl(safeBucket, safeRelativePath),
    };
  }

  extractObjectKeyFromUrl(urlValue) {
    const url = new URL(urlValue);
    const publicBaseUrl = String(this.config.mediaPublicBaseUrl || "")
      .trim()
      .replace(/\/+$/, "");

    if (publicBaseUrl && urlValue.startsWith(publicBaseUrl)) {
      return decodeURIComponent(urlValue.slice(publicBaseUrl.length).replace(/^\/+/, ""));
    }

    const pathname = decodeURIComponent(url.pathname).replace(/^\/+/, "");
    const pathParts = pathname.split("/").filter(Boolean);
    if (pathParts[0] === this.bucket) {
      pathParts.shift();
    }
    const normalizedKey = pathParts.join("/");

    if (!normalizedKey.startsWith(`${this.prefix}/`)) {
      throw new Error("UNSUPPORTED_MEDIA_URL");
    }

    return normalizedKey;
  }

  async deleteObjectByUrl(urlValue) {
    const objectKey = this.extractObjectKeyFromUrl(urlValue);
    await this._client.send(
      new DeleteObjectCommand({
        Bucket: this.bucket,
        Key: objectKey,
      }),
    );
  }

  async handleGetRequest(req, res) {
    const requestedPath = decodeURIComponent(String(req.params?.[0] || "").trim());
    if (!requestedPath) {
      throw new Error("INVALID_MEDIA_PATH");
    }

    const [bucket, ...restParts] = requestedPath.split("/").filter(Boolean);
    const mediaPath = restParts.join("/");
    const redirectUrl = this.buildPublicUrl(bucket, mediaPath);
    res.redirect(302, redirectUrl);
  }
}

function createMediaStorage(config, overrides = {}) {
  const mediaBackend = String(config?.mediaBackend || "local")
    .trim()
    .toLowerCase();

  switch (mediaBackend) {
    case "local":
    case "filesystem":
      return new LocalMediaStorage({config});
    case "s3":
    case "object-storage":
      return new S3MediaStorage({config, client: overrides.s3Client || null});
    default:
      throw new Error(
        `Unsupported LINEAGE_MEDIA_BACKEND value: ${mediaBackend}`,
      );
  }
}

module.exports = {
  LocalMediaStorage,
  S3MediaStorage,
  createMediaStorage,
  sanitizeRelativePath,
};
