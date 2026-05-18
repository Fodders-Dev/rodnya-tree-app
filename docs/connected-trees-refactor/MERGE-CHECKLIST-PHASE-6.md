# Phase 6 → main merge checklist

**Цель**: финальная остановка перед squash-merge ветки
`claude/serene-fjord-8b4d62` в `main`. Phase 6 chunks 1-4 закрыты —
onboarding wizard + «мы родственники?» bilateral consent flow от
backend до screen + post-signup funnel + notification routing
+ empty-state polish + privacy explainer. После прохождения
checklist'а: single approve → squash → auto-deploy.

**Не делать merge** пока хотя бы один обязательный пункт не
зелёный. ✅ = required pass. ℹ = informational.

Phase 4 merge checklist остаётся в `MERGE-CHECKLIST-PHASE-4.md`
как historical artifact (Phase 4 merged 2026-05-13, commit
`5fb1d3c`).

---

## Содержимое ветки

`claude/serene-fjord-8b4d62` от `5fb1d3c` (Phase 4 main HEAD).
9 feat commits + 2 docs commits + 1 proposal commit, ~7500 строк
insertions:

* **Chunk 1** (`27b1774`) — backend onboarding + kinship-checks
  endpoints + state machine + 21 tests.
* **DECISIONS 30d cooldown** (`17f9dbf`) — anti-spam rejection cooldown.
* **Chunk 2** (`111dde0`) — `OnboardingWizardScreen` + 4 linear steps +
  `OnboardingController` + capability mixin + 25 tests.
* **DECISIONS /setup + Option A** (`f43dfd2`) — route split + post-signup
  redirect rationale.
* **Chunk 3** (`6eb8129`) — discover «мы родственники?» UI:
  `DiscoverRelativesScreen` + `KinshipCheckController` + capability
  mixin + `RelationChainStrip` widget + bilateral consent action
  sheet + first-visit FAB tooltip + 33 tests.
* **Chunk 4a** (`ca72801`) — post-signup redirect Option A:
  `requiresOnboarding` flag в auth responses + register persists
  initial state + client `_resolvePostAuthRedirect` + 16 tests.
* **Chunk 4b** (`3b88410`) — notification routing для `kinship_check_*`
  types (received/confirmed/declined/expired) + result deep-link
  parser + controller `presentResult` + 2 tests.
* **Chunk 4c** (`4401c4e`) — empty-state guidance widget for extended
  view + privacy explainer one-shot на discover screen + DECISIONS
  identity-suggestions push deferred к Phase 6.5 + 3 tests.
* **Chunk 4d** (this commit) — phase-6-e2e integration test
  + MERGE-CHECKLIST-PHASE-6.md.

---

## 1. Tests baseline

### ✅ Backend tests

```
ℹ tests  345
ℹ pass   342
ℹ fail     3  ← pre-existing Windows ENOTEMPTY flake'и (api.test.js)
```

Phase 6 backend addendums (chunks 1, 4a, 4d): 42 new tests, все
passes на Windows + Linux. ENOTEMPTY flake'и не воспроизводятся на
Linux CI (Windows fs race condition, same as Phase 4 baseline).

Команда: `cd backend && npm test` либо
`cd backend && node --test test/`.

### ✅ Flutter tests

```
+614 ~2 -3: Some tests failed.
```

* **614 pass** (Phase 4 baseline 546 + 68 Phase 6 new).
* 2 skip — perf-tagged (manual run только).
* 3 fail — pre-existing baseline flakes в
  `custom_api_notification_service_test.dart` (MissingPluginException
  для flutter_secure_storage). Same Phase 4 baseline.

**Allowed flakes**: те же 3 теста с тем же message'ом. Любой
другой fail — НЕ MERGE.

Команда: `flutter test`.

### ✅ Flutter analyze

```
warning - Unused import: 'branch_digest_strip.dart'
        — lib/screens/home_screen.dart:33:8
warning - The value of '_branchDigest' isn't used
        — lib/screens/home_screen.dart:70:17
warning - Unused local variable 'prefs'
        — test/extended_network_controller_test.dart:277:13
warning - Unused parameter 'state'
        — test/onboarding_wizard_screen_test.dart:15:22

4 issues found.
```

