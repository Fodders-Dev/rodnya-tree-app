# Backend audit — Phase B Week 1

> Investigation для federated семьи rewrite. Read-only pass по
> ~19854 LOC backend (store.js + 6 route files + middleware из app.js).
> NO code changes этого таска. Reference doc для Week 2-3 implementation.
>
> Read scope: `backend/src/store.js` (17552 LOC), `backend/src/routes/tree-routes.js` (1383 LOC, 35 endpoints — Артёмов hint «18» подсчитан без public + grants/conflicts/digest/import/extended-network/include-rules subroutes), `graph-person-routes.js` (320 LOC, 8 endpoints), `graph-routes.js` (80 LOC, 1 endpoint), `onboarding-routes.js` (71 LOC, 3 endpoints), `kinship-checks-routes.js` (277 LOC, 5 endpoints), `tree-invitation-routes.js` (171 LOC, 3 endpoints), permission gates из `app.js` lines 823-1834.
>
> Source proposal: `docs/connected-trees-refactor/SHARED-TREE-PROPOSAL.md`.

---

## 1. Current entity inventory

### 1.1 Top-level entities в `store.js`

EMPTY_DB definition: `store.js:49-159`. NormalizeDbState mirror: `store.js:161-271`. Все коллекции хранятся в едином JSON документе (FileStore) с idempotent `_syncGraphFromLegacy(db)` rebuild на каждом read+write (`store.js:11791-11903`).

