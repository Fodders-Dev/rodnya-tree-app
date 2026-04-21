#!/usr/bin/env bash
set -euo pipefail

ARCHIVE_PATH="${1:-}"
TARGET_DIR="${2:-/opt/rodnya/livekit}"
SERVICE_NAME="${3:-rodnya-livekit.service}"
CADDYFILE_PATH="${4:-/etc/caddy/Caddyfile}"
BACKEND_ENV_PATH="${5:-/etc/rodnya-backend.env}"
LIVEKIT_HOST="${6:-}"
TURN_HOST="${7:-}"
LIVEKIT_API_KEY="${8:-}"
LIVEKIT_API_SECRET="${9:-}"
LIVEKIT_WEBHOOK_KEY="${10:-}"
NODE_IP="${11:-212.69.84.167}"
NETWORK_INTERFACE="${12:-ens1}"
TURN_TLS_PORT="${13:-5349}"
BACKEND_SERVICE_NAME="${14:-rodnya-backend.service}"
BACKUP_ROOT="${BACKUP_ROOT:-/opt/rodnya/backups}"
CERT_ROOT="${CERT_ROOT:-/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory}"
TIMESTAMP="${DEPLOY_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"

log() {
  printf '[rodnya-livekit] %s\n' "$*"
}

fail() {
  printf '[rodnya-livekit] ERROR: %s\n' "$*" >&2
  exit 1
}

if [[ -z "$ARCHIVE_PATH" || -z "$LIVEKIT_HOST" || -z "$TURN_HOST" || -z "$LIVEKIT_API_KEY" || -z "$LIVEKIT_API_SECRET" || -z "$LIVEKIT_WEBHOOK_KEY" ]]; then
  fail "usage: $0 <archive-path> [target-dir] [service-name] [caddyfile] [backend-env] <livekit-host> <turn-host> <api-key> <api-secret> <webhook-key> [node-ip] [network-interface] [turn-tls-port] [backend-service-name]"
fi

if [[ ! -f "$ARCHIVE_PATH" ]]; then
  fail "archive not found: $ARCHIVE_PATH"
fi

if [[ ! -f "$CADDYFILE_PATH" ]]; then
  fail "caddyfile not found: $CADDYFILE_PATH"
fi

if [[ ! -f "$BACKEND_ENV_PATH" ]]; then
  fail "backend env not found: $BACKEND_ENV_PATH"
fi

if ! command -v python3 >/dev/null 2>&1; then
  fail "python3 is required on the server"
fi

scratch_dir="$(mktemp -d)"
target_parent="$(dirname "$TARGET_DIR")"
backup_dir="${BACKUP_ROOT}/${TIMESTAMP}-livekit"
cert_dir="${CERT_ROOT}/${TURN_HOST}"
cert_file="${cert_dir}/${TURN_HOST}.crt"
key_file="${cert_dir}/${TURN_HOST}.key"

cleanup() {
  rm -rf "$scratch_dir"
}
trap cleanup EXIT

mkdir -p "$BACKUP_ROOT" "$target_parent" "$backup_dir"

log "extracting livekit release archive"
tar -xzf "$ARCHIVE_PATH" -C "$scratch_dir"

release_dir="$scratch_dir"
if [[ -d "$scratch_dir/deploy/livekit" ]]; then
  release_dir="$scratch_dir/deploy/livekit"
fi

for required_file in docker-compose.yml livekit.yaml.tmpl rodnya-livekit.service README.md .env.example; do
  if [[ ! -f "$release_dir/$required_file" ]]; then
    fail "archive does not contain $required_file"
  fi
done

if [[ -d "$TARGET_DIR" ]]; then
  log "backing up previous livekit directory"
  tar -czf "${backup_dir}/livekit.tgz" -C "$TARGET_DIR" .
fi

mkdir -p "$TARGET_DIR"
rsync -a --delete "$release_dir"/ "$TARGET_DIR"/

log "writing runtime env"
cat > "${TARGET_DIR}/.env" <<EOF
LIVEKIT_IMAGE_TAG=v1.11.0
LIVEKIT_API_KEY=${LIVEKIT_API_KEY}
LIVEKIT_API_SECRET=${LIVEKIT_API_SECRET}
LIVEKIT_NODE_IP=${NODE_IP}
LIVEKIT_NETWORK_INTERFACE=${NETWORK_INTERFACE}
LIVEKIT_TURN_DOMAIN=${TURN_HOST}
LIVEKIT_TURN_TLS_PORT=${TURN_TLS_PORT}
LIVEKIT_TURN_CERT_FILE=${cert_file}
LIVEKIT_TURN_KEY_FILE=${key_file}
EOF

log "rendering livekit.yaml"
TARGET_DIR="$TARGET_DIR" python3 <<'PY'
import os
from pathlib import Path

target_dir = Path(os.environ["TARGET_DIR"])
env_path = target_dir / ".env"
template_path = target_dir / "livekit.yaml.tmpl"
output_path = target_dir / "livekit.yaml"

values = {}
for raw_line in env_path.read_text(encoding="utf-8").splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    key, value = line.split("=", 1)
    values[key] = value