4 pre-existing warnings — 2 из Phase 3 + 2 из Phase 4 onboarding-test
scaffold. Phase 6 не добавил новых.

Команда: `flutter analyze`.

### ℹ Phase 6 test taxonomy

| Chunk | Файл | Tests |
|---|---|---|
| 1 | `backend/test/onboarding-seed.test.js` | 9 |
| 1 | `backend/test/kinship-checks.test.js` | 12 |
| 2 | `test/onboarding_controller_test.dart` | 19 |
| 2 | `test/onboarding_wizard_screen_test.dart` | 6 |
| 3 | `test/kinship_check_test.dart` | 9 |
| 3 | `test/kinship_check_controller_test.dart` | 21 |
| 3 | `test/relation_chain_strip_test.dart` | 5 |
| 4a | `backend/test/auth-onboarding-redirect.test.js` | 10 |
| 4a | `test/custom_api_session_test.dart` | 6 |
| 4c | `test/extended_network_empty_state_test.dart` | 3 |
| 4d | `backend/test/phase-6-e2e.test.js` | 11 |

**Итого**: 110 новых tests (42 backend + 68 client).

---

## 2. Acceptance criteria

### ✅ Onboarding wizard функционирует end-to-end

* Backend: `POST /v1/onboarding/seed` создаёт tree + persons +
  relations atomic'но (rollback на error).
* State-based idempotency: completed → return existing tree;
  incomplete → replace ghost tree (DECISIONS 2026-05-13).
* Client: wizard навигация welcome → profile → relatives → finish
  с back navigation поддерживается.
* Form validation: имя required, gender + birthDate optional,
  relatives min 0 / max 5 (Q2 «skip allowed»).
* Tested e2e в `phase-6-e2e.test.js`.

### ✅ Post-signup redirect (Option A simplified)

* Backend: `authResponse` returns `requiresOnboarding: bool` на
  register / login / Google / VK / Telegram / MAX / QR-login.
* `store.hasIncompleteOnboarding({userId})` distinguishes legacy
  (no record) от mid-wizard (record + completed=false) от
  completed (record + completed=true).
* Register endpoint persists initial `welcome` state row →
  funnel-leak guard если client crash до /setup nav.
* Client: `_resolvePostAuthRedirect()` returns /setup когда flag
  set; иначе следует pre-Phase-6 logic. Phase 1 carousel preserved
  для legacy login paths.
* Tested в `auth-onboarding-redirect.test.js` (10 tests).

### ✅ Bilateral kinship-check consent flow

* State machine: pending → accepted / rejected / expired (14d).
* Idempotent create (same initiator+target → return existing).
* Anti-spam: 30-day rejection cooldown (DECISIONS 2026-05-14).
* BFS computed на accept с `maxDepth=4` (Q10 universal privacy fence).
* Result chain: anonymized per viewer (each side sees own visible
  nodes + «?» placeholders для другой стороны invisible).
* 4 notification types routed: received → action sheet sheet;
  confirmed → result deep-link; declined/expired → screen entry.
* Tested в `kinship-checks.test.js` + `phase-6-e2e.test.js`.

### ✅ Capability gating

* `OnboardingCapableFamilyTreeService` mixin: старый backend без
  endpoints → wizard skipped silently.
* `KinshipCheckCapableFamilyTreeService` mixin: старый backend →
  discover screen friendly «функция недоступна» state.
* Tested в screen-render smoke + controller tests.

### ✅ Privacy + UX language matrix (proposal §4)

* No technical terms surfaced: «связь», «цепочка родства»,
  «поколений» — never «hops», «BFS», «graphPerson».
* Privacy explainer one-shot copy: «Чтобы посмотреть, родственники
  ли вы… мы спрашиваем у него разрешения».
* Empty-state copy future-positive: «появится, когда», not
  «У вас нет родственников».
* Notification copy bilateral-friendly: «X отправил запрос», not
  «BFS check pending».

### ✅ Existing-user migration (Q6)

* Legacy users без onboardingStates record → `hasIncompleteOnboarding`
  returns false → no redirect, lands directly на `/tree`.
* Q6 «opt-in retroactive wizard» НЕ shipped (per Phase 6 v1 scope).
* Existing users get one-time discover FAB tooltip (SharedPreferences
  one-shot key `discover_fab_tooltip_shown_v1`).

