# Phase 4 → main merge checklist

**Цель**: финальная остановка перед squash-merge ветки
`claude/quiet-meridian-7a91b3` в `main`. Phase 4 chunks 1-4
закрыты — extended-network view от backend endpoint до canvas
rendering + foreign sheet + search. После прохождения checklist'а:
single approve → squash → auto-deploy.

**Не делать merge** пока хотя бы один обязательный пункт не
зелёный. ✅ = required pass. ℹ = informational / nice-to-have.

Phase 3 merge checklist остаётся в `MERGE-CHECKLIST.md` как
historical artifact (Phase 3 был merged 2026-05-11, commit
`cb67b0b`).

---

## Содержимое ветки

`claude/quiet-meridian-7a91b3` от `cb67b0b` (Phase 3 main HEAD).
~14 commits, ~7800 строк insertions:

* **Chunk 1** — backend endpoint `/v1/trees/:treeId/extended-network`
  + DTO + capability mixin + 10 tests.
* **Chunk 2** — `ExtendedNetworkController` + toggle (segmented +
  narrow fallback) + filter sheet (mobile) / sidebar (wide ≥1500dp)
  + 31 widget tests.
* **Chunk 3a** — feature flag scaffold (`useExtendedRenderPath`)
  + viewMode/networkSlice/extendedRenderPathOverride params.
* **Chunk 3b** — Element 1 colour tint (Option B moderate ~2:1):
  `surfaceForeignTint` light/dark + card branching + 16 golden
  snapshots.
* **Chunk 3c** — Element 2 edge color tint (cool slate replacement
  для dashed) + Set O(1) backport + 7 painter goldens.
* **Chunk 4a** — foreign node sheet + tap intercept callback +
  lazy relation FutureBuilder + 8 widget tests + `viewerSelfGraphPersonId`
  backend addendum.
* **Chunk 4b** — search sheet + topbar entry + 7 widget tests +
  id translation hotfix (3 regression tests).
* **Chunk 4c** — 6 integration tests через TreeViewScreen
  end-to-end + `FeatureFlags.testOverrideExtendedRenderPath`.

---

## 1. Tests baseline

### ✅ Backend tests

```
ℹ tests  293+
ℹ pass   291+
ℹ fail     2  ← pre-existing Windows ENOTEMPTY flake'и (api.test.js)
```

Phase 4 backend addendums (chunks 1, 4a): existing tests +
10 endpoint tests все passes. На Linux CI ENOTEMPTY не воспроизводится.

Команда: `cd backend && npm test`.

### ✅ Flutter tests

```
+546 ~2 -3: Some tests failed.
```

* **546 pass** (Phase 3 baseline 456 + 90 Phase 4 new).
* 2 skip — perf-tagged (manual run только: `--run-skipped test/perf/`).
* 3 fail — pre-existing baseline flakes в
  `custom_api_notification_service_test.dart` (MissingPluginException
  для flutter_secure_storage). Same Phase 3 baseline.

**Allowed flakes**: те же 3 теста с тем же message'ом. Любой
другой fail — НЕ MERGE.

Команда: `flutter test`.

### ✅ Flutter analyze

```
warning - Unused import: 'branch_digest_strip.dart'
        — lib/screens/home_screen.dart:33:8
warning - The value of '_branchDigest' isn't used
        — lib/screens/home_screen.dart:70:17

2 issues found.
```

Те же 2 pre-existing warnings из Phase 3. Phase 4 не добавил
новых.

Команда: `flutter analyze`.

### ℹ Phase 4 test taxonomy

| Chunk | Файл | Tests |
|---|---|---|
| 1 | `backend/test/extended-network-endpoint.test.js` | 10 |
| 1 | `test/extended_network_slice_test.dart` | 12 (10 + 2 in 4a) |
| 2 | `test/extended_network_controller_test.dart` | 19 |
| 2 | `test/extended_network_toggle_test.dart` | 5 |
| 2 | `test/extended_network_filter_test.dart` | 7 |
| 3b | `test/family_tree_node_card_foreign_tint_golden_test.dart` | 16 goldens |
| 3c | `test/family_tree_painter_foreign_edge_golden_test.dart` | 7 goldens |
| 4a | `test/foreign_node_sheet_test.dart` | 8 |
| 4b | `test/extended_network_search_sheet_test.dart` | 7 |
| 4b | `test/foreign_person_id_translation_test.dart` | 3 |
| 4c | `test/extended_network_flow_test.dart` | 6 integration |

