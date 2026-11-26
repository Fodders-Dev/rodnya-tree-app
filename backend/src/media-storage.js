const fs = require("node:fs/promises");
const path = require("node:path");

const {
  S3Client,
  PutObjectCommand,
  DeleteObjectCommand,
  GetObjectCommand,
  HeadBucketCommand,
  HeadObjectCommand,
} = require("@aws-sdk/client-s3");
const {Readable} = require("node:stream");

function sanitizeRelativePath(inputValue) {
  const rawString = String(inputValue || "");
  if (/[\x00-\x1f\x7f\\]/.test(rawString)) {
    throw new Error("INVALID_MEDIA_PATH");
  }
  const rawValue = rawString.trim();
  const rawParts = rawValue.split("/").filter(Boolean);
  if (rawParts.some((part) => part === "." || part === "..")) {
    throw new Error("INVALID_MEDIA_PATH");
  }

  const normalized = path.posix.normalize(`/${rawValue}`).replace(/^\/+/, "");

  if (!normalized || normalized === "." || normalized.startsWith("..")) {
    throw new Error("INVALID_MEDIA_PATH");
  }

  return normalized;
}

const SAFE_INLINE_IMAGE_MIMES = new Set([
  "image/png",
  "image/jpeg",
  "image/jpg",
  "image/webp",
  "image/gif",
  "image/avif",
  "image/heic",
  "image/heif",
]);

const SAFE_INLINE_EXTENSIONS = new Set([
  ".png",
  ".jpg",
  ".jpeg",
  ".webp",
  ".gif",
  ".avif",
  ".heic",
  ".heif",
  ".mp3",
  ".m4a",
  ".aac",
  ".ogg",
  ".opus",
  ".wav",
  ".mp4",
  ".mov",
  ".webm",
]);

function isSafeInlineMedia(contentType, filePath = "") {
  const normalizedType = String(contentType || "")
    .split(";")[0]
    .trim()
    .toLowerCase();
  if (normalizedType) {
    if (SAFE_INLINE_IMAGE_MIMES.has(normalizedType)) {
      return true;
    }
    if (
      normalizedType.startsWith("audio/") ||
      normalizedType.startsWith("video/")
    ) {
      return true;
    }
    return false;
  }
  const ext = path.extname(String(filePath || "")).toLowerCase();
  return SAFE_INLINE_EXTENSIONS.has(ext);
}

