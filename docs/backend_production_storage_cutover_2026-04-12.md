# Backend Production Storage Cutover - 2026-04-12

## Result
- Production backend on `https://api.rodnya-tree.ru` now runs with:
  - `RODNYA_BACKEND_STORAGE=postgres`
  - `RODNYA_MEDIA_BACKEND=s3`
- State storage: local `PostgreSQL` on the production host.
- Media storage: local `MinIO` with public HTTPS delivery through Caddy at:
  - `https://api.rodnya-tree.ru/storage/rodnya-media/...`
- Legacy `/media/...` URLs remain valid and now redirect to the new storage path.

## Server-side changes
- Installed and enabled `postgresql`.
- Installed and enabled `minio`.
- Added Caddy route:
  - `handle_path /storage/* { reverse_proxy 127.0.0.1:9000 }`
- Updated `/etc/rodnya-backend.env` with PostgreSQL and S3 settings.
- Switched live backend mode to `postgres + s3` and restarted `rodnya-backend.service`.

## Migration path that was used
1. Added production env vars for PostgreSQL and S3 without switching the live backend yet.
2. Ran dry-run on production data:
   - `node scripts/migrate-state-to-postgres.js --dry-run`
   - `node scripts/migrate-media-to-s3.js --dry-run`
3. Took a cold backup in `/opt/rodnya/backups/20260412-163109-pg-s3-cutover/`.
4. Stopped `rodnya-backend.service`.
5. Migrated state snapshot from `/var/lib/rodnya/dev-db.json` into PostgreSQL.
6. Migrated `/var/lib/rodnya/uploads` into MinIO bucket `rodnya-media` with public-read policy.
7. Switched live backend env to `postgres + s3`.
8. Restarted `rodnya-backend.service`.

## Verification
- Internal readiness:
  - `http://127.0.0.1:8080/ready` returns `storage=postgres`, `media=s3`.
- External readiness:
  - `https://api.rodnya-tree.ru/ready` returns `storage=postgres`, `media=s3`.
- Legacy media compatibility:
  - `https://api.rodnya-tree.ru/media/...` returns `302` to `/storage/rodnya-media/...`.
- Public media delivery:
  - `https://api.rodnya-tree.ru/storage/rodnya-media/...` returns `200` with correct `Content-Type`.
- Fresh production write smoke:
  - temporary QA account registered;
  - new media upload returned an S3-backed HTTPS URL;
  - HEAD on that URL returned `200`;
  - `DELETE /v1/media` removed the object and HEAD then returned `404`;
  - QA account was deleted.
- Full production delete-account cascade smoke:
  - temporary owner and peer accounts were created against live `postgres + s3`;
  - owner uploaded profile, post and chat media;
  - owner created a tree, a post and a direct chat with attachment;
  - `DELETE /v1/auth/account` removed owned state from `PostgreSQL`;
  - all uploaded media URLs returned `404` after account deletion;
  - peer no longer saw the direct chat;
  - leftover QA accounts were cleaned up.

## Backup path after cutover
- Updated `/usr/local/bin/rodnya-backup.sh`.
- Daily backup now includes:
  - `/etc/rodnya-backend.env`
  - legacy `dev-db.json`
  - legacy `uploads.tar.gz`
  - `rodnya-postgres.dump`
  - `minio-data.tar.gz`

## Rollback outline
1. Stop `rodnya-backend.service`.
2. Restore `/etc/rodnya-backend.env` from the cutover backup and switch back to `file + local`.
3. Restore `/var/lib/rodnya/dev-db.json` and `/var/lib/rodnya/uploads` from the same backup set if needed.
4. Start `rodnya-backend.service`.
5. Re-check `/ready`, login, chats, and media URLs.

## Remaining follow-up
- Final RuStore console pass: upload screenshots, store card text and moderator comment.
- A later hardening pass can move MinIO credentials away from root credentials to a dedicated limited-access key.
