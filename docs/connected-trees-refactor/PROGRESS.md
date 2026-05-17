# Прогресс по фазам

Каждая завершённая фаза получает запись здесь. Формат:

```
## Phase N — название

**Завершено**: YYYY-MM-DD
**Сессия(и)**: ссылки или короткие хеши коммитов
**Что сделано** (bullet list):
* …
**Тесты**:
* backend: passed / failed
* flutter analyze: passed
* manual smoke: что именно проверили
**Что осталось из этой фазы**:
* …
**Что НЕ запланировано но всплыло** (для следующих фаз):
* …
```

---

## 2026-05-09 — Phase 0 audit + конфликт планов разрешён

**Сессия**: claude/infallible-pike-41360c (Phase 0 design & audit)

**Что сделано**:
* Полный audit backend + client + tests + docs.
* Артефакты:
  * [AUDIT.md](AUDIT.md) — inventory всех мест, трогающих
    `treeId`/`creatorId`/`memberIds`/`linkPersonToUser` etc.
  * [IDENTITY-MATCHER.md](IDENTITY-MATCHER.md) — анализ сигналов
    matcher'а, false-positive risks, план Phase 2 расширения.
  * [SCHEMA.md](SCHEMA.md) — ER-диаграммы legacy + graph mirror +
    diff и migration-шаги.

**Главное обнаружение**: в коде уже существует unified-graph слой
(`graphPersons`/`graphRelations`/`branches`/`branchPersonViews`),
исполняющий бо́льшую часть «целевой модели». Это исполнение RFC
[`docs/tree_model_overhaul_rfc.md`](../tree_model_overhaul_rfc.md)
от 2026-05-07. Сделанные фазы по RFC: Phase 0 (person-picker),
Phase 1.1 (identity propagation), Phase 1.2 (silent 💡 matcher),
Phase 3.1 (schema graph), Phase 3.4 (post.branchIds[]), Phase 6.1
(BranchSwitcherChip).

**Конфликт планов**: PLAN.md (этой сессии) описывает single-tree-
per-user модель, RFC + код — multi-branch over global graph модель.
Это разные модели данных.

**Разрешение**: PLAN.md SUPERSEDED by RFC. Чисто B (RFC выигрывает),
без гибридов. Запись в [DECISIONS.md](DECISIONS.md) от 2026-05-09.
Дополнительные decisions: memberIds → split (owner-model + branch
share), linkPersonToUser → DEPRECATED как часть Phase 3, Phase 3
заблокирован 4 нерешёнными RFC-вопросами.

**Тесты**: не запускались (read-only audit).

**Что осталось из этой фазы**: ничего. Phase 0 закрыт.

**Что НЕ запланировано но всплыло**: Phase 1.3 (edit-time conflict
surfacing) уже частично исполнен в коде (видны `identityFieldConflicts`
коллекция, routes, store-методы). Нужен dedicated audit-pass
конкретно по 1.3 чтобы зафиксировать что осталось до DoD.

---

## 2026-05-09 — Phase 1.3 (edit-time conflict surfacing) — already closed in code

**Сессия**: claude/infallible-pike-41360c (Phase 0 audit + 1.3 verification)

**Контекст**: задача от user'а — «продолжай по плану RFC — закрывай
Phase 1.3 (edit-time conflict surfacing)». Audit показал, что Phase 1.3
УЖЕ полностью реализован в коде в предыдущих сессиях, со включённым
optional UI bottom-sheet для resolve (RFC помечал его как «отложить»).

**Что есть в коде**:

Backend:
* [backend/src/store.js:60-66](backend/src/store.js:60) — коллекция
  `identityFieldConflicts` в `EMPTY_DB` + комментарий объясняющий
  её назначение.
* [backend/src/store.js:143-145](backend/src/store.js:143) — нормализация
  при чтении JSONB.