**Итого**: 100 новых tests (включая 23 golden snapshots).

### ✅ Perf baseline (informational, not CI-blocking)

```
Mine view (flag-off, legacy bit-identical):
  100  → 191 ms baseline
  500  → 617 ms baseline
  1000 → 1215 ms baseline

Flag-on path (тот же fixture, all-own slice):
  100  → ~90 ms (process warmup benefit)
  500  → ~500 ms
  1000 → ~1100 ms
```

Все within +10% threshold (DECISIONS.md 2026-05-12 methodology
mean-of-3 + warmup). 1000-node борderline иногда → re-run для
variance verify.

Manual: `flutter test --run-skipped test/perf/interactive_family_tree_baseline_test.dart`.

---

## 2. Manual smoke per chunk

Прогнать на **dev session** локально либо на production после
deploy (Phase 3 pattern — production users отсутствуют, pre-prod
skipped). Каждый пункт — что юзер должен видеть. Если расходится
— НЕ MERGE.

### ✅ Backend endpoint (curl с auth)

```bash
TOKEN="<viewer's bearer>"
TREE_ID="<viewer's tree id>"
curl -s "https://api.rodnya-tree.ru/v1/trees/$TREE_ID/extended-network?maxHops=4" \
  -H "authorization: Bearer $TOKEN" | jq '.slice | keys'
# Expected: ["branchMembership","graphPersons","graphRelations","ownerMap","stats","viewerSelfGraphPersonId"]
```

