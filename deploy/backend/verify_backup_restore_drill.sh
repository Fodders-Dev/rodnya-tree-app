#!/usr/bin/env bash
set -euo pipefail

BACKUP_ROOT="${1:-/opt/rodnya/backups}"
TARGET_DIR="${2:-/tmp/rodnya-backup-restore-drill}"

latest_backup_dir="$(find "$BACKUP_ROOT" -maxdepth 1 -type d -name '*-backend' | sort | tail -n 1)"
if [[ -z "${latest_backup_dir:-}" ]]; then
  echo "[backup-restore-drill] no backend backup directories found in $BACKUP_ROOT" >&2
  exit 1
fi

archive_path="$latest_backup_dir/backend.tgz"
if [[ ! -f "$archive_path" ]]; then
  echo "[backup-restore-drill] latest backup does not contain backend.tgz: $archive_path" >&2
  exit 1
fi

rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"
tar -xzf "$archive_path" -C "$TARGET_DIR"

for required_path in package.json package-lock.json src/server.js; do
  if [[ ! -f "$TARGET_DIR/$required_path" ]]; then
    echo "[backup-restore-drill] missing $required_path inside restored backup" >&2
    exit 1
  fi
done

echo "[backup-restore-drill] latest backup: $archive_path"
echo "[backup-restore-drill] restored into: $TARGET_DIR"
echo "[backup-restore-drill] archive looks valid for rollback activation"
