# Production migration runbook — connected-trees → federated семя

> Phase B Week 8 staged rollout procedure. Migrates existing
> connected-per-user-trees data к federated семья model. **DO NOT
> execute production migration без полного runbook completion**.

---

## Pre-flight (T-24h перед migration)

### Required preconditions

1. **Full DB backup verified restorable**
   - Standard backup via `rodnya-backup.service` daily snapshot.
   - Verify restore процедура rehearsed на staging within last 7 days.
   - Pre-migration snapshot taken **immediately перед --commit** (см. Step 2.1).

2. **Staging migration successful**
   - Run identical migration script на staging environment.
   - All 8 verification checks pass.
   - Manual smoke verified (см. Step 4 smoke flow).
   - Staging run logs archived для audit trail.

3. **Backend deployed с Phase B Week 2-3 code**
   - All 9 Phase B ships landed (Ship 1-9). Migration script полагается на:
     - Entity collections в EMPTY_DB normalizeDbState (Ship 1)
     - Семя+membership store methods (Ship 1, 3)
     - tree.semyaId reverse-FK field (Ship 5)
     - resolveTreeAudienceUserIds extension (Ship 9)

4. **Feature flag `RODNYA_FEDERATED_SEMYI_ENABLED` default OFF**
   - Migration runs BEFORE flag flip.
   - After migration verified, flag flipped в follow-up deploy.
   - Frontend Week 5-6 не release'нут до flag flip.

5. **hardDelete background job confirmed compatible**
   - `hardDelete-job-config.js` schedule documented.
   - Verify no concurrent run scheduled during migration window.
   - Phase 3.6 hard-delete operates on `graphPersons.deletedAt` + `branchPersonViews` cleanup —
     orthogonal к семя layer, no collision expected.

6. **Maintenance window scheduled**
   - 30-60 min window during low-traffic period.
   - Status page notification published 2h in advance.
   - On-call rota acknowledged.

### Pre-flight checks

```bash
# 1. Verify backup
sudo systemctl status rodnya-backup.service
ls -lh /var/lib/rodnya/backups/  # check latest snapshot exists

# 2. Verify backend deployed
cd /var/lib/rodnya/backend
git log -1  # confirm Ship 9 commit (b8992ae+) либо later на main
node -e "const s = require('./src/store'); console.log('store loaded')"

# 3. Confirm feature flag OFF
grep RODNYA_FEDERATED_SEMYI_ENABLED /etc/rodnya/backend.env
# should NOT exist либо be 'false' / empty

# 4. Dry-run в production data (read-only)
sudo -u rodnya node scripts/migrate-trees-to-semyi.js --quiet
# Verify counts: семя created = expected user count
```

---

## Execution

### Step 1 — Stop backend service

```bash
sudo systemctl stop rodnya-api.service
sudo systemctl stop rodnya-livekit.service
# Realtime hub drops connections — clients reconnect automatically
# после restart.
```

### Step 2 — Take pre-migration snapshot

```bash
# 2.1 Force backup immediately
sudo /var/lib/rodnya/scripts/backup-now.sh
# либо manual:
sudo cp /var/lib/rodnya/backend/data/dev-db.json \
        /var/lib/rodnya/backups/dev-db.pre-semya-migration.json
ls -lh /var/lib/rodnya/backups/dev-db.pre-semya-migration.json
```

### Step 3 — Run migration --commit

```bash
cd /var/lib/rodnya/backend
sudo -u rodnya node scripts/migrate-trees-to-semyi.js --commit 2>&1 | \
  tee /tmp/migration-$(date +%Y%m%d-%H%M%S).log
```

Expected output:
```
=== Migration plan ===
Будут созданы:
  семя:                  N        # N = active users with trees
  members:               M        # M >= N (owner + shared editors)
  tree.semyaId updates:  N
...
✓ Migration committed к ...
=== Post-migration verification ===
✓ count(семя not-deleted) === count(trees with valid creator)
✓ all users-with-trees have at least one семя membership
✓ no orphaned trees (each eligible tree bound к семя)
✓ tree.semyaId reverse-FK consistent
✓ personIdentities count preserved
✓ each семя has ≥1 owner (invariant §3.3)
✓ graphPersons count preserved
✓ migrationStatus.treesToSemyi marker set к complete-v1
✅ All verifications pass.
```