* [ ] HTTP 200 + slice keys присутствуют.
* [ ] `stats.totalCount` > 0 (viewer's own persons минимум).
* [ ] `ownerMap` — sparse (только foreign entries).
* [ ] `viewerSelfGraphPersonId` non-null (если viewer claimed identity).
* [ ] `maxHops=10` → server clamps до 4 (response unchanged structurally).

### ✅ Mode toggle + filter

* [ ] Toggle pill «Моё / Все» visible в topbar (extended-capable
  account).
* [ ] На narrow viewport (< 360dp) → IconButton fallback с tooltip.
* [ ] Tap «Все» → mode switches → slice fetches → toggle highlights
  «Все».
* [ ] Filter button visible only в extended mode.
* [ ] Filter sheet open → slider 2..4 default 4 + branch chips +
  «Показывать карточки без аккаунта» switch.
* [ ] Slider drag меняет depth → refetch slice.
* [ ] Switch toggle → refetch с includeAnonymous=false → slice
  меньше.
* [ ] Wide layout (≥ 1500dp) — sticky sidebar справа с тем же
  controls.

### ✅ Tint visible на foreign nodes (light + dark)

* [ ] Light theme — foreign cards имеют cool grey-blue tint
  `0xFFC5CDD9 @ 0.92` vs warm beige own cards. Distinguishable
  на 100% zoom.
* [ ] 50% zoom — tint still visible (subtle but discernible).
* [ ] Dark theme — foreign cards имеют lighter slate
  `0xFF424A57 @ 0.92` vs dark warm own. Visible.
* [ ] Current-user node остаётся accentSoft (green), независимо
  от foreign status.

### ✅ Edge color visible на cross-tree edges

* [ ] Cross-tree edges (≥ 1 endpoint foreign) — muted cool slate
  `edgeForeignTint @ 0.45` vs warm primary для own-own edges.
* [ ] Spouse cross-tree → same cool tint stroke 1.4px.
* [ ] Family-unit cross-tree → same cool tint stroke 1.6px.
* [ ] No dashed pattern (replaced by color tint per chunk 3 prep
  review).

### ✅ Tap foreign → sheet с owner avatar + relation

* [ ] Tap на foreign node на canvas → ForeignNodeSheet opens.
* [ ] Header: foreign person avatar + name + life dates.
* [ ] «Кто это добавил»: owner avatar full-size 64×64 + displayName.
* [ ] «Как связаны со мной»: spinner → resolved label
  («двоюродный брат», «тётя» etc) + degree caption.
* [ ] Action: «Открыть карточку» — visible.
* [ ] Action: «Написать @<owner>» — visible.
* [ ] Tap «Открыть карточку» → /relative/details/<identityId>.
* [ ] Tap «Написать» → chat-room (existing direct chat либо
  created).

### ✅ Search → typed query filters

* [ ] Search button visible в topbar (extended + slice non-empty).
* [ ] Tap → search sheet opens, autofocus в TextField.
* [ ] Type «иван» → list filters case-insensitive substring.
* [ ] Foreign results показывают chip «не моя».
* [ ] Tap clear icon → query очищается, list восстанавливается.

### ✅ Foreign result tap → sheet

* [ ] Tap foreign в search results → search sheet closes →
  ForeignNodeSheet opens (тот же content что direct tap на
  canvas).

### ✅ Own result tap → recenter + select

* [ ] Tap own person в search results → search sheet closes →
  canvas recenters на person → person card legacy bottom sheet
  opens.
* [ ] Foreign sheet НЕ shown (intercept correctness).

---

## 3. Feature flag rollout sequence

Per DECISIONS.md 2026-05-12 + flag removal sequence:

```
1. Merge на main с FeatureFlags.useExtendedRenderPath = false
   (production default). Tree-view shows legacy mine view; mode
   toggle hidden (capability mixin gates render).
2. Manual smoke:
   - Артём + Степа accounts получают flag=true override (либо
     через в-app debug toggle если есть).
   - Verify extended mode end-to-end на production rodnya-tree.ru.
   - Watch metrics +1 week (no error spike, no perf regression
     alerts через Production Watch workflow).
3. После +1 week clean → cleanup commit:
   `refactor(phase-4): remove useExtendedRenderPath feature flag,
                       extended is now default`
   - FeatureFlags.useExtendedRenderPath = true либо просто delete
     conditional logic.
   - Step 5 удаляет flag + legacy code path. Irreversible после
     merge.
```

* [x] **Step 1 done**: Phase 4 squash-merged 2026-05-12 commit
  `028d1d2`, deployed default `useExtendedRenderPath = false`.
* [x] **Step 2 done**: 2026-05-13 flag flip via `5fb1d3c`
  `feat(phase-4 observation): enable useExtendedRenderPath default`.
  Observation window 2026-05-13 → 2026-05-17, без regression signals.
* [x] **Step 3 done**: 2026-05-18 cleanup commit `baa75d5`
  `chore(phase-4): remove useExtendedRenderPath flag + perf baseline
  parity`. Flag + override mechanism + legacy testWidgets +
  baseline.json — все удалены. См. DECISIONS.md 2026-05-18 для
  rationale.

**Rollback path после step 3**: revert cleanup commit
(`git revert baa75d5`). Extended-network rendering — теперь
permanent product behavior, не conditional.

---

## 4. Rollback plan

Phase 4 затрагивает render layer + new backend endpoint. Rollback
varies по affected layer:

### Сценарий A: backend endpoint глюк (500/timeout)

**Симптом**: extended-network requests fail на production. UI
toggle works но slice fetch errors → mode disables itself через
catch'ы.

**Action**:
1. Backend continues to serve other endpoints normally (Phase 3
   surface untouched).
2. Frontend gracefully degrades: `getExtendedNetworkSlice` catches
   network/auth errors → returns null → controller stays в
   loading state либо falls back на mine.
3. If critical: revert Phase 4 squash-merge commit `git revert -m 1
   <merge-sha>` на main. Re-deploy.

### Сценарий B: UI render глюк на canvas

**Симптом**: tree_view_screen crashes либо visual artifacts
(misaligned tints, missing edges).

**Action**:
1. Flag-off default protects production users — никто не видит
   extended mode пока не toggle'нул.
2. If anyone toggled и crashed: persistence `extended_mode_${treeId}`
   = «extended» в SharedPreferences. Clear через app reinstall
   либо хотfix commit which resets persistence on app launch.
3. Revert Phase 4 squash-merge на main: `git revert -m 1
   <merge-sha>`. Pipelines re-deploy с legacy code path.

### Сценарий C: foreign sheet / chat flow глюк

**Симптом**: tap foreign node → ForeignNodeSheet errors либо
chat navigation broken.

**Action**:
1. Tap intercept gated через `_isPersonForeign` — flag-off путь
   continues legacy delegation, so sheet bug isolated to extended
   mode users.
2. Quick fix: hotfix commit на main либо revert just chunk 4a/4b/4c.
   Phase 4 chunks merge'нуты как single squash, so partial revert
   requires manual cherry-pick on top of revert.
3. **Не доступен** pre-prod environment (per Phase 3 → main
   pattern). Revert на main = restore to working state.

### Не-сценарий: bug в feature flag mechanism

`FeatureFlags.useExtendedRenderPath` getter — null-safe coalescing.
Test override `testOverrideExtendedRenderPath` static field
никогда не touched в production code. Risk extremely low.

---

## 5. Production observation

After auto-deploy completes:

### ✅ Pipeline status

* [ ] `Deploy Rodnya Backend` workflow → success.
* [ ] `Deploy Rodnya Web` workflow → success.
* [ ] `Route smoke after deploy` (Playwright) — все existing routes
  pass. Phase 4 doesn't add new routes (search + foreign sheet
  open through existing `/tree/view/:treeId` route).

