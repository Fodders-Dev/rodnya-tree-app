const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");

const {
  backfillPersonIdentities,
  collectLocalMediaObjects,
  hashSnapshot,
  inferMediaContentType,
  summarizeSnapshot,
} = require("../src/migration-utils");

test("summarizeSnapshot counts known collections and hash is stable", () => {
  const snapshot = {
    users: [{id: "u-1"}],
    personIdentities: [{id: "identity-1"}],
    chats: [{id: "c-1"}, {id: "c-2"}],
    messages: [{id: "m-1"}],
  };

  const summary = summarizeSnapshot(snapshot);
  assert.equal(summary.users, 1);
  assert.equal(summary.personIdentities, 1);
  assert.equal(summary.chats, 2);
  assert.equal(summary.messages, 1);
  assert.equal(summary.notifications, 0);
  assert.equal(hashSnapshot(snapshot), hashSnapshot({...snapshot}));
});

test("backfillPersonIdentities creates stable identities for legacy persons", () => {
  const ids = ["identity-a", "identity-b"];
  const snapshot = {
    persons: [
      {id: "person-1", treeId: "tree-1", identityId: null},
      {id: "person-2", treeId: "tree-1"},
    ],
    personIdentities: [],
  };

  const migration = backfillPersonIdentities(snapshot, {
    idFactory: () => ids.shift(),
    now: () => "2026-04-29T00:00:00.000Z",
  });

  assert.equal(migration.changed, true);
  assert.deepEqual(
    snapshot.persons.map((person) => person.identityId),
    ["identity-a", "identity-b"],
  );
  assert.deepEqual(snapshot.personIdentities, [
    {
      id: "identity-a",
      userId: null,
      personIds: ["person-1"],
      createdAt: "2026-04-29T00:00:00.000Z",
      updatedAt: "2026-04-29T00:00:00.000Z",
    },
    {
      id: "identity-b",
      userId: null,
      personIds: ["person-2"],
      createdAt: "2026-04-29T00:00:00.000Z",
      updatedAt: "2026-04-29T00:00:00.000Z",
    },
  ]);

  const secondRun = backfillPersonIdentities(snapshot, {
    idFactory: () => {
      throw new Error("idFactory should not be called");
    },
    now: () => "2026-04-29T01:00:00.000Z",
  });
  assert.equal(secondRun.changed, false);
  assert.equal(snapshot.personIdentities.length, 2);
});

test("backfillPersonIdentities preserves existing identity ids", () => {
  const snapshot = {
    persons: [{id: "person-1", treeId: "tree-1", identityId: "identity-existing"}],
    personIdentities: [],
  };

  const migration = backfillPersonIdentities(snapshot, {
    idFactory: () => "identity-new",
    now: () => "2026-04-29T00:00:00.000Z",
  });

  assert.equal(migration.changed, true);
  assert.equal(snapshot.persons[0].identityId, "identity-existing");
  assert.deepEqual(snapshot.personIdentities[0], {
    id: "identity-existing",
    userId: null,
    personIds: ["person-1"],
    createdAt: "2026-04-29T00:00:00.000Z",
    updatedAt: "2026-04-29T00:00:00.000Z",
  });
});

test("inferMediaContentType covers common media extensions", () => {
  assert.equal(inferMediaContentType("photo.JPG"), "image/jpeg");
  assert.equal(inferMediaContentType("clip.mp4"), "video/mp4");
  assert.equal(inferMediaContentType("voice.ogg"), "audio/ogg");
  assert.equal(inferMediaContentType("unknown.bin"), "application/octet-stream");
});

test("collectLocalMediaObjects maps bucket-relative media layout", async () => {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-media-"));
  const imagePath = path.join(tempDir, "chat", "2026", "photo.jpg");
  const audioPath = path.join(tempDir, "voice", "note.ogg");

  await fs.mkdir(path.dirname(imagePath), {recursive: true});
  await fs.mkdir(path.dirname(audioPath), {recursive: true});
  await fs.writeFile(imagePath, Buffer.from("jpeg"));
  await fs.writeFile(audioPath, Buffer.from("ogg"));

  const result = await collectLocalMediaObjects(tempDir);
  const normalized = result
    .map((entry) => `${entry.bucket}/${entry.relativePath}`)
    .sort((left, right) => left.localeCompare(right));

  assert.deepEqual(normalized, ["chat/2026/photo.jpg", "voice/note.ogg"]);
});