If ANY check fails → **STOP**, proceed к Rollback (Section 6).

### Step 4 — Restart backend service

```bash
sudo systemctl start rodnya-api.service
sudo systemctl start rodnya-livekit.service
sudo systemctl status rodnya-api.service  # confirm healthy
```

### Step 5 — Post-migration smoke test

Manual curl smoke (~5 min):

```bash
# 5.1. Confirm семя endpoint responds для existing user
TOKEN=$(curl -s -X POST https://api.rodnya-tree.ru/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"smoke-test@rodnya.app","password":"..."}' \
  | jq -r .accessToken)

curl -H "Authorization: Bearer $TOKEN" \
     https://api.rodnya-tree.ru/v1/me/semya \
     | jq '.semyi | length'
# expected: 1 (auto-created «Моя семья»)

# 5.2. Verify tree GET still works (legacy endpoint)
TREE_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
     https://api.rodnya-tree.ru/v1/trees \
     | jq -r '.trees[0].id')

curl -H "Authorization: Bearer $TOKEN" \
     https://api.rodnya-tree.ru/v1/trees/$TREE_ID/persons \
     | jq '.persons | length'
# expected: number of persons pre-migration

# 5.3. Verify tree.semyaId binding through семя detail
SEMYA_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
     https://api.rodnya-tree.ru/v1/me/semya \
     | jq -r '.semyi[0].id')

curl -H "Authorization: Bearer $TOKEN" \
     https://api.rodnya-tree.ru/v1/semya/$SEMYA_ID \
     | jq '.semya.treeId'
# expected: $TREE_ID

# 5.4. Membership list shows owner role
curl -H "Authorization: Bearer $TOKEN" \
     https://api.rodnya-tree.ru/v1/semya/$SEMYA_ID/memberships \
     | jq '.memberships[0].role'
# expected: "owner"
```

If smoke fails on any check → **STOP**, proceed к Rollback.

---

## Step 6 — Verification queries (production state assertions)

Direct database read через verify mode:

```bash
sudo -u rodnya node scripts/migrate-trees-to-semyi.js --verify
```

All 8 checks must pass. If any fail, log + report immediately to incident channel.

### Manual query-style checks через node REPL:

```bash
sudo -u rodnya node -e "
const fs = require('fs');
const db = JSON.parse(fs.readFileSync('/var/lib/rodnya/backend/data/dev-db.json', 'utf-8'));
console.log('Users:', db.users.length);
console.log('Trees:', db.trees.length);
console.log('Semya:', db.semyi.length, '(' + db.semyi.filter(s => !s.deletedAt).length + ' active)');
console.log('Memberships:', db.semyaMembers.length, '(' + db.semyaMembers.filter(m => !m.hiddenAt).length + ' active)');
console.log('PersonIdentities (preserved):', db.personIdentities.length);
console.log('GraphPersons (preserved):', db.graphPersons.length);
console.log('Bound trees:', db.trees.filter(t => t.semyaId).length);
console.log('Unbound trees:', db.trees.filter(t => !t.semyaId).length);
"
```

Expected (per Артёма numbers from Week 1):
- Users: 70
- Trees: 15
- Semya: 15 (15 active)
- Memberships: ≥15 (one owner per tree, plus shared-tree viewers)
- PersonIdentities: 75 (preserved unchanged)
- GraphPersons: 351 (preserved unchanged)
- Bound trees: 15
- Unbound trees: 0 (after migration)

---

## Rollback procedure

If migration fails либо post-smoke surfaces issue:

### Immediate rollback (within maintenance window)

```bash
# 1. Stop backend
sudo systemctl stop rodnya-api.service
sudo systemctl stop rodnya-livekit.service

# 2. Restore pre-migration snapshot
sudo cp /var/lib/rodnya/backups/dev-db.pre-semya-migration.json \
        /var/lib/rodnya/backend/data/dev-db.json

# 3. Verify restoration via --verify (should report «not migrated»)
sudo -u rodnya node scripts/migrate-trees-to-semyi.js --verify
# Expected: migrationStatus.treesToSemyi marker should NOT be 'complete-v1'

# 4. Restart backend
sudo systemctl start rodnya-api.service
sudo systemctl start rodnya-livekit.service
```