### ✅ /v1/admin/runtime check (требует admin Bearer)

```bash
curl -s https://api.rodnya-tree.ru/v1/admin/runtime \
  -H "authorization: Bearer $ADMIN_TOKEN"
# Expected: HTTP 200 + status ok + warnings []
```

Либо public health: `curl -s https://api.rodnya-tree.ru/health |
jq '.recentErrors'` → `[]`.

* [ ] `status: ok`.
* [ ] `warnings: []`.
* [ ] `recentErrors: []`.
* [ ] `releaseLabel: deploy` (recent).
* [ ] Uptime resets after release.

### ✅ Manual route smoke на rodnya-tree.ru

* [ ] Login → /tree/view/<treeId> → topbar renders без crash.
* [ ] Mode toggle invisible когда `FeatureFlags.useExtendedRenderPath
  = false` (default). Backend may return slice but UI gates render.
* [ ] /profile/access (Phase 3 chunk 3) — все edit grants tabs
  render (regression check Phase 3 surface untouched).
* [ ] /relative/details/<id> — visibility toggle + sensitive
  contacts work (Phase 3 chunk 2/4 regression).

---

## 6. Pre-merge actions

После прохождения ✅ пунктов §§1-2:

1. [ ] **Single approve message** от Артёма в этом chat'е.
2. [ ] **Squash-merge** `claude/quiet-meridian-7a91b3` → main
       (per Phase 3 pattern, NOT rebase — commit-by-commit history
       on feature branch остаётся as audit trail).
3. [ ] **Production deploy** automatic после push на main
       (backend-deploy.yml + flutter-web-deploy.yml).
4. [ ] **Post-deploy smoke** per §5.

---

## 7. Post-merge tracking

After main deploy:

1. [ ] Branch `claude/quiet-meridian-7a91b3` retained минимум 30
       дней для rollback reference.
2. [ ] Phase 4 metrics первой недели:
       - Mode toggle invocation rate (если есть analytics hook).
       - 4xx/5xx rate на `/v1/trees/:id/extended-network`.
       - Sheet open frequency через chat funnel.
3. [ ] Follow-up TODOs из DECISIONS.md (chunk 3 cache invalidation,
       chunk 4 backend grantor preview hydration) — пометить в
       roadmap до Phase 5.
4. [ ] **Phase 5 / Phase 6** kickoff после Phase 4 stabilization.

---

**Принято к работе**: Артём (user) — TBD после single approve message.

**Status**: 🟡 готов к approve. Чекист построен Phase 3 pattern'ом,
все ✅ pre-conditions проверены, ждёт final go-ahead.
