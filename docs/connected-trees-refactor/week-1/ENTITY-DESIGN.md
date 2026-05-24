# Entity design — Phase B семья + membership schema

> Phase B Week 1 deliverable. Schema definitions для new entities,
> mapping к existing infrastructure, role transitions, invariants.
> Source: `SHARED-TREE-PROPOSAL.md` (commit `0904c7b`) + `BACKEND-AUDIT.md`
> findings.

---

## 1. Entity schemas

Все Phase B entities хранятся в едином JSON document (FileStore +
PostgresStore wrapper, существующий pattern из `backend/src/store.js`).
Schemas TypeScript-like для clarity; backend Node-side остаётся plain JS
с runtime validators.

### 1.1 `семьи` (singular: `семья`)

```typescript
type Семья = {
  id: string;              // uuid v4
  name: string;            // «Семья Ивановых», editable by owner per Q2
  ownerId: string;         // FK users.id — primary owner (multi-owner via members.role)
  treeId: string;          // FK trees.id — 1:1 mirror (см. invariant §3.1)
  description?: string;    // optional, ≤500 chars
  createdAt: string;       // ISO timestamp
  updatedAt: string;       // ISO timestamp (touched on name/description edit)
  deletedAt?: string|null; // soft-delete per Q4 orphan policy
};
```

**Storage**: top-level `db.семьи: Семья[]` array (mirror existing
`db.trees` pattern, `store.js:109`).

**Lifecycle**:
- Create: `seedOnboarding` (existing path) либо explicit
  `POST /v1/semyi`. `tree` создаётся одновременно atomically.
- Update: `PATCH /v1/semyi/:id` — name/description, owner only.
- Soft-delete: `DELETE /v1/semyi/:id` sets `deletedAt`; tree + persons
  preserve (orphan policy Q4).
- Hard-delete: never API-exposed; only background job если все
  members removed AND retention window expired (analog Phase 3.6
  hardDelete pattern, 90d).

### 1.2 `семьяMembers`

```typescript
type СемьяMember = {
  id: string;                    // uuid v4
  семьяId: string;               // FK семьи.id
  userId: string;                // FK users.id
  role: 'owner' | 'editor' | 'viewer';
  joinedAt: string;              // ISO timestamp
  invitedByUserId: string | null;// FK users.id; null when seeded migration
  hasInviteGrant: boolean;       // Q7 — editor with explicit owner-granted invite power
                                  // owner always has invite power; field meaningful for role='editor'
  hiddenAt?: string | null;      // если member soft-removed (rejoin path возможен)
};
```

**Storage**: `db.семьяMembers: СемьяMember[]`.

**Indexes (functional)**:
- by `семьяId` (членский list)
- by `userId` (мои семьи)
- by `(семьяId, userId)` unique pair — invariant: один user только одна
  membership per семья (см. §3.2).

**Roles** (per `SHARED-TREE-PROPOSAL.md` §3.2 table):

| Role | Read tree | Edit persons/relations | Invite others | Promote/demote | Delete семья |
|---|---|---|---|---|---|
| `owner` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `editor` | ✅ | ✅ | only if `hasInviteGrant=true` (Q7) | ❌ | ❌ |
| `viewer` | ✅ | ❌ | ❌ | ❌ | ❌ |

### 1.3 `семьяMemberHiddenPersons`

```typescript
type СемьяMemberHiddenPerson = {
  семьяId: string;     // FK семьи.id
  userId: string;      // FK users.id
  personId: string;    // FK persons.id (within семья's tree)
  hiddenAt: string;    // ISO timestamp
};
```

**Storage**: `db.семьяMemberHiddenPersons: СемьяMemberHiddenPerson[]`.

**Composite key**: `(семьяId, userId, personId)` unique. No `id` field —
record itself идентичен ключу.

**Semantics**: per-user opaque flag «не показывать person X в семье Y
в моём view». Не мутирует tree, не видно другим members. Restored
через DELETE row либо «restore from hidden list» UI affordance.