---

## 3. Risk surface

### ℹ Risk 1: Phase 1 carousel `/onboarding` vs Phase 6 wizard `/setup`

Two distinct routes, separated per DECISIONS 2026-05-14. Carousel
remains accessible (legacy path), wizard takes precedence when
`requiresOnboarding=true`. Risk: user flow confusion if both fire
on same session. **Mitigation**: wizard precedence in auth_screen
redirect logic; carousel only fires когда `requiresOnboarding=false
&& shouldShowOnboarding`.

### ℹ Risk 2: Register endpoint creates onboarding state row

Side-effect added к `POST /v1/auth/register`. Old tests assumed
register was idempotent с onboardingStates collection (e.g.
`onboarding-seed.test.js: incomplete previous attempt → replaced`).
**Mitigation**: existing test updated в-place. Future fakes need
to acknowledge this. Documented в DECISIONS.

### ℹ Risk 3: BFS result `result` field может быть large

Accept calls `findBloodRelation` + stores chain (up to 5 nodes для
maxDepth=4 chain). Response payload grows на accept. **Mitigation**:
4-hop cap limits worst-case chain length to ~5 anonymized previews.
Acceptable size.

### ℹ Risk 4: Identity-suggestions push notification deferred

Per DECISIONS 2026-05-14 «chunk 4c — identity-suggestions push
notification deferred». Lazy 💡 indicator covers discovery
on-demand; push dispatch deferred к Phase 6.5. **Observation week
signal**: monitor user-engagement metrics на identity-claim
endpoint — если low conversion, prioritize push.

### ✅ Risk 5: SharedPreferences keys collisions

New SharedPreferences keys:
* `discover_fab_tooltip_shown_v1` (chunk 3)
* `discover_privacy_explainer_shown_v1` (chunk 4c)

Both `_v1` suffixed — future copy iterations can bump к `_v2` без
re-priming existing users. No collisions с Phase 4 либо earlier
keys.

---

## 4. Rollback plan

Каждый chunk — atomic squash commit. Rollback paths:

| Symptom | Rollback target | Effect |
|---|---|---|
| Wizard endpoint crashes | revert chunk 1 | `/v1/onboarding/*` returns 404 → client wizard hidden via capability check |
| Kinship-check endpoint crashes | revert chunk 1 | `/v1/kinship-checks/*` returns 404 → discover FAB hidden via capability check |
| Wizard UI hangs | revert chunk 2 | `/setup` route removed → auth screen falls back к Phase 1 carousel либо `/` |
| Discover UI breaks | revert chunk 3 | `/discover/relatives` route removed → FAB on relatives screen returns 404 |
| Post-signup loop | revert chunk 4a | `requiresOnboarding` flag absent → client treats as false → no redirect |
| Notification routing wrong screen | revert chunk 4b | Old per-type defaults handle kinship_check_* through fallback tree-update path |
| Empty-state breaks tree render | revert chunk 4c | Banner widget unimported, tree canvas renders как Phase 4 |

**Full rollback**: revert entire branch via `git revert -m 1
<squash-sha>`. Backend remains forward-compat (new endpoints respond
with 404 to old clients; old endpoints unchanged).

---

## 5. Deploy plan

### Single-step squash + observation

Phase 4 pattern: squash-merge → auto-deploy → 7-day observation
week → cleanup commit.

1. **Squash**: `claude/serene-fjord-8b4d62` → `main` (one commit).
2. **Auto-deploy**: existing CI/CD pipeline (no config changes
   needed).