* [backend/src/store.js:9732-9917](backend/src/store.js:9732)
  (`_propagateIdentityFields`) — реализация RFC §1.3 пункт 2:
  - `lastPropagatedFields` snapshot per (target person, field).
  - Detection: `current vs lastWritten` определяет local edit.
  - Snapshot-on-equal: stamps lastPropagatedFields даже когда
    значения совпадают, чтобы будущий local edit вёл в conflict path.
  - Mute check: `keep`-resolved пары не resurfacatятся.
  - Refresh existing row вместо append duplicates — UI стабильнее.
* [backend/src/store.js:8421-8439](backend/src/store.js:8421)
  (`listIdentityConflicts`) — фильтрует по accessibleTrees, treeId,
  personId; только unresolved.
* [backend/src/store.js:8449-...](backend/src/store.js:8449)
  (`resolveIdentityConflict`) — `keep`/`overwrite`, idempotent на
  повторный клик, `FORBIDDEN` если caller не имеет access на target.
* [backend/src/store.js:7292-7308](backend/src/store.js:7292) — GDPR
  cleanup в `deleteUser` (RFC §1.3 пункт 4).
* [backend/src/routes/tree-routes.js:426-498](backend/src/routes/tree-routes.js:426)
  — endpoints `GET /v1/trees/:treeId/conflicts` + `POST .../resolve`.
  Tree-scoped (RFC mention: «one HTTP call covers every visible card»).

Tests:
* [backend/test/api.test.js:4452+](backend/test/api.test.js:4452) —
  full happy-path test: detect conflict, refresh existing row,
  resolve `keep` (silent mute), resolve `overwrite` (target updated,
  lastPropagatedFields refreshed, no duplicate conflict).
* [backend/test/api.test.js:4736+](backend/test/api.test.js:4736) —
  GDPR sweep: deleted user's conflicts dropped.

Flutter:
* [lib/backend/interfaces/identity_conflicts_capable_family_tree_service.dart](lib/backend/interfaces/identity_conflicts_capable_family_tree_service.dart)
  — capability mixin с двумя методами.
* [lib/backend/models/identity_field_conflict.dart](lib/backend/models/identity_field_conflict.dart)
  — DTO с `fromJson`.
* [lib/services/custom_api_family_tree_service.dart:253-...](lib/services/custom_api_family_tree_service.dart:253)
  — реализация `getIdentityConflictsForTree` + `resolveIdentityConflict`.
* [lib/widgets/interactive_family_tree.dart:83](lib/widgets/interactive_family_tree.dart:83)
  — приём `identityConflictCounts` через props.
* [lib/widgets/interactive_family_tree.dart:5644+](lib/widgets/interactive_family_tree.dart:5644)
  — `_IdentityConflictsBadge` (⚠️ dot на карточке).
* [lib/screens/tree_view_screen.dart:147](lib/screens/tree_view_screen.dart:147)
  — `_identityConflictCounts` state + `_refreshIdentityConflictCounts`,
  `_handleShowIdentityConflictsForPerson`.
* [lib/screens/tree_view_screen.dart:1318+](lib/screens/tree_view_screen.dart:1318)
  — `_IdentityConflictsSheet` для resolve UI с `keep`/`overwrite`
  кнопками. Хоть RFC помечал его как «отложить», в коде он сделан.

**Тесты на 2026-05-09**:
* `node --test` в backend: 100/101 пройдено.
  * Один fail: `presence, typing and read-state realtime updates
    reach chat participants` ([api.test.js:12249](backend/test/api.test.js:12249))
    — Windows-flaky `ENOTEMPTY: directory not empty, rmdir` на
    cleanup tmp-папки. **Не связан с Phase 1.3**, упомянут в RFC
    как «unrelated Windows ENOTEMPTY rmdir flake».
  * Все Phase 1.3 тесты — зелёные.
* `flutter analyze` на main: **8 issues**, все pre-existing,
  ничего из Phase 1.3:
  * 2 warnings про `_branchDigest`/`branch_digest_strip` import в
    [lib/screens/home_screen.dart:33,70](lib/screens/home_screen.dart:33)
    — сознательно оставлены автором коммита `c4f3a80` («парятся
    на случай ребрендирования; сам _branchDigest field в state'е
    оставляем»).
  * 6 errors в [test/theme_provider_test.dart](test/theme_provider_test.dart)
    — pre-existing test rot после коммита `249184e feat(theme):
    три первоклассных режима — система / светлая / тёмная`.
    Тесты ссылаются на удалённые `initialPlatformBrightness`
    параметр и `isDarkMode` getter. **Не связано с Phase 1.3,
    отдельный bug.**