rendered = template_path.read_text(encoding="utf-8")
for key, value in values.items():
    rendered = rendered.replace("${" + key + "}", value)

output_path.write_text(rendered, encoding="utf-8")
PY

log "installing systemd unit"
install -m 0644 "${TARGET_DIR}/rodnya-livekit.service" "/etc/systemd/system/${SERVICE_NAME}"

log "updating caddy routes"
CADDYFILE_PATH="$CADDYFILE_PATH" LIVEKIT_HOST="$LIVEKIT_HOST" TURN_HOST="$TURN_HOST" python3 <<'PY'
import os
from pathlib import Path
import re

caddyfile = Path(os.environ["CADDYFILE_PATH"])
livekit_host = os.environ["LIVEKIT_HOST"]
turn_host = os.environ["TURN_HOST"]
block = f"""
# Rodnya LiveKit begin
{livekit_host} {{
  encode zstd gzip
  reverse_proxy 127.0.0.1:7880
}}

{turn_host} {{
  respond 204
}}
# Rodnya LiveKit end
""".lstrip("\n")

text = caddyfile.read_text(encoding="utf-8")
text = re.sub(
    r"\n?# Rodnya LiveKit(?: pilot)? begin.*?# Rodnya LiveKit(?: pilot)? end\n?",
    "\n",
    text,
    flags=re.S,
)
text = text.rstrip() + "\n\n" + block
caddyfile.write_text(text, encoding="utf-8")
PY

log "validating caddy config"
/usr/bin/caddy validate --config "$CADDYFILE_PATH"
systemctl reload caddy

log "waiting for caddy certificates"
for attempt in $(seq 1 30); do
  if [[ -f "$cert_file" && -f "$key_file" ]]; then
    break
  fi
  curl -ksSI "https://${TURN_HOST}" >/dev/null 2>&1 || true
  curl -ksSI "https://${LIVEKIT_HOST}" >/dev/null 2>&1 || true
  sleep 2
done

if [[ ! -f "$cert_file" || ! -f "$key_file" ]]; then
  fail "caddy did not issue certificate files for ${TURN_HOST}"
fi

log "updating backend env"
BACKEND_ENV_PATH="$BACKEND_ENV_PATH" LIVEKIT_HOST="$LIVEKIT_HOST" LIVEKIT_API_KEY="$LIVEKIT_API_KEY" LIVEKIT_API_SECRET="$LIVEKIT_API_SECRET" LIVEKIT_WEBHOOK_KEY="$LIVEKIT_WEBHOOK_KEY" python3 <<'PY'
import os
from pathlib import Path

env_path = Path(os.environ["BACKEND_ENV_PATH"])
values = {
    "RODNYA_LIVEKIT_URL": f"https://{os.environ['LIVEKIT_HOST']}",
    "RODNYA_LIVEKIT_API_KEY": os.environ["LIVEKIT_API_KEY"],
    "RODNYA_LIVEKIT_API_SECRET": os.environ["LIVEKIT_API_SECRET"],
    "RODNYA_LIVEKIT_WEBHOOK_KEY": os.environ["LIVEKIT_WEBHOOK_KEY"],
}

lines = env_path.read_text(encoding="utf-8").splitlines()
filtered = []
for line in lines:
    if any(line.startswith(key + "=") for key in values):
      continue
    filtered.append(line)

if filtered and filtered[-1].strip():
    filtered.append("")

for key, value in values.items():
    filtered.append(f"{key}={value}")

filtered.append("")
env_path.write_text("\n".join(filtered), encoding="utf-8")
PY

log "validating compose"
(
  cd "$TARGET_DIR"
  /usr/bin/docker compose config >/dev/null
)

systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"
systemctl restart "$BACKEND_SERVICE_NAME"

log "waiting for backend readiness"
READY_URL="http://127.0.0.1:8080/ready"
for attempt in $(seq 1 20); do
  if curl -fsS "$READY_URL" >/tmp/rodnya-livekit-ready.json; then
    if python3 - <<'PY'
import json
from pathlib import Path
payload = json.loads(Path("/tmp/rodnya-livekit-ready.json").read_text(encoding="utf-8"))
raise SystemExit(0 if payload.get("liveKitEnabled") is True else 1)
PY
    then
      break
    fi
  fi
  sleep 2
done

if ! systemctl is-active --quiet "$SERVICE_NAME"; then
  fail "${SERVICE_NAME} is not active"
fi

if ! systemctl is-active --quiet "$BACKEND_SERVICE_NAME"; then
  fail "${BACKEND_SERVICE_NAME} is not active"
fi

if ! python3 - <<'PY'
import json
from pathlib import Path
payload = json.loads(Path("/tmp/rodnya-livekit-ready.json").read_text(encoding="utf-8"))
raise SystemExit(0 if payload.get("liveKitEnabled") is True else 1)
PY
then
  fail "backend readiness did not expose liveKitEnabled=true"
fi

log "livekit release activated"
printf 'livekit_host=%s\nturn_host=%s\n' "$LIVEKIT_HOST" "$TURN_HOST"
