const fs = require("node:fs/promises");
const path = require("node:path");

async function ensureDir(dirPath) {
  await fs.mkdir(dirPath, {recursive: true});
}

async function pathExists(targetPath) {
  try {
    await fs.access(targetPath);
    return true;
  } catch (_) {
    return false;
  }
}

async function resolveRepoRoot() {
  const candidates = [
    process.cwd(),
    path.resolve(__dirname, ".."),
  ];

  for (const candidate of candidates) {
    if (!candidate) {
      continue;
    }
    const buildWebRoot = path.join(candidate, "build", "web");
    const sourceWebRoot = path.join(candidate, "web");
    if (await pathExists(buildWebRoot) && await pathExists(sourceWebRoot)) {
      return candidate;
    }
  }

  throw new Error(
    "Could not resolve repository root with build/web and web directories.",
  );
}

async function copyRecursive(sourcePath, targetPath) {
  const stats = await fs.stat(sourcePath);
  if (stats.isDirectory()) {
    await ensureDir(targetPath);
    const entries = await fs.readdir(sourcePath, {withFileTypes: true});
    for (const entry of entries) {
      await copyRecursive(
        path.join(sourcePath, entry.name),
        path.join(targetPath, entry.name),
      );
    }
    return;
  }

  await ensureDir(path.dirname(targetPath));
  await fs.copyFile(sourcePath, targetPath);
}

async function collectAssetFiles(rootPath, currentPath = rootPath) {
  const entries = await fs.readdir(currentPath, {withFileTypes: true});
  const files = [];
  for (const entry of entries) {
    const entryPath = path.join(currentPath, entry.name);
    if (entry.isDirectory()) {
      files.push(...await collectAssetFiles(rootPath, entryPath));
      continue;
    }

    const relativePath = path
      .relative(rootPath, entryPath)
      .split(path.sep)
      .join("/");
    if (
      relativePath === "AssetManifest.json" ||
      relativePath === "AssetManifest.bin.json" ||
      relativePath === "FontManifest.json"
    ) {
      continue;
    }
    files.push(relativePath);
  }
  return files.sort();
}

async function readAndroidFontManifest(repoRoot) {
  const candidates = [
    path.join(
      repoRoot,
      "build",
      "app",
      "intermediates",
      "flutter",
      "rustoreRelease",
      "flutter_assets",
      "FontManifest.json",
    ),
    path.join(repoRoot, "build", "unit_test_assets", "FontManifest.json"),
  ];

  for (const candidate of candidates) {
    if (!await pathExists(candidate)) {
      continue;
    }
    try {
      const content = await fs.readFile(candidate, "utf8");
      const parsed = JSON.parse(content);
      if (Array.isArray(parsed)) {
        return parsed;
      }
    } catch (_) {}
  }

  return [];
}

async function resolveFlutterAssetSource(repoRoot) {
  const candidates = [
    path.join(repoRoot, "build", "unit_test_assets"),
    path.join(
      repoRoot,
      "build",
      "app",
      "intermediates",
      "flutter",
      "rustoreRelease",
      "flutter_assets",
    ),
    path.join(
      repoRoot,
      "build",
      "app",
      "intermediates",
      "flutter",
      "devRelease",
      "flutter_assets",
    ),
  ];

  for (const candidate of candidates) {
    if (await pathExists(candidate)) {
      return candidate;
    }
  }

  return null;
}

function filterFontManifest(fontManifest, assetFiles) {
  const assetSet = new Set(assetFiles);
  const filtered = fontManifest
    .map((entry) => {
      if (!entry || typeof entry !== "object") {
        return null;
      }

      const fonts = Array.isArray(entry.fonts)
        ? entry.fonts.filter((font) => {
          const asset = font?.asset;
          return typeof asset === "string" && assetSet.has(asset);
        })
        : [];

      if (!fonts.length || typeof entry.family !== "string") {
        return null;
      }

      return {
        family: entry.family,
        fonts,
      };
    })
    .filter(Boolean);

  if (filtered.length > 0) {
    return filtered;
  }

  const fallbackManifest = [];
  if (assetSet.has("fonts/MaterialIcons-Regular.otf")) {
    fallbackManifest.push({
      family: "MaterialIcons",
      fonts: [{asset: "fonts/MaterialIcons-Regular.otf"}],
    });
  }
  if (assetSet.has("packages/cupertino_icons/assets/CupertinoIcons.ttf")) {
    fallbackManifest.push({
      family: "packages/cupertino_icons/CupertinoIcons",
      fonts: [{asset: "packages/cupertino_icons/assets/CupertinoIcons.ttf"}],
    });
  }
  return fallbackManifest;
}

async function writeGeneratedManifests(repoRoot) {
  const assetRoot = path.join(repoRoot, "build", "web", "assets");
  await ensureDir(assetRoot);

  const assetFiles = await collectAssetFiles(assetRoot);
  const assetManifest = Object.fromEntries(
    assetFiles.map((assetPath) => [assetPath, [assetPath]]),
  );
  const fontManifest = filterFontManifest(
    await readAndroidFontManifest(repoRoot),
    assetFiles,
  );

  await fs.writeFile(
    path.join(assetRoot, "AssetManifest.json"),
    `${JSON.stringify(assetManifest)}\n`,
    "utf8",
  );
  await fs.writeFile(
    path.join(assetRoot, "AssetManifest.bin.json"),
    `${JSON.stringify(assetManifest)}\n`,
    "utf8",
  );
  await fs.writeFile(
    path.join(assetRoot, "FontManifest.json"),
    `${JSON.stringify(fontManifest)}\n`,
    "utf8",
  );

  return {
    assetCount: assetFiles.length,
    fontCount: fontManifest.length,
  };
}

async function main() {
  const repoRoot = await resolveRepoRoot();
  const buildWebRoot = path.join(repoRoot, "build", "web");
  const sourceWebRoot = path.join(repoRoot, "web");
  const buildWebAssetRoot = path.join(buildWebRoot, "assets");
  const entriesToSync = [
    "icons",
    "favicon.png",
    "manifest.json",
    "push",
    "max_auth.html",
    "telegram_login.html",
  ];

  await fs.access(buildWebRoot);
  await ensureDir(buildWebAssetRoot);

  for (const entry of entriesToSync) {
    const sourcePath = path.join(sourceWebRoot, entry);
    const targetPath = path.join(buildWebRoot, entry);
    await copyRecursive(sourcePath, targetPath);
  }

  const flutterAssetSource = await resolveFlutterAssetSource(repoRoot);
  if (flutterAssetSource) {
    for (const entry of ["assets", "fonts", "packages", "shaders"]) {
      const sourcePath = path.join(flutterAssetSource, entry);
      if (!await pathExists(sourcePath)) {
        continue;
      }
      await copyRecursive(sourcePath, path.join(buildWebAssetRoot, entry));
    }
  }

  const faviconPngPath = path.join(sourceWebRoot, "favicon.png");
  const faviconIcoPath = path.join(buildWebRoot, "favicon.ico");
  if (await pathExists(faviconPngPath)) {
    await fs.copyFile(faviconPngPath, faviconIcoPath);
  }

  const manifestSummary = await writeGeneratedManifests(repoRoot);

  process.stdout.write(
    `[sync_web_shell_assets] synced ${entriesToSync.join(", ")} and favicon.ico fallback into build/web; generated ${manifestSummary.assetCount} assets and ${manifestSummary.fontCount} font families\n`,
  );
}

main().catch((error) => {
  console.error("[sync_web_shell_assets] failed", error);
  process.exitCode = 1;
});
