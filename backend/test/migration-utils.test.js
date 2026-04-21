const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");

const {
  collectLocalMediaObjects,
  hashSnapshot,
  inferMediaContentType,
  summarizeSnapshot,
} = require("../src/migration-utils");

test("summarizeSnapshot counts known collections and hash is stable", () => {
  const snapshot = {
    users: [{id: "u-1"}],
    chats: [{id: "c-1"}, {id: "c-2"}],
    messages: [{id: "m-1"}],
  };

  const summary = summarizeSnapshot(snapshot);
  assert.equal(summary.users, 1);
  assert.equal(summary.chats, 2);
  assert.equal(summary.messages, 1);
  assert.equal(summary.notifications, 0);
  assert.equal(hashSnapshot(snapshot), hashSnapshot({...snapshot}));
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