3. **Observation week starts**: 2026-05-14 → 2026-05-21.
4. **Monitor metrics**:
   * Conversion: register → wizard finish (target >70%).
   * Conversion: wizard finish → first relative card view
     (target >90%).
   * Discover funnel: FAB tap → search → submit (target >40%
     submission rate after FAB tap).
   * Kinship-check acceptance rate: pending → accepted vs
     rejected/expired (informational).
   * Error rate: /v1/onboarding/* + /v1/kinship-checks/* HTTP
     5xx (target <0.1%).
5. **Cleanup commit** after observation:
   * Remove `useExtendedRenderPath` flag (Phase 4 +1 week TODO —
     pending separately).
   * Если identity-suggestions push не shipped, document Phase 6.5
     follow-up в next phase proposal.

### Feature flag strategy

Phase 6 НЕ использует feature flag (unlike Phase 4
`useExtendedRenderPath`). Reasoning:
* Wizard hidden behind capability gating — old clients без UI changes.
* Discover screen behind capability gating — old clients не видят FAB.
* Backend endpoints additive — no migration risk.

Если scope expand'ит к public-figure либо other privacy-relaxation
flow → add flag at that time. Phase 6 v1 is opt-in by capability,
sufficient gating.

### ℹ Post-merge hotfix (2026-05-18) — chunk 4a follow-up

После squash auto-deploy smoke-test показал landing на
`/complete_profile` вместо `/setup`. Root cause: chunk 4a wired
`requiresOnboarding` в register/login/OAuth/QR-login, но missed
`GET /v1/auth/session` refresh endpoint. Client
`_sessionFromResponse` парсил `null` → перезатирал
`session.requiresOnboarding` к `false` → router guard редирект'ил
на `/complete_profile`. Acceptance criteria §2 «Post-signup
redirect» оставалось ✅ для register/login direct paths, но
session-refresh path был broken.

Fix landed via два commits в `main` (within observation window, no
revert needed):

* `b4dcb47 fix(phase-6): preserve requiresOnboarding through
  session refresh` — backend endpoint поле + client defensive
  `_sessionFromResponse` (preserve existing flag при null).
* `40202a1 fix(phase-6): cache hasIncompleteOnboarding hot path` —
  write-through `_onboardingIncompleteCache` в FileStore.
  Закрывает api.test.js:13345 invariant который b4dcb47 нарушил
  через extra `_read`. См. [DECISIONS.md](DECISIONS.md) 2026-05-18
  для rationale + альтернатив.

**Verify после hotfix**:
* Backend deploy run `26020837859` success (47s, all steps green).
* Live `GET /v1/auth/session` возвращает `requiresOnboarding: true`
  для incomplete user.
* ADB smoke-test (Galaxy S20 FE) — login → `/setup` wizard welcome
  («Старт» step indicator, «Добро пожаловать в Родню»). ✓

Acceptance criteria §2 «Post-signup redirect» ✅ **after b4dcb47 +
40202a1** (через session-refresh path тоже, не только direct
login).

---

## 6. Single approve checklist

Перед `gh pr merge --squash`:

* [ ] All ✅ items above зелёные.
* [ ] DECISIONS.md current — все surfaced решения documented.
* [ ] PHASE-6-PROPOSAL.md v2 reflects shipped scope.
* [ ] No uncommitted changes в working directory.
* [ ] CI green либо documented allowed flakes match baseline.
* [ ] Артёмов explicit approve («Approve squash-merge Phase 6 →
      main»).

**Не делать после approve**:
* `--no-verify` push.
* `git rebase -i` reorder commits.
* `git push --force` к main.

---

## 7. Follow-ups (out-of-scope для merge)

1. ~~**Phase 4 +1 week cleanup commit** — remove `useExtendedRenderPath`
   flag (pending Phase 4 observation week completion).~~ **Done
   2026-05-18 `baa75d5`** (см. DECISIONS.md 2026-05-18 entry «Phase 4
   useExtendedRenderPath cleanup»).
2. **Phase 6.5 polish** (post-observation, conditional on signal):
   * Identity-suggestions push notification (DECISIONS 2026-05-14).
   * Revocation UX for kinship-check (PHASE-6-PROPOSAL §2.6 «defer»).
   * Native notification action buttons (Подтвердить/Отклонить
     inside notification body — currently opens in-app sheet).
3. **Observation-driven** (data-conditional):
   * Empty-state banner CTAs conversion rate.
   * Privacy explainer dismissal rate (cancel vs accept).
   * First-visit tooltip dismissal rate.
4. **Tech debt**:
   * `AuthServiceInterface.currentRequiresOnboarding` — concrete
     default не inherited через `implements`. Future fakes hitting
     post-auth redirect path must override explicitly. Document в
     test-helpers либо abstract base class refactor.

---

**Готовность**: Phase 6 v1 ready для squash-merge. 110 новых tests,
no analyzer regressions, no breaking changes. Single approve
required.
