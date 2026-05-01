const fs = require("node:fs/promises");
const path = require("node:path");
const crypto = require("node:crypto");

const SNAPSHOT_COLLECTION_KEYS = [
  "users",
  "sessions",
  "trees",
  "persons",
  "personIdentities",
  "circles",
  "circleMembers",
  "relations",
  "chats",
  "chatDrafts",
  "chatPins",
  "messages",
  "relationRequests",
  "treeInvitations",
  "notifications",
  "posts",
  "stories",
  "comments",
  "reports",
  "blocks",
  "pushDevices",
  "pushDeliveries",
];

const MIME_TYPES_BY_EXTENSION = new Map([
  [".aac", "audio/aac"],
  [".avif", "image/avif"],
  [".gif", "image/gif"],
  [".heic", "image/heic"],
  [".heif", "image/heif"],
  [".jpeg", "image/jpeg"],
  [".jpg", "image/jpeg"],
  [".json", "application/json"],
  [".m4a", "audio/mp4"],
  [".mov", "video/quicktime"],
  [".mp3", "audio/mpeg"],
  [".mp4", "video/mp4"],
  [".oga", "audio/ogg"],
  [".ogg", "audio/ogg"],
  [".pdf", "application/pdf"],
  [".png", "image/png"],
  [".svg", "image/svg+xml"],
  [".txt", "text/plain; charset=utf-8"],
  [".wav", "audio/wav"],
  [".webm", "video/webm"],
  [".webp", "image/webp"],
]);

function summarizeSnapshot(snapshot) {
  return Object.fromEntries(
    SNAPSHOT_COLLECTION_KEYS.map((key) => [
      key,
      Array.isArray(snapshot?.[key]) ? snapshot[key].length : 0,
    ]),
  );
}

function formatSnapshotSummary(summary) {
  return SNAPSHOT_COLLECTION_KEYS.map((key) => `${key}=${summary[key] || 0}`).join(
    ", ",
  );
}

function stableSerialize(value) {
  if (Array.isArray(value)) {
    return `[${value.map((entry) => stableSerialize(entry)).join(",")}]`;
  }
  if (value && typeof value === "object") {
    const keys = Object.keys(value).sort((left, right) =>
      left.localeCompare(right),
    );
    return `{${keys
      .map((key) => `${JSON.stringify(key)}:${stableSerialize(value[key])}`)
      .join(",")}}`;
  }
  return JSON.stringify(value);
}

function hashSnapshot(snapshot) {
  return crypto
    .createHash("sha256")
    .update(stableSerialize(snapshot))
    .digest("hex");
}

function normalizeNullableString(value) {
  const normalized = String(value || "").trim();
  return normalized ? normalized : null;
}

function normalizeIdList(value) {
  return Array.from(
    new Set(
      (Array.isArray(value) ? value : [])
        .map((entry) => normalizeNullableString(entry))
        .filter(Boolean),
    ),
  ).sort((left, right) => left.localeCompare(right));
}