**Что осталось из Phase 1.3**: ничего. RFC DoD достигнут.

**Что НЕ запланировано но всплыло**:
* ✅ `theme_provider_test.dart` test-rot починен по запросу user'а
  («хочу чтобы оформил все сделал»). Переписан под новый API
  ThemeProvider (`isExplicitDark`/`isSystemMode`/`resolvedBrightness(context)`,
  циклический `toggleTheme`). 10/10 тестов зелёные. `flutter
  analyze test/` — `No issues found!`. Покрытие: default=system,
  load 'dark'/'light'/'system' из prefs, setThemeMode persists+notifies+idempotent,
  toggle цикл system→light→dark→system, resolvedBrightness override
  в explicit modes + follow MediaQuery в system mode, AppTheme
  readability.
* ✅ Backend regression baseline: identity-matcher.test.js (2 → 25
  тестов, +23) + migration-utils.test.js (9 → 18, +9). Покрытие:
  threshold edges, biographical gate, FP guards (claimed/already-linked
  skip), cross-tree privacy gate, ё/е normalization, branch.ownerId
  rename, memberIds mirror + legacy 'members' fallback, canonical
  person picking (claimed user wins, fallback по updatedAt), empty
  snapshot defensive. Полный backend suite после добавлений:
  227/229 pass, 2 fail — известные Windows ENOTEMPTY race на rmdir
  WS-серверов (упомянуты в RFC как unrelated flake).
* ⚠️ Pre-existing failure (НЕ из-за моих изменений): 3 теста в
  [test/custom_api_notification_service_test.dart](test/custom_api_notification_service_test.dart)
  падают и на `main`, и в worktree:
  - `polls unread notifications and deduplicates delivered ids`
  - `suppresses muted chat notifications`
  - `forwards silent mode to chat notifications`

  Все три ожидают `hasLength(1)` от `shownChatNotifications` /
  `shownGenericNotifications` callbacks, но callbacks не
  вызываются. Это business-logic mismatch в notification service
  flow, не quick fix — требует debugging внутреннего sync pipeline.
  Полный flutter test suite: **379 pass, 3 fail** (все 3 — этот
  файл). Не блокирует connected-trees-refactor работу;
  кандидат на отдельный bug-fix session.
* В worktree `flutter analyze` показывает **дополнительные 25
  errors** (33 total) про двойные пути к `FamilyPerson`/`Gender`.
  Это worktree-specific issue: `.dart_tool/package_config.json`
  указывает на корневое репо, и analyzer видит модели как
  определённые «дважды». На main эта проблема отсутствует. Не блокер.

---

## 2026-05-10 — Phase 3 разблокирован, Phase 3.1 proposal готов

**Сессия**: продолжение claude/infallible-pike-41360c

**Что изменилось**:
* Артём ответил на 4 RFC-вопроса (см. [DECISIONS.md](DECISIONS.md)
  запись 2026-05-10):
  - **A**: privacy = `connected-via-blood-graph` default (≤4 hops),
    sensitive fields owner-only, deceased + >100лет = public auto,
    owner override через UI.
  - **B**: migration conflicts через highest-completeness wins
    per-field, divergent → identityFieldConflicts (Phase 1.3 reuse).
  - **C**: default owner-only edit, без auto-extension по hops.
    Owner extension через explicit grants. Merge — двусторонний
    consent. 30-day soft-delete.
  - **D**: branch.includeRules.maxHops default 5, slider 3..8 в UI;
    findBloodRelation maxDepth=10 не меняется.
* Создан [PHASE-3.1-SCHEMA-PROPOSAL.md](PHASE-3.1-SCHEMA-PROPOSAL.md)
  — полный design proposal по schema changes. **Ожидает review
  Артёма перед началом кода.**