### 1.4 `семьяInvitations`

```typescript
type СемьяInvitation = {
  id: string;                    // uuid v4
  семьяId: string;               // FK семьи.id
  recipientUserId?: string;      // FK users.id если existing user invited
  recipientEmail?: string;       // если invite-by-email new user
  recipientPhone?: string;       // если invite-by-phone new user
  role: 'editor' | 'viewer';     // pre-decided role, default 'viewer' per Q1
  invitedByUserId: string;       // FK users.id
  createdAt: string;             // ISO timestamp
  expiresAt: string;             // default 30d per §7.4 Q2 follow-up; PATCH-able by owner
  status: 'pending' | 'accepted' | 'rejected' | 'expired' | 'revoked';
  acceptedAt?: string | null;
  rejectedAt?: string | null;
  revokedAt?: string | null;
  revokedByUserId?: string | null;
};
```

**Storage**: `db.семьяInvitations: СемьяInvitation[]`.

**State machine** (sources: Phase 6.5 revocation precedent
`store.js:17110+ kinshipChecks`):

```
                  +-------+
                  | pending |
                  +----+----+
                       |
       +---------------+----------------+----------+
       v               v                v          v
   accepted        rejected         expired    revoked
   (terminal)     (terminal)       (terminal) (terminal)
```

- `pending` → `accepted` only by `recipientUserId` (либо by user matched
  via email/phone at accept time, mirrors Phase 6.5 acceptance pattern).
- `pending` → `rejected` only by recipient.
- `pending` → `revoked` only by inviter либо семья owner.
- `pending` → `expired` automatically (background job либо lazy-on-read).

Migration: existing `treeInvitations` (`store.js:133`) → `семьяInvitations`
с `role='viewer'` default (Q1 safest).

### 1.5 `семьяBrowseTokens`

```typescript
type СемьяBrowseToken = {
  id: string;
  семьяId: string;
  token: string;            // long random — URL-safe base64 (32 bytes entropy)
  createdByUserId: string;  // FK users.id (owner либо editor с grant)
  createdAt: string;
  expiresAt: string;        // default 7d per §3.4 Journey 4, PATCH-able
  revokedAt?: string | null;
  lastUsedAt?: string | null; // optional analytics
};
```

**Storage**: `db.семьяBrowseTokens: СемьяBrowseToken[]`.

**Usage flow** (per `SHARED-TREE-PROPOSAL.md` §3.4 Journey 4):
1. Owner либо editor-с-grant generates → returns shareable URL
   `https://rodnya-tree.ru/browse/{token}`.
2. Recipient opens link → backend resolves token → ephemeral
   read-only session (no persistent membership, no record in
   `семьяMembers`).
3. Browse session limited по token expiry. Token revoke возможен
   anytime.

**Security**: token = capability. Treat как Bearer secret. Не log
plaintext в audit (log SHA256 prefix).

---

## 2. Role transitions

### 2.1 Promote / demote

| From → To | Allowed by | Pre-conditions | Side-effects |
|---|---|---|---|
| viewer → editor | owner | — | None |
| editor → owner | owner | — | invitee получает invite-grant transition (owner always has это implicitly) |
| owner → editor | owner | ≥1 другой active owner remains после change (invariant §3.3) | Если member was last owner with `hasInviteGrant=true` editors, no automatic promotion другого. Recommend banner. |
| owner → viewer | owner | ≥1 другой active owner | Same as above |
| editor → viewer | owner либо self | — | Cancel pending invitations issued by этим editor stay (recipient still accept/reject). |
| editor `hasInviteGrant` toggle | owner | — | Cancel-pending-invitations option в UI (расширение) |

### 2.2 Member kick / leave

| Operation | Allowed by | Pre-conditions | Side-effects |
|---|---|---|---|
| Kick member | owner | Target не последний owner | Hidden persons rows для kicked user cleared. Pull-target persons preserved. |
| Leave (self) | self | Если self=owner: ≥1 другой active owner | Same as kick. Cancel pending invitations issued by leaver. |

