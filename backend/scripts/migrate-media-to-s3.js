#!/usr/bin/env node

const fs = require("node:fs/promises");

const {
  CreateBucketCommand,
  HeadBucketCommand,
  PutBucketPolicyCommand,
  S3Client,
} = require("@aws-sdk/client-s3");

const {createConfig} = require("../src/config");
const {S3MediaStorage} = require("../src/media-storage");
const {
  collectLocalMediaObjects,
  formatBytes,
  inferMediaContentType,
} = require("../src/migration-utils");

function parseArgs(argv) {
  const result = {
    createBucket: false,
    dryRun: false,
    publicRead: false,
    sourceRoot: "",
  };

  for (const argument of argv) {
    if (argument === "--dry-run") {
      result.dryRun = true;
      continue;
    }
    if (argument === "--create-bucket") {
      result.createBucket = true;
      continue;
    }
    if (argument === "--public-read") {
      result.publicRead = true;
      continue;
    }
    if (argument.startsWith("--source-root=")) {
      result.sourceRoot = argument.slice("--source-root=".length);
    }
  }

  return result;
}

async function ensureBucket(config) {
  const client = new S3Client({
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

  try {
    await client.send(new HeadBucketCommand({Bucket: config.s3Bucket}));
    console.log(`[media-migration] bucket already exists: ${config.s3Bucket}`);
  } catch (error) {
    const statusCode = Number(error?.$metadata?.httpStatusCode || 0);
    if (statusCode && statusCode !== 404) {
      throw error;
    }
    await client.send(new CreateBucketCommand({Bucket: config.s3Bucket}));
    console.log(`[media-migration] created bucket: ${config.s3Bucket}`);
  }

  return client;
}

async function ensurePublicReadPolicy(client, bucket) {
  const policy = {
    Version: "2012-10-17",
    Statement: [
      {
        Sid: "AllowPublicReadForMediaObjects",
        Effect: "Allow",
        Principal: "*",
        Action: ["s3:GetObject"],
        Resource: [`arn:aws:s3:::${bucket}/*`],
      },
    ],
  };

  await client.send(
    new PutBucketPolicyCommand({
      Bucket: bucket,
      Policy: JSON.stringify(policy),
    }),
  );
  console.log(`[media-migration] ensured public read policy for bucket: ${bucket}`);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const config = createConfig();
  const sourceRoot = args.sourceRoot || config.mediaRootPath;
  const mediaObjects = await collectLocalMediaObjects(sourceRoot);
  const totalBytes = mediaObjects.reduce((sum, entry) => sum + entry.sizeBytes, 0);

  console.log(`[media-migration] source root: ${sourceRoot}`);
  console.log(
    `[media-migration] found ${mediaObjects.length} files (${formatBytes(totalBytes)})`,
  );

  if (args.dryRun) {
    console.log("[media-migration] dry-run complete, object storage upload skipped");
    return;
  }

  if (args.createBucket) {
    const client = await ensureBucket(config);
    if (args.publicRead) {
      await ensurePublicReadPolicy(client, config.s3Bucket);
    }
  }

  const storage = new S3MediaStorage({config});
  await storage.ensureReady();

  for (const entry of mediaObjects) {
    const fileBuffer = await fs.readFile(entry.absolutePath);
    const contentType = inferMediaContentType(entry.absolutePath);
    const result = await storage.saveObject({
      bucket: entry.bucket,
      relativePath: entry.relativePath,
      contentType,
      fileBuffer,
    });
    console.log(
      `[media-migration] uploaded ${entry.bucket}/${entry.relativePath} -> ${result.url}`,
    );
  }

  console.log("[media-migration] object storage migration completed");
}

main().catch((error) => {
  console.error("[media-migration] failed:", error);
  process.exitCode = 1;
});
