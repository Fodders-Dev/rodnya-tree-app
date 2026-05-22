#!/usr/bin/env bash
set -euo pipefail

run_low_priority() {
  if command -v ionice >/dev/null 2>&1; then
    ionice -c3 nice -n 19 "$@"
  else
    nice -n 19 "$@"
  fi
}

stamp="$(date -u +%Y%m%d-%H%M%S)"
out_dir="/var/backups/rodnya/$stamp"
mkdir -p "$out_dir"
cp /etc/rodnya-backend.env "$out_dir/rodnya-backend.env"
if [ -f /var/lib/rodnya/dev-db.json ]; then
  cp /var/lib/rodnya/dev-db.json "$out_dir/dev-db.json"
fi
if [ -d /var/lib/rodnya/uploads ]; then
  run_low_priority tar -C /var/lib/rodnya -czf "$out_dir/uploads.tar.gz" uploads
fi
postgres_url="$(grep '^LINEAGE_POSTGRES_URL=' /etc/rodnya-backend.env | cut -d= -f2- || true)"
if [ -n "$postgres_url" ] && command -v pg_dump >/dev/null 2>&1; then
  if command -v timeout >/dev/null 2>&1; then
    if command -v ionice >/dev/null 2>&1; then
      timeout --signal=TERM --kill-after=30s 45m ionice -c3 nice -n 19 pg_dump "$postgres_url" -Fc -f "$out_dir/rodnya-postgres.dump"
    else
      timeout --signal=TERM --kill-after=30s 45m nice -n 19 pg_dump "$postgres_url" -Fc -f "$out_dir/rodnya-postgres.dump"
    fi
  else
    run_low_priority pg_dump "$postgres_url" -Fc -f "$out_dir/rodnya-postgres.dump"
  fi
fi
if [ -d /var/lib/minio/data ]; then
  run_low_priority tar -C /var/lib/minio -czf "$out_dir/minio-data.tar.gz" data
fi
find /var/backups/rodnya -mindepth 1 -maxdepth 1 -type d | sort | head -n -7 | xargs -r rm -rf