function applySafeMediaDownloadHeaders(res, {contentType, filePath, existingContentDisposition} = {}) {
  if (!res || typeof res.setHeader !== "function") {
    return;
  }
  res.setHeader("x-content-type-options", "nosniff");
  res.setHeader(
    "content-security-policy",
    "default-src 'none'; sandbox",
  );
  if (!isSafeInlineMedia(contentType, filePath)) {
    res.setHeader("content-disposition", "attachment");
  } else if (existingContentDisposition) {
    res.setHeader("content-disposition", existingContentDisposition);
  }
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

  /// Гейт бинарного PUT против перезаписи чужого объекта по известному
  /// публичному URL: пути легитимных клиентов уникальны (uuid/timestamp),
  /// повторное имя = чья-то попытка подменить файл.
  async objectExists(bucket, relativePath) {
    const {resolvedPath} = this.resolveMediaFilePath(bucket, relativePath);
    try {
      await fs.access(resolvedPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  async saveObject({req, bucket, relativePath, contentType, fileBuffer, uploaderUserId = null}) {
    const {safeBucket, safeRelativePath, resolvedPath} = this.resolveMediaFilePath(
      bucket,
      relativePath,
    );

    await fs.mkdir(path.dirname(resolvedPath), {recursive: true});
    await fs.writeFile(resolvedPath, fileBuffer);
    if (uploaderUserId || contentType) {
      await fs.writeFile(
        `${resolvedPath}.meta.json`,
        JSON.stringify({
          uploaderUserId: uploaderUserId ? String(uploaderUserId) : null,
          contentType: contentType ? String(contentType) : null,
        }),
      );
    }

    return {
      bucket: safeBucket,
      path: safeRelativePath,
      contentType: contentType ? String(contentType) : null,
      size: fileBuffer.length,
      url: this.buildPublicUrl(req, safeBucket, safeRelativePath),
    };
  }

  _extractBucketAndPathFromUrl(urlValue) {
    const url = new URL(urlValue);
    const mediaPrefix = "/media/";
    if (!url.pathname.startsWith(mediaPrefix)) {
      throw new Error("UNSUPPORTED_MEDIA_URL");
    }

    const relativePath = decodeURIComponent(url.pathname.slice(mediaPrefix.length));
    const [bucket, ...restParts] = relativePath.split("/").filter(Boolean);
    const mediaPath = restParts.join("/");
    const resolved = this.resolveMediaFilePath(bucket, mediaPath);
    return {
      ...resolved,
      bucket: resolved.safeBucket,
      relativePath: resolved.safeRelativePath,
    };
  }

  async getObjectOwnerInfo(urlValue) {
    const {relativePath, resolvedPath} = this._extractBucketAndPathFromUrl(urlValue);
    let uploaderUserId = null;
    try {
      const rawMeta = await fs.readFile(`${resolvedPath}.meta.json`, "utf8");
      const parsed = JSON.parse(rawMeta);
      if (parsed?.uploaderUserId) {
        uploaderUserId = String(parsed.uploaderUserId).trim();
      }
    } catch (_) {
      uploaderUserId = null;
    }
    return {relativePath, uploaderUserId};
  }

  async deleteObjectByUrl(urlValue) {
    const {resolvedPath} = this._extractBucketAndPathFromUrl(urlValue);
    await fs.rm(resolvedPath, {force: true});
    await fs.rm(`${resolvedPath}.meta.json`, {force: true});
  }

  async handleGetRequest(req, res) {
    const requestedPath = String(req.params?.[0] || "").trim();
    const [bucket, ...restParts] = decodeURIComponent(requestedPath)
      .split("/")
      .filter(Boolean);
    const mediaPath = restParts.join("/");
    if (mediaPath.endsWith(".meta.json")) {
      throw new Error("MEDIA_FILE_NOT_FOUND");
    }
    const {resolvedPath} = this.resolveMediaFilePath(bucket, mediaPath);
    let storedContentType = null;
    try {
      const rawMeta = await fs.readFile(`${resolvedPath}.meta.json`, "utf8");
      storedContentType = JSON.parse(rawMeta)?.contentType || null;
    } catch (_) {
      storedContentType = null;
    }
    applySafeMediaDownloadHeaders(res, {
      contentType: storedContentType,
      filePath: resolvedPath,
    });
    res.sendFile(resolvedPath);
  }

  async handlePublicGetRequest(req, res) {
    return this.handleGetRequest(req, res);
  }
}

class S3MediaStorage {
  constructor({config, client = null}) {
    const bucket = String(config?.s3Bucket || "").trim();
    if (!bucket) {
      throw new Error(
        "RODNYA_S3_BUCKET is required when RODNYA_MEDIA_BACKEND=s3",
      );
    }

    this.config = config;
    this.bucket = bucket;
    this.prefix = sanitizeRelativePath(config?.s3Prefix || "rodnya");
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

  hasAllowedPrefix(value) {
    return value.startsWith(`${this.prefix}/`);
  }

  isLegacyPublicBucket(value) {
    // Phase E: gatherings + polls carry public photos like posts — without
    // this, S3-served image URLs throw UNSUPPORTED_MEDIA_URL in prod.
    return [
      "avatars",
      "posts",
      "stories",
      "chat",
      "gatherings",
      "polls",
    ].includes(value);
  }

  buildPublicUrl(bucket, relativePath) {
    const {objectKey} = this.buildObjectKey(
      bucket,
      relativePath,
    );
    return this.buildPublicUrlForObjectKey(objectKey);
  }

  buildPublicUrlForObjectKey(objectKey) {
    const publicBaseUrl = String(this.config.mediaPublicBaseUrl || "").trim();
    const normalizedObjectKey = sanitizeRelativePath(objectKey);

    if (publicBaseUrl) {
      const normalizedBaseUrl = publicBaseUrl.replace(/\/+$/, "");
      return `${normalizedBaseUrl}/${encodePathSegments(
        normalizedObjectKey.split("/"),
      )}`;
    }

    if (!this.config.s3Endpoint) {
      throw new Error(
        "RODNYA_MEDIA_PUBLIC_BASE_URL or RODNYA_S3_ENDPOINT is required for S3 media URLs",
      );
    }

    const normalizedEndpoint = String(this.config.s3Endpoint).trim().replace(
      /\/+$/,
      "",
    );
    return `${normalizedEndpoint}/${this.bucket}/${encodePathSegments(
      normalizedObjectKey.split("/"),
    )}`;
  }

  async ensureReady() {
    await this._client.send(new HeadBucketCommand({Bucket: this.bucket}));
  }

  /// См. LocalMediaStorage.objectExists — та же роль для S3-бэкенда.
  async objectExists(bucket, relativePath) {
    const {objectKey} = this.buildObjectKey(bucket, relativePath);
    try {
      await this._client.send(
        new HeadObjectCommand({Bucket: this.bucket, Key: objectKey}),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  async saveObject({bucket, relativePath, contentType, fileBuffer, uploaderUserId = null}) {
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
        ...(uploaderUserId
          ? {Metadata: {"uploader-user-id": String(uploaderUserId)}}
          : {}),
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

    let normalizedKey;
    if (publicBaseUrl && urlValue.startsWith(publicBaseUrl)) {
      const suffix = decodeURIComponent(
        urlValue.slice(publicBaseUrl.length).replace(/^\/+/, ""),
      );
      normalizedKey = sanitizeRelativePath(suffix);
    } else {
      const pathname = decodeURIComponent(url.pathname).replace(/^\/+/, "");
      const pathParts = pathname.split("/").filter(Boolean);
      if (pathParts[0] === this.bucket) {
        pathParts.shift();
      }
      normalizedKey = sanitizeRelativePath(pathParts.join("/"));
    }

    if (!this.hasAllowedPrefix(normalizedKey)) {
      throw new Error("UNSUPPORTED_MEDIA_URL");
    }

    return normalizedKey;
  }

  async getObjectOwnerInfo(urlValue) {
    const objectKey = this.extractObjectKeyFromUrl(urlValue);
    const afterPrefix = this.hasAllowedPrefix(objectKey)
      ? objectKey.slice(this.prefix.length + 1)
      : objectKey;
    const [, ...restParts] = afterPrefix.split("/").filter(Boolean);
    const relativePath = restParts.join("/");
    let uploaderUserId = null;
    try {
      const head = await this._client.send(
        new HeadObjectCommand({Bucket: this.bucket, Key: objectKey}),
      );
      if (head?.Metadata?.["uploader-user-id"]) {
        uploaderUserId = String(head.Metadata["uploader-user-id"]).trim();
      }
    } catch (_) {
      uploaderUserId = null;
    }
    return {relativePath, uploaderUserId};
  }

  resolveObjectKey(requestedPath) {
    const normalizedPath = sanitizeRelativePath(requestedPath);
    if (this.hasAllowedPrefix(normalizedPath)) {
      return normalizedPath;
    }

    const [bucket, ...restParts] = normalizedPath.split("/").filter(Boolean);
    const mediaPath = restParts.join("/");
    if (!bucket || !mediaPath) {
      throw new Error("INVALID_MEDIA_PATH");
    }

    const {objectKey} = this.buildObjectKey(bucket, mediaPath);
    return objectKey;
  }

  resolvePublicObjectKey(requestedPath) {
    const normalizedPath = sanitizeRelativePath(requestedPath);
    const pathParts = normalizedPath.split("/").filter(Boolean);
    if (pathParts[0] === this.bucket) {
      pathParts.shift();
    }

    const objectKey = pathParts.join("/");
    if (!objectKey || !this.hasAllowedPrefix(objectKey)) {
      if (
        pathParts.length > 1 &&
        this.isLegacyPublicBucket(pathParts[0])
      ) {
        return `${this.prefix}/${objectKey}`;
      }
      throw new Error("UNSUPPORTED_MEDIA_URL");
    }

    return objectKey;
  }

  setObjectResponseHeaders(res, objectMetadata, objectKey = "") {
    // Advertise byte-range support so clients (Android MediaPlayer /
    // audioplayers via UrlSource, video scrubbing, browsers) issue
    // Range requests instead of giving up. Required for non-faststart
    // m4a whose moov atom sits at the end of the file.
    res.setHeader("accept-ranges", "bytes");
    if (objectMetadata.ContentType) {
      res.setHeader("content-type", objectMetadata.ContentType);
    }
    if (
      Number.isFinite(objectMetadata.ContentLength) &&
      objectMetadata.ContentLength >= 0
    ) {
      res.setHeader("content-length", String(objectMetadata.ContentLength));
    }
    if (objectMetadata.ETag) {
      res.setHeader("etag", objectMetadata.ETag);
    }
    if (objectMetadata.CacheControl) {
      res.setHeader("cache-control", objectMetadata.CacheControl);
    }
    applySafeMediaDownloadHeaders(res, {
      contentType: objectMetadata.ContentType,
      filePath: objectKey,
      existingContentDisposition: objectMetadata.ContentDisposition,
    });
    if (objectMetadata.LastModified instanceof Date) {
      res.setHeader(
        "last-modified",
        objectMetadata.LastModified.toUTCString(),
      );
    }
  }

  isMissingObjectError(error) {
    const statusCode = Number(error?.$metadata?.httpStatusCode || 0);
    return (
      statusCode === 404 ||
      error?.name === "NoSuchKey" ||
      error?.name === "NotFound"
    );
  }

  async sendReadableBody(body, res) {
    if (!body) {
      res.status(200).end();
      return;
    }

    if (typeof body.pipe === "function") {
      await new Promise((resolve, reject) => {
        body.on("error", reject);
        res.on("close", resolve);
        body.pipe(res);
      });
      return;
    }

    if (typeof body.transformToWebStream === "function") {
      const webStream = body.transformToWebStream();
      await this.sendReadableBody(Readable.fromWeb(webStream), res);
      return;
    }

    if (typeof body.transformToByteArray === "function") {
      res.end(Buffer.from(await body.transformToByteArray()));
      return;
    }

    if (typeof body.arrayBuffer === "function") {
      res.end(Buffer.from(await body.arrayBuffer()));
      return;
    }

    if (Buffer.isBuffer(body) || typeof body === "string") {
      res.end(body);
      return;
    }

    throw new Error("UNSUPPORTED_MEDIA_BODY");
  }

  isRangeNotSatisfiable(error) {
    const statusCode = Number(error?.$metadata?.httpStatusCode || 0);
    return (
      statusCode === 416 ||
      error?.name === "InvalidRange" ||
      error?.Code === "InvalidRange"
    );
  }

  async sendRangeNotSatisfiable(res, objectKey) {
    res.setHeader("accept-ranges", "bytes");
    try {
      const head = await this._client.send(
        new HeadObjectCommand({Bucket: this.bucket, Key: objectKey}),
      );
      if (Number.isFinite(head.ContentLength)) {
        res.setHeader("content-range", `bytes */${head.ContentLength}`);
      }
    } catch (_) {
      // Best-effort — still return 416 even if the size probe fails.
    }
    res.status(416).end();
  }

  async streamObjectResponse({req, res, objectKey}) {
    const isHeadRequest = String(req.method || "GET").toUpperCase() === "HEAD";
    const rangeHeader =
      (req.headers && req.headers.range) ||
      (typeof req.get === "function" ? req.get("range") : undefined) ||
      undefined;

    try {
      if (isHeadRequest) {
        const headResponse = await this._client.send(
          new HeadObjectCommand({Bucket: this.bucket, Key: objectKey}),
        );
        this.setObjectResponseHeaders(res, headResponse, objectKey);
        res.status(200).end();
        return;
      }

      const commandInput = {Bucket: this.bucket, Key: objectKey};
      if (rangeHeader) {
        // S3 / S3-compatible storage understands Range natively and
        // returns ContentRange + the chunk's ContentLength + a partial
        // Body. We just forward the header and relay the result as 206.
        commandInput.Range = rangeHeader;
      }

      const objectResponse = await this._client.send(
        new GetObjectCommand(commandInput),
      );
      this.setObjectResponseHeaders(res, objectResponse, objectKey);
      if (rangeHeader && objectResponse.ContentRange) {
        res.setHeader("content-range", objectResponse.ContentRange);
        res.status(206);
      }
      await this.sendReadableBody(objectResponse.Body, res);
    } catch (error) {
      if (this.isRangeNotSatisfiable(error)) {
        await this.sendRangeNotSatisfiable(res, objectKey);
        return;
      }
      if (this.isMissingObjectError(error)) {
        throw new Error("MEDIA_FILE_NOT_FOUND");
      }
      throw error;
    }
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

    const objectKey = this.resolveObjectKey(requestedPath);
    const redirectUrl = this.buildPublicUrlForObjectKey(objectKey);
    res.redirect(302, redirectUrl);
  }

  async handlePublicGetRequest(req, res) {
    const requestedPath = decodeURIComponent(String(req.params?.[0] || "").trim());
    if (!requestedPath) {
      throw new Error("INVALID_MEDIA_PATH");
    }

    const objectKey = this.resolvePublicObjectKey(requestedPath);
    await this.streamObjectResponse({req, res, objectKey});
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
        `Unsupported RODNYA_MEDIA_BACKEND value: ${mediaBackend}`,
      );
  }
}

module.exports = {
  LocalMediaStorage,
  S3MediaStorage,
  createMediaStorage,
  sanitizeRelativePath,
};
