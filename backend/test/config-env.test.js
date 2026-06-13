const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const {createConfig} = require("../src/config");

test("createConfig reads postgres pool max from env", () => {
  const previous = process.env.RODNYA_POSTGRES_POOL_MAX;
  process.env.RODNYA_POSTGRES_POOL_MAX = "3";

  try {
    const config = createConfig();
    assert.equal(config.postgresPoolMax, 3);
  } finally {
    if (previous == null) {
      delete process.env.RODNYA_POSTGRES_POOL_MAX;
    } else {
      process.env.RODNYA_POSTGRES_POOL_MAX = previous;
    }
  }
});

test("createConfig читает OTA-апдейтер из env (точные имена переменных)", () => {
  const keys = [
    "RODNYA_LATEST_ANDROID_VERSION_CODE",
    "RODNYA_LATEST_ANDROID_VERSION_NAME",
    "RODNYA_LATEST_ANDROID_APK_URL",
    "RODNYA_MIN_ANDROID_VERSION_CODE",
    "RODNYA_LATEST_ANDROID_NOTES",
    "RODNYA_LATEST_ANDROID_APK_SHA256",
  ];
  const previous = Object.fromEntries(keys.map((k) => [k, process.env[k]]));
  process.env.RODNYA_LATEST_ANDROID_VERSION_CODE = "42";
  process.env.RODNYA_LATEST_ANDROID_VERSION_NAME = "1.0.3";
  process.env.RODNYA_LATEST_ANDROID_APK_URL =
    "https://s3.ru-msk.example/rodnya/rodnya-1.0.3.apk";
  process.env.RODNYA_MIN_ANDROID_VERSION_CODE = "40";
  process.env.RODNYA_LATEST_ANDROID_NOTES = "Чинят чаты";
  process.env.RODNYA_LATEST_ANDROID_APK_SHA256 = "a".repeat(64);

  try {
    const config = createConfig();
    assert.deepEqual(config.latestAndroidUpdate, {
      versionCode: 42,
      versionName: "1.0.3",
      apkUrl: "https://s3.ru-msk.example/rodnya/rodnya-1.0.3.apk",
      minVersionCode: 40,
      notes: "Чинят чаты",
      sha256: "a".repeat(64),
    });
  } finally {
    for (const k of keys) {
      if (previous[k] == null) {
        delete process.env[k];
      } else {
        process.env[k] = previous[k];
      }
    }
  }
});

test("createConfig без OTA-env: versionCode/minVersionCode = 0, строки пустые", () => {
  const keys = [
    "RODNYA_LATEST_ANDROID_VERSION_CODE",
    "RODNYA_LATEST_ANDROID_VERSION_NAME",
    "RODNYA_LATEST_ANDROID_APK_URL",
    "RODNYA_MIN_ANDROID_VERSION_CODE",
    "RODNYA_LATEST_ANDROID_NOTES",
    "RODNYA_LATEST_ANDROID_APK_SHA256",
  ];
  const previous = Object.fromEntries(keys.map((k) => [k, process.env[k]]));
  for (const k of keys) {
    delete process.env[k];
  }

  try {
    const config = createConfig();
    assert.equal(config.latestAndroidUpdate.versionCode, 0);
    assert.equal(config.latestAndroidUpdate.minVersionCode, 0);
    assert.equal(config.latestAndroidUpdate.apkUrl, "");
  } finally {
    for (const k of keys) {
      if (previous[k] == null) {
        delete process.env[k];
      } else {
        process.env[k] = previous[k];
      }
    }
  }
});

test("createConfig derives postgres snapshot cache path from the backend data path", () => {
  const previousDataPath = process.env.RODNYA_BACKEND_DATA_PATH;
  const previousSnapshotCachePath = process.env.RODNYA_POSTGRES_SNAPSHOT_CACHE_PATH;
  process.env.RODNYA_BACKEND_DATA_PATH = "/srv/rodnya/state/dev-db.json";
  delete process.env.RODNYA_POSTGRES_SNAPSHOT_CACHE_PATH;

  try {
    const config = createConfig();
    assert.equal(
      config.postgresSnapshotCachePath,
      path.join(
        path.dirname(process.env.RODNYA_BACKEND_DATA_PATH),
        "postgres-state-cache.json",
      ),
    );
  } finally {
    if (previousDataPath == null) {
      delete process.env.RODNYA_BACKEND_DATA_PATH;
    } else {
      process.env.RODNYA_BACKEND_DATA_PATH = previousDataPath;
    }
    if (previousSnapshotCachePath == null) {
      delete process.env.RODNYA_POSTGRES_SNAPSHOT_CACHE_PATH;
    } else {
      process.env.RODNYA_POSTGRES_SNAPSHOT_CACHE_PATH = previousSnapshotCachePath;
    }
  }
});
