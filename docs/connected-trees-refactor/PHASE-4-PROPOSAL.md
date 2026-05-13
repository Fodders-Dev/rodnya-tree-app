# Phase 4 proposal v2 — расширенная сеть через identity-граф

**Дата**: 2026-05-12
**Source of truth ветки**: `claude/quiet-meridian-7a91b3` от `cb67b0b`.
**Изменения от v1**: 10 design questions закрыты review циклом
(см. `DECISIONS.md` 2026-05-12). Главные сдвиги: depth slider
range `2..4` (не `3..10`); slider совпадает с privacy fence
(`_connectedVisibilityMaxHops = 4`) — Phase 4 = pure
visualization layer, не scope extension. §7 open questions = 0.

**Ссылки**:
* `tree_model_overhaul_rfc.md` — original RFC, Phase 4 listed как «BFS UI для расширенной сети».
* `PHASE-3.4-UI-PROPOSAL.md` §6 — Phase 3.4 specifically НЕ делает Phase 4 BFS, deferred.
* `DECISIONS.md` **2026-05-10** «два независимых maxHops» — `_connectedVisibilityMaxHops = 4` (privacy BFS, Phase 3.1) vs `branch.includeRules.maxHops` (UX dial, Phase 3.4). Phase 4 — НЕ третья constant; slider в filter panel **совпадает** с privacy fence.
* `DECISIONS.md` **2026-05-12** «Phase 4 архитектурные answers» — 10 decisions cross-referenced из этого proposal'а.

---

## 0. Контекст и DoD

### Что Phase 4 делает

* **Новый view mode** в `tree_view_screen` — «Расширенная сеть».
  Помимо персон собственной ветки, на канвасе появляются persons
  чужих веток, до которых я могу дойти по identity-графу — **в
  пределах privacy fence `_connectedVisibilityMaxHops = 4` hops**
  (см. DECISIONS.md 2026-05-12 Q1.B/Q6.A).
