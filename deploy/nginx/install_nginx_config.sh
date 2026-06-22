#!/usr/bin/env bash
# Idempotent installer for the rodnya-tree.ru nginx fallback config.
#
# Run as root on the production VM after pulling the latest commit when
# updating the nginx fallback config:
#
#   sudo deploy/nginx/install_nginx_config.sh
#
# ⚠️ ORDER: deploy the WEB release (flutter build web → web deploy) BEFORE
# running this. The config serves static pages from the web root
# (/invite/index.html, /oauth/callback/index.html). If nginx is active,
# reloading before those files exist makes those routes 404 until the web
# deploy lands.
#
# What it does:
#   1. Drops the WebSocket-upgrade map into /etc/nginx/conf.d/.
#   2. Copies the rodnya site config into sites-available + symlinks
#      it into sites-enabled.
#   3. Removes any stale `rodnya.conf.bak*` / `rodnya.conf.codex*`
#      siblings that nginx -t was warning about.
#   4. Validates with `nginx -t` and reloads only when nginx.service is
#      active. If validation fails, restores the previous config and exits
#      non-zero so the deploy can fail fast instead of leaving the host in
#      a broken state.

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
SITES_AVAILABLE="/etc/nginx/sites-available"
SITES_ENABLED="/etc/nginx/sites-enabled"
CONF_D="/etc/nginx/conf.d"
SITE_NAME="rodnya"
backup_dir="/tmp/rodnya-nginx-stale-$(date +%Y%m%d-%H%M%S)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "[install_nginx_config] must run as root" >&2
  exit 1
fi

if [[ ! -d "${SITES_AVAILABLE}" ]] || [[ ! -d "${SITES_ENABLED}" ]] || [[ ! -d "${CONF_D}" ]]; then
  echo "[install_nginx_config] missing /etc/nginx layout — is nginx installed?" >&2
  exit 1
fi

mkdir -p "${backup_dir}"

previous_available="${backup_dir}/${SITE_NAME}.sites-available.previous"
previous_enabled_file="${backup_dir}/${SITE_NAME}.sites-enabled.previous"
previous_enabled_target=""
previous_enabled_kind="missing"

if [[ -e "${SITES_AVAILABLE}/${SITE_NAME}" ]]; then
  cp -a "${SITES_AVAILABLE}/${SITE_NAME}" "${previous_available}"
fi

if [[ -L "${SITES_ENABLED}/${SITE_NAME}" ]]; then
  previous_enabled_kind="symlink"
  previous_enabled_target="$(readlink "${SITES_ENABLED}/${SITE_NAME}")"
elif [[ -e "${SITES_ENABLED}/${SITE_NAME}" ]]; then
  previous_enabled_kind="file"
  cp -a "${SITES_ENABLED}/${SITE_NAME}" "${previous_enabled_file}"
fi

restore_previous_config() {
  echo "[install_nginx_config] restoring previous nginx config" >&2

  if [[ -e "${previous_available}" ]]; then
    cp -a "${previous_available}" "${SITES_AVAILABLE}/${SITE_NAME}"
  else
    rm -f "${SITES_AVAILABLE}/${SITE_NAME}"
  fi

  rm -f "${SITES_ENABLED}/${SITE_NAME}"
  case "${previous_enabled_kind}" in
    symlink)
      ln -s "${previous_enabled_target}" "${SITES_ENABLED}/${SITE_NAME}"
      ;;
    file)
      cp -a "${previous_enabled_file}" "${SITES_ENABLED}/${SITE_NAME}"
      ;;
    missing)
      ;;
  esac
}

echo "[install_nginx_config] dropping connection-upgrade.conf into ${CONF_D}/"
install -m 0644 "${SOURCE_DIR}/connection-upgrade.conf" \
  "${CONF_D}/connection-upgrade.conf"

echo "[install_nginx_config] writing ${SITES_AVAILABLE}/${SITE_NAME}"
install -m 0644 "${SOURCE_DIR}/${SITE_NAME}.conf" \
  "${SITES_AVAILABLE}/${SITE_NAME}"

# Remove the stale conflicting siblings that journalctl was warning
# about. We keep them in /tmp/ for forensics in case someone needs to
# review what was there.
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
  echo "[install_nginx_config] nginx -t FAILED — rolling back and NOT reloading" >&2
  restore_previous_config
  exit 1
fi

if systemctl is-active --quiet nginx; then
  echo "[install_nginx_config] reloading nginx"
  systemctl reload nginx
else
  echo "[install_nginx_config] nginx.service is not active — config validated but not reloaded"
fi
echo "[install_nginx_config] done"