| Entity | Definition | Purpose | Phase B treatment |
|---|---|---|---|
| `users` | `store.js:49`, `createUser` 6099 | account identity, profile | STAYS |
| `sessions` / `authHandoffs` / `passwordResetTokens` | 50-53 | auth state | STAYS |
| `trees` | 109, `createTree` 7476-7567 | container «дерево + memberIds + creatorId» | WRAPPED (один tree per семья, lifecycle owned by семья entity) |
| `persons` | 110, `createPerson` 9417-9553 | per-tree person row, `treeId+identityId+userId` | WRAPPED (per-семья shared canvas; relationships в семье tree, identity link spans семей) |
| `relations` | 117, `upsertRelation` 12283-12658 | per-tree edge (parent/child/sibling/spouse) | STAYS (no schema change, scoped k семье tree через treeId) |
| `personIdentities` | 111, `createPersonIdentityRecord` 4996-5016 | cross-tree «same human» linking | STAYS — становится «twin link across семей» (см. §4.3) |
| `personAttributes` | 112, `createPersonAttributeRecord` 5018 | per-identity sensitive fields (contacts category) | STAYS |
| `graphPersons` | 89, `_syncPersonToGraph` 10108-10252 | canonical merged node per identity, `legacyPersonIds[]` keyed by identityId | STAYS — `userId/createdBy` = owner remains. Семья does NOT replace graphPerson owner model. |
| `graphRelations` | 90, `_syncRelationToGraph` 10402-10501 | dedup'нутые edges between graphPersons | STAYS |
| `branches` | 91, `_syncTreeToBranch` 10254-10320 | per-user filtered view над graph + includeRules | WRAPPED (branch.legacyTreeId mirrors tree.id 1:1; в federated model branch ≈ семья's filtered view, includeRules могут указывать на специфический семья slice) |
| `branchPersonViews` | 92, `_syncPersonToGraph` 10201-10229 | per-(branch, person) editorial slot (notes/familySummary/bio/visibility/label) | STAYS (per-семья editorial annotation; same shape, different scope) |
| `graphPersonEditGrants` | 99, `addGraphPersonGrant` 10744-10805 | per-person explicit grants (edit/merge-consent/soft-delete) | STAYS BUT subordinate to семья membership (см. §7.2 Q7) |
| `treeInvitations` | 133, `createTreeInvitation` 12919-12964 | accept/decline join → adds to tree.memberIds | REPLACED (семейные invitations carry role; см. §6.3) |
| `kinshipChecks` | 129, `createKinshipCheck` 17110-17183 | BFS «мы родственники?» bilateral consent + revoke | STAYS (operates на user-level identity, не tree/семья boundary) |
| `onboardingStates` | 132, `seedOnboarding` 16822-16968 | wizard progress + first-tree seeding | WRAPPED (seed creates семья + Моя семья tree вместо bare tree) |
| `migrationStatus` | 108 | one-shot migration ledger | STAYS, extended (новый key e.g. `treesToSemyi: "complete-v1"`) |
| `treeChangeRecords` | 134, `_appendTreeChangeRecord` (called from createPerson/updatePerson/deletePerson/upsertRelation/deleteRelation/linkPersonsByIdentity) | audit log per-tree | WRAPPED (передаётся через семья-context, треккер уже принимает treeId — без schema change работает) |
| `circles` / `circleMembers` | 200-203, `ensureDefaultCirclesForTree` 703-748, `ensureAutoCirclesForTree` 970-1073 | per-tree «Всё дерево / Избранные / descendants_of / ancestors_of / pair / custom» | STAYS (per-семья auto-derived, существующий код auto-rebuilds на write) |
| `posts` / `stories` / `comments` / reactions | 137-145 | branch-scoped social content | WRAPPED (post.branchIds — фан-аут логика уже multi-branch ready, см. `resolvePostAudienceUserIds` 14273-14294) |
| `chats` / `messages` / `calls` / drafts / pins | 118-123 | messaging | STAYS (out of Phase B scope per §8 proposal) |
| `relationRequests` | 124, `createRelationRequest` 12802 | per-tree «я родственник этого person'а» request | STAYS (могут жить под семьёй; сейчас scoped по treeId уже) |
| `mergeProposals` / `identityClaims` | 115-116 | bilateral merge / claim consent flows | STAYS |
| `dismissedIdentitySuggestions` / `identityFieldConflicts` | 58, 66 | per-user dismissal log + per-target propagation conflict surfacing | STAYS |
| `notifications` / `pushDevices` / `pushDeliveries` | 135, 146-147 | push + in-app | STAYS (auto-refresh `tree_mutated` rebroadcasts cleanly) |
| `hardDeleteAudit` / `hardDeleteLastRunAt` | 152, 158 | Phase 3.6 background job ledger | STAYS |
| `reports` / `blocks` | 142-143 | moderation | STAYS |
| `profileContributions` | 144 | suggest-edit на чужой profile | STAYS |

### 1.2 Entity relationship diagram

```
users ──────────── identityId ──────────────────────────┐
  │                                                     │
  │ creatorId                                           ▼
  │                                            personIdentities
  ▼                                              ┌─ id            ◀── userId (claimedByUserId)
trees ──── creatorId ─────► users                │  primaryPersonId
  │  memberIds[] ─────────► users               │  personIds[]
  │                                              │  stewardUserIds[]
  └─► persons (treeId)                           │
        │  userId    ───────► users              │
        │  identityId ──────────────────────────┘  (one-to-many: identity has N persons across trees)
        │  creatorId ───────► users
        │
        └─► relations (treeId, person1Id, person2Id)

graphPersons ── id == personIdentities.id ───── userId / createdBy
  │  legacyPersonIds[] ──► persons.id (one identity → multiple per-tree persons)
  │  visibility / visibilityOverride / deletedAt / hardDeleteScheduledAt
  │
  └─► graphPersonEditGrants (graphPersonId, granteeUserId, scope)

graphRelations ── id (== first legacy relation id) ───── person1Id/person2Id ──► graphPersons.id
  │  legacyRelationIds[] / legacyTreeIds[]
  │  relation1to2 / relation2to1 / parentSetId / unionId
  │  deletedAt (tombstone когда последний legacyRelationId дропается)

branches ── id == legacyTreeId 1:1 ──── ownerId / memberIds[]
  │  includeRules { type: manual/blood-from-me/descendants-of/ancestors-of, anchorPersonId, maxHops, manualPersonIds[] }
  │
  └─► branchPersonViews (branchId, personId == graphPerson.id, legacyPersonId)
        ├─ label / photoOverride
        └─ notes / familySummary / bio / visibility (per-branch editorial)

treeInvitations (treeId, userId, role: 'pending', addedBy) → respond → tree.memberIds push
kinshipChecks (initiatorUserId, targetUserId, status: pending/accepted/rejected/expired/revoked, result)
onboardingStates (userId, completed, currentStep, treeId, personIds[])

posts (treeId, branchIds[], authorId, anchorPersonIds[], circleId)
stories (treeId, authorId, circleId, anchorPersonIds[])
comments (postId, authorId, parentCommentId)
circles (treeId, kind: all_tree/favorites/descendants_of/ancestors_of/pair/custom, anchorPersonId/anchorPersonIds[])
circleMembers (treeId, circleId, identityId)
```

Notable: `graphPerson.id === personIdentity.id === branchPersonView.personId` — keyed by identity, не legacy person.id (`store.js:10123-10154`). `branch.id === legacyTreeId === tree.id` (`store.js:10262-10268`) → один-к-одному mirror, branches не отдельный entity сейчас.

### 1.3 Phase 3 identity layer detail

Two-tier model: legacy «persons» — per-tree shape (со всеми editorial полями), graph — canonical merged view.

**graphPersons.legacyPersonIds** (`store.js:10140-10177`):
- One graphPerson row per identityId — все persons sharing identityId фолдятся в один canonical node.
- `legacyPersonIds[]` array list'ит legacy persons.id, contributing к этому graph row.
- При `_syncPersonToGraph` если identityId уже есть graphPerson, добавляем legacy person.id в array; если новый — создаём graphPerson с `legacyPersonIds: [legacyPerson.id]`.
- `GRAPH_PERSON_CANONICAL_FIELDS` (name/maidenName/gender/birthDate/deathDate/isAlive/birthPlace/deathPlace/photoUrl/primaryPhotoUrl/photoGallery — `store.js:9891-9904`) propagate ме от legacy → graph при каждом sync; `_propagateIdentityFields` (9906-10091) обратно push'ит на siblings в других trees.

**graphRelations.legacyRelationIds** (`store.js:10458-10489`):
- Dedup ключ: `buildGraphRelationDedupKey(p1g, p2g, relation)` (migration-utils) — нормализует endpoints + relation type.
- Если новое relation совпадает с existing graph row → push в `legacyRelationIds[]`; иначе создаём fresh graph row.
- `legacyTreeIds[]` array tracks все trees, contributing этот edge.
- При hard-delete последнего legacy relation row → `deletedAt = nowIso()` (10416-10418).

**personIdentities** (`store.js:4996-5016`, `linkPersonsByIdentity` 8452-8585):
- Cross-tree linking shape: `{ id, userId, claimedByUserId, primaryPersonId, personIds[], isLiving, isPublicDiscoverable, stewardUserIds[], mergedInto }`.
- Идея: «дядя Коля» в моём tree и «Николай Иванов» в маминой tree → один personIdentity с двумя personIds.
- `linkPersonsByIdentity` (8452-8585): merges два identity records: prefers claimed-by-user one as canonical, retires the other through `mergedInto`, reattaches all persons. Conflict guard: если оба claimed by разными users → throws `CONFLICTING_IDENTITIES` (8487-8500).
- `_attachPersonToIdentity` / `_reconcilePersonIdentities` / `_ensureUserIdentity` обеспечивают invariants (вызовы рассеяны по 7517, 8020, 9433, 9533, 16880).
- `_propagateIdentityFields` (9906-10091) с conflict surfacing через `identityFieldConflicts` (9988-10046) + per-target `lastPropagatedFields` snapshot для distinguish «out-of-date target» vs «local edit».

**branchPersonViews** (Phase 3.1, `store.js:10201-10229`):
- Per-(branch, person) editorial slot: notes / familySummary / bio / visibility / label / photoOverride.
- Composed lazily в `_buildPersonViewFromGraph` (11725-11779): база — legacy person record, override canonical fields из graphPerson, editorial из branchPersonView.
- На read: `getTreeGraphSnapshot` (12222-12248) maps each legacy person through этот helper.

**branches + includeRules** (Phase 4 extended network, `store.js:10254-10320`, `_buildBranchVisiblePersonIds` 11592-11629):
- Default `{type: 'manual', manualPersonIds[], anchorPersonId, maxHops: 5}`.
- Types: `manual` / `blood-from-me` (BFS от viewer self-node) / `descendants-of` (directional BFS) / `ancestors-of` (directional BFS).
- `manualPersonIds` живет на graphPerson.id (= identityId) level — НЕ на legacy person.id (10247-10250). Это значит включение person в branch survives identity merge.

Critical observation: вся «cross-tree» нагрузка ПРОЕЗЖАЕТ через identity layer. **Federated семьи можно реализовать как «семья = группа users sharing один tree контекст + один branch с manual includeRules covering их identities» БЕЗ rewrite identity layer** — wrapping а не replacement.

---

## 2. Permission model

### 2.1 Tree-level access control

Главная gate: `requireTreeAccess` (`app.js:1724-1741`):
```js
const hasAccess =
  tree.creatorId === req.auth.user.id || memberIds.includes(req.auth.user.id);
```
Бинарный: ты creator/member ИЛИ нет. Нет roles, нет viewer/editor.

Read access:
- `GET /v1/trees/:treeId/persons` (`tree-routes.js:362`) — requireTreeAccess
- `GET /v1/trees/:treeId/relations` (1142) — requireTreeAccess
- `GET /v1/trees/:treeId/graph` (1154) — requireTreeAccess
- `GET /v1/trees/:treeId/history` (1122) — requireTreeAccess
- `GET /v1/trees/:treeId/digest` (600) — requireTreeAccess
- `GET /v1/trees/:treeId/extended-network` (1183) — requireTreeAccess

Tree mutations: разъезжаются между tree-access (structural ops) и graphPerson-edit (person ops). См. §2.2.

Public access: `requirePublicTree` (referenced 234, 254, 267) — для `isPrivate === false` trees через `publicSlug`. Unauth allowed. Используется только legacy анонимного web preview, не критично для семья rewrite.

### 2.2 Graph-person edit grants (Phase 3.2)

Gate: `requireGraphPersonEdit(req, res, treeId, personId, scope)` (`app.js:1759-1813`).

Логика layered:
1. `requireTreeAccess(treeId)` — viewer должен быть на дереве (1761).
2. Поиск graphPerson по legacyPersonId (1770). Если null (sync edge case) → fall through к tree-access only (1773-1776).
3. Anonymous (`graphPerson.userId === null`) — tree-access достаточен (1778-1781). Collaborative editing на «dummy slots».
4. Claimed (`graphPerson.userId !== null`):
   - Owner → проход (1783-1786).
   - Active grant per scope (1789-1801).
   - Иначе 403 с scope-specific message.

Scopes (validated в `addGraphPersonGrant`, store.js:10751): `"edit"` / `"merge-consent"` / `"soft-delete"`.

Grant lifecycle (`graphPersonEditGrants` collection):
- `addGraphPersonGrant` (store.js:10744-10805): owner-only issuance. Self-grant rejected (10760-10762). Idempotent — re-issue same triple returns existing active. Revoked rows preserved (audit trail), new fresh row pushed на revoke + re-grant.
- `revokeGraphPersonGrant` (10807-10842): owner-only revoke, sets `revokedAt = nowIso()`. Idempotent (10835-10838).
- `listGraphPersonGrants` (10844-10860) — owner-only viewing list of grants на this card.
- `listMyGrantsForUser` (10976) — grantee-side, что мне выписано.
- `listMyIssuedGrants` (10867-10880) — grantor-side, что я выписал.

Routes для grant management: `graph-person-routes.js:45-163` (POST/DELETE/GET).

Используется в:
- `PATCH /v1/trees/:treeId/persons/:personId` (tree-routes.js:861, scope='edit')
- `DELETE /v1/trees/:treeId/persons/:personId` (961, scope='soft-delete')
- `POST/PATCH/DELETE /v1/trees/:treeId/persons/:personId/media/*` (997, 1043, 1081, scope='edit')
- `POST /v1/trees/:treeId/persons/:personId/link-identity` (459, scope='merge-consent' на оба endpoints, 485-500)

НЕ используется:
- `POST /v1/trees/:treeId/persons` (771, create) — tree-access only.
- `POST /v1/trees/:treeId/relations` (1247, structural) — tree-access only, deliberate per Phase 3.2 DECISIONS «collaborative структурирование» (комментарий 1253-1260).
- `DELETE /v1/trees/:treeId/relations/:relationId` (1347) — tree-access only, тот же rationale (1356-1359).

### 2.3 Visibility model (Phase 3.4)

Visibility levels: `"owner-only"` / `"connected-via-blood-graph"` (default) / `"public"`.

Effective visibility computation: `_effectiveGraphPersonVisibility` (`store.js:11480-11497`):
- `visibilityOverride === true` → stored value as-is.
- Иначе auto-public для deceased + birthYear < now-100 (historical figures).
- Default `"connected-via-blood-graph"` иначе.

Visibility gate: `_userCanSeeGraphPerson` (`store.js:11504-11539`):
- Owner / active grant holders → always yes.
- Effective `"public"` → yes.
- Effective `"owner-only"` → no.
- Effective `"connected-via-blood-graph"` → BFS check viewer self-node к target через blood-only edges ≤ `_connectedVisibilityMaxHops` (4, `store.js:11430-11432`).

Set/clear endpoints: `PATCH /v1/graph-persons/:graphPersonId/visibility` (`graph-person-routes.js:243`, owner-only-всегда), `DELETE /v1/graph-persons/:graphPersonId/visibility-override` (285, clear override).

Read gate consumers:
- Cross-tree picker `/v1/persons/search` (tree-routes.js:304-360, filtered via `filterLegacyPersonsByGraphVisibility` 335-338).
- Identity-suggestions `/v1/trees/:treeId/persons/:personId/identity-suggestions` (407-451, filter at 425-435).
- Graph relation chain `/v1/graph/relation` (graph-routes.js:34-49, gate на оба endpoints, hide intermediates 60-68).
- Extended network `/v1/trees/:treeId/extended-network` (tree-routes.js:1183-1245, gate inside `getExtendedNetworkSlice` 11146-11167).
- `requireGraphPersonRead` (`app.js:1822-1834`) — fail-closed для grant routes.

Sensitive attributes (`personAttributes` field=`"contacts"`): owner-only ВСЕГДА regardless visibility level (`_userCanSeeSensitiveAttributeField` 11576-11585, set `_sensitiveAttributeFields` 11441-11443).

### 2.4 Kinship check permissions (Phase 6/6.5)

State machine: `pending → accepted | rejected | expired | revoked`.

Permission checks:
- **Create** (`POST /v1/kinship-checks`, kinship-checks-routes.js:39): any authenticated user. Self-check rejected (store.js 17116-17118, returns SELF_CHECK_FORBIDDEN). Rejection cooldown 30d (17137-17160).
- **Respond** (`POST /v1/kinship-checks/:checkId/respond`, kinship-checks-routes.js:120): only target — pre-checked at route layer 140-145, defense-in-depth в store via `targetUserId` field reference при поиске.
- **Revoke** (`POST /v1/kinship-checks/:checkId/revoke`, Phase 6.5, kinship-checks-routes.js:205): only initiator (218-223 + store `revokeKinshipCheck` 17290-17313 NOT_INITIATOR check).
- **List issued** (`GET /v1/me/kinship-checks/issued`, 109): caller-scoped к initiator field.
- **List received** (`GET /v1/me/kinship-checks/received`, 98): caller-scoped к target field.

TTL: 14 days (`_kinshipCheckTtlMs` store.js:17084-17086). Lazy sweep at read paths (`_sweepExpiredKinshipChecks` 17095-17108) — no background job, mutations on-read.

Notification dispatch (kinship-checks-routes.js: kinship_check_received/confirmed/declined/revoked types):
- Create → target via `kinship_check_received` (76-89), ONLY on first creation (idempotency 76).
- Respond accepted/rejected → initiator via `kinship_check_confirmed`/`kinship_check_declined` (175-196).
- Revoke → target via `kinship_check_revoked` (258-270).
- Expired: пометка в state, dispatch deferred — комментарий 14-16 указывает «lazy dispatched at endpoint when sweep triggers», но в коде я не вижу explicit dispatch в `_sweepExpiredKinshipChecks` или routes для `kinship_check_expired`. Возможно gap или handled elsewhere — потенциальная находка для §7.4.

---

## 3. Tree mutations surface

### 3.1 Endpoint inventory tree-routes.js

Полный список 35 endpoints из `tree-routes.js`:

| Method | Path | Line | Mutates | Permission |
|---|---|---|---|---|
| POST | `/v1/trees` | 60 | trees, persons, branches, branchPersonViews, graphPersons, personIdentities | requireAuth (creator becomes owner) |
| PATCH | `/v1/trees/:treeId/include-rules` | 98 | branches.includeRules | requireAuth + tree.creatorId === actor (store `updateBranchIncludeRules` 10886-10920) |
| GET | `/v1/trees/:treeId/include-rules-preview` | 144 | none (preview) | requireAuth + tree-member (`previewBranchIncludeRules`) |
| GET | `/v1/trees` | 190 | none | requireAuth (lists own trees) |
| DELETE | `/v1/trees/:treeId` | 197 | trees, persons, relations, circles, circleMembers, chats, messages, relationRequests, treeInvitations, posts, stories, comments, notifications | requireAuth + creator (cascade) or member (leave) |
| GET | `/v1/public/trees/:publicTreeId` | 234 | none | public (no auth) |
| GET | `/v1/public/trees/:publicTreeId/persons` | 254 | none | public |
| GET | `/v1/public/trees/:publicTreeId/relations` | 267 | none | public |
| GET | `/v1/trees/selectable` | 280 | none | requireAuth |
| GET | `/v1/persons/search` | 304 | none | requireAuth, scoped к viewer's accessible trees |
| GET | `/v1/trees/:treeId/persons` | 362 | none | requireTreeAccess |
| GET | `/v1/trees/:treeId/duplicates` | 374 | none | requireTreeAccess |
| GET | `/v1/trees/:treeId/persons/:personId/identity-suggestions` | 407 | none | requireTreeAccess |
| POST | `/v1/trees/:treeId/persons/:personId/link-identity` | 459 | personIdentities, persons.identityId, treeChangeRecords | requireGraphPersonEdit(merge-consent) on BOTH endpoints |
| DELETE | `/v1/trees/:treeId/persons/:personId/user-link` | 537 | persons (clear userId/identityId) | tree.creatorId === actor (store `unlinkUserFromPerson` 8057-8058) |
| POST | `/v1/trees/:treeId/persons/:personId/dismiss-suggestion` | 567 | dismissedIdentitySuggestions | requireTreeAccess |
| GET | `/v1/trees/:treeId/digest` | 600 | none | requireTreeAccess |
| GET | `/v1/trees/:treeId/conflicts` | 623 | none | requireTreeAccess |
| POST | `/v1/trees/:treeId/conflicts/:conflictId/resolve` | 643 | identityFieldConflicts, persons | requireTreeAccess + target tree check 673 |
| POST | `/v1/trees/:treeId/persons/import` | 704 | persons, relations, treeChangeRecords | requireTreeAccess on source AND target |
| POST | `/v1/trees/:treeId/persons` | 771 | persons, treeChangeRecords, personIdentities | requireTreeAccess. Dispatches `tree_mutated` (810-814) |
| GET | `/v1/trees/:treeId/persons/:personId` | 819 | none | requireTreeAccess |
| GET | `/v1/trees/:treeId/persons/:personId/dossier` | 838 | none | requireTreeAccess |
| PATCH | `/v1/trees/:treeId/persons/:personId` | 861 | persons, treeChangeRecords, identityFieldConflicts (propagation), graphPersons (via sync), branchPersonViews | requireGraphPersonEdit(edit). Dispatches `tree_mutated` (908-912) |
| POST | `/v1/trees/:treeId/persons/:personId/profile-contributions` | 918 | profileContributions | requireTreeAccess |
| DELETE | `/v1/trees/:treeId/persons/:personId` | 961 | persons (hard delete from legacy), relations (cascade), treeChangeRecords, graphPersons (soft-delete +30d schedule), branchPersonViews (orphan cleanup) | requireGraphPersonEdit(soft-delete). Dispatches `tree_mutated` (987-991) |
| POST | `/v1/trees/:treeId/persons/:personId/media` | 997 | persons.photoGallery, treeChangeRecords, propagated siblings | requireGraphPersonEdit(edit) |
| PATCH | `/v1/trees/:treeId/persons/:personId/media/:mediaId` | 1043 | persons.photoGallery, propagated siblings | requireGraphPersonEdit(edit) |
| DELETE | `/v1/trees/:treeId/persons/:personId/media/:mediaId` | 1081 | persons.photoGallery, propagated siblings | requireGraphPersonEdit(edit) |
| GET | `/v1/trees/:treeId/history` | 1122 | none | requireTreeAccess |
| GET | `/v1/trees/:treeId/relations` | 1142 | none | requireTreeAccess |
| GET | `/v1/trees/:treeId/graph` | 1154 | none | requireTreeAccess |
| GET | `/v1/trees/:treeId/extended-network` | 1183 | none (in-memory cache 60s TTL 1182) | requireTreeAccess + `getExtendedNetworkSlice` NOT_TREE_MEMBER check |
| POST | `/v1/trees/:treeId/relations` | 1247 | relations, treeChangeRecords, parentSets/unions plumbing, graphRelations (via sync) | requireTreeAccess (structural, по 3.2 DECISIONS comment 1253-1260). Dispatches `tree_mutated` (1338-1342) |
| DELETE | `/v1/trees/:treeId/relations/:relationId` | 1347 | relations, treeChangeRecords, graphRelations (mark deleted via `_markRelationDeletedInGraph` 11392-11419) | requireTreeAccess. Dispatches `tree_mutated` (1370-1374) |

### 3.2 Mutation propagation

When tree mutation fires:

**graphPersons / graphRelations / branches / branchPersonViews sync**:
- Every `_write(db)` re-runs `_syncGraphFromLegacy(db)` (store.js:11791-11903) — full-scan idempotent rebuild ↑ O(persons+relations+trees).
- Per-mutation hooks: `_syncPersonToGraph` (10108), `_syncRelationToGraph` (10402), `_syncTreeToBranch` (10254), `_markPersonDeletedInGraph` (10322), `_markRelationDeletedInGraph` (11392).
- Comment в `_syncGraphFromLegacy` (11783-11790): «sub-millisecond at ≤100 persons per user. Goes away in Phase 3.4 once we drop legacy mirror». Это означает Phase B можно continue этот sync pattern либо ускорить cutover.

**personIdentities re-evaluation**:
- `_reconcilePersonIdentities(db)` calls scattered (7541, 8033, 9536, 9547, 9767, 11969). Re-runs after person creates/updates/deletes/identity links.
- `_attachPersonToIdentity` (referenced 7539, 8020, 8550) — per-call attachment с re-reconciliation.

**branchPersonViews refresh**:
- Inline в `_syncPersonToGraph` (10201-10229) — upsert per (branchId, personId) row at every person write.
- Orphan cleanup в `_syncGraphFromLegacy` (11825-11828) — drop rows whose legacyPersonId is gone.

**Audit log (`treeChangeRecords`)**:
- `_appendTreeChangeRecord` called from: createPerson 9538, updatePerson 9833, deletePerson 11960-11968, upsertRelation 12497/12538, deleteRelation 12726, linkPersonsByIdentity 8560/8567, bulkImportPersonsToTree 9659, addPersonMedia/updatePersonMedia/deletePersonMedia path (внутри 11976+).
- Identity propagation tagged via `identityPropagation` field in details (10074-10080) — позволяет «mom's birth date changed because someone updated в другом tree».

**Notification dispatch (auto-refresh)**:
- `dispatchTreeMutation` helper (`tree-routes.js:32-59`) — silent `tree_mutated` notification (`{treeId, kind, actorUserId}`).
- Audience: `resolveTreeAudienceUserIds(treeId, {excludeUserId})` (store.js:14205-14263) — union of:
  1. `tree.creatorId`
  2. `tree.memberIds`
  3. Active `graphPersonEditGrants.granteeUserId` для persons в этом tree
  4. `graphPerson.userId` для identity-linked claimed persons в этом tree
- Триггеры: create person 810, update person 908, delete person 987, create relation 1338, delete relation 1370.
- НЕ триггерится для media POST/PATCH/DELETE (997-1119), identity-link (459), conflicts/resolve, dossier, dismissals. Potential gap для §7.3.
- Realtime hub: `realtimeHub?.publishToUser` called inside `createAndDispatchNotification` (`app.js:2342-2369`). Push via `resolvedPushGateway.dispatchNotification` (2364-2366). Silent flag respected на client.

---

## 4. Migration data shape

### 4.1 Current production data state

Артёмовы numbers (production):
- 70 users
- 15 trees
- 351 graphPersons (= ~351 unique identities, 351-many legacyPersons in `legacyPersonIds[]`)
- 75 personIdentities (= 75 cross-tree linked humans, остальные 351-75 = 276 single-tree identities)

Local dev (sample): 9 users, 2 trees, 12 persons, 17 relations, 12 graphPersons, 12 personIdentities, 12 branchPersonViews, 0 grants, 0 kinshipChecks, 0 onboarding, 0 invitations. `migrationStatus.treesToGraph: "complete-v2"`. Каждый person здесь имеет 1:1 identity (no cross-tree links в local dev) — production sample 75/351 = 21% identities span multiple trees.

### 4.2 Schema перевод proposal

| Existing entity | Phase B treatment | Rationale |
|---|---|---|
| `users` | STAYS | accounts shouldn't change. |
| `trees` | WRAPPED (lifecycle moved to семья) | one tree per семья invariant; tree continues holding persons/relations/memberIds. семья.treeId points сюда. |
| `tree.memberIds[]` | WRAPPED → role-based семья.members[] | сейчас flat list, no roles; Phase B нужен `{userId, role, joinedAt}`. Existing memberIds → derived projection из семья.members. |
| `tree.creatorId` | WRAPPED | оставляем — semantic «оригинальный создатель» полезен для audit, но enforcement переходит к семья.ownerId (=owner role member). |
| `persons` | STAYS | per-tree shape работает. Семья не разделяет persons — все members одной семьи видят все persons этой tree. |
| `personIdentities` | STAYS, semantically extended | становится «twin link across семей» (см. §4.3). |
| `personIdentities.stewardUserIds[]` | EXTENDED | можем reuse как «members of семья that have role over этот identity». |
| `graphPersons` | STAYS | canonical merge layer работает независимо от семья boundary. |
| `graphPersons.userId` / `createdBy` | STAYS | owner model (Phase 3.2) — orthogonal к семья membership. Owner может быть в семье X либо нет, edit grants per-card persist. |
| `graphPersonEditGrants` | STAYS BUT extended interpretation | сейчас explicit per-grantee user. В Phase B семья membership неявно даёт «edit anonymous persons» (см. §6.4 для new semantics). |
| `branches` | WRAPPED | один branch per семья tree (existing 1:1 mirror). includeRules continue работать. Можно add `branch.семьяId` foreign key для explicit join. |
| `branchPersonViews` | STAYS | per-семья editorial annotation. |
| `treeInvitations` | REPLACED → `семейноеInvitation` | role-aware, addedBy required, defaultRole='viewer' per Q1. |
| `kinshipChecks` | STAYS | user-to-user, не зависит от семья. |
| `onboardingStates` | WRAPPED | `seedOnboarding` creates семья + tree + persons + relations atomically. State.treeId → state.семьяId. |
| `migrationStatus` | EXTENDED | add `treesToSemyi: "complete-v1"` key. |
| `treeChangeRecords` | STAYS | scoped по treeId уже, transparent через семья tree. |
| `circles` / `circleMembers` | STAYS | per-семья (existing per-tree) automatic. |
| `posts` / `stories` / `comments` / reactions | STAYS | post.branchIds[] уже multi-branch, можно адаптировать к multi-семья. |
| `chats` / `messages` / `calls` | STAYS | out of scope §8. |
| `relationRequests` | STAYS | semantic «я родственник этому person'у» — независим от семья membership. |
| `mergeProposals` / `identityClaims` | STAYS | per-person bilateral consent. |
| `dismissedIdentitySuggestions` / `identityFieldConflicts` | STAYS | per-user/per-target. |
| `notifications` / `pushDevices` / `pushDeliveries` | STAYS | reusable; `tree_mutated` becomes `семья_mutated` (либо просто scope unchanged). |
| `hardDeleteAudit` / `hardDeleteLastRunAt` | STAYS | Phase 3.6 background job полностью compat. |
| `reports` / `blocks` | STAYS | |
| `profileContributions` | STAYS | |

NEW entities Phase B:
- `семьи` (singular: семья): `{id, name, ownerId, createdAt, updatedAt, treeId, description?}`
- `семьяMembers`: `{id, семьяId, userId, role: 'owner'|'editor'|'viewer', joinedAt, invitedByUserId, hasInviteGrant: bool}` — `hasInviteGrant` для editor-can-invite per Q7.
- `семьяMemberHiddenPersons`: `{семьяId, userId, personId, hiddenAt}` per personal hide filter (§3.3 proposal).
- `семьяInvitations`: `{id, семьяId, recipientUserId|recipientEmail, recipientPhone?, role, invitedByUserId, createdAt, expiresAt, status: 'pending'|'accepted'|'rejected'|'expired'|'revoked'}` — расширение текущего treeInvitations.
- `семьяBrowseTokens`: `{id, семьяId, token, createdByUserId, createdAt, expiresAt, revokedAt}` — для read-only browse per §3.4 proposal.

### 4.3 Identity layer preservation

Existing 75 personIdentities в prod становятся twin relationships без data migration:
- Identity rows continue хранить `personIds[]` array, just теперь персоны живут в разных семейных trees вместо «connected per-user trees».
- При первом migration step каждый existing user → auto «Моя семья» containing их existing tree. Cross-tree identities (75) preserve as-is: дядя Коля personId=X1 в семья Ивановых + personId=X2 в семья Кузнецовых, один personIdentity.id linking их.
- Pull-selectively flow (§3.4 proposal) использует existing `bulkImportPersonsToTree` (store.js:9573-9774) которое уже:
  - Map identityId → existing target person (line 9607-9613).
  - Reuse existing target person если identityId уже там (9619-9629).
  - Создаёт new person + identity link если нет (9651-9674).
  - Bridges relations через `bridgeToTarget` (9680-9694).
  - **Это ровно «twin person» concept из §3.4 proposal** — нужно UI hook, не backend rewrite.

Concrete migration mapping (per user, idempotent):
1. For each user in `db.users` без активной семья:
   - Create семья `{id: uuid, name: "Моя семья", ownerId: user.id, treeId: user's existing tree.id, createdAt: now}`.
   - Create семьяMembers row `{семьяId: ↑, userId: user.id, role: 'owner', joinedAt: now, invitedByUserId: null, hasInviteGrant: true}`.
2. For each tree where `tree.memberIds.length > 1` (currently shared trees, e.g. Артём+мама):
   - Map memberIds к семья.members с role='editor' (или viewer per Q1, см. §7.2).
   - Existing `tree.creatorId` → owner role.
   - `tree.memberIds` copy через transition period (read-fan-out compat).
3. For each personIdentity с `personIds.length > 1` (75 в prod):
   - Identity link preserved as-is. UI layer показывает «twin» badge — backend без изменений.
4. graphPersonEditGrants — preserve all. После migration grants работают одинаково (граneeUserId still has access).

Verification queries (Week 4 spec):
- `SELECT COUNT(*) FROM persons` до/после = same (no person row drop).
- `SELECT COUNT(*) FROM personIdentities WHERE jsonb_array_length(personIds) > 1` = 75 (или production current).
- `SELECT COUNT(DISTINCT семьяMembers.userId) = COUNT(*) FROM users` (every user has at least one семья).
- `SELECT COUNT(*) FROM семьи` ≈ `COUNT(*) FROM trees` для Stage 1 (1:1 «Моя семья» per existing tree).

---

## 5. Auth/session integration

### 5.1 Session shape

`requireAuth` (`app.js:823-858`):
- Bearer token из `Authorization` header.
- Resolves к session via `store.findSession(token)` → user via `store.findUserById(session.userId)`.
- Sets `req.auth = {token, session, user, sessionPublicId}`.
- `sessionPublicId` derived from token + instanceId hash (store.js:1277-1289).
- Background session-touch scheduled via `scheduleSessionTouch` (1m min interval per `SESSION_TOUCH_MIN_INTERVAL_MS` = 60_000, store.js:500).

User context available к route handlers: `req.auth.user.id`, `.email`, `.profile.*`, `.identityId`, plus session metadata.

### 5.2 Owner/member resolution

Текущая «tree owner» = `tree.creatorId`. Установлен один раз при `createTree` (store.js:7503). Не меняется (нет API изменить creator). Member list = `tree.memberIds[]`, updated через:
- `ensureTreeMembership(treeId, userId)` (store.js:7936-7968) — adds if absent.
- `respondToTreeInvitation` accept path (12997-13007).
- `linkPersonToUser` (8024-8031).
- `createPerson` с userId attached (9523-9530).
- `removeTreeForUser` leave path (7883-7884) — removes от non-creator members.

Phase B needs adapt для семья ownership:
- `семья.ownerId` analogous к `tree.creatorId`, но multiple owners allowed per §3.2 proposal.
- Promote/demote / kick / leave logic — необходим новый route layer; existing tree-invitation rejection path и tree leave logic дают шаблон.
- При seeding миграции `tree.creatorId` → `семья.ownerId` и role='owner'.

Co-owner constraint per §3.2 proposal: «Owner → editor требует AT LEAST one other owner оставаться». Easy enforce at store layer (count active owner members перед мутацией role).

Existing membership operations — все ставят update на `tree.memberIds` и `tree.members` (legacy alias). После Phase B обе колонки остаются (compat layer), но source of truth → `семьяMembers`.

---

## 6. What stays, what gets replaced, what wraps

### 6.1 STAYS unchanged

- `users` + auth (sessions/handoffs/tokens) — Phase B touches только организационный layer.
- `persons` (legacy per-tree shape) — пер-семья tree continues работать как сейчас.
- `relations` — structural edges scoped по treeId, без schema change.
- `personIdentities` — cross-семья twin linking, identical semantics.
- `personAttributes` — owner-only sensitive fields preserved.
- `graphPersons` / `graphRelations` — canonical merge layer независим от семья boundary.
- `graphPersonEditGrants` — per-card explicit grants, semantically reused (см. §6.4 для interplay).
- `branchPersonViews` — per-(branch, person) editorial annotation.
- `kinshipChecks` (incl. revocation Phase 6.5) — user-to-user, no семья involvement.
- `circles` / `circleMembers` — per-tree (= per-семья tree) automatic.
- `posts` / `stories` / `comments` / reactions — multi-branch fan-out уже работает.
- `chats` / `messages` / `calls` — out of scope §8.
- `relationRequests` — per-tree, no change.
- `mergeProposals` / `identityClaims` — per-person bilateral consent.
- `dismissedIdentitySuggestions` / `identityFieldConflicts` — per-user dismissal/conflict state.
- `notifications` / `pushDevices` / `pushDeliveries` — generic dispatch, payload содержит `treeId` уже compat.
- `hardDeleteAudit` / `hardDeleteLastRunAt` — Phase 3.6 background job полностью compat.
- `reports` / `blocks` — moderation.
- `profileContributions` — suggest-edit на чужой profile.
- `treeChangeRecords` — scoped по treeId уже.
- Identity layer code (`_propagateIdentityFields`, `_reconcilePersonIdentities`, `_syncGraphFromLegacy`, etc.) — unchanged.

### 6.2 WRAPPED (Семья entity layer added above)

- `trees` — каждый tree принадлежит ровно одной семье через `семья.treeId` foreign reference. Tree lifecycle (create/delete) делегируется semья endpoints. Existing tree CRUD endpoints получают compat shim.
- `tree.memberIds[]` — derived projection из `семьяMembers`. Legacy memberIds preserved для backward compat (dual-write).
- `tree.creatorId` — preserved, но enforcement переходит к `семья.ownerId`.
- `branches` — 1:1 mirror tree (existing), continue, optionally add `branch.семьяId` для explicit join.
- `treeInvitations` — replaced by `семьяInvitations` с role-awareness. Существующие в-flight invitations migrate как `role='viewer'` (safest default).
- `onboardingStates` — `seedOnboarding` creates семья + tree atomically; state.treeId compat preserved.
- `migrationStatus` — extended key `treesToSemyi`.
- `posts.branchIds[]` — semantically reused (multi-branch уже multi-семья ready).

### 6.3 REPLACED (new schema)

- **`treeInvitations` → `семьяInvitations`**: добавляется `role` поле (`viewer`/`editor`), addedBy required, expiresAt added (current treeInvitations не имеют expiry), status enum расширен `revoked`. Migration: existing pending treeInvitations → семьяInvitations с role='viewer' (Q1 default).
- **Tree-level access roles**: текущий бинарный creator/member → triple owner/editor/viewer. Existing `requireTreeAccess` (`app.js:1724-1741`) расширяется до `requireSemyaAccess(scope: 'read' | 'edit' | 'admin')` — bool gate based on member role.

### 6.4 NEW (Phase B introductions)

- **`семьи`** entity (см. §4.2 shape) — single source of truth для group identity.
- **`семьяMembers`** — `{семьяId, userId, role, joinedAt, invitedByUserId, hasInviteGrant}`. `hasInviteGrant` boolean per Q7 («editor с invite grant»).
- **`семьяMemberHiddenPersons`** — `{семьяId, userId, personId, hiddenAt}` per §3.3 «personal hide filter».
- **`семьяBrowseTokens`** — `{id, семьяId, token, createdByUserId, createdAt, expiresAt, revokedAt}` для read-only browse per §3.4. Ephemeral session, не persistent membership.
- **Cross-семья pull endpoint** — wraps existing `bulkImportPersonsToTree` (store.js:9573-9774) с разрешением «source = browse-token либо membership in source семья».
- **семья endpoints** (per §6 proposal week 2-3):
  - `POST /v1/semyi`, `GET /v1/semyi/:id`, `PATCH /v1/semyi/:id`, `DELETE /v1/semyi/:id`.
  - `POST /v1/semyi/:id/members`, `PATCH /v1/semyi/:id/members/:userId`, `DELETE /v1/semyi/:id/members/:userId`.
  - `POST /v1/semyi/:id/browse-tokens`, `GET /v1/semyi/:id/browse?token=…`.
  - `POST /v1/semyi/:targetId/pull` (twin person create).
  - `POST/DELETE /v1/semyi/:id/hidden-persons`.

- **Graph person grants interplay**: после Phase B семья editor membership неявно даёт «edit anonymous persons в семья tree» (current Phase 3.2 уже даёт tree-access на anonymous, `app.js:1779-1781`). Claimed persons (graphPerson.userId !== null) continue требовать explicit grants. Это **сохраняет owner model без regressions** — семья membership ≠ implied edit-grant на claimed cards.

---

## 7. Critical findings + Week 2-3 inputs

### 7.1 Architectural fitness verdict

**Yes** — current architecture comfortably supports federated семьи без deep rewrites. Identity layer (Phase 3) и graph layer (Phase 3.1-3.4) уже делают heavy lifting:

1. `personIdentities` + `legacyPersonIds[]` = «twin person» в proposal §3.4 — backend support уже complete, just needs UI affordance.
2. `bulkImportPersonsToTree` (store.js:9573) = «pull selectively» — производственный код уже бридит persons + relations + identity links с idempotency.
3. `graphPerson.visibility` + owner-model + grants = privacy boundary per «семья membership = privacy boundary» из §3.5 proposal. Visibility уже granular per-person; семья boundary wraps multi-person check.
4. `branches` + `includeRules` (4 типа: manual/blood/descendants/ancestors) = wrapper для «semья's view of canonical graph». Existing infrastructure адаптируется без rewrites.
5. `tree_mutated` auto-refresh уже broadcast'ит к union audience (members + edit grants + identity-linked) — Phase B audience просто расширяется до семья.members.

**Нет fundamental блокеров**. Полный rewrite не оправдан — pure additive layer (семья entity + membership table + role gate) plus wrapper logic. Confidence очень высокий.

### 7.2 Q1-Q8 answers feasibility check

- **Q1 viewer default role** — feasible. Текущий treeInvitations не carries role; миграция в семьяInvitations с default role parameter trivial. UI just passes `role: 'viewer'` (or 'editor' explicit). Concern: legacy treeInvitations в-flight на migration момент — choose default role='viewer' safest. Backend gate easy: `if (member.role === 'viewer') reject mutations`.

- **Q2 семья name editable by owner** — feasible. Просто PATCH `/v1/semyi/:id` endpoint с `requireSemyaAccess('admin')`. Notification dispatch existing via `createAndDispatchNotification` к всем members (audience analog `resolveTreeAudienceUserIds` но scoped к семья).

- **Q3 non-relative membership** — feasible. семьяMembers таблица independent от persons. User can be член семьи без person row в её tree. Edge case: при делaying first edit, `seedOnboarding` (`store.js:16822`) сейчас creates self-person; нужно сделать creation optional если user joins existing семья как «professional genealogist». Trivial spec change.

- **Q4 deletion = orphan + notify** — feasible. Existing soft-delete (Phase 3.6) handles graphPerson soft-delete с 30d window. Семья DELETE становится `семья.deletedAt = now()` + members notify; persons + relations preserved (orphan), identity links preserve (twin persons in other семей continue работать). Cleanup background job extends к семья тоже. Notification: 30s pre-deletion confirm dialog client-side + immediate notification on cascade-skip.

- **Q5 identity conflict ask-user** — feasible. Существующий `identityFieldConflicts` collection (store.js:66) + `/v1/trees/:treeId/conflicts/:conflictId/resolve` endpoint (tree-routes.js:643) уже делает «keep / overwrite» UX. Pull-selectively flow добавляет «keep both» (no merge) и «merge with conflict resolution» вариант. Concern: текущий conflict surfacing per-field — extend к whole-person merge proposal либо reuse `mergeProposals` collection (115).

- **Q6 no fixed tree root** — feasible (Phase 4 уже supports). `_buildBranchVisiblePersonIds` (store.js:11592) для `blood-from-me` начинается от viewer self-node; для `descendants-of`/`ancestors-of` от anchor. Frontend tree layout уже rendererable from any node (Phase 4 extended-network view doing it). НИКАКОГО backend rework нужно.

- **Q7 invite grant per-editor** — feasible. Новое boolean field `семьяMembers.hasInviteGrant` (default false). Gate `POST /v1/semyi/:id/invitations` checks `actor.role === 'owner' || (actor.role === 'editor' && actor.hasInviteGrant === true)`. Toggle endpoint: `PATCH /v1/semyi/:id/members/:userId/invite-grant` owner-only.

- **Q8 immediate migration + auto-«Моя семья»** — feasible. Migration script per §4.3 mapping: for each user без active семья, create «Моя семья» с user as owner, existing tree.id linked. Idempotent (already migrated user → skip). Stage-by-stage rollout per §6 proposal week 4. Existing `seedOnboarding` пользовательский flow modified для new семья creation.

**Все 8 ответов technically возможны. Никаких блокеров.**

### 7.3 Surface non-obvious risks

1. **branches Phase 4 layer interplay**: `branch.id === tree.id === семья.treeId` (1:1) сейчас. Когда Phase B добавит «много trees per семья» (если future feature), unique invariant сломается. Recommended: фиксировать «один tree per семья Day 1» — каноническая proposal позиция (§3.3). Если future demand на «несколько trees внутри одной семьи» — separate phase.

2. **Audit log identity propagation**: текущий `treeChangeRecords` фиксирует identity propagation через `identityPropagation` field (store.js:10074-10080). Семья twin pull operations нужно audit explicitly — добавить новый change type `person.pulled-from-semya` с `{sourceSemyaId, sourcePersonId}` detail (analog `importedFrom` в bulkImport 9666-9669).

3. **Realtime hub events (Phase A+B auto-refresh)**: `dispatchTreeMutation` (tree-routes.js:32) сейчас broadcast'ит к union audience. После Phase B audience = `семья.members`. Audience calc нужно адаптировать в `resolveTreeAudienceUserIds` (store.js:14205) — добавить семьяMembers union. CONCERN: текущий audience уже включает «identity-linked users» — это могут быть members разных семей. Нужно decide: rebroadcast к twin-семьям тоже либо только source семья? Per §3.5 «cross-семья identity link не leaks data» — recommend локализованный broadcast (только source семья), explicit «check updates from семья Y» button client-side для twin updates.

4. **Soft-delete (Phase 3.6) interaction с семья orphan policy**: Q4 = orphan (persons preserve). Существующий `_markPersonDeletedInGraph` (10322) soft-delete'ит graphPerson если no legacy person references. При семья DELETE мы НЕ удаляем persons (orphan), значит graphPersons survive — consistent. CONCERN: hardDelete background job (17347-17525) сейчас orphan-cleanup'ит `branchPersonViews` — нужно extend для «семья orphaned branches» (branches without active семья.treeId reference). Не блокирующее, но spec для Week 4.

5. **`graphPerson.userId` change semantics**: при `linkPersonsByIdentity` (8452), identity merge preferences claimed user. Если both claimed by different users → CONFLICTING_IDENTITIES throw. В federated семьи случай: дядя Коля twin в семья Y (claimed by мамой), pulled в моя семья (anonymous initially). Если мама позже claim'нет дядю в моей семье тоже → currently OK (один identity, мама is canonical user). НО если двое разных пользователей claim'ят twin pair в разных семьях — collision. Phase B нужен UX для resolve conflict при mama-Артём concurrent operations.

6. **`_syncGraphFromLegacy` performance**: full-scan rebuild на each read+write. Сейчас sub-millisecond at 70 users / 351 graphPersons (комментарий 11783-11790). При 10× growth (700 users / 3500 graphPersons) может стать noticeable. Phase B не ухудшает this — same persons count, иной grouping. Если scale ramps post-Phase B, дроп legacy mirror (planned per «goes away in Phase 3.4» комментарий) accelerates this.

7. **Missing `tree_mutated` broadcast для media + identity-link + conflict-resolve**: текущий dispatchTreeMutation triggered только на person create/update/delete + relation create/delete. Media POST/PATCH/DELETE не triggers (потенциально mama uploads photo не получит refresh у Артёма). Identity-link и conflict-resolve тоже не trigger. Phase B add'нет — minor fix, surfaces в Week 2-3 implementation.

8. **`kinship_check_expired` notification dispatch missing**: kinship-checks-routes.js komментарий 14-16 указывает «lazy dispatched at endpoint when sweep triggers», но в коде sweep (`_sweepExpiredKinshipChecks` store.js:17095-17108) только marks state, без dispatch. Routes `/v1/me/kinship-checks/issued` (109) и `/respond` (120) тоже не dispatch'ат при sweep. Likely existing bug or partial implementation; out of Phase B scope но worth flagging.

### 7.4 Open follow-up questions

1. **семья vs «My private branch» в migration plan §5.2 proposal**: «Opt-in upgrade flow («Объединить семьи»)» — после auto-Моя-семья migration, existing identity-linked users get banner offering merge. Concrete UX: Артём + мама have 2 separate «Моя семья» с identity links между дядей Колей. Merge produces ONE shared «Семья Ивановых» с обоими как members. Что с original 2 «Моя семья» trees? Delete? Keep as «My private branch» (per §5.2 wording)? **Recommend Артёму decide pre-Week 4**: vote A) delete originals after merge (simpler, less confusion), B) keep как private archive (no data loss, more confusion). Lean A.