* **Backend endpoint** `GET /v1/trees/:treeId/extended-network` —
  возвращает graph slice: my-tree persons + extended persons +
  graphRelations между ними. Privacy gate из Phase 3.1 применяется
  **per-target-node** (fence не relax'ается, не per-path).
* **UI controls** для toggle'а между «Моё дерево» и «Расширенная
  сеть», visualization чужих nodes (colour tint + owner-avatar
  badge), tap-on-foreign-node → информационный sheet (без
  «Попросить доступ» button — Q4.A), search scope mine+extended
  (Q5.A), filter panel с depth slider **2..4** (Q6.A) +
  scrollable chips (Q7.A).
* **Performance** на mid-range mobile (Samsung A52-class): first
  paint ≤ 1.5s, smooth 60fps scroll до 500+ visible nodes. Slice
  cap ≤ 1000 persons (Q5.A) с UX hint «Сузить через фильтры»
  если cap достигнут.

### Что Phase 4 НЕ делает

* **Не делает write на чужие nodes напрямую**. Edit grants
  (Phase 3) — единственный путь к edit. Без grant'а tap → snackbar
  «Это карточка @other-user'а, попросите доступ».
* **Не делает "Найти родство"** (path resolution от viewer'а к
  arbitrary target'у с custom relation label'ом). Это Phase 5
  feature; Phase 4 показывает structural edges as-is.
* **Не делает hard-delete background job** (Phase 3.6).
* **Не делает мульти-tree merge UI**. Если у меня в extended view
  виден чужой node, который дублирует моего — это suggestion
  (Phase 1.2 capability) либо conflict (Phase 1.3 capability),
  оба уже surfaced.
* **Не меняет** `_connectedVisibilityMaxHops = 4` (privacy BFS) и
  `branch.includeRules.maxHops` (per-branch UX dial). Phase 4
  добавляет третий dial — `extendedNetworkMaxHops`.

### DoD Phase 4

* Toggle «Моё дерево / Расширенная сеть» в `tree_view_screen`
  AppBar (per Q8.A — per-tree persist; Q8.C narrow mobile fallback
  decision'ится in implementation).
* В extended режиме user видит чужие nodes с явным визуальным
  signal'ом — **colour tint warm (my) vs cool (foreign)** + muted
  edge color для cross-tree edges. Без always-visible owner badge
  на canvas (chunk 3 prep review tightened, см. §5.A — badge на
  on-tap в chunk 4 sheet'е).
* Tap на чужой node → sheet с owner identity + «Написать» (chat
  flow) + «Открыть карточку» (read-only person card). **Никаких
  «Попросить доступ» stub'ов** (Q4.A).
* Search в extended view — client-side filter по slice (Q5.A);
  slice cap ≤ 1000 persons.
* Filter panel: depth slider **2..4** (default 4, Q6.A) +
  scrollable chips (Q7.A).
* Backend `/v1/trees/:treeId/extended-network` отдаёт graph slice
  ≤ 1 round-trip; ≤ 30MB +RAM overhead vs my-only view; ≤ 1.5s
  до first paint на Samsung A52-class. Server clamps `maxHops`
  query param к 2..4 (под privacy fence).
* `flutter analyze` clean, widget tests + integration tests на
  toggle + render extended slice + tap foreign node + denied
  edit attempt.
* Phase 3 invariants preserved: ownership ≠ creator gate
  (DECISIONS.md 2026-05-11), owner-only visibility/contacts,
  capability mixin pattern (старый сервер без endpoint'а →
  toggle disabled с tooltip'ом).

---

## 1. Existing UI baseline (контекст)

* **`tree_view_screen.dart`** — single-tree view. Canvas + sidebar
  + AppBar с branch switcher chip (Phase 3.4 added). Currently
  ВСЕ persons видимы — нет mode toggle.
* **`interactive_family_tree.dart`** — рисует graph: nodes, edges,
  badge'ями ⚠ (Phase 1.3 conflicts) и 💡 (Phase 1.2 suggestions).
  Layout — force-directed либо layered (зависит от branch type).
* **`relatives_screen.dart`** — list view моих persons. Phase 3.4
  chunk 5 добавил conflict badges per-row.
* **Backend `_userCanSeeGraphPerson(viewerUserId, graphPersonId)`**
  (Phase 3.1) — privacy BFS до 4 hops. Это **read-gate**. Phase 4
  использует это как fundamental privacy fence, но добавляет
  **dedicated extended-network endpoint** который применяет gate
  один раз и возвращает batched slice.
* **`branch.includeRules`** (Phase 3.4 chunk 1) — определяет какие
  persons показываются в my-tree view (manual / blood-from-me /
  descendants-of / ancestors-of). Phase 4 НЕ меняет includeRules;
  они продолжают определять «моё дерево». Extended view — orthogonal
  surface.
* **`graphPersons` + `graphRelations` schema** (Phase 3.1) —
  canonical store. Phase 4 читает оттуда же.

---

## 2. Per-feature wireframes

### 2.1 Mode toggle entry point (Q8)

**Где живёт переключатель** — best guess **AppBar segmented
control** в `tree_view_screen`, справа от branch switcher chip:

```
┌─────────────────────────────────────────────────────────────┐
│ ← [Бабушкина ветка ▾]    [Моё дерево | Расш. сеть]    [⋮]   │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ... canvas ...                                              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Persist strategy (закреплена review, Q8.A closed)**: **per-tree**.
Каждая ветка помнит свой mode отдельно. SharedPreferences с
key'ом `extended_mode_${treeId}`. Default «Моё дерево» при
отсутствии preference'а — opt-in явный.

**Reasoning**: friends-tree вряд ли нужен extended (там нет
identity-cross-link'ов обычно); blood-tree — наоборот, главное
место использования. Global preference теряет per-tree intent.

**URL shareability deferred** (Q8.B closed) — Phase 4 v1 не
реализует `/tree/view/:treeId?mode=extended&depth=N`. Phase 5+
если сценарий «look at my tree this way» появится в feedback'е.

**Narrow mobile fallback** (Q8.C closed) — labels «Моё / Все»
(short) с font scaling. Layout testing откладывается до
implementation chunk. Fallback: icon-only (`mode_outlined` /
`network_check_outlined`) с tooltip'ами если на 320dp cramped.

**Альтернативы рассмотрены и отвергнуты**:
* Bottom sheet pull-up — скрытый, юзер не догадается.
* Side drawer item — далеко от canvas, неудобно во время
  изучения.
* Global preference — coarse, теряет per-tree intent.

### 2.2 Extended graph view (Q1, Q2, Q3)

**Q1 — семантика «Расширенной сети» (модель A/B/C)**:

Три возможные модели:

* **Model A. Polite walk** — только nodes которые принадлежат
  user-аккаунтам connected'нo с моей extended family. Anonymous
  persons вне моего hop-radius'а исключены.
* **Model B. Full graph slice** — все nodes до которых я могу
  дойти по identity-графу в radius'е N hops, включая anonymous'ов
  чужих веток. Privacy gate из Phase 3.1 уже фильтрует.
* **Model C. Federated view** — мой tree + любая чужая tree, в
  которой есть хотя бы один общий graphPerson с моей. Show full
  чужую ветку наложением.

**Рекомендация (закреплена review)**: **Model B — Full graph
slice**, depth slider **2..4 default 4** (DECISIONS.md
2026-05-12 Q6.A). Совпадает с `_connectedVisibilityMaxHops = 4` —
slider это **filter «сузить view для clarity»**, не «расширить
scope». Reasoning:

* **Model A** фильтрует anonymous'ов — но именно anonymous'ы
  (предки, вписанные родственниками) часто и есть ценность
  Phase 4 («ой, моя бабушка в Машиной ветке тоже есть, и у неё
  есть отец, которого я не знал»). Model A режет это use case.
* **Model C** (federated, чужая ветка целиком) — privacy edge
  case'ы (person без direct identity link с моим, но с
  visibility=public — показывать ли наложением чужой ветки?
  Phase 4 не должен внезапно делать public-feed). Также scope
  взрывной по объёму.
* **Model B** + slider 2..4 даёт юзеру dial: 4 hops = «полная
  доступная сеть», 2 hops = «близкие + бабушки/дедушки».

**Q1.B (closed)**: privacy fence respected. Phase 4 не relax'ает
fence — depth slider не превышает `_connectedVisibilityMaxHops`.
Если post-deploy реальный use case потребует > 4 hops — это
Phase 5+ feature с consent flow, не Phase 4.

**Q1.A (closed)**: public-frontier walk за fence невозможен как
emergent property Q1.B — fence per-target-node, не per-path. См.
DECISIONS.md 2026-05-12.

**Q2 — визуальное разделение my vs others' nodes**:

V2 proposal'е был blanket «colour tint + 18×18 owner-avatar badge +
dashed edges». Артёмов review (chunk 3 prep, 2026-05-12) tightened
visual palette до tablular per-item explicit-approval decisions —
«не подкидывай 5 визуальных элементов вместе, может «протащиться»
через одобрение комплекта».

Полная visual palette chunk 3 в **§5.A chunk 3 visual design** ниже
(после Q-table в §6/§7) — там 5 элементов с pro/con/verdict и
explicit-approval request'ом на каждый.

**Wireframe (target после chunk 3 implementation)**:
```
   ┌──────────────────┐         ┌──────────────────┐
   │ [Я]    Иван П.   │ ──────  │ ░░ Маша П.    ░░ │
   │  warm beige bg   │ primary │ ░ cool grey bg ░ │  <- tint only
   └──────────────────┘  edge   └──────────────────┘  no badge
                                       │
                                       │ muted edge color
                                       │ (solid, не dashed)
                                       ▼
                              ┌──────────────────┐
                              │ ░░ Дед Семён   ░░ │
                              │ ░ cool grey bg ░  │
                              └──────────────────┘

   Tap на foreign node → expanded sheet с owner avatar + chat (chunk 4).
```

**Q3 — edge resolution для cross-tree relations**:

Три варианта:

* **A. От моего viewpoint** — backend resolve'ит path для каждого
  cross-tree edge и возвращает label «двоюродный брат», «двоюродная
  тётя» etc.
* **B. As-is** — backend возвращает структурный graphRelations
  edges (parent/child/spouse/sibling), UI рисует без интерпретации.
* **C. Hybrid** — структура by default, tap on edge → sheet с
  resolved relation-to-me (lazy path resolution server-side).

**Рекомендация (закреплена review)**: **C — Hybrid**. Structural
rendering by default (performance: no path resolution на каждый
из 100+ edges). Relation-to-me — **lazy compute через tap на
node** (Q3.A closed, DECISIONS.md 2026-05-12): tap on foreign
node → sheet содержит row «Как этот человек связан со мной»,
который lazy fetch'ит `/v1/trees/:id/relation-path` (existing
endpoint, Phase 2).

**Edge tap НЕ используется** — edges на mobile микроскопические,
попасть пальцем сложно. Node tap target простой и reliable.

### 2.3 Editability flow (Q4)

**Q4 — editability в extended view + UX denial handling**:

**Рекомендация**: **B — grants-aware**. Логика:

* **Mine nodes** (где `effectiveOwnerUserId == viewerUserId`) —
  fully editable (как сейчас в my-only view).
* **Others' nodes с edit grant'ом мне** — editable. UI ровно тот же
  что my-only.
* **Others' nodes без grant'а** — read-only. Tap → sheet с:
  * Owner avatar + displayName + «@username».
  * «Открыть карточку» button → переход в person card view (без
    edit affordances).
  * «Написать @username» button если canStartChat (см.
    `_canStartChat` в relatives_screen).
  * «Попросить доступ» button → Phase 5 feature stub (опционально
    показываем «coming soon»; alternative — skip кнопку до Phase 5).

**Denial handling** при попытке edit:
* Long-press / overflow menu «Изменить имя» → если grant'а нет:
  snackbar «Это карточка @other-user'а — у вас нет доступа на
  изменение.»
* Server при попытке PATCH без grant'а → 403 `NOT_OWNER` /
  `NO_EDIT_GRANT` (Phase 3.2). UI ловит и показывает то же
  message что defensive client-side (defense in depth).

**Sensitive contacts** в extended view — **никогда** не показываются
для не-self person'ов. Phase 3.4 chunk 4 invariant сохраняется
(`_isViewerOwnPerson(person)` gate). Tap-sheet НЕ содержит phone/
email чужого пользователя; «Написать» button открывает chat, не
показывая контакт.

**«Попросить доступ» button НЕ в Phase 4** (Q4.A closed). Lure
без выполнения = false UX promise. Юзер сейчас идёт через chat
(«@username, могу я редактировать карточку Бабушки Лиды?»).
Real edit-request flow с notification ping owner'у — Phase 5+.

### 2.4 Search в extended view (Q5)

**Q5 — search scope**:

Три варианта:
* **A. Mine-only** — даже в extended режиме поиск ищет только в
  branch.includeRules.personIds.
* **B. Mine + extended visible** — поиск в том scope'е что сейчас
  визуально на canvas.
* **C. Global** — все publicly searchable persons + grant-accessible.

**Рекомендация**: **B — Mine + extended visible**. Search должен
match'ить «что юзер сейчас видит». Если он в extended mode искал
«Семён» — он ожидает Семёна-из-Машиной-ветки тоже.

Global search (C) deferred → Phase 5 «Найти родственника».

**Search bar location**: top of canvas в extended mode (same place
where my-only view имеет «Найти на дереве» если есть). Если нет —
добавляем search input bar inline.

**Search performance** (Q5.A closed): client-side filter по уже-
fetched extended slice. No round-trip. **Slice cap = 1000 persons**;
больше — показываем UX hint «Слишком много карточек — сузьте
через фильтры». Server-side search endpoint и пагинация — Phase 5+
если production случаев slice > 1000 обнаружится в realistic
trafic'е. У тестовых users < 100 persons, premature optimization
сейчас.

### 2.5 Filter/controls panel layout (Q7)

**Q7 — где живут filter'ы (по owner, по relation, по generation)**:

**Рекомендация (закреплена review)**: **inline drawer (mobile)
+ persistent sidebar (wide)**. Pattern уже используется в
`relatives_screen`. **Chips horizontally scrollable** (Q7.A
closed) — standard Material Filter Chips, scrollable container
обходит cramping на narrow.

**Mobile (narrow)**:
* Top-right на canvas — кнопка «Фильтры (N)» где N = активных
  filter'ов.
* Tap → DraggableScrollableSheet snap'ом снизу (Material standard),
  не full-screen modal.
* Контент:
  * **Slider depth `2..4` default `4`** (Q6.A closed — совпадает
    с `_connectedVisibilityMaxHops`). Labels: 2 = «Ближний круг»,
    3 = «Средний круг», 4 = «Полная доступная сеть».
  * **Multi-select chips «По веткам»** — какие чужие trees
    included. Horizontally scrollable.
  * **Multi-select chips «По генерациям»** — `-3` to `+3` от
    меня (great-grandparents to great-grandchildren). Horizontally
    scrollable.
  * Switch «Показывать anonymous (не привязанные к аккаунту)».

**Desktop (wide ≥ 900px)**:
* Sticky right sidebar 280px wide.
* Те же controls но всегда видимы. Chips wrap (не scroll), там
  есть место.
* Live preview: «Показано 47 / 92 persons по текущим фильтрам».

**State**: filter values persist per-tree (вместе с view mode,
Q8.A). SharedPreferences keyed `tree_${treeId}_extendedFilters`.

---

## 3. Architecture

### 3.1 Backend

**Новый endpoint**: `GET /v1/trees/:treeId/extended-network`

**Query params**:
* `maxHops: int` (default 4, range **2..4**) — slider value
  (Q6.A). Server clamp'ит и выше (`min(maxHops, 4)`), и ниже
  (`max(maxHops, 2)`) для defensive parsing.
* `includeAnonymous: bool` (default true).
* `branchIds: csv` (default all) — фильтр по конкретным веткам
  если юзер хочет crisp'ный slice.

**Response shape**:
```json
{
  "graphPersons": [...],
  "graphRelations": [...],
  "branchMembership": {
    "graphPersonId": ["branchId-1", "branchId-2"]
  },
  "ownerMap": {
    "graphPersonId": {
      "userId": "...",
      "displayName": "...",
      "photoUrl": "..."
    }
  },
  "stats": {
    "totalCount": 47,
    "myCount": 12,
    "extendedCount": 35,
    "anonymousCount": 8,
    "maxHopsReached": false,
    "capReached": false
  }
}
```

**`ownerMap` is sparse** (chunk 1 implementation choice, DECISIONS.md
2026-05-12 nice-to-have #1): map содержит entries **только для
foreign nodes** (где `owner !== viewer`). Viewer-owned nodes
implicit'но resolve'ятся через `slice.getOwnerInfo(id) == null`
client-side. На 90%+ typical viewer'е это даёт значимую экономию
payload + memory.

**Gating logic** (server-side, Q1.B closed):
1. Privacy BFS от viewer'а на `_connectedVisibilityMaxHops = 4`
   определяет «whom viewer is allowed to read» — privacy fence,
   per-target-node (не per-path).
2. Внутри этого set — BFS на `maxHops` (2..4, clamped) определяет
   extended slice. Поскольку cap === fence, query maxHops=4 даёт
   полный allowed set; maxHops=2 даёт focused subset.
3. Sensitive attributes (`field === 'contacts'`) фильтруются
   per-person как раньше (Phase 3.4 chunk 4 invariant).
4. graphRelations возвращаются только если **оба endpoints в
   slice** — никаких partial edges, никакого public-node-as-portal
   leak'а (Q1.A emergent).
5. Slice cap 1000 persons; если BFS hits limit — truncate +
   `stats.capReached: true` для UX hint'а (Q5.A).

**Capability mixin**: `ExtendedNetworkCapableFamilyTreeService` —
дополнительный optional contract. Старый сервер без endpoint'а —
client receives 404 → UI disable'ит toggle + tooltip «Обновите
приложение».

**Performance**: server caches per-viewer slice на 60 секунд
in-memory (Redis-style ETag). Invalidate on `setVisibility`,
`addGrant`, `acceptIdentityClaim`. Этого достаточно для
mobile-class workload.

### 3.2 Frontend widgets

**Новые**:
* `lib/screens/tree_view_screen.dart` — extended mode rendering
  branch (existing class extended, не отдельный screen).
* `lib/widgets/extended_network_toggle.dart` — segmented control
  в AppBar.
* `lib/widgets/extended_network_filter_sheet.dart` —
  DraggableScrollableSheet с controls (mobile).
* `lib/widgets/extended_network_filter_sidebar.dart` — sticky
  right sidebar (desktop).
* `lib/widgets/foreign_node_action_sheet.dart` — tap-sheet для
  чужих nodes (owner avatar + chat / open / suggest).
* `lib/backend/interfaces/extended_network_capable_family_tree_service.dart`.
* `lib/backend/models/extended_network_slice.dart` — DTO.

**Changes в existing**:
* `lib/widgets/interactive_family_tree.dart` — добавляется param
  `viewMode` (enum `BranchViewMode.mine | extendedNetwork`) + per-
  node `ownerInfo`. Rendering за feature-flag `useExtendedRenderPath`:
  - Node fill: warm (my) vs cool grey-blue (foreign).
  - Edge color: primary (my-to-my) vs surfaceVariant (cross-tree),
    solid (НЕ dashed — chunk 3 prep tightened, см. §5.A Element 2).
  - **Без overlay badge'ей на canvas** (Element 3 ON DEMAND only —
    owner avatar в chunk 4 tap-sheet'е).
* `lib/services/custom_api_family_tree_service.dart` — implements
  ExtendedNetwork capability.
* `lib/providers/tree_provider.dart` — `viewMode` per-tree
  persist через SharedPreferences.

### 3.3 State management

**`ExtendedNetworkController`** (новый ChangeNotifier либо Cubit,
зависит от существующего pattern'а; в проекте Provider + GetIt —
делаем ChangeNotifier для consistency):

```
class ExtendedNetworkController extends ChangeNotifier {
  final String treeId;
  ExtendedNetworkSlice? _slice;
  bool _isLoading;
  String? _error;
  ExtendedNetworkFilters _filters; // depth, branches, generations

  Future<void> refresh();
  Future<void> updateFilters(ExtendedNetworkFilters next);
  bool get hasData => _slice != null;
}
```

Live'ётся как DI'd singleton per-tree через
`Provider.of<ExtendedNetworkController>(context)`.

### 3.4 Routing

* НЕ добавляем новые routes. Extended mode — internal state
  `tree_view_screen`'а, не отдельный URL. URL остаётся
  `/tree/view/:treeId`; mode persist через storage.
* Shareable URL (`?mode=extended&depth=N`) — **deferred Phase 5+**
  (Q8.B closed, DECISIONS.md 2026-05-12). Phase 4 v1 — UI only.

---

## 4. Performance budget (Q6)

### Targets на Samsung A52-class (Snapdragon 720G, 6GB RAM,
Android 13)

| Metric | Target | Strategy |
|---|---|---|
| First paint extended view | ≤ 1.5s от tap toggle'а | 1 round-trip endpoint, lazy compute server-side, response ≤ 200KB |
| Steady-state 60fps scroll | до 500 visible nodes | Viewport-based rendering (RenderObject visible-bounds check) |
| RAM overhead | ≤ +30MB vs my-only | DTO компактный — graphPerson preview (id + name + photoUrl + isAlive), полные attributes lazy on tap |
| Battery (10-min session) | ≤ +3% vs my-only | Не polling; refetch on user action (mode toggle / filter change / pull-to-refresh) |
| Network | ≤ 1 round-trip per mode-toggle | Single endpoint; no follow-up fetches до tap-on-foreign-node |

### Strategy details

**Viewport rendering**: `InteractiveFamilyTree` сейчас рисует все
nodes на одном Canvas. На 500+ persons — janks. Phase 4 добавляет
visible-bounds filter: только nodes intersect'ящиеся с current
viewport проходят paint(). Layout computed once, paint cheap.

**Lazy fetch на open**: backend slice не включает person attributes
полностью — только preview (id, name, photo, isAlive, ownerUserId,
branchIds). Tap on foreign node → `getPersonById(treeId,
graphPersonId)` если ещё не cached. Standard pattern.

**Server-side cache**: per-viewer ETag 60s. Invalidate triggers:
visibility change, grant change, identity claim. Не invalidate
на propagation conflict (Phase 1.3 already debounces).

**Fallback на slow connection**: если `/extended-network` round-
trip > 3s — show loading skeleton with «Загружаем расширенную
сеть...» и offer кнопку «Отмена». Не block'ируем return to
my-only view.

### Slice size re-estimate (Q6.A closed)

С slider'ом capped at 4 hops (== privacy fence), realistic slice
sizes:

* **2 hops**: self + immediate (parents/kids/spouse) + grandparents
  + siblings + niblings ≈ **7-15 persons** typical.
* **3 hops**: + great-grandparents + cousins ≈ **20-40 persons**.
* **4 hops** (default): full allowed extended sub-graph ≈ **30-100
  persons** typical для среднего пользователя.

Outliers (богатые extended families с 200+ persons в 4-hop walk'е)
exist, но Phase 4 cap (1000 persons, Q5.A) их закрывает с UX hint
«сузить через фильтры».

Performance targets (см. table выше) остаются — slice size cap
делает их достижимыми с большим margin'ом.

---

## 5. Privacy semantics

### Phase 4 invariants (Q1.B closed, Q1.A emergent)

* `_connectedVisibilityMaxHops = 4` (privacy BFS, Phase 3.1) **не
  меняется**. Privacy fence — viewer never sees graphPerson beyond
  4 hops по blood-graph'у.
* Filter slider в UI (2..4 default 4) — это **view filter inside
  privacy-allowed set**. Slider не «расширяет scope», а «сужает
  view для clarity» когда юзер хочет focused subset.
* **Public-frontier walk за fence НЕВОЗМОЖЕН** (Q1.A emergent).
  Privacy fence resolves **per-target-node**, не per-path.
  Сценарий «public X используется как портал к private Y» режется
  на render Y (или его sensitive fields). Это property privacy
  schema из Phase 3.1, Phase 4 не меняет.
* graphRelations возвращаются только если **оба endpoints в
  slice** — никаких partial edges, никаких «namesignals» вне
  fence'а.

См. **DECISIONS.md 2026-05-12** для full reasoning Q1.B / Q1.A.

### Owner-only-всегда invariants preserved

* Visibility toggle (Phase 3.4 chunk 2) — owner-only на render.
  Extended view **показывает** чужой node если он privacy-allowed,
  но **НЕ показывает** owner visibility controls.
* Sensitive contacts (chunk 4) — owner-only-всегда. Foreign node
  tap-sheet **никогда** не leak'ает phone/email чужого юзера.
* Edit grants (chunk 3) — gate'ят editability как описано в §2.3.

### Anonymous persons в extended view

Anonymous person'ы (graphPerson без `userId`, owned by `createdBy`):
* Если owner privacy-allowed мне — anonymous person отображается с
  badge owner'а creator'а (`createdBy`'s avatar) — DECISION
  «ownership ≠ creator» применяется: для **privacy data** owner =
  userId after claim, но для **anonymous case** (нет userId) =
  createdBy.
* Edit grant: на anonymous person через createdBy. Если grant
  выписан — editable.

---

## 5.A Chunk 3 visual design — tabular per-item approval

Артёмов review (2026-05-12, chunk 3 prep) после reading chunk 2
commit'а tightened визуальную палитру chunk 3. V1 proposal'е был
blanket «colour tint + 18×18 owner-avatar badge + dashed cross-tree
edges»; review раскрыл его в 5 **независимых** decisions с pro/con
analysis. Per Артёмов request: «не подкидывай 5 визуальных
элементов вместе — может «протащиться» через одобрение комплекта».

Каждый элемент ниже — **отдельный approval gate** перед chunk 3
implementation. Status `Pending` означает «жду explicit approval».
`Approved (2026-05-12)` — закрытый decision, в DECISIONS.md.

### Element 1: Colour tint own vs foreign nodes — ESSENTIAL

**Verdict (Артёмов review)**: **Approved (2026-05-12)** — обязателен.

**Reasoning**: без tint'а foreign nodes визуально идентичны своим;
юзер путает «это я добавил» vs «это Степа добавил». Без него весь
extended mode бессмыслен — юзер просто видит больше нод без
понимания откуда они.

**Implementation**:
* My nodes — current warm beige (`primaryContainer` из
  RodnyaDesignTokens). Не меняется.
* Foreign nodes — cool grey-blue tint (low saturation,
  `surfaceContainerLow` либо custom token). НЕ яркий — оттенок,
  не цвет.
* Контраст ≥ 3:1 на обоих themes (Material Design accessibility
  baseline).
* На большой дистанции (≥10 nodes) должен оставаться читаем
  без eye strain.

**Caveat (Артёмов 2026-05-12)**: WCAG 3:1 — только non-text UI
минимум. **Визуально проверить на 50% zoom** (scroll-out view).
Если tint становится indistinguishable на scrolled-out — увеличить
saturation. Golden snapshot tests на **2-3 zoom levels** (1.0,
0.5, 0.25) — DECISIONS.md 2026-05-12.

### Element 2: Edge color tint (cross-tree edges) — ESSENTIAL

**Verdict (Артёмов review)**: **Approved as replacement (2026-05-12)** —
edge color tint вместо dashed pattern. Solid edges, но muted
цвет для cross-tree.

**Reasoning**: dashed pattern на тонкой 1-2px line почти не виден,
плюс рендеринг dashed Path в Flutter Canvas дороже solid (extra
path operations при каждом фрейме scroll'а). Edge color дешевле,
видимее, semantically точно.

**Implementation**:
* My-to-my edges — `primary` palette (current).
* Cross-tree edges — `surfaceVariant` (приглушённый neutral).
* Solid lines both, без dashed patterns.
* Stroke width одинаков (1.5px либо как сейчас в legacy).

### Element 3: Owner avatar badge — ON DEMAND, не always-visible

**Verdict (Артёмов review)**: **Approved as on-tap only (2026-05-12)**.

**Reasoning v1 (proposed)**: 18×18 owner-avatar badge всегда видим
на foreign nodes — даёт context «кто добавил».

**Reasoning v2 (chunk 3 prep)**:
* Pro: «кто это добавил» сразу видно.
* Con: на slice с 50+ foreign nodes — 50 микро-аватарок = visual
  noise. На 320dp 18×18 badge может накладываться на text карточки.
* **Compromise**: показывать ТОЛЬКО на hover/tap. По умолчанию
  foreign node только с tint'ом, БЕЗ аватарки. Tap → expanded
  card с owner avatar full size + name + chat button (chunk 4
  работа на самом sheet'е).

**Implementation**:
* Никаких overlay badge'ей на canvas nodes по умолчанию.
* Tap → foreign node action sheet (chunk 4) рендерит owner avatar
  full size.

### Element 4: Conflict ⚠ badge — KEEP existing (Phase 3.4 chunk 5)

**Verdict**: **Approved (existing, no change, 2026-05-12)**.

Phase 3.4 chunk 5 уже реализовал conflict badge на canvas (per-node
warning icon с count'ом). Chunk 3 не trogает — badge продолжает
работать для both my и foreign nodes (если у них unresolved
identity-field conflicts).

### Element 5: Deleted state — KEEP existing

**Verdict**: **Approved (existing, no change, 2026-05-12)**.

Existing deleted-state UI (фон + текст «Удалено») сохраняется.
Extended view не показывает `deletedAt != null` graphPersons
(они отсеяны на backend'е), так что в practice deleted-state в
extended mode не появится — но defensive code path остаётся.

### DROPPED elements (chunk 3 prep review)

| Element | Reason for drop |
|---|---|
| Dashed cross-tree edges | Заменён на edge color tint (Element 2). Dashed на тонкой line почти не виден + рендеринг дороже. |
| Always-visible owner badge | Заменён на on-tap (Element 3). Always-visible = noise на 50+ foreign nodes. |

### Chunk 3 implementation gates

Перед coding chunk 3 — обязательны:

1. **Perf baseline** — synthetic fixture'ы 100 / 500 / 1000 persons,
   измерить first paint + scroll FPS на legacy code path (before
   ANY changes). Save baseline number. Если new render path
   regress'нёт legacy view (mine mode) — RED FLAG, halt chunk 3.
2. **Visual snapshot tests** — golden file per state:
   * own node (tint warm)
   * foreign node (tint cool, без badge)
   * own + conflict ⚠
   * foreign + conflict ⚠
   * deleted (legacy)

   **Pin all variables** (Артёмов 2026-05-12) для reproducible
   files across dev machines + CI runners:
   * `ThemeMode.light` (force, не system).
   * Fixed window size: 1920×1080 (desktop) либо 390×844 (mobile).
   * `MediaQueryData.textScaler = TextScaler.noScaling`.
   * Multi-zoom: 1.0, 0.5, 0.25 (per Element 1 caveat).
3. **Feature-flag** `useExtendedRenderPath` (`bool` const либо runtime).
   При `false` — legacy code path, identical bit-for-bit. Защита
   от regression во время review. После chunk 4 (или + 1 prod
   week) flag удаляется.

---

## 6. UX considerations

### 6.A: Семантика «Расширенной сети» (Q1) — recap

См. §2.2. **Закреплено: Model B (Full graph slice)**, depth
slider **2..4 default 4** (== privacy fence). DECISIONS.md
2026-05-12 Q1.B/Q6.A.

### 6.B: Avatar badge layout — DROPPED (chunk 3 prep)

V1 plan: 18×18 always-visible owner avatar в углу foreign node'а.
Chunk 3 prep review (2026-05-12) **dropped** этот element:
50+ foreign nodes × 18×18 = visual noise + risk overlap на narrow
viewport. Replaced на **on-tap only** в chunk 4 foreign node sheet'е
(там avatar full size + displayName + chat button).

См. **§5.A Element 3** + DECISIONS.md 2026-05-12.

### 6.C: Edge tap target (Q3)

Hybrid: structural rendering, tap on **node** (не edge) → sheet
включает «Как этот человек относится ко мне» row. Tap on edge —
too fiddly target на canvas, особенно на mobile.

### 6.D: Foreign node tap-sheet actions (Q4)

Order priority (Q4.A closed: НЕТ «Попросить доступ» stub в Phase 4):
1. Owner identity (avatar + displayName + «@username» либо «без
   аккаунта»).
2. Relation-to-me row (lazy compute on sheet open).
3. «Открыть карточку» — переход на person card view (read-only
   variant).
4. «Написать @username» — если canStartChat.
5. (skip «Открыть в дереве владельца» — privacy regression).
6. (skip «Попросить доступ» — Phase 5+ feature, DECISIONS.md Q4.A).

### 6.E: Mode toggle (Q8) — recap

См. §2.1. **Закреплено: AppBar segmented control + per-tree
persist** (Q8.A). URL shareability deferred Phase 5+ (Q8.B).
Narrow mobile fallback test in implementation (Q8.C).
DECISIONS.md 2026-05-12.

---

## 7. Open questions — все закрыты

Review-revise цикл с Артёмом (2026-05-12) закрыл все 10 open
questions из v1. Каждая → DECISION в
`DECISIONS.md` 2026-05-12. Quick reference:

| Q# | Тема | Closure |
|---|---|---|
| Q1.A | Public-frontier walk за fence | Невозможен (emergent из Q1.B) — fence per-target-node, не per-path |
| Q1.B | Privacy fence vs view filter | **RESPECT FENCE** — Phase 4 = pure visualization, не scope extension |
| Q3.A | Edge tap vs node tap для relation-to-me | **Node tap** — edge tap UX-вред на mobile |
| Q4.A | «Попросить доступ» button в Phase 4 | **Defer** — без stub, real flow в Phase 5+ |
| Q5.A | Search ≤ 1000 persons | **Client-side filter**, server-side search Phase 5+ |
| Q6.A | Depth slider default conservative/ambitious | **Range 2..4 default 4** — slider совпадает с privacy fence |
| Q7.A | Chips vs dropdown filter | **Chips horizontal scroll** — Material standard |
| Q8.A | View mode persist scope | **Per-tree** — different preferences для family vs friends tree'ев |
| Q8.B | Shareable URL для extended slice | **Defer** — Phase 5+ если сценарий обнаружится |
| Q8.C | Narrow mobile segmented control | **Test in implementation** — fallback icon-only если cramped на 320dp |

**0 open questions в v2.** Любые новые discovery during
implementation → отдельный DECISION либо follow-up TODO в
DECISIONS.md.

---

## 8. Risks + testing strategy

### 8.1 Risks

| Risk | Mitigation |
|---|---|
| `/extended-network` slow (> 3s) на real data | Server cache 60s; loading skeleton с отменой; fallback на my-only без error'а |
| Slice > 1000 persons → janks даже с viewport rendering | Hard cap 1000 + UX hint «Сузить через фильтры». Telemetry для real distribution |
| Privacy leak: чужой sensitive contact в tap-sheet | Phase 3.4 chunk 4 invariants — sensitive attributes server-side filtered. Defense in depth: client owner-check перед render'ом. Widget test для этого |
| Старый сервер без endpoint'а → blank screen | Capability mixin gate — toggle disabled с tooltip. Existing pattern из Phase 3.4 |
| Per-tree persist confusing когда юзер открывает чужую ветку через invite | Session-only reset для new tree visits; persist только после явного toggle'а |
| Cross-tree edge → пропавший node на edge endpoint'е (если другой endpoint вне privacy fence) | Server: filter edges где оба endpoints в slice; never partial edges |

### 8.2 Testing strategy

**Backend**:
* `test/extended-network-endpoint.test.js` — gating (privacy fence
  applied), pagination/limit, capability detection, cache invalidation.
* Расширенный `test/owner-model-enforcement.test.js` — extended
  view не bypass'ит Phase 3.2 gates.

**Flutter**:
* `test/extended_network_toggle_test.dart` — segmented control
  render + tap + persist.
* `test/extended_network_filter_sheet_test.dart` — sliders +
  chips + apply.
* `test/foreign_node_action_sheet_test.dart` — owner display +
  actions (chat / open / deny edit).
* `test/extended_network_controller_test.dart` — fetch + filter +
  invalidation.
* `test/interactive_family_tree_extended_test.dart` — viewport
  bounds check + colour tint (warm/cool) + edge color tint
  (primary/surfaceVariant) + feature-flag off/on diff. Golden
  files per state (см. §5.A implementation gates).

**Integration**:
* `integration_test/extended_network_flow_test.dart` — toggle →
  fetch → render → tap foreign → sheet → close. End-to-end mobile
  emulator.

**Performance**:
* Synthetic fixture с 500 / 1000 / 2000 persons. Measure first paint
  + scroll fps на Samsung A52 либо closest emulator. Fail CI если
  > 1.5s / < 50fps.

### 8.3 Migration / backward-compat

* **Backend без endpoint'а** → 404; client capability check скрывает
  toggle. Existing pattern.
* **Старая Flutter app без Phase 4 widgets** → toggle missing,
  но my-only view продолжает работать. Phase 4 НЕ ломает Phase 3
  surface'ы.
* **Schema additions** — нет. Phase 4 читает из существующего
  `graphPersons` / `graphRelations` / `branches`. Migration
  v2→v3 не требуется.

---

## 9. Approval flow / implementation outline

* V1 proposal commit'нут baseline'ом `32a8f8d`.
* V2 (this document) — review-revise iteration после ответов
  Артёма 2026-05-12.
* DECISIONS.md update commit'нут `eeefde1` отдельно — chronological
  audit trail чище (decision живёт как first-class record, не
  embedded в proposal версии).
* До approve'а v2 — **0 commits кода** в этом worktree.
* После approve'а — phased implementation, 4 chunks по аналогии
  с Phase 3.4:

  ### Chunk 1 — backend endpoint + capability + Flutter scaffold

  * `GET /v1/trees/:treeId/extended-network` server-side
    (route + store BFS + privacy gate applied per-target-node).
  * Query params: `maxHops` (clamp 2..4), `includeAnonymous`,
    `branchIds`.
  * Response cap 1000 persons + `capReached` flag.
  * Backend tests: privacy gate, fence respect, cap behavior,
    capability detection.
  * Flutter:
    `lib/backend/interfaces/extended_network_capable_family_tree_service.dart`,
    `lib/backend/models/extended_network_slice.dart`,
    service implementation в `custom_api_family_tree_service.dart`.
  * Unit tests для DTO parsing.

  ### Chunk 2 — mode toggle + filter sheet (UI scaffold)

  * `lib/widgets/extended_network_toggle.dart` — segmented control
    в AppBar.
  * `lib/widgets/extended_network_filter_sheet.dart` —
    DraggableScrollableSheet с slider **2..4 default 4** + chips
    horizontal scroll.
  * `lib/widgets/extended_network_filter_sidebar.dart` — wide
    layout variant.
  * `lib/providers/extended_network_controller.dart` — ChangeNotifier
    + per-tree persist (SharedPreferences key
    `extended_mode_${treeId}` + `extended_filters_${treeId}`).
  * Widget tests на toggle render, persist, filter sheet
    interactions.
  * UI пока без rendering чужих nodes — placeholder «Загружается
    расширенная сеть» / empty state.

  ### Chunk 3 — extended rendering на canvas

  Visual palette tightened review'ом (см. **§5.A**). Реализуем
  только **Approved** элементы; **Dropped** не trogano.

  **Pre-implementation gates** (см. §5.A «Chunk 3 implementation gates»):
  1. Perf baseline 100/500/1000 fixture'ы (legacy mine view) —
     CI artifact, threshold для regression check'а.
  2. Visual snapshot tests (golden files) — own/foreign/conflict/
     deleted states.
  3. Feature-flag `useExtendedRenderPath` — runtime либо const,
     false → legacy bit-identical path.

  **Implementation tasks**:
  * `lib/widgets/interactive_family_tree.dart` — добавляется param
    `viewMode` + per-node `ownerInfo`. Внутри:
    - Node fill: warm beige (my) либо cool grey-blue (foreign).
      Tint logic за feature-flag.
    - Edge color: primary (my-to-my) либо surfaceVariant (cross-tree).
      Solid, без dashed.
    - **НЕТ overlay badge'ей на canvas** — owner avatar только
      в chunk 4 tap-sheet'е (Element 3 ON DEMAND).
  * Viewport-based rendering (RenderObject visible-bounds check)
    для 500+ persons performance — нужно если baseline покажет
    regression. Может оказаться overkill при slice cap=1000.
  * Synthetic performance fixture 500/1000 persons; CI fails если
    first paint regress'нёт > 10% от baseline.

  ### Chunk 4 — foreign node tap-sheet + relation-to-me + search

  * `lib/widgets/foreign_node_action_sheet.dart` — owner identity
    row + «Написать» (chat existing flow) + «Открыть карточку»
    (read-only). **Без «Попросить доступ» stub** (Q4.A).
  * Relation-to-me lazy compute через existing
    `/v1/trees/:id/relation-path` (Phase 2).
  * Search в extended scope — client-side filter по slice.
  * Slice cap UX hint «Сузить через фильтры» если `capReached`.
  * Integration test end-to-end: toggle → fetch → render → tap
    foreign node → sheet → close.

---

**Status v2**: ready для approve. После approve — chunk 1.

**Open questions**: **0** (все 10 закрыты в v1→v2 review цикле,
см. §7 + DECISIONS.md 2026-05-12).