### 2.3 Invitation flow

| Step | Actor | Result |
|---|---|---|
| Create invitation | owner либо editor-with-grant | `семьяInvitations` row, push к recipient если existing user |
| Accept | recipient | `семьяMembers` row created с role=invitation.role |
| Reject | recipient | invitation.status='rejected' |
| Revoke | inviter либо owner | invitation.status='revoked' |
| Expire | system (lazy on read либо background sweep) | invitation.status='expired' |

---

## 3. Invariants (enforced at store layer)

### 3.1 One-tree-per-семья

`семья.treeId` unique across non-deleted семьи. Tree, который ссылается
на семья (`tree.семьяId` reverse FK добавляем для O(1) lookup, см. §6
audit) — точно одна семья.

Migration: при «Объединить семьи» merge consolidates 2 trees → 1; old
tree.id orphaned либо deleted per §7.4 Q1 audit (TBD by Артём).

### 3.2 Membership uniqueness

`(семьяId, userId)` unique. User cannot have multiple membership rows
в одной семье. Если пытается принять invitation когда already member —
no-op (либо update role если invitation role > current role).

### 3.3 At-least-one-owner invariant

```
COUNT(семьяMembers WHERE семьяId = X AND role = 'owner' AND hiddenAt IS NULL) >= 1
```

Enforce при:
- Demote owner → editor/viewer
- Kick owner
- Self-leave owner

Если single-owner attempts demote — backend returns error
`SINGLE_OWNER_DEMOTE_FORBIDDEN`. UI suggest «promote another member to
owner first».

Семья deletion bypasses этот invariant (owner deleting семья — all
members lose access regardless of role).

### 3.4 Role hierarchy для invite grant

`hasInviteGrant=true` allowed только если `role='editor'`. Owner
implicitly has invite power (field meaningless). Migration: при
demote editor→viewer reset `hasInviteGrant=false`.

### 3.5 Twin person across семей через identity link

`personIdentities` row may have multiple `personIds[]` distributed
across семьи. Invariant per existing Phase 3 design (`store.js:4996+`):
- Each `personId` ∈ exactly one `personIdentities` row.
- `personIdentities.personIds[]` no duplicates.
- На pull-selectively: new person row created, identity row updated
  (push к existing identityIds[] либо create new identity).

Семья rewrite preserves этот invariant. Pull `bulkImportPersonsToTree`
(store.js:9573-9774) уже maintain'ает.

### 3.6 Hidden filter scope

`семьяMemberHiddenPersons.personId` обязательно references person в
этой семье tree. Если person deleted → hidden row cascade-deleted
(consistency cleanup в background job либо lazy on read).

Cross-семья case: если twin person в семье X скрыт у user Y, в семье Z
другой twin (linked identity) НЕ скрыт automatically. Hide filter
строго scoped per (семья, user, personId) triple.

---

## 4. Migration mapping (data-side spec)

Detailed implementation в `MIGRATION-DRYRUN.md`. Здесь — high-level
shape transformation.

### 4.1 Per-user семья seeding

```
Input:  db.users → 70 rows
        db.trees → 15 rows (with tree.creatorId + tree.memberIds[])

Output: db.семьи     → ≥70 rows («Моя семья» per user, plus shared)
        db.семьяMembers → ≥70 rows (each user as owner of своя семья)
```

Idempotent: повторный run не дублирует. Marker — `migrationStatus.treesToSemyi = "complete-v1"`.

### 4.2 Shared tree → multi-member семья

Existing `tree.memberIds.length > 1` cases (например Артём поделился
с мамой):
- tree.creatorId → семья.ownerId + role='owner'
- tree.memberIds (except creator) → семьяMembers с role='editor' per
  Q1 ИЛИ role='viewer' default per Q1 (Артём favors viewer safer).
  Tie-breaker: existing shared trees мигрируем как viewer (safest,
  owner может promote после migration banner).

