#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -z "${LINEAGE_RELEASE_SIGNING_PROPERTIES:-}" && -z "${LINEAGE_KEYSTORE_FILE:-}" ]]; then
  if [[ ! -f "$REPO_ROOT/android/release-signing.properties" ]]; then
    echo "Warning: release signing is not configured. Set LINEAGE_RELEASE_SIGNING_PROPERTIES or LINEAGE_KEYSTORE_* env vars before building." >&2
  fi
fi

cd "$REPO_ROOT"

artifact_kind="${1:-appbundle}"
shift $(( $# > 0 ? 1 : 0 )) || true

defines=(
  --dart-define=LINEAGE_RUNTIME_PRESET=prod_custom_api
  --dart-define=LINEAGE_ENABLE_LEGACY_DYNAMIC_LINKS=false
  --dart-define=LINEAGE_APP_STORE=rustore
  --dart-define=LINEAGE_ENABLE_RUSTORE_BILLING=false
  --dart-define=LINEAGE_ENABLE_RUSTORE_REVIEW=true
  --dart-define=LINEAGE_ENABLE_RUSTORE_UPDATES=true
)

build_artifact() {
  local artifact_type="$1"
  local build_args=(
    build "$artifact_type" --flavor rustore --release
    "${defines[@]}"
  )

  if [[ -n "${LINEAGE_BUILD_NAME:-}" ]]; then
    build_args+=(--build-name="$LINEAGE_BUILD_NAME")
  fi

  if [[ -n "${LINEAGE_BUILD_NUMBER:-}" ]]; then
    build_args+=(--build-number="$LINEAGE_BUILD_NUMBER")
  fi

  flutter "${build_args[@]}"
}

case "$artifact_kind" in
  appbundle)
    build_artifact appbundle
    ;;
  apk)
    build_artifact apk
    ;;
  both)
    build_artifact appbundle
    build_artifact apk
    ;;
  *)
    echo "Unsupported artifact kind: $artifact_kind. Use appbundle, apk or both." >&2
    exit 1
    ;;
esac
