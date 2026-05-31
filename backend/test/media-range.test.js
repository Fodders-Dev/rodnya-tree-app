// Media Range support (2026-05-30): S3MediaStorage must serve byte-range
// requests (206 + Content-Range + Accept-Ranges) so Android MediaPlayer /
// audioplayers can read a non-faststart m4a's trailing moov atom. Bug:
// it used to return 200 + the full body for ranged requests, so playback
// stalled. Drives S3MediaStorage.streamObjectResponse with a fake S3
// client + mock req/res (no live HTTP / live S3).

const test = require("node:test");
const assert = require("node:assert/strict");

const {S3MediaStorage} = require("../src/media-storage");

const TOTAL = 421390;
const OBJECT_KEY = "rodnya/article-audio/rec.m4a";
const REQUESTED_PATH = OBJECT_KEY; // already prefixed with `rodnya/`

function fakeS3Client() {
  return {
    async send(command) {
      const name = command.constructor.name;
      if (name === "HeadObjectCommand") {
        return {ContentType: "audio/m4a", ContentLength: TOTAL};
      }
      // GetObjectCommand
      const range = command.input.Range;
      if (range) {
        const m = /bytes=(\d+)-(\d+)?/.exec(range);
        const start = Number(m[1]);
        const end = m[2] !== undefined ? Number(m[2]) : TOTAL - 1;
        const len = end - start + 1;
        return {
          ContentType: "audio/m4a",
          ContentLength: len,
          ContentRange: `bytes ${start}-${end}/${TOTAL}`,
          Body: Buffer.alloc(len),
        };
      }
      return {
        ContentType: "audio/m4a",
        ContentLength: TOTAL,
        Body: Buffer.alloc(TOTAL),
      };
    },
  };
}

function makeStorage(client) {
  return new S3MediaStorage({
    config: {s3Bucket: "test-bucket", s3Prefix: "rodnya"},
    client,
  });
}

function mockReq({method = "GET", range} = {}) {
  return {
    method,
    headers: range ? {range} : {},
    params: {0: REQUESTED_PATH},
    get(header) {
      return header.toLowerCase() === "range" ? range : undefined;
    },
  };
}

function mockRes() {
  return {
    headers: {},
    statusCode: 200,
    ended: false,
    body: null,
    setHeader(key, value) {
      this.headers[key.toLowerCase()] = value;
    },
    getHeader(key) {
      return this.headers[key.toLowerCase()];
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    end(buf) {
      this.ended = true;
      this.body = buf ?? null;
      return this;
    },
    on() {},
  };
}

test("full GET advertises Accept-Ranges + 200 + full length", async () => {
  const storage = makeStorage(fakeS3Client());
  const res = mockRes();
  await storage.handlePublicGetRequest(mockReq(), res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.getHeader("accept-ranges"), "bytes");
  assert.equal(res.getHeader("content-length"), String(TOTAL));
  assert.equal(res.getHeader("content-type"), "audio/m4a");
});

test("ranged GET → 206 + Content-Range + chunk length", async () => {
  const storage = makeStorage(fakeS3Client());
  const res = mockRes();
  await storage.handlePublicGetRequest(
    mockReq({range: "bytes=0-99"}),
    res,
  );

  assert.equal(res.statusCode, 206);
  assert.equal(res.getHeader("content-range"), `bytes 0-99/${TOTAL}`);
  assert.equal(res.getHeader("accept-ranges"), "bytes");
  assert.equal(res.getHeader("content-length"), "100");
});

test("open-ended range (bytes=N-) → 206 to end of file", async () => {
  const storage = makeStorage(fakeS3Client());
  const res = mockRes();
  await storage.handlePublicGetRequest(
    mockReq({range: "bytes=400000-"}),
    res,
  );

  assert.equal(res.statusCode, 206);
  assert.equal(res.getHeader("content-range"), `bytes 400000-${TOTAL - 1}/${TOTAL}`);
});

test("HEAD → 200 + Accept-Ranges + full length, no body", async () => {
  const storage = makeStorage(fakeS3Client());
  const res = mockRes();
  await storage.handlePublicGetRequest(mockReq({method: "HEAD"}), res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.getHeader("accept-ranges"), "bytes");
  assert.equal(res.getHeader("content-length"), String(TOTAL));
  assert.equal(res.body, null);
});

test("unsatisfiable range → 416 + Content-Range bytes */total", async () => {
  const client = {
    async send(command) {
      if (command.constructor.name === "HeadObjectCommand") {
        return {ContentLength: TOTAL};
      }
      const err = new Error("Requested Range Not Satisfiable");
      err.name = "InvalidRange";
      err.$metadata = {httpStatusCode: 416};
      throw err;
    },
  };
  const storage = makeStorage(client);
  const res = mockRes();
  await storage.handlePublicGetRequest(
    mockReq({range: "bytes=999999999-"}),
    res,
  );

  assert.equal(res.statusCode, 416);
  assert.equal(res.getHeader("accept-ranges"), "bytes");
  assert.equal(res.getHeader("content-range"), `bytes */${TOTAL}`);
});
