# Phase 4 proposal — расширенная сеть через identity-граф

**Дата**: 2026-05-12
**Source of truth ветки**: `claude/quiet-meridian-7a91b3` от `cb67b0b`.
**Ссылки**:
* `tree_model_overhaul_rfc.md` — original RFC, Phase 4 listed как «BFS UI для расширенной сети».
* `PHASE-3.4-UI-PROPOSAL.md` §6 — Phase 3.4 specifically НЕ делает Phase 4 BFS, deferred.
* `DECISIONS.md` 2026-05-10 «два независимых maxHops» — `_connectedVisibilityMaxHops = 4` (privacy BFS, Phase 3.1) vs `branch.includeRules.maxHops` (UX dial, Phase 3.4). Phase 4 — третья constant: `extendedNetworkMaxHops`.

---

## 0. Контекст и DoD

### Что Phase 4 делает

* **Новый view mode** в `tree_view_screen` — «Расширенная сеть».
  Помимо персон собственной ветки, на канвасе появляются persons
  чужих веток, до которых я могу дойти по identity-графу за
  ограниченное число hops (точное число — Q1 ниже).
* **Backend endpoint** `GET /v1/trees/:treeId/extended-network` —
  возвращает graph slice: my-tree persons + extended persons +
  graphRelations между ними, фильтрованные через Phase 3 visibility
  gate.
* **UI controls** для toggle'а между «Моё дерево» и «Расширенная
  сеть», visualization чужих nodes (colour tint + owner-avatar
  badge), tap-on-other → информационный sheet, search scope,
  filter panel.
* **Performance** на mid-range mobile (Samsung A52-class): first
  paint ≤ 1.5s, smooth 60fps scroll до 500+ visible nodes.

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
  AppBar (либо где Q8 решит).
* В extended режиме user видит чужие nodes с явным визуальным
  signal'ом (colour + avatar) что они не его.
* Tap на чужой node → sheet с owner info + действиями (chat / open
  in their tree if allowed / suggest edit if Phase 5 готов).
* Backend `/v1/trees/:treeId/extended-network` отдаёт graph slice
  ≤ 1 round-trip; ≤ 30MB +RAM overhead vs my-only view; ≤ 1.5s
  до first paint на Samsung A52-class.
* `flutter analyze` clean, widget tests + integration tests на
  toggle + render extended slice + tap denied edit.
* Phase 3 invariants preserved: ownership ≠ creator gate, owner-
  only visibility section, capability mixin pattern (старый
  сервер без `/extended-network` endpoint'а → toggle disabled
  с пояснением).

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

**Persist strategy**: **per-tree**. Каждая ветка помнит свой mode
отдельно. Reasoning: friends-tree вряд ли нужен extended (там нет
identity-cross-link'ов обычно); blood-tree — наоборот, главное место
использования. Storage: `TreeProvider` extends with
`viewMode: Map<treeId, BranchViewMode>` в SharedPreferences.

**Default**: «Моё дерево» при первом открытии конкретной ветки.
Юзер opt-in'ит явно.

**Альтернативы рассмотрены**:
* Bottom sheet pull-up — скрытый, юзер не догадается что
  «Расширенная сеть» есть.
* Side drawer item — далеко от canvas, неудобно переключаться
  «во время изучения».
* Global preference — слишком coarse, теряет per-tree intent.

**→ Open Question Q8.A** ниже: per-tree vs global persist если у
юзера много branches и он хочет «всегда extended по умолчанию».

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

**Рекомендация**: **Model B — Full graph slice**, depth =
`extendedNetworkMaxHops = 6` (proposal). Reasoning:

* Natural extension `_connectedVisibilityMaxHops = 4` (privacy BFS).
  Phase 4 = read-view той самой visibility frontier'и, плюс
  «дотягиваемся ещё на 2 hops» чтобы юзер мог открыть для себя
  кого он напрямую не помнит.
* Model A фильтрует anonymous'ов — но именно anonymous'ы (предки,
  вписанные родственниками) часто и есть ценность Phase 4
  («ой, моя бабушка в Машиной ветке тоже есть, и у неё есть
  отец, которого я не знал»).
* Model C показывает чужую ветку целиком — этот scope взрывной
  по объёму, и privacy edge case'ы (что если в чужой ветке есть
  person без direct identity link с моим, но с visibility = public
  — показывать ли? Phase 4 не должен внезапно делать public-feed).