### Backend revert (если schema-level issue)

```bash
# Если bug в Ship 1-9 code surfaces только в production:
cd /var/lib/rodnya/backend
git fetch
git checkout <pre-Ship-1 commit SHA>  # e.g. 8ab3b02 (pre Phase B)
npm ci
sudo systemctl restart rodnya-api.service
```

Note: backend revert leaves семя collections в db но code не uses them.
Subsequent forward fix может re-deploy + re-run migration в new pre-flight cycle.

---

## Post-migration tasks

### Within 24h after successful migration

1. **Status page update**
   - Mark maintenance window closed.
   - Note successful migration completion.

2. **Monitor logs для unexpected errors**
   ```bash
   sudo journalctl -u rodnya-api.service -f \
     | grep -i "semya\|membership\|invitation"
   ```
   Watch for new error patterns indicating client incompatibility.

3. **Feature flag remains OFF** для observation window.
   - 1-week observation per `project_phase_observation_pattern` memory rule.
   - If clean: schedule flag flip via separate deploy.

### Within 1 week after migration

1. **Flag flip preparation**
   - Verify no escalations.
   - Frontend Week 5-6 ships deployed (if completed) — UI consuming семя endpoints.

2. **Feature flag flip — separate deploy**
   ```bash
   echo "RODNYA_FEDERATED_SEMYI_ENABLED=true" >> /etc/rodnya/backend.env
   sudo systemctl restart rodnya-api.service
   ```
   After flip: `requireTreeAccess` для bound trees uses семя membership gate. Legacy `tree.memberIds` gate fires только для unbound trees (which shouldn't exist after migration).

3. **Observation week post-flip**
   - Monitor permission denial rates.
   - Verify push notification delivery (audience extension Ship 9 should expand recipients).

### Within 3 months after migration

1. **Sunset legacy code**
   - Remove dual-write shim в addMembership/removeMembership (Ship 5).
   - Remove fallback path в requireTreeAccess.
   - Drop `tree.memberIds[]` legacy field.

---

## Risk register

| Risk | Severity | Mitigation |
|---|---|---|
| **Data loss during migration** | 🔴 HIGH | Pre-migration snapshot mandatory. Backup verified restorable. Rollback procedure rehearsed. |
| **Backend crashes mid-migration** | 🟠 MEDIUM | Single-file JSON storage — atomic via temp-file rename pattern. Partial writes impossible. |
| **Concurrent client mutation during migration** | 🟠 MEDIUM | Backend stopped before migration. Clients reconnect after restart, операции serialized против fresh schema. |
| **Idempotency bug** | 🟡 LOW | Script tested на dev (commit + re-commit = skip). Marker `migrationStatus.treesToSemyi.version` gates re-run. |
| **Verification false-positive** | 🟡 LOW | 8 independent checks cover semantic invariants. Manual smoke в Step 5 catches end-to-end issues. |
| **PostgresStore mismatch** | 🟠 MEDIUM | Script handles file-store mode только. Postgres-state migration goes через `migrate-state-to-postgres.js` separately. Verify production storage mode before run. |
| **Realtime hub state drift** | 🟡 LOW | Hub restarts с backend, all clients reconnect. Cached audience snapshots discarded. |

---

## Sign-off requirements

Per Артёма approval matrix:

* [ ] Artyom (Артём) approval — direction confirmed via SHARED-TREE-PROPOSAL.md sign-off (0904c7b commit).
* [ ] Staging migration logs reviewed by Artyom.
* [ ] Production maintenance window scheduled and notified.
* [ ] On-call rota acknowledges window.
* [ ] Pre-migration backup verified.
* [ ] Frontend Week 5-6 deployment status confirmed (либо separate flag flip scheduled).

---

## Contact + escalation

- **Primary**: Artyom (Артём) — owner project.
- **Secondary**: On-call SRE rota per `rota.md`.
- **Escalation channel**: `#rodnya-incidents` Slack/Telegram.

**Принято**: Artyom + Claude, 2026-05-25.