### 4.3 Identity links → twins

`db.personIdentities` (75 в prod) — no schema change. Identity rows
preserve `personIds[]` distribution. Phase B UI отображает как «twin»
badge.

### 4.4 Existing treeInvitations

In-flight `treeInvitations` (status=pending) → `семьяInvitations` с:
- role='viewer' (Q1 default safe)
- expiresAt = createdAt + 30d (если original не expired)
- Original treeInvitation status='migrated' (terminal, audit trail).

### 4.5 Tree.creatorId / memberIds compat shim

Phase B dual-write период (~3 months):
- Backend writes к `семьяMembers` (source of truth) AND maintains
  `tree.memberIds[]` derived projection.
- Backend reads: семья-aware endpoints читают `семьяMembers`; legacy
  tree endpoints читают `tree.memberIds` (которые в sync через
  derived projection).
- After 3 months observation + 95% app-update — drop legacy
  `tree.memberIds[]` array в single backend release.

---

## 5. Pull-selectively detail (twin person create)

Per `SHARED-TREE-PROPOSAL.md` §3.4 Mode 3. Backend leverages existing
`bulkImportPersonsToTree` (store.js:9573-9774).

**Endpoint** (новый Week 2-3):

```
POST /v1/semyi/:targetSemyaId/pull
Body: {
  sourceSemyaId: string,
  sourcePersonId: string,
  includeRelations?: 'direct' | 'lineage' | 'none',  // default 'direct'
  // sourceBrowseToken: string (если actor browsing as guest, не member)
}
Response: 201 {
  pulledPerson: { id, identityId, ... },
  identityLink: { identityId, twins: [...] },
  bridgedRelations: [{ id, ... }],
}
```

**Authorization gate** (extension `requireSemyaAccess` per audit §6.3):
- Actor должен быть member targetSemyaId (role >= 'editor').
- Source access: либо member sourceSemyaId (any role), либо valid
  `семьяBrowseToken` для sourceSemyaId.

**Side-effects** (mirror existing bulkImport):
- Если sourcePerson.identityId уже linked к existing person в target
  семья tree → no-op (returns existing twin info).
- Иначе создаётся new person в target tree с identityId, либо new
  identity если source person was anonymous.
- Bridged relations: parent/spouse/child edges к existing persons
  в target tree если identityId match.
- Audit log: новый change type `person.pulled-from-semya`
  с `{sourceSemyaId, sourcePersonId, sourcePersonName}` detail.

---

## 6. Browse mode detail (read-only access)

Per `SHARED-TREE-PROPOSAL.md` §3.4 Mode 2.

**Token generation**:
```
POST /v1/semyi/:id/browse-tokens
Auth: семья owner либо editor (no grant required для self-generated browse)
Body: { expiresInDays?: number (default 7, max 30) }
Response: 201 { token, expiresAt, shareUrl: "https://rodnya-tree.ru/browse/{token}" }
```

**Browse session**:
```
GET /v1/semyi/:id/browse?token=...
No auth required (token is auth)
Response: 200 семья's tree snapshot (read-only)
  - persons + relations as-is
  - photos НЕТ (privacy boundary, см. §3.5 proposal)
  - person attributes (sensitive contacts) НЕТ
  - branchPersonViews → only `label` field exposed
```

**Pull-selectively from browse**:
- Browse user calls `POST /v1/semyi/:myId/pull` с
  `sourceBrowseToken` (per §5).

**Token revocation**:
```
DELETE /v1/semyi/:id/browse-tokens/:tokenId
Auth: owner либо token creator
```

**Privacy posture**: browse мode = «open читать canonical tree shape +
names, не leaks photos/comments/sensitive data». Matches Article 23
GDPR «data minimization» интуицию.

---

## 7. Personal hide filter detail

Per `SHARED-TREE-PROPOSAL.md` §3.3.

**Hide endpoint**:
```
POST /v1/semyi/:id/hidden-persons
Body: { personId: string }
Auth: семья member (any role)
Response: 201 { семьяId, userId, personId, hiddenAt }
```