**Что НЕ сделано**: ничего в коде. Никакого implementation до
approve proposal.

**Открытые вопросы в proposal'е** (минимум):
* Q1: re-run миграции v1→v2 целиком при cutover, или incremental
  patch?
* Q3: ОК что visibility override недоступен между Phase 3.1 и 3.4?

---

## 2026-05-14 — Catchup: Phases 3 squash + 4 + 6 shipped

**Контекст**: PROGRESS.md не обновлялся между 2026-05-10 и 2026-05-14.
За это окно к main приземлились три major phases. Catchup-entry чтобы
доку не оставлять стале (детали — в per-phase merge checklists).

**Что landed**:

* **2026-05-11 — Phase 3 squash** (commit `cb67b0b`) — finalisation
  of connected per-user trees через identity граф. Source-of-truth:
  [DECISIONS.md](DECISIONS.md) 2026-05-10 ответы A-D + RFC
  `tree_model_overhaul_rfc.md`.

* **2026-05-12 — Phase 4** (commit `028d1d2`) — extended-family
  network. Backend `/v1/trees/:treeId/extended-network` + BFS slice
  + foreign node sheet + search + 100 new tests. Behind feature
  flag `useExtendedRenderPath` initially.
  * Details: [MERGE-CHECKLIST-PHASE-4.md](MERGE-CHECKLIST-PHASE-4.md).

* **2026-05-13 — Phase 4 flag-on flip** (commit `5fb1d3c`) — default
  enabled. 7-day observation week starts. Cleanup commit (flag +
  legacy code path removal) pending ~2026-05-17 минимум.

* **2026-05-14 — Phase 6** (commit `414b218`) — onboarding wizard
  (`/setup`) + kinship-check «мы родственники?» discovery
  (`/discover/relatives`) + post-signup redirect + notification
  routing + empty-state polish. 110 new tests (42 backend +
  68 client).
  * Details: [MERGE-CHECKLIST-PHASE-6.md](MERGE-CHECKLIST-PHASE-6.md) +
    [PHASE-6-PROPOSAL.md](PHASE-6-PROPOSAL.md).
  * Decisions: 30d rejection cooldown, /setup route split,
    Option A post-signup redirect, identity-suggestions push
    deferred к Phase 6.5.
  * Observation window: 2 weeks, ends ~2026-05-28.

**Phase 3.4 status** (NOT shipped, parked):
* Branch `claude/infallible-pike-41360c` at `66a31ac` — docs
  «Phase 3.4 done, merge-to-main checklist». Visibility toggle +
  grants + branch wizard + sensitive contacts + conflict badges
  + migration strings («Дерево» → «Ветка»).
* Branch ready-to-merge per its own checklist; awaiting Артёмов
  squash decision. Phase 4 + 6 не required this UI work
  (orthogonal scope), так что timeline diverged from original
  cutover plan in CURRENT-PHASE.md.

**Тесты на 2026-05-14** (full suites):
* Backend: 345 tests / 342 pass / 3 fail. Все 3 — pre-existing
  Windows ENOTEMPTY flakes в `api.test.js` (rmdir tmp race on
  Windows; не воспроизводится на Linux CI). Same baseline as
  Phase 4 merge.
* Flutter: 614 pass / 2 skip (perf-tagged) / 3 fail. Все 3 —
  pre-existing baseline в `custom_api_notification_service_test.dart`
  (MissingPluginException для flutter_secure_storage в test
  context).
* `flutter analyze`: 2 warnings (intentionally parked `_branchDigest`/
  `branch_digest_strip` per commit `c4f3a80`). Post commit
  `8a27462` (2026-05-14 tech-debt closure) — 2 leftover test
  scaffold warnings closed.

**Что осталось** (per CURRENT-PHASE.md):
* Phase 4 +1w cleanup commit (~2026-05-17 минимум).
* Phase 6 observation метрики до ~2026-05-28.
* Phase 3.4 merge decision (Артёмов call).
* Phase 3.6 hard-delete background job (warm-up filler, design pending).
