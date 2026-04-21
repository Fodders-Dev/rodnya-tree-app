#!/usr/bin/env bash
set -euo pipefail

ARCHIVE_PATH="${1:-}"
TARGET_DIR="${2:-/opt/rodnya/backend}"
SERVICE_NAME="${3:-rodnya-backend.service}"
BUILD_LABEL_ARG="${4:-}"
BACKUP_ROOT="${BACKUP_ROOT:-/opt/rodnya/backups}"
APP_OWNER="${APP_OWNER:-rodnya}"
APP_GROUP="${APP_GROUP:-rodnya}"
NPM_BIN="${NPM_BIN:-/usr/bin/npm}"
READY_URL="${READY_URL:-http://127.0.0.1:8080/ready}"
BUILD_LABEL="${BUILD_LABEL:-$BUILD_LABEL_ARG}"
TIMESTAMP="${DEPLOY_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"

log() {
  printf '[rodnya-backend] %s\n' "$*"
}

fail() {
  printf '[rodnya-backend] ERROR: %s\n' "$*" >&2
  exit 1
}

if [[ -z "$ARCHIVE_PATH" ]]; then
  fail "usage: $0 <archive-path> [target-dir] [service-name] [build-label]"
fi

if [[ ! -f "$ARCHIVE_PATH" ]]; then
  fail "archive not found: $ARCHIVE_PATH"
fi

if [[ ! -x "$NPM_BIN" ]]; then
  fail "npm not found: $NPM_BIN"
fi

target_parent="$(dirname "$TARGET_DIR")"
target_name="$(basename "$TARGET_DIR")"
next_dir="${target_parent}/.${target_name}.next-${TIMESTAMP}"
previous_dir="${target_parent}/.${target_name}.previous"
failed_dir="${target_parent}/.${target_name}.failed-${TIMESTAMP}"
backup_dir="${BACKUP_ROOT}/${TIMESTAMP}-backend"
scratch_dir="$(mktemp -d)"
ready_ok="false"

cleanup() {
  rm -rf "$scratch_dir"
}
trap cleanup EXIT

check_ready() {
  local attempts="${1:-15}"
  local delay_seconds="${2:-2}"

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if curl -fsS "$READY_URL" >/dev/null; then
      ready_ok="true"
      return 0
    fi
    sleep "$delay_seconds"
  done

  return 1
}

rollback_release() {
  if [[ ! -d "$previous_dir" ]]; then
    fail "new release failed and no previous backend release is available"
  fi

  log "rolling back backend release"
  rm -rf "$failed_dir"
  if [[ -d "$TARGET_DIR" ]]; then
    mv "$TARGET_DIR" "$failed_dir"
  fi
  mv "$previous_dir" "$TARGET_DIR"
  systemctl restart "$SERVICE_NAME"
  check_ready 15 2 || fail "rollback failed: ${SERVICE_NAME} did not become ready"
  fail "backend release failed readiness check and was rolled back"
}

mkdir -p "$BACKUP_ROOT" "$target_parent" "$backup_dir"

log "extracting archive: $ARCHIVE_PATH"
tar -xzf "$ARCHIVE_PATH" -C "$scratch_dir"

if [[ ! -f "$scratch_dir/package.json" ]]; then
  fail "archive does not look like a backend release: package.json missing"
fi

if [[ ! -f "$scratch_dir/src/server.js" ]]; then
  fail "archive does not look like a backend release: src/server.js missing"
fi

if [[ ! -f "$scratch_dir/package-lock.json" ]]; then
  fail "archive does not look like a backend release: package-lock.json missing"
fi

rm -rf "$next_dir"
mkdir -p "$next_dir"
rsync -a --delete "$scratch_dir"/ "$next_dir"/

log "installing production dependencies"
(
  cd "$next_dir"
  NODE_ENV=production "$NPM_BIN" ci --omit=dev
)

if [[ -n "$BUILD_LABEL" ]]; then
  printf '%s\n' "$BUILD_LABEL" > "$next_dir/.last_release_id"
fi

chmod -R u=rwX,go=rX "$next_dir"
chown -R "${APP_OWNER}:${APP_GROUP}" "$next_dir"

if [[ -d "$TARGET_DIR" ]]; then
  log "creating backup archive in $backup_dir"
  tar -czf "${backup_dir}/${target_name}.tgz" -C "$TARGET_DIR" .
  rm -rf "$previous_dir"
  mv "$TARGET_DIR" "$previous_dir"
fi

log "activating new backend release at $TARGET_DIR"
mv "$next_dir" "$TARGET_DIR"

log "restarting ${SERVICE_NAME}"
systemctl restart "$SERVICE_NAME"

if ! check_ready 15 2; then
  rollback_release
fi

rm -rf "$previous_dir"

log "backend release activated"
if [[ -n "$BUILD_LABEL" ]]; then
  log "build label: $BUILD_LABEL"
fi
