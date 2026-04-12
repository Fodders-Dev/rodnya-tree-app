const fs = require("node:fs/promises");
const path = require("node:path");

async function ensureDir(dirPath) {
  await fs.mkdir(dirPath, {recursive: true});
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

async function main() {
  const repoRoot = path.resolve(__dirname, "..");
  const buildWebRoot = path.join(repoRoot, "build", "web");
  const sourceWebRoot = path.join(repoRoot, "web");
  const entriesToSync = [
    "icons",
    "favicon.png",
    "manifest.json",
    "push",
  ];

  await fs.access(buildWebRoot);

  for (const entry of entriesToSync) {
    const sourcePath = path.join(sourceWebRoot, entry);
    const targetPath = path.join(buildWebRoot, entry);
    await copyRecursive(sourcePath, targetPath);
  }

  process.stdout.write(
    `[sync_web_shell_assets] synced ${entriesToSync.join(", ")} into build/web\n`,
  );
}

main().catch((error) => {
  console.error("[sync_web_shell_assets] failed", error);
  process.exitCode = 1;
});
