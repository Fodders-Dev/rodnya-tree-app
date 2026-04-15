const test = require("node:test");
const assert = require("node:assert/strict");

const {createApp} = require("../src/app");

function createTestConfig() {
  return {
    corsOrigin: "*",
    authRateLimitMax: 0,
    defaultRateLimitMax: 0,
    mutationRateLimitMax: 0,
    uploadRateLimitMax: 0,
    safetyRateLimitMax: 0,
    rateLimitWindowMs: 60_000,
    publicApiUrl: "https://api.rodnya-tree.ru",
    publicAppUrl: "https://rodnya-tree.ru",
  };
}

test("createApp exposes public storage route for media backends", async () => {
  const requestedPaths = [];
  const app = createApp({
    store: {},
    config: createTestConfig(),
    pushGateway: {},
    mediaStorage: {
      mediaMode: "s3",
      async handleGetRequest(req, res) {
        res.status(500).send(`wrong-route:${req.params[0]}`);
      },
      async handlePublicGetRequest(req, res) {
        requestedPaths.push(req.params[0]);
        res.status(200).json({ok: true});
      },
    },
  });

  const server = await new Promise((resolve) => {
    const nextServer = app.listen(0, "127.0.0.1", () => resolve(nextServer));
  });

  try {
    const address = server.address();
    const response = await fetch(
      `http://127.0.0.1:${address.port}/storage/rodnya-media/lineage/posts/post-1.jpg`,
    );

    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {ok: true});
    assert.deepEqual(requestedPaths, [
      "rodnya-media/lineage/posts/post-1.jpg",
    ]);
  } finally {
    await new Promise((resolve, reject) => {
      server.close((error) => {
        if (error) {
          reject(error);
          return;
        }
        resolve();
      });
    });
  }
});
