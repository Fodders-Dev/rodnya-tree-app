# Server ops scripts

## Что это

Bash scripts для server-side ops (backups, deploys, etc).
Deployed manually через `scp` + `chmod` на `212.69.84.167` (SSH alias `rodnya` в `~/.ssh/config`).

## rodnya-backup.sh

* **Deployed at**: `/usr/local/bin/rodnya-backup.sh`
* **Triggered by**: `rodnya-backup.service` (systemd timer, daily 03:17 UTC)
* **Output**: `/var/backups/rodnya/YYYYMMDD-HHMMSS/`
* **Retention**: 7 newest subdirs (`find -type d ... | sort | head -n -7 | xargs rm -rf`)

## Deployment procedure

1. Edit script локально (LF endings enforced через `.gitattributes`).
2. Verify hex: `tail -c 20 ops/scripts/rodnya-backup.sh | xxd` — должно заканчиваться `0a` (LF), не `0d 0a` (CRLF).
3. `scp ops/scripts/rodnya-backup.sh rodnya:/usr/local/bin/`
4. `ssh rodnya 'chmod +x /usr/local/bin/rodnya-backup.sh'`
5. Manual verify: `ssh rodnya 'systemctl start rodnya-backup'` — должен exit 0.
6. Daily timer next fire 03:17 UTC.

## CRLF caveat

**Никогда не редактируй через Windows tools без LF enforcement.**
CRLF drift caused **15-day failure 2026-05-05 → 2026-05-19**. См. [DECISIONS.md 2026-05-19](../../docs/connected-trees-refactor/DECISIONS.md) "rodnya-backup.service CRLF fix".

Root cause: `xargs -r rm -rf<CR>` made `rm` see invalid option (carriage return interpreted as flag character), `set -euo pipefail` killed script. 

Fix per file: `sed -i 's/\r$//' /usr/local/bin/rodnya-backup.sh` (already applied на сервере + verified).

Prevention: `.gitattributes` enforces `*.sh text eol=lf` для всех Windows checkouts через git's normalization. Verify через `git config core.autocrlf` (должно быть `input` либо `false`, не `true`).

## /var/backups/rodnya/manual/ findings (2026-05-22 audit)

* **Contents**: 1 file, 17.6KB total directory size.
  * `dev-db-20260330T154512Z.json` — single JSON snapshot from 2026-03-30 15:45 UTC (53 days old at audit time).
* **Activity**: 0 files modified в последние 30 days. Не active.
* **Покрытие auto-cleanup**: `manual/` lives **outside** auto-managed dated subdirs (`YYYYMMDD-HHMMSS/`), retention script не trogает.
* **Recommendation**: candidate либо для (a) archival к offsite cold storage если нужен исторический snapshot, либо (b) deletion как small + old + не used recovery point. Решение — Артёма call. Не auto-delete: это recovery infrastructure, mistaken removal could matter if needed retroactively.
