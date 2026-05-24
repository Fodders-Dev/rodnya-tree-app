# Week 1 summary — Phase B kickoff readiness

> Final deliverable Week 1 — what's discovered + what's designed +
> что готово к Week 2-3 backend rewrite + outstanding blockers.

---

## Deliverables shipped (this commit)

| Doc | Lines | Purpose |
|---|---:|---|
| [BACKEND-AUDIT.md](./BACKEND-AUDIT.md) | 566 | Deep read of 19854 LOC backend, entity inventory, permission model, risks |
| [ENTITY-DESIGN.md](./ENTITY-DESIGN.md) | 420 | Семья + Membership + hide filter + invitations + browse tokens schemas + invariants |
| [MIGRATION-DRYRUN.md](./MIGRATION-DRYRUN.md) | 500 | Script (idempotent + dry-run mode) + dev-db dry-run output + verification queries + rollback procedure |
| WEEK-1-SUMMARY.md (this) | ~200 | Consolidation + Week 2-3 readiness signal |

Total: ~1700 LOC (под cap 2000 per task spec).

**No code changes** — Week 1 strictly investigation + design per
Артёмов directive.

---

## Critical findings

### ✅ NO fundamental blockers

Federated семья rewrite implementable как **additive layer**
(семья entity + membership + role gates) над existing infrastructure.
Identity layer (Phase 3) и graph layer (Phase 3.1-3.4) уже делают
heavy lifting:

- `personIdentities` + `legacyPersonIds[]` = «twin person» concept
  из proposal §3.4 — backend support complete.
- `bulkImportPersonsToTree` (store.js:9573-9774) = «pull selectively»
  endpoint — производственный код уже бридит persons + relations +
  identity links с idempotency.
- `branches` + `includeRules` (4 типа: manual/blood/descendants/
  ancestors) = wrapper «семья view of canonical graph», infrastructure
  reusable.
- `tree_mutated` Phase A+B auto-refresh broadcast уже scope-able к
  семья audience.
- `graphPersonEditGrants` (Phase 3.2) preserves owner model orthogonal
  к семья membership.

Confidence very high. Полный rewrite не оправдан.

### ✅ All 8 Q1-Q8 answers technically feasible

Audit §7.2 confirmed for each Артёмов answer:
- Q1 viewer default role — feasible, simple enum field
- Q2 семья name editable by owner — feasible, PATCH endpoint
- Q3 non-relative membership — feasible, `seedOnboarding` adapt
- Q4 deletion = orphan + notify — feasible, soft-delete pattern
- Q5 identity conflict ask-user — feasible, reuse `identityFieldConflicts`
- Q6 no fixed tree root — feasible, Phase 4 already supports
- Q7 invite grant per-editor — feasible, boolean field на membership
- Q8 immediate migration с auto-«Моя семья» — feasible, idempotent script

**No escalations needed**.

### ⚠️ Non-obvious risks surfaced (Week 2-3 must address)

1. **Missing `tree_mutated` broadcasts** для media/identity-link/
   conflict-resolve operations (audit §7.3 item 7). Phase A+B
   auto-refresh не covers это полностью. Quick fix in Week 2-3.

2. **`kinship_check_expired` notification dispatch absent**
   (audit §7.3 item 8). Komментарий promises lazy dispatch, but
   code только marks state. Pre-existing bug, out-of-Phase-B but
   flag для separate fix.

3. **Audit log new change type needed**: `person.pulled-from-semya`
   с `{sourceSemyaId, sourcePersonId}` detail для Phase B twin
   pull operations. Mirror existing `importedFrom` pattern в
   `bulkImportPersonsToTree`.

4. **`_syncGraphFromLegacy` performance** — full-scan O(persons+
   relations+trees) per write. Sub-millisecond at 70 users; scales
   linearly. Recommend planned drop в Phase 3.4 после dual-write
   sunset (комментарий в коде уже предсказывает это).

5. **Concurrent owner edits** edge case (entity-design §8.4) — race
   condition если двое owners одновременно promote/demote. Mitigation
   via existing FileStore lock pattern, atomic «verify ≥1 owner after
   change» внутри lock window.

### 📋 8 open follow-up questions для Артёма pre-Week 2

См. `BACKEND-AUDIT.md` §7.4 для full list. Critical ones для решения
перед Week 2 start:

1. **«Объединить семьи» post-migration**: delete originals либо keep
   как private archive? (Lean A — delete simpler)
2. **семьяInvitation expiry default** — recommend 30 days, PATCH-able
3. **Multi-семья per identity invariant** — recommend no limit
   (Telegram-like), monitor scale
4. **Hide filter visibility on cross-семья twin updates** — recommend
   skip notification если twin hidden
5. **Семья DELETE notification scope** — recommend async с restore
   option в retention window
6. **kinshipChecks intra-семья UI hint** — recommend defer к Phase B+1
7. **migrationStatus rollback semantics** — recommend read-only mode
   first, then code revert
8. **`identityClaims` collection role** — recommend same semantics
   per-user, не per-семья

Если Артём не decide pre-Week 2 — defaults (выше) auto-apply, можем
revisit при первом implementation conflict.

---

## Entity design highlights

### Семья entity (`db.семьи`)
```
{id, name, ownerId, treeId, description?, createdAt, updatedAt, deletedAt?}
```
Soft-delete per Q4 orphan policy. Multi-owner via `семьяMembers.role='owner'`.

### Membership entity (`db.семьяMembers`)
```
{id, семьяId, userId, role: 'owner'|'editor'|'viewer',
 joinedAt, invitedByUserId, hasInviteGrant: boolean, hiddenAt?}
```
Composite unique key `(семьяId, userId)`. Q7 invite grant on editor only.