**→ Open Question Q1.A**: `extendedNetworkMaxHops` = 6 — обоснован?
Можно сделать UX dial (3..10) в filter panel, либо hardcode.

**Q2 — визуальное разделение my vs others' nodes**:

**Рекомендация**: **colour tint + small owner-avatar badge** в
углу узла. Чем выделяем:

* **Цвет**: my nodes — `primaryContainer` (warm beige по design tokens
  RodnyaDesignTokens). Others' nodes — `surfaceContainerLow` (cool
  muted neutral). Контраст ≥ 3:1 на обоих themes.
* **Avatar badge**: 18×18 круглый avatar owner'а в правом нижнем
  углу узла. Без подписи (имя в tap-sheet'е).
* **Не использовать**: border ring (избыточно, и border уже
  используется для conflict ⚠ badge'ей Phase 1.3).
* **Edge style**: my-to-my edges — solid. Cross-tree edges
  (any-to-other либо other-to-other) — dashed. Это уже было в
  RFC §...

**Wireframe**:
```
   ┌──────────────────┐         ┌──────────────────┐
   │ [Я]    Иван П.   │ ──────  │ [@] Маша П.      │
   │  warm bg         │  solid  │  cool bg + 👤    │
   └──────────────────┘         └──────────────────┘
                                       ╎
                                       ╎ dashed (cross-tree)
                                       ╎
                              ┌──────────────────┐
                              │ [@]  Дед Семён   │
                              │  cool + 👤       │
                              └──────────────────┘
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

**Рекомендация**: **C — Hybrid**. Structural rendering by default
(performance: no path resolution на каждый из 100+ edges); tap
on edge — lazy compute via `/v1/trees/:id/relation-path` (existing
endpoint, Phase 2). Это сохраняет mental model «extended view =
structural fact», а path resolution — explicit user action.

**→ Open Question Q3.A**: вместо «tap on edge» — long-press на
node чтобы получить «как этот человек относится ко мне». Edge
tap-targets на canvas сложные; node tap проще.

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

**Search performance**: client-side filter по уже-fetched extended
slice. No round-trip. Limit slice size до ≤ 1000 persons; больше —
показываем zoom-out hint «Сузить через фильтры».

### 2.5 Filter/controls panel layout (Q7)

**Q7 — где живут filter'ы (по owner, по relation, по generation)**:

**Рекомендация**: **inline drawer (A) + persistent sidebar (B) на
wide layout**. Pattern уже используется в `relatives_screen`
(там два column layout на desktop).

**Mobile (narrow)**:
* Top-right на canvas — кнопка «Фильтры (N)» где N = активных
  filter'ов.
* Tap → DraggableScrollableSheet snap'ом снизу (Material standard),
  не full-screen modal.
* Контент:
  * Slider depth `extendedNetworkMaxHops` 3..10 (default 6).
  * Multi-select chips «По веткам» — какие чужие trees included.
  * Multi-select chips «По генерациям» — `-3` to `+3` от меня
    (great-grandparents to great-grandchildren).
  * Switch «Показывать anonymous (не привязанные к аккаунту)».

**Desktop (wide ≥ 900px)**:
* Sticky right sidebar 280px wide.
* Те же controls но всегда видимы.
* Live preview: «Показано 47 / 92 persons по текущим фильтрам».

**State**: filter values persist per-tree (вместе с view mode).
SharedPreferences keyed `tree_${treeId}_extendedFilters`.

---

## 3. Architecture

### 3.1 Backend

**Новый endpoint**: `GET /v1/trees/:treeId/extended-network`

**Query params**:
* `maxHops: int` (default 6, range 3..10) — `extendedNetworkMaxHops`.
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
    "maxHopsReached": false
  }
}
```

**Gating logic** (server-side):
1. Privacy BFS от viewer'а на `_connectedVisibilityMaxHops = 4`
   определяет «whom viewer is allowed to read».
2. Внутри этого set — BFS на `maxHops` (3..10) определяет extended
   slice.
3. Sensitive attributes (`field === 'contacts'`) фильтруются
   per-person как раньше.
4. graphRelations возвращаются только если оба endpoints в slice.

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
  `viewMode` (enum `BranchViewMode.mine | extendedNetwork`),
  node rendering ветвится на colour tint + owner avatar
  badge. Edges: dashed для cross-tree.
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

**→ Open Question Q8.B**: shareable URL для extended view?
`/tree/view/:treeId?mode=extended&depth=6` — shareable link на
конкретный slice. Полезно для «отправь мне свою расширенную
сеть посмотреть» flow.

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

### Open Question Q6.A

`extendedNetworkMaxHops` default = 6 даёт ~50-200 persons на
typical user (по моему предположению). Реальный среднестатистический
объём — unknown без production data. План: enable feature flag,
собрать week первой production метрики distinct visible nodes per
viewer, потом fine-tune'ить default. **→ Open Question Q6.A**:
запускать с default = 4 (более conservative) и поднимать после?

---

## 5. Privacy semantics

### Phase 4 invariants

* `_connectedVisibilityMaxHops = 4` (privacy BFS, Phase 3.1) **не
  меняется**. Это privacy fence — viewer never sees graphPerson
  beyond 4 hops по blood-graph'у regardless of `extendedNetworkMaxHops`.
* `extendedNetworkMaxHops` (3..10, default 6) — **read-only walk**
  inside того что privacy gate уже allows. Если viewer privacy-
  visible до 4 hops, и `extendedNetworkMaxHops = 6` — реальный
  walk = `min(4, 6) = 4`. Это deliberate: `extendedNetworkMaxHops`
  не obtain'ит больше чем privacy позволяет.

**Wait** — это нужно проверить. Может быть `extendedNetworkMaxHops`
действует **внутри** privacy-set'а (т.е. expands view among
privacy-allowed nodes), не **снаружи**?

**→ Open Question Q1.B**: что Phase 4 extends — privacy fence или
view filter? Текущая proposal'а интерпретация: view filter, fence
остаётся 4. Альтернатива: relax privacy fence до 6 если viewer
явно opt-in'ил extended mode (но это privacy regression — нет).

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

## 6. UX considerations

### 6.A: Семантика «Расширенной сети» (Q1) — recap

См. §2.2. **Рекомендация: Model B (Full graph slice)** с
`extendedNetworkMaxHops = 6` default.

### 6.B: Avatar badge layout (Q2)

Avatar badge 18×18 в правом нижнем углу node'а. Node size — 64×64
(current). Badge размер компромисс между recognizability и не-
закрывать-name. Если node размер ≠ 64×64 на разных zoom levels —
badge scale'ится пропорционально, min 12×12 чтобы не disappear'ить.

### 6.C: Edge tap target (Q3)

Hybrid: structural rendering, tap on **node** (не edge) → sheet
включает «Как этот человек относится ко мне» row. Tap on edge —
too fiddly target на canvas, особенно на mobile.

### 6.D: Foreign node tap-sheet actions (Q4)

Order priority:
1. Owner identity (avatar + displayName + «@username» либо «без
   аккаунта»).
2. Relation-to-me row (lazy compute on sheet open).
3. «Открыть карточку» — переход на person card view (read-only
   variant).
4. «Написать @username» — если canStartChat.
5. «Попросить доступ» — feature stub, Phase 5 implementation.
6. (skip «Открыть в дереве владельца» — privacy regression).

### 6.E: Mode toggle (Q8) — recap

См. §2.1. **Рекомендация: AppBar segmented control + per-tree
persist**.

---

## 7. Open questions

Эти questions surface'нуты для review-revise цикла с Артёмом.
До approve'а — НИ ОДНОГО code commit'а (per твоему правилу).

### Q1.A. `extendedNetworkMaxHops` default = 6 — обоснован?

Внутри privacy fence (4 hops) `extendedNetworkMaxHops = 6` ≥ 4 →
practically clamp'ится к 4. Тогда зачем UX dial 3..10? Может
default = 4, UX dial 3..6 (всегда ≤ privacy fence)?

**Sub-question**: можно ли позволять `extendedNetworkMaxHops > 4`
для **public** persons (visibility = public) — тогда extended view
бы тянул дальше через public-frontier? Это совсем другой scope
(global-discovery), Phase 5+.

### Q1.B. Privacy fence vs view filter — что Phase 4 expands?

Текущая интерпретация: view filter inside privacy-allowed set.
Privacy fence (4 hops) — hard wall. Альтернатива (relax fence) —
privacy regression. **→ моя сильная позиция: keep fence, expand
view только**. Подтверди или скажи иначе.

### Q3.A. Edge tap target vs node tap для relation-to-me

Edge tap-target маленький, особенно на mobile. Node tap + sheet
row «relation-to-me» — более reliable. Кроме того, edge может
быть «структурный» (parent-of) — relation-to-me компьютится через
**path** от меня к target node'у, не через single edge. Так что
node tap семантически более корректен.

Подтверди или предложи иной trigger.

### Q4.A. «Попросить доступ» button — Phase 4 либо Phase 5?

Это grant-request flow (юзер pinger'ит owner'а «дай мне edit
grant»). Phase 4 surface'ит button, Phase 5 имплементит обработку.
Если в Phase 4 button = stub «coming soon» — confusing UX. Лучше
**не показывать button** до Phase 5, либо реализовать минимальный
notification ping в Phase 4.

### Q5.A. Search в extended mode — client-side filter sufficient?

При slice ≤ 1000 persons — client filter справится. Для slice
1000+ нужен server-side search endpoint. На текущей proposal'е
slice limit 1000; если real data покажет регулярные slice'ы
> 1000 — нужен Phase 4.1 server-side search addendum.

### Q6.A. `extendedNetworkMaxHops` default conservative (4) или ambitious (6)?

Без production data — guess'ом. **Моё предложение**: запустить с
default = 4 (≡ privacy fence), feature flag, через неделю собрать
метрику «distinct visible nodes per viewer / per session» и
fine-tune'ить.

### Q7.A. Filter panel — chips или dropdown?

Multi-select branches / generations — chips более dscan'абельны,
dropdown компактнее. На mobile space ограничен. **Моё
предложение**: chips для ≤ 6 опций (branches обычно ≤ 4-5),
dropdown для many (generations -3..+3 = 7 опций → dropdown +
range slider'ом).

### Q8.A. View mode persist — per-tree, global, или hybrid?

Per-tree рекомендован выше. **Альтернатива**: global preference
«всегда extended по умолчанию» switch в Settings + per-tree
override. Тогда юзер с многими branches не должен toggle'ить
каждую.

### Q8.B. Shareable URL для extended slice?

`/tree/view/:treeId?mode=extended&depth=6&branchIds=A,B` —
shareable link. Полезен для «покажи мне свою сеть» flow в chat'е.
Но прокидывает state через URL, что усложняет
`AppShellRouteModule`. Decide: in scope Phase 4 или deferred.

### Q8.C. Toggle UX на narrow mobile (< 360px)

Segmented control из 2 опций («Моё дерево» / «Расш. сеть») —
~180px width минимум. На очень узких экранах (Galaxy S10e, iPhone
SE 1st gen) AppBar trip'ится. **Альтернатива**: icon-only switch
(`mode_outlined` ↔ `network_check_outlined`) либо overflow menu
item.

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
  bounds check + colour tint + dashed cross-tree edges.

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

## 9. Approval flow

* Этот document — input для review-revise цикла.
* До approve'а Артёма — **0 commits кода** в этом worktree (только
  proposal commit, плюс revise iterations этого же proposal).
* После approve'а — phased implementation (вероятно chunks 1-4,
  по аналогии с Phase 3.4):
  * **Chunk 1** — backend endpoint + capability mixin + Flutter
    DTO + service implementation.
  * **Chunk 2** — toggle + state controller + filter sheet (UI без
    extended rendering — just empty state).
  * **Chunk 3** — extended rendering в `interactive_family_tree`
    (colour tint + avatar badge + dashed edges).
  * **Chunk 4** — foreign node tap-sheet + relation-to-me lazy
    compute + search в extended scope.
  * (Performance optimization — across chunks, не separate chunk).

---

**Принято к review**: Артём (user) — **TBD**.

**Open questions to answer**: Q1.A, Q1.B, Q3.A, Q4.A, Q5.A, Q6.A,
Q7.A, Q8.A, Q8.B, Q8.C.