function backfillPersonIdentities(
  snapshot,
  {
    idFactory = () => crypto.randomUUID(),
    now = () => new Date().toISOString(),
  } = {},
) {
  const target = snapshot && typeof snapshot === "object" ? snapshot : {};
  const persons = Array.isArray(target.persons) ? target.persons : [];
  const rawIdentities = Array.isArray(target.personIdentities)
    ? target.personIdentities
    : [];
  const beforeHash = hashSnapshot({
    persons,
    personIdentities: rawIdentities,
  });
  const timestamp = now();
  const identitiesById = new Map();
  let createdCount = 0;
  let linkedPersonCount = 0;

  target.persons = persons;

  function upsertIdentity(rawIdentity = {}, fallbackId = null) {
    const identityId =
      normalizeNullableString(rawIdentity?.id) ||
      normalizeNullableString(fallbackId) ||
      normalizeNullableString(idFactory());
    if (!identityId) {
      return null;
    }

    const existing = identitiesById.get(identityId);
    const nextPersonIds = normalizeIdList([
      ...normalizeIdList(existing?.personIds),
      ...normalizeIdList(rawIdentity?.personIds),
    ]);

    if (existing) {
      identitiesById.set(identityId, {
        ...existing,
        ...rawIdentity,
        id: identityId,
        userId:
          normalizeNullableString(existing.userId) ||
          normalizeNullableString(rawIdentity?.userId),
        personIds: nextPersonIds,
        createdAt: existing.createdAt || rawIdentity?.createdAt || timestamp,
        updatedAt: rawIdentity?.updatedAt || existing.updatedAt || timestamp,
      });
      return identitiesById.get(identityId);
    }

    const identity = {
      ...rawIdentity,
      id: identityId,
      userId: normalizeNullableString(rawIdentity?.userId),
      personIds: nextPersonIds,
      createdAt: rawIdentity?.createdAt || timestamp,
      updatedAt: rawIdentity?.updatedAt || timestamp,
    };
    identitiesById.set(identityId, identity);
    return identity;
  }

  for (const identity of rawIdentities) {
    upsertIdentity(identity);
  }

  const identityIdByPersonId = new Map();
  for (const identity of identitiesById.values()) {
    for (const personId of normalizeIdList(identity.personIds)) {
      if (!identityIdByPersonId.has(personId)) {
        identityIdByPersonId.set(personId, identity.id);
      }
    }
  }

  for (const person of persons) {
    if (!person || typeof person !== "object") {
      continue;
    }

    const personId = normalizeNullableString(person.id);
    if (!personId) {
      continue;
    }

    const existingIdentityId =
      normalizeNullableString(person.identityId) ||
      identityIdByPersonId.get(personId) ||
      null;
    let identity = existingIdentityId
      ? identitiesById.get(existingIdentityId)
      : null;

    if (!identity) {
      identity = upsertIdentity(
        {
          id: existingIdentityId || undefined,
          personIds: [personId],
        },
        existingIdentityId,
      );
      createdCount += 1;
    }

    if (!identity) {
      continue;
    }

    if (person.identityId !== identity.id) {
      person.identityId = identity.id;
      linkedPersonCount += 1;
    }

    const nextPersonIds = normalizeIdList([
      ...(identity.personIds || []),
      personId,
    ]);
    if (nextPersonIds.length !== normalizeIdList(identity.personIds).length) {
      linkedPersonCount += 1;
    }
    identity.personIds = nextPersonIds;
  }

  target.personIdentities = Array.from(identitiesById.values())
    .map((identity) => ({
      ...identity,
      id: normalizeNullableString(identity.id),
      userId: normalizeNullableString(identity.userId),
      personIds: normalizeIdList(identity.personIds),
      createdAt: identity.createdAt || timestamp,
      updatedAt: identity.updatedAt || timestamp,
    }))
    .filter(
      (identity) =>
        identity.id &&
        (identity.userId ||
          (Array.isArray(identity.personIds) && identity.personIds.length > 0)),
    );

  const afterHash = hashSnapshot({
    persons: target.persons,
    personIdentities: target.personIdentities,
  });

  return {
    snapshot: target,
    changed: beforeHash !== afterHash,
    createdCount,
    linkedPersonCount,
  };
}

async function walkFiles(rootPath) {
  const entries = await fs.readdir(rootPath, {withFileTypes: true});
  const nestedPaths = [];

  for (const entry of entries) {
    const resolvedPath = path.join(rootPath, entry.name);
    if (entry.isDirectory()) {
      nestedPaths.push(...(await walkFiles(resolvedPath)));
      continue;
    }
    if (entry.isFile()) {
      nestedPaths.push(resolvedPath);
    }
  }

  return nestedPaths;
}

async function collectLocalMediaObjects(rootPath) {
  const normalizedRootPath = path.resolve(rootPath);
  const absoluteFilePaths = await walkFiles(normalizedRootPath);

  return Promise.all(
    absoluteFilePaths.map(async (absolutePath) => {
      const relativePath = path
        .relative(normalizedRootPath, absolutePath)
        .replace(/\\/g, "/");
      const [bucket, ...restParts] = relativePath.split("/").filter(Boolean);
      if (!bucket || restParts.length === 0) {
        throw new Error(
          `Unexpected media layout for ${absolutePath}. Expected <bucket>/<path>.`,
        );
      }

      const stat = await fs.stat(absolutePath);
      return {
        absolutePath,
        bucket,
        relativePath: restParts.join("/"),
        sizeBytes: stat.size,
      };
    }),
  );
}

function inferMediaContentType(filePath) {
  const extension = path.extname(String(filePath || "")).trim().toLowerCase();
  return MIME_TYPES_BY_EXTENSION.get(extension) || "application/octet-stream";
}

function formatBytes(sizeBytes) {
  if (!Number.isFinite(sizeBytes) || sizeBytes < 1024) {
    return `${Math.max(0, Number(sizeBytes) || 0)} B`;
  }
  const units = ["KB", "MB", "GB", "TB"];
  let value = sizeBytes / 1024;
  let index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index += 1;
  }
  return `${value.toFixed(1)} ${units[index]}`;
}

module.exports = {
  SNAPSHOT_COLLECTION_KEYS,
  backfillPersonIdentities,
  collectLocalMediaObjects,
  formatBytes,
  formatSnapshotSummary,
  hashSnapshot,
  inferMediaContentType,
  summarizeSnapshot,
};