### Personal hide filter (`db.семьяMemberHiddenPersons`)
```
{семьяId, userId, personId, hiddenAt}
```
Per-user opaque flag. Не mutates tree, не visible to other members.

### Семья invitations (`db.семьяInvitations`)
```
{id, семьяId, recipientUserId|email|phone, role, invitedByUserId,
 createdAt, expiresAt, status, acceptedAt?, rejectedAt?, revokedAt?, revokedByUserId?}
```
Status machine mirrors Phase 6.5 kinshipChecks. Default role viewer (Q1).
Default expiry 30 days (см. open question).

### Browse tokens (`db.семьяBrowseTokens`)
```
{id, семьяId, token, createdByUserId, createdAt, expiresAt, revokedAt?, lastUsedAt?}
```
Token = capability. Default 7d expiry. Read-only browse session, no
persistent membership. Per `SHARED-TREE-PROPOSAL.md` §3.4 Journey 4.

---

## Migration readiness

### Local dev-db dry-run result

```
Будут созданы:
  семьи:    2  (one per existing tree)
  members:  2  (one owner per семья, no shared trees in dev sample)
Пропущены:
  users без trees: 7  (smoke users — handled by future seedOnboarding)
  уже migrated: 0
```

Script idempotent. Dry-run safe (no DB writes). Production scaling:
~15 семьи + ~15-30 members при production data (70 users, 15 trees).

### Verification queries (7 checks)

All ready для post-migration validation:
- ✓ count(семьи) === count(trees with valid creator)
- ✓ all users-with-trees have ≥1 семья membership
- ✓ no orphaned trees (each tree referenced by семья)
- ✓ personIdentities count preserved (75 prod)
- ✓ each семья has ≥1 owner (§3.3 invariant)
- ✓ graphPersons count preserved (351 prod)
- ✓ migrationStatus.treesToSemyi marker = complete-v1

### Production migration gated на Week 4

Per `SHARED-TREE-PROPOSAL.md` §6 timeline. Script + verification ready
сегодня; production run scheduled Week 4 после backend rewrite (Week
2-3) лands.

---

## Week 2-3 readiness signal

✅ **GO for backend rewrite**.

Implementation gates:
1. ✅ Backend audit complete — known landscape, no surprises
2. ✅ Entity schema finalized — `ENTITY-DESIGN.md` reference
3. ✅ Migration script written + dry-run tested locally
4. ⏳ Артёмов sign-off на Week 1 deliverables
5. ⏳ Артёмов answers на 8 follow-up open questions
   (либо defaults accepted)

Week 2 task scope (per `SHARED-TREE-PROPOSAL.md` §6):
- `семьи` CRUD endpoints (POST/GET/PATCH/DELETE `/v1/semyi`)
- `семьяMembers` endpoints (invitations, role transitions, kick/leave)
- `семьяBrowseTokens` endpoints (create/revoke/use)
- `семьяMemberHiddenPersons` endpoints (hide/unhide/list)
- Cross-семья pull endpoint (`POST /v1/semyi/:targetId/pull`) wrapping
  existing `bulkImportPersonsToTree`
- Permission gate `requireSemyaAccess(scope)` extension от
  `requireTreeAccess`
- Backend test rewrite (~50% of tree-routes tests adapt к семья scope)
- Dual-write compat shim (tree.memberIds derived projection)

Week 3 task scope:
- `dispatchTreeMutation` → `dispatchSemyaMutation` (audience =
  семьяMembers)
- Missing `tree_mutated` broadcasts (media/identity-link/conflict-
  resolve) — see audit §7.3 item 7
- New audit log change type `person.pulled-from-semya`
- Integration tests covering Q1-Q8 behaviors
- Verification: full backend regression suite passes (122/123 baseline
  preserved)

---

## Blockers / surprises

**None blocking** — Week 1 investigation finished без showstoppers.

**Minor surprises**:
1. tree-routes.js has **35 endpoints**, не 18 как Артём hinted
   (counting subroutes — grants/conflicts/digest/import/extended-
   network/include-rules). Scope для adapt slightly larger но still
   manageable в Week 2-3.
2. `circles` / `circleMembers` auto-derived от tree (per-tree
   default circles + auto-circles for descendants/ancestors). Will
   automatically работать per-семья после Phase B — no extra work.

**Pre-existing bugs surfaced** (out-of-Phase-B scope но worth
tracking):
1. `kinship_check_expired` notification dispatch absent (см. risks #2).
2. `tree_mutated` broadcast gaps (см. risks #1).

Both can be addressed в Week 2-3 либо separately по Артёмов call.

---

## Recommendation для Артёма

**Sign-off ready**. Direction confirmed по audit findings. No surprises
significant enough к rethink approach.

Pre-Week 2 actions от тебя:

1. **Review 3 docs**:
   - `BACKEND-AUDIT.md` — особенно §7 (critical findings + 8 follow-up
     questions)
   - `ENTITY-DESIGN.md` — особенно §1 (schemas), §2 (role transitions),
     §3 (invariants)
   - `MIGRATION-DRYRUN.md` — особенно §6 («Объединить семьи» upgrade
     flow) + §10 (production acceptance criteria)

2. **Answer 8 open follow-up questions** (audit §7.4) либо accept
   recommendation defaults.

3. **Confirm Week 2-3 start** — dispatched после твоего sign-off.

Если что-то в дизайне concerns surface — iterate Week 1 docs first
перед код Week 2. Cheap к менять docs, expensive к менять
implementation.

---

**Week 1 complete**. Ready для Week 2-3 backend rewrite dispatch.
