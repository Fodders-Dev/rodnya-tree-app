const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const {Writable, Readable} = require("node:stream");

const {
  LocalMediaStorage,
  S3MediaStorage,
} = require("../src/media-storage");

test("local media storage saves, serves and deletes files", async () => {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "lineage-media-"));
  const storage = new LocalMediaStorage({
    config: {
      mediaRootPath: tempDir,
      publicApiUrl: "https://api.rodnya-tree.ru",
    },
  });

  try {
    await storage.ensureReady();
    const saved = await storage.saveObject({
      req: null,
      bucket: "avatars",
      relativePath: "user-1/photo.txt",
      contentType: "text/plain",
      fileBuffer: Buffer.from("hello", "utf8"),
    });

    assert.equal(
      saved.url,
      "https://api.rodnya-tree.ru/media/avatars/user-1/photo.txt",
    );
    assert.equal(saved.size, 5);

    const sentFiles = [];
    await storage.handleGetRequest(
      {params: {"0": "avatars/user-1/photo.txt"}},
      {
        sendFile(filePath) {
          sentFiles.push(filePath);
        },
      },
    );
    assert.equal(sentFiles.length, 1);
    assert.match(sentFiles[0], /avatars[\\/]user-1[\\/]photo\.txt$/);

    await storage.deleteObjectByUrl(saved.url);
    await assert.rejects(
      () => fs.access(path.join(tempDir, "avatars", "user-1", "photo.txt")),
    );
  } finally {
    await fs.rm(tempDir, {recursive: true, force: true});
  }
});

test("s3 media storage uses object storage client and redirects reads", async () => {
  const commands = [];
  const storage = new S3MediaStorage({
    config: {
      s3Bucket: "rodnya-media",
      s3Region: "ru-msk",
      s3Endpoint: "https://s3.example.ru",
      s3Prefix: "lineage",
      mediaPublicBaseUrl: "https://cdn.rodnya-tree.ru/media",
      s3ForcePathStyle: true,
    },
    client: {
      async send(command) {
        commands.push({
          name: command.constructor.name,
          input: command.input,
        });
        return {};
      },
    },
  });

  const saved = await storage.saveObject({
    bucket: "chat",
    relativePath: "room-1/clip.mp4",
    contentType: "video/mp4",
    fileBuffer: Buffer.from("video"),
  });
  assert.equal(
    saved.url,
    "https://cdn.rodnya-tree.ru/media/lineage/chat/room-1/clip.mp4",
  );
  assert.equal(commands[0].name, "PutObjectCommand");
  assert.equal(commands[0].input.Bucket, "rodnya-media");
  assert.equal(commands[0].input.Key, "lineage/chat/room-1/clip.mp4");

  const redirects = [];
  await storage.handleGetRequest(
    {params: {"0": "chat/room-1/clip.mp4"}},
    {
      redirect(statusCode, url) {
        redirects.push({statusCode, url});
      },
    },
  );
  assert.deepEqual(redirects, [
    {
      statusCode: 302,
      url: "https://cdn.rodnya-tree.ru/media/lineage/chat/room-1/clip.mp4",
    },
  ]);

  await storage.handleGetRequest(
    {params: {"0": "lineage/chat/room-1/clip.mp4"}},
    {
      redirect(statusCode, url) {
        redirects.push({statusCode, url});
      },
    },
  );
  assert.deepEqual(redirects[1], {
    statusCode: 302,
    url: "https://cdn.rodnya-tree.ru/media/lineage/chat/room-1/clip.mp4",
  });

  await storage.deleteObjectByUrl(saved.url);
  assert.equal(commands[1].name, "DeleteObjectCommand");
  assert.equal(commands[1].input.Key, "lineage/chat/room-1/clip.mp4");
});

test("s3 media storage streams public storage urls", async () => {
  const commands = [];
  const storage = new S3MediaStorage({
    config: {
      s3Bucket: "rodnya-media",
      s3Region: "ru-msk",
      s3Endpoint: "http://127.0.0.1:9000",
      s3Prefix: "lineage",
      mediaPublicBaseUrl: "https://api.rodnya-tree.ru/storage/rodnya-media",
      s3ForcePathStyle: true,
    },
    client: {
      async send(command) {
        commands.push({
          name: command.constructor.name,
          input: command.input,
        });
        if (command.constructor.name === "GetObjectCommand") {
          return {
            ContentType: "image/jpeg",
            ContentLength: 5,
            ETag: '"abc123"',
            Body: Readable.from([Buffer.from("photo")]),
          };
        }
        throw new Error(`Unexpected command: ${command.constructor.name}`);
      },
    },
  });

  class MockResponse extends Writable {
    constructor() {
      super();
      this.headers = {};
      this.statusCode = 200;
      this.bodyChunks = [];
      this.on("finish", () => this.emit("close"));
    }

    _write(chunk, encoding, callback) {
      this.bodyChunks.push(Buffer.from(chunk));
      callback();
    }

    setHeader(name, value) {
      this.headers[String(name).toLowerCase()] = value;
    }

    status(code) {
      this.statusCode = code;
      return this;
    }
  }

  const response = new MockResponse();
  await storage.handlePublicGetRequest(
    {
      method: "GET",
      params: {"0": "rodnya-media/lineage/posts/post-1.jpg"},
    },
    response,
  );

  assert.equal(commands.length, 1);
  assert.equal(commands[0].name, "GetObjectCommand");
  assert.equal(commands[0].input.Bucket, "rodnya-media");
  assert.equal(commands[0].input.Key, "lineage/posts/post-1.jpg");
  assert.equal(response.headers["content-type"], "image/jpeg");
  assert.equal(response.headers["content-length"], "5");
  assert.equal(Buffer.concat(response.bodyChunks).toString("utf8"), "photo");
});
