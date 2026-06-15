#!/usr/bin/env bash
# Установить как /usr/local/bin/rodnya-set-android-update (chmod 755),
# запускается воркфлоу android-ota-release.yml через `sudo -n`.
#
# Идемпотентно переключает backend /v1/app/latest на новый Android-релиз:
# переписывает RODNYA_LATEST_ANDROID_* (+ RODNYA_MIN_ANDROID_VERSION_CODE)
# в env-файле бэкенда и рестартит сервис. Остальные строки env не трогает.
#
# Usage: rodnya-set-android-update <versionCode> <versionName> <apkUrl> <sha256> <notesBase64> <minVersionCode>
set -euo pipefail

CODE="${1:?versionCode required}"
NAME="${2:?versionName required}"
URL="${3:?apkUrl required}"
SHA="${4:?sha256 required}"
NOTES_B64="${5:-}"
MIN="${6:-0}"

NOTES="$(printf '%s' "$NOTES_B64" | base64 -d 2>/dev/null || true)"

ENV_FILE="${RODNYA_BACKEND_ENV:-/etc/rodnya-backend.env}"
SERVICE="${RODNYA_BACKEND_SERVICE:-rodnya-backend.service}"

[ -f "$ENV_FILE" ] || { echo "env file $ENV_FILE not found" >&2; exit 1; }

# Бэкап перед правкой (откат при необходимости).
cp -a "$ENV_FILE" "${ENV_FILE}.bak.$(date -u +%Y%m%dT%H%M%SZ)"

tmp="$(mktemp)"
# Сохраняем всё, кроме старых OTA-строк.
grep -vE '^(RODNYA_LATEST_ANDROID_(VERSION_CODE|VERSION_NAME|APK_URL|APK_SHA256|NOTES)|RODNYA_MIN_ANDROID_VERSION_CODE)=' \
  "$ENV_FILE" > "$tmp" || true
{
  echo "RODNYA_LATEST_ANDROID_VERSION_CODE=${CODE}"
  echo "RODNYA_LATEST_ANDROID_VERSION_NAME=${NAME}"
  echo "RODNYA_LATEST_ANDROID_APK_URL=${URL}"
  echo "RODNYA_LATEST_ANDROID_APK_SHA256=${SHA}"
  echo "RODNYA_LATEST_ANDROID_NOTES=${NOTES}"
  if [ "${MIN}" != "0" ]; then echo "RODNYA_MIN_ANDROID_VERSION_CODE=${MIN}"; fi
} >> "$tmp"

install -m 600 "$tmp" "$ENV_FILE"
rm -f "$tmp"

systemctl restart "$SERVICE"
echo "rodnya-set-android-update: vc=${CODE} name=${NAME} min=${MIN} → restarted ${SERVICE}"
