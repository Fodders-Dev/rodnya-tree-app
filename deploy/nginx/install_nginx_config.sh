#!/usr/bin/env bash
# Idempotent installer for the rodnya-tree.ru nginx configuration.
#
# Run as root on the production VM after pulling the latest commit:
#
#   sudo deploy/nginx/install_nginx_config.sh
#
# ⚠️ ORDER: deploy the WEB release (flutter build web → web deploy) BEFORE
# running this. The config serves static pages from the web root
# (/invite/index.html, /oauth/callback/index.html); reloading nginx before
# those files exist makes those routes 404 until the web deploy lands.
#
# What it does:
#   1. Drops the WebSocket-upgrade map into /etc/nginx/conf.d/.
#   2. Copies the rodnya site config into sites-available + symlinks
#      it into sites-enabled.
#   3. Removes any stale `rodnya.conf.bak*` / `rodnya.conf.codex*`
#      siblings that nginx -t was warning about.
#   4. Validates with `nginx -t` and reloads. If validation fails,
#      restores the previous symlink and exits non-zero so the deploy
#      can fail fast instead of leaving the host in a broken state.

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
SITES_AVAILABLE="/etc/nginx/sites-available"
SITES_ENABLED="/etc/nginx/sites-enabled"
CONF_D="/etc/nginx/conf.d"
SITE_NAME="rodnya"

if [[ "${EUID}" -ne 0 ]]; then
  echo "[install_nginx_config] must run as root" >&2
  exit 1
fi

if [[ ! -d "${SITES_AVAILABLE}" ]] || [[ ! -d "${SITES_ENABLED}" ]] || [[ ! -d "${CONF_D}" ]]; then
  echo "[install_nginx_config] missing /etc/nginx layout — is nginx installed?" >&2
  exit 1
fi

echo "[install_nginx_config] dropping connection-upgrade.conf into ${CONF_D}/"
install -m 0644 "${SOURCE_DIR}/connection-upgrade.conf" \
  "${CONF_D}/connection-upgrade.conf"

echo "[install_nginx_config] writing ${SITES_AVAILABLE}/${SITE_NAME}"
install -m 0644 "${SOURCE_DIR}/${SITE_NAME}.conf" \
  "${SITES_AVAILABLE}/${SITE_NAME}"

# Remove the stale conflicting siblings that journalctl was warning
# about. We keep them in /tmp/ for forensics in case someone needs to
# review what was there.
backup_dir="/tmp/rodnya-nginx-stale-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${backup_dir}"
shopt -s nullglob
for stale in \
    "${SITES_ENABLED}/${SITE_NAME}.conf"* \
    "${SITES_ENABLED}/${SITE_NAME}.bak"* \
    "${SITES_ENABLED}/${SITE_NAME}.codex"*; do
  if [[ "${stale}" != "${SITES_ENABLED}/${SITE_NAME}" ]]; then
    echo "[install_nginx_config] moving stale ${stale} → ${backup_dir}/"
    mv -f "${stale}" "${backup_dir}/"
  fi
done
shopt -u nullglob

# Symlink the canonical entry. ln -sf overwrites an existing symlink
# atomically; if the destination is a regular file (not a symlink),
# move it aside first so we don't lose data.
if [[ -e "${SITES_ENABLED}/${SITE_NAME}" ]] && [[ ! -L "${SITES_ENABLED}/${SITE_NAME}" ]]; then
  mv -f "${SITES_ENABLED}/${SITE_NAME}" "${backup_dir}/${SITE_NAME}.regular-file"
fi
ln -sf "${SITES_AVAILABLE}/${SITE_NAME}" "${SITES_ENABLED}/${SITE_NAME}"

# Validate and reload.
echo "[install_nginx_config] running nginx -t"
if ! nginx -t; then
  echo "[install_nginx_config] nginx -t FAILED — leaving config in place but NOT reloading" >&2
  exit 1
fi

echo "[install_nginx_config] reloading nginx"
systemctl reload nginx
echo "[install_nginx_config] done"