**Unhide endpoint**:
```
DELETE /v1/semyi/:id/hidden-persons/:personId
Auth: same row owner либо семья owner (override)
```

**List endpoint** (для settings UI):
```
GET /v1/semyi/:id/hidden-persons
Response: 200 [{ personId, hiddenAt, personSummary: { id, primaryName } }, ...]
```

**Read-path filtering**:
- `GET /v1/semyi/:id/tree` либо equivalent — backend filters hidden
  persons из response (если actor имеет hide row для них).
- Relations связанные с hidden persons остаются в response с
  `hiddenEndpoint: true` flag — frontend renders «скрытый родственник»
  placeholder в graph либо skip render.

**No notification when user hides** — strictly local action, other
members не learn о hide.

**Cross-семья**: hide filter scoped per (семья, user). Twin в другой
семья НЕ hidden automatically (per invariant §3.6).

---

## 8. Edge cases + future-proofing

### 8.1 User в multiple семьях одновременно

Day 1 design (per `SHARED-TREE-PROPOSAL.md` §3.1). User session
contains `currentSemyaId` (либо frontend top-level switcher
manages context). Backend endpoints all семья-scoped explicit, no
ambient context (avoids «edited wrong tree» class of bugs).

### 8.2 Семья с identity-linked persons из чужих семей (twin chain)

Пример: дядя Коля twin в семья A, twin в семья B, twin в семья C —
один `personIdentity` с three `personIds[]`. Update в семья A
propagates через `_propagateIdentityFields` (store.js:9906) с
opt-in conflict surfacing.

Caveat: scale concern если identity в 100+ семьях (см. audit §7.4
follow-up Q3). Sub-millisecond at small scale; cap либо async batch
если становится bottleneck.

### 8.3 Семья orphan after all members leave

If все members leave (including owners), семья orphaned. Current
spec (per `SHARED-TREE-PROPOSAL.md` §3.2): «If last owner leaves —
семья orphaned (см. open question #4 — answered: orphan policy)».

Cleanup background job (extension hardDeleteExpired
store.js:17347) — после 90d window orphaned семьи (no members) hard-
delete. Persons preserved если есть identity links to other семьи;
если orphan persons (no twin elsewhere) — также soft-delete then
hard-delete после window.

### 8.4 Concurrent owner edits

Owner A demotes Owner B → Editor at same millisecond Owner B
demotes Owner A → Editor. Race condition: оба success → семья без
owners (violates §3.3 invariant).

Mitigation: backend serial check via existing FileStore lock pattern
(store.js:1100-1200 area). Atomic «verify ≥1 owner after change»
inside lock window. Second concurrent write detects empty-owner-set
post-change → rejects с `SINGLE_OWNER_DEMOTE_FORBIDDEN`.

### 8.5 Browse token sharing chain

Token = capability. User A generates token, shares ссылку c user B,
user B forwards to user C. User C accesses → semантически OK (token
не expires per access; expires per time window).

Если concern: future feature add «browse token tied to single user»
(server records first-user that resolves token, rejects subsequent
different users). Day 1 — unrestricted forward (matches Telegram
public channel link UX).

---

## 9. Cross-references

| Concept | Doc |
|---|---|
| Phase B vision + journeys | `SHARED-TREE-PROPOSAL.md` |
| Current backend state + risks | `week-1/BACKEND-AUDIT.md` |
| Migration script + verification | `week-1/MIGRATION-DRYRUN.md` (next) |
| Week 2-3 implementation kickoff | `week-1/WEEK-1-SUMMARY.md` (final) |
| Architectural ADRs | `DECISIONS.md` (historic) |
| Phase 3 schema | `IDENTITY-MATCHER.md`, `SCHEMA.md`, `AUDIT.md` |

---

**Doc complete.** Total ~420 LOC. Reference paths verified against
audit findings. Ready for Week 2-3 backend implementation when Артём
signs-off на этот entity schema.
