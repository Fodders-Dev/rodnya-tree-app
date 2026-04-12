#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -z "${LINEAGE_RELEASE_SIGNING_PROPERTIES:-}" && -z "${LINEAGE_KEYSTORE_FILE:-}" ]]; then
  echo "Warning: release signing is not configured. Set LINEAGE_RELEASE_SIGNING_PROPERTIES or LINEAGE_KEYSTORE_* env vars before building." >&2
fi

cd "$REPO_ROOT"

build_args=(
  build appbundle --flavor rustore --release
  --dart-define=LINEAGE_RUNTIME_PRESET=prod_custom_api
  --dart-define=LINEAGE_ENABLE_LEGACY_DYNAMIC_LINKS=false
  --dart-define=LINEAGE_APP_STORE=rustore
  --dart-define=LINEAGE_ENABLE_RUSTORE_BILLING=false
  --dart-define=LINEAGE_ENABLE_RUSTORE_REVIEW=true
  --dart-define=LINEAGE_ENABLE_RUSTORE_UPDATES=true
)

if [[ -n "${LINEAGE_BUILD_NAME:-}" ]]; then
  build_args+=(--build-name="$LINEAGE_BUILD_NAME")
fi

if [[ -n "${LINEAGE_BUILD_NUMBER:-}" ]]; then
  build_args+=(--build-number="$LINEAGE_BUILD_NUMBER")
fi

flutter "${build_args[@]}"