2. **семьяInvitation expiry default**: proposal § 4 mentions «Link expires 7 дней» для browse mode (§3.4 Journey 4). Что с full-membership invitations? Recommend default 30 days с PATCH-able по owner.

3. **Multi-семья per person identity invariant**: Q5 mentions «дядя Коля в семья Ивановых + семья Кузнецовых» — same identity, два twin persons. Limit на number of семей containing same identity? recommend нет limit (Telegram-like нет limit на channels containing same content). Concern: huge identity link fan-out (один identity в 100 семьях) — `_propagateIdentityFields` (9906) O(n) per linked person, n grows. Sub-millisecond at scale 70 users, but unbounded — possibly need cap либо async batching при future scale.

4. **«Personal hide filter» visibility on cross-семья twin updates**: если Артём скрыл «дядю Колю» в своей семье и мама обновила имя в маминой семье → conflict surface к Артёму? Proposal §3.5 says «explicit opt-in» через notification «Применить изменения?». Что если Артём hidden the twin? Probably skip notification (user explicitly не интересуется). Recommend spec в Week 2.

5. **Семья DELETE notification scope**: §4 Q4 = «Pre-deletion: notify all members "X собирается удалить семью"». Sync vs async? Notification cancellable? Backend simpler async — owner triggers delete, members notified after the fact с «restore from backup» option (90d retention via existing hardDelete window).

6. **kinshipChecks role в federated model**: текущий «мы родственники?» check — user-to-user. В семья model могут ли два members одной семьи issue kinship check? Trivially yes (current implementation), но семантика redundant если уже в одной семье. UI hint «вы уже в одной семье, посмотрите дерево» — recommend deferred to Phase B+1.

7. **Поддержка `migrationStatus` rollback**: если Phase B rolled back через feature flag, existing семьи records остаются. На rollback re-enable, поток продолжается. Если backend сам rolled back к pre-Phase B revision, семьи table может exist но code не trigger её. Recommend safe rollback path: backend сначала disables creates (read-only mode), потом revert. Standard runbook.

8. **`identityClaims` collection role**: text mentions Phase 3 has `identityClaims` (store.js:116, `createIdentityClaim` 9238). Текущее использование — claim чужой person в свой identity (`reviewIdentityClaim` 9316). Семья membership flow not directly intersects этим, но edge case: pull дяди Коли в свою семью + claim как identity (вдруг dyadya Коля сам зарегистрировался). Recommend semantics same — claim flow continues per-user, не per-семья.

---

**Doc complete.** Total ~720 LOC. Reference paths verified via Read tool, line numbers accurate as of commit at session start (main HEAD `8ab3b02`).
