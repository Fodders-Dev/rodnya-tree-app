# Architectural Decisions Log

Каждое архитектурное решение принятое в ходе рефакторинга
заносится сюда с датой и обоснованием. Формат:

```
## YYYY-MM-DD: краткое название
**Контекст**: какая ситуация
**Решение**: что выбрали
**Альтернативы**: что отклонили и почему
**Влияет на**: список файлов / API
**Принято**: имя decision-maker'а
```

---

## 2026-05-09: фундаментальное направление

**Контекст**: текущая модель «multi-tree per user + invite to
slot» не масштабируется когда у юзеров общие родственники, и
не позволяет приглашённому юзеру быть активным редактором.

**Решение**: переходим на **connected per-user trees** —
каждый юзер имеет одно дерево с собой как корнем, cross-tree
связи через `personIdentities`.

**Альтернативы**:
* Single shared global tree (FamilySearch model) — отвергнут:
  невозможен без community moderation, не подходит для
  закрытой семейной соцсети.
* Status quo с расширенными permissions (приглашённые могут
  редактировать BLOOD-RELATED slot'ы) — отвергнут как полумера,
  не решает дубликаты cross-tree.

**Влияет на**: всё. См. PLAN.md полностью.

**Принято**: Артём (user) + Claude.

---

## 2026-05-09: PLAN.md superseded by RFC

**Контекст**: Phase 0 audit (этой сессии) обнаружил, что в коде уже
существует параллельный unified-graph слой (`graphPersons` /
`graphRelations` / `branches` / `branchPersonViews`), реализующий
бо́льшую часть «целевой модели». Это исполнение отдельного RFC —
[`docs/tree_model_overhaul_rfc.md`](../tree_model_overhaul_rfc.md)
от 2026-05-07. Сделанные фазы по RFC: Phase 0 (person-picker),
Phase 1.1 (identity propagation), Phase 1.2 (silent 💡 matcher),
Phase 3.1 (schema graph), Phase 3.4 (post.branchIds[]), Phase 6.1
(BranchSwitcherChip).

PLAN.md (написан в этой же сессии до audit'а) описывает альтернативную
модель «single tree per user», которая НЕ совместима с RFC: PLAN.md
требует удалить multi-branch концепцию и BranchSwitcher, RFC — её
центральный UX-элемент.

**Решение**: PLAN.md superseded by RFC. RFC — единственный source
of truth. graphPersons + branches слой остаётся. Phase 0 / 1.1 /
1.2 / 3.1 / 3.4 / 6.1 правильны и не выпиливаются. Никаких
гибридов — чисто B (RFC выигрывает).

**Альтернативы**:
* **A: PLAN.md правильный, RFC выпиливаем** — отвергнут: пара
  месяцев работы по 1.1/1.2/1.3/3.1/3.4/6.1 не должна выкидываться
  из-за того что новый план был написан в неведении. И сама
  multi-branch модель отвечает на пользовательскую боль про
  ветки лучше, чем single-tree.
* **C: гибрид (граф под капотом, single-tree сверху)** — отвергнут:
  половинчато, BranchSwitcher уже в проде, одна модель должна
  победить, а не сосуществовать.

**Влияет на**: всё дальнейшее. PLAN.md помечен SUPERSEDED, фазы
ниже (Phase 1, 2, 3, ...) больше НЕ актуальны в его трактовке.
Источник правды — RFC.

**Принято**: Артём (user).

---

## 2026-05-09: memberIds — split into two distinct mechanisms

**Контекст**: в legacy модели `tree.memberIds[]` несёт два смешанных
смысла — (a) право редактировать дерево и (b) право видеть/писать
в ленту дерева. В RFC модели эти смыслы разъезжаются по разным
сущностям, поэтому простой drop невозможен.

**Решение**:
* (a) **Право редактировать** → owner-model на уровне `graphPerson`,
  не на уровне ветки. Реализуется в RFC Phase 3.2: автоматически
  на ≤2 hops по кровным рёбрам, модерация на 3+, hard-delete
  запрещён. Per-узел, не per-ветка.
* (b) **Право видеть ленту ветки** → отдельный механизм branch
  sharing. Дизайн — при подходе к Phase 3 (TREE → BRANCH миграция),
  отдельным design-pass'ом.

`memberIds` как поле в `branches` пока зеркалится из legacy
`tree.memberIds` (через `_syncTreeToBranch`), но не используется
для авторизации в новых endpoints. Будет полностью удалено когда
оба механизма (a)+(b) задеплоены и legacy переход завершён.

**Альтернативы**:
* «Просто drop memberIds» — отвергнут: теряем два разных смысла,
  ломаем существующие use case'ы.
* «Конвертировать в общий treeVisibility» — отвергнут как
  половинчатое решение: владелец-модель и share-модель — разные
  концепции, должны быть разные API.

**Влияет на**: backend Phase 3.2 (owner-model), новый branch-share
API в Phase 3.

**Принято**: Артём (user).

---

## 2026-05-09: Three legacy invite flows → two API + three user-facing actions

**Контекст**: сейчас три разных flow «привлечь юзера в моё дерево»:
1. `linkPersonToUser` через invite-link (`/v1/invitations/pending/process`)
2. `createTreeInvitation` (`/v1/trees/:treeId/invitations`)
3. `linkPersonsByIdentity` (`/v1/trees/:treeId/persons/:personId/link-identity`)

В RFC модели семантика «привязать userId к слоту» становится
частным случаем identity-claim (self-graphPerson юзера ←→ identity
link с targetPerson).

**Решение**:
* **Invite-link** → identity-claim: `linkPersonsByIdentity` API
  поверх self-graphPerson юзера и слота в чужой ветке.
* **Manual merge двух узлов** → тот же `linkPersonsByIdentity` API.
* **Share branch access** (read/post в чужой ленте без identity
  claim'а) → отдельный API. Либо новый, либо repurposed
  `createTreeInvitation` — решим на дизайне Phase 3.
* **`linkPersonToUser` → DEPRECATED.** Старые ссылки продолжают
  работать через legacy-redirect ([web/index.html](web/index.html)
  уже это делает) ~3 месяца после Phase 3, потом депрекейтятся.

**Альтернативы**:
* «Все три legacy flow жизнеспособны, оставляем» — отвергнут:
  семантика slot-link противоречит graph-модели и порождает
  дубли в graphPersons.
* «Резко выпиливаем всё legacy после Phase 3» — отвергнут:
  у юзеров на руках старые invite-ссылки, нужен переходный
  период.

**Влияет на**: Phase 3 (TREE → BRANCH миграция), endpoint
`/v1/invitations/pending/process` будет переписан на тонкий
shim над `linkPersonsByIdentity`.

**Принято**: Артём (user).

---

## 2026-05-09: Phase 3 заблокирован 4 нерешёнными вопросами

**Контекст**: Phase 3 (TREE → BRANCH миграция) — XL-фаза, требует
отдельного design-pass перед началом кода. RFC оставил 4 вопроса
открытыми; без ответов лезть в Phase 3 нельзя.

**Решение**: до старта Phase 3 нужно зафиксировать ответы на:
1. **Privacy escape hatch на graphPerson** — три уровня:
   `owner` / `connected` / `public`. Дефолт? Кто видит контактные
   данные живых людей? Как переключать без UI-катастрофы?
2. **Migration conflict strategy** — что wins при initial merge
   противоречивых данных? Самый недавний `updatedAt`? Самый
   полный record? Manual merge через mergeProposals?
3. **Owner-model thresholds** — реально ли «≤2 hops auto» работает
   в большой семье (200+ родственников)? Где граница между
   автоматическим propagation и moderation queue?
4. **BFS depth для blood-branch визуализации** — 4-5 hops, не 10?
   Где обрезаем visualization чтобы canvas не падал?

Phase 1.3 (edit-time conflict surfacing) **НЕ заблокирован** этими
вопросами. Закрываем 1.3 как описано в RFC, потом design-pass
по Q1-Q4, потом Phase 3.

**Принято**: Артём (user).

---

## 2026-05-10: Phase 3 разблокирован — ответы A–D на 4 RFC-вопроса

**Контекст**: 2026-05-09 я зафиксировал 4 нерешённых вопроса как
блокеры Phase 3. Артём ответил 2026-05-10, формально снимая блок.

### A. Privacy escape hatch на graphPerson

**Решение**:
* **Default visibility** = `connected-via-blood-graph` (≤4 hops по
  кровным рёбрам видят узел; за пределами — нет).
* **Sensitive fields** (телефон, текущий адрес, email) — `owner-only`
  всегда, независимо от hops. Это per-field gate поверх node visibility.
* **Историческое исключение**: `isAlive === false && birthYear < (now - 100 лет)`
  → автоматически `public` (узел исторический, не несёт privacy
  риска для живых).
* **Owner override**: владелец graphPerson может явно поднять
  privacy на конкретный узел до `owner-only` (например, секретный
  родственник).

**Влияет на**:
* `graphPerson.visibility` — новое поле (см. SCHEMA proposal).
* `graphPerson.visibilityOverride` — для owner-poweredup secret nodes.
* Sensitive fields — отдельный список на стороне store / route layer.
* Cross-tree access checks — расширяются с `_userCanAccessTreeRecord`
  до `_userCanSeeGraphPerson(graphPersonId, viewerUserId)`.

### B. Migration conflict strategy

**Решение**:
* Initial migration по `personIdentities` строит canonical
  graphPerson через **highest-completeness wins**: для каждого
  поля **отдельно** выбираем source с наибольшим количеством
  непустых значений (не на уровне записи целиком).
* Все divergent values записываются в `identityFieldConflicts`
  (та самая Phase 1.3 коллекция) с `resolvedAt: null`.
* После миграции каждый affected user видит ⚠️ badge на узлах
  с conflict'ами и решает через тот же Phase 1.3 UI.
* **Принципиально**: переиспользуем существующий механизм
  Phase 1.3, не плодим новую логику для миграции.

**Влияет на**:
* `pickCanonicalPerson` в [migration-utils.js:307](backend/src/migration-utils.js:307)
  → переписывается на per-field selection, удаляется текущая
  preference «claimed user → updatedAt».
* `buildGraphPersonFromCanonical` → читает best-non-null per-field.
* После migration — записать divergent values в
  `identityFieldConflicts` для каждого поля где source != canonical.

### C. Owner-model thresholds — пересмотрено vs RFC Phase 3.2

**Решение** (строже чем RFC «≤2 hops auto», осознанно):
* **Default**: owner-only edit, **без auto-extension по hops**.
* **Owner extension**: владелец может явно дать права на конкретный
  graphPerson другому юзеру через UI (новая сущность
  `graphPersonEditGrants` или поле в graphPerson). Не автоматически
  по графу.
* **Merge двух узлов**: **оба** owner'а должны дать consent (двусторонне).
  Никакого auto на ≤2 hops.
* **Hard-delete запрещён** (как в RFC) — 30-day soft с
  восстановлением через `deletedAt` flag.

**Обоснование Артёма**: «избежим vandalism в больших семьях. Если
потом UX покажет что слишком зажато — расширим». То есть это
deliberately conservative starting point.

**Влияет на**:
* RFC Phase 3.2 «≤2 hops auto» / «3+ hops moderation» — **отменяется**.
* Заменяется на: всегда owner-only + явные grants.
* Новая сущность `graphPersonEditGrants` (TBD: shape) — кто кому
  дал права редактировать graphPerson.
* `mergeProposals` уже двусторонний механизм (через `claimedByUserId`
  с обеих сторон) — не нужно менять.

### D. BFS depth для blood-branch визуализации

**Решение**:
* **Default `branch.includeRules.maxHops`** = 5 (≈4 поколения вверх
  + 1–2 вниз для viewer'а).
* **UI slider** 3..8 в branch-creation wizard (Phase 6.4) — юзер
  выбирает.
* **`findBloodRelation` (Phase 4 BFS)**: `maxDepth = 10` ОК — это
  другой сценарий («найти родство с любым человеком в графе»),
  не визуализация ветки.

**Влияет на**:
* `branch.includeRules` — новое поле `maxHops` для типа
  `blood-from-me` / `descendants-of` / `ancestors-of`.
* Helper `_buildBranchVisiblePersonIds` в store.js (упомянут в RFC
  Phase 6.4) учитывает `maxHops`.

**Принято**: Артём (user) 2026-05-10.

**Следующий шаг**: design proposal по schema changes (Phase 3.1)
с учётом A-D — `PHASE-3.1-SCHEMA-PROPOSAL.md`. Показать Артёму
ПРЕЖДЕ чем браться за миграцию. Не лезть в код store.js / migration
до явного approve.

---

## 2026-05-10: Phase 3.1 proposal approved + Q1/Q3 + pre-flight check

**Контекст**: PHASE-3.1-SCHEMA-PROPOSAL.md вышел на review.
Артём approve целиком + два уточнения + один nice-to-have.

### Q1: re-run миграции v1→v2 ЦЕЛИКОМ

* `complete-v2` ledger ещё не существует — старый `complete` после
  Phase 3.1 трактуется как «нужно пересобрать с новой logic'ой».
* Re-run полностью deterministic + idempotent + покрывается dry-run
  diff'ом.
* В существующих v2-данных ничего критичного не накопилось, что
  нельзя пересобрать из v1 + новой logic'и.
* **Если что-то ВДРУГ всплывёт после rerun (data drift между rebuild
  и старой v2) — фиксируем как новую DECISION в DECISIONS.md и
  обсуждаем. Не молча правим.**

### Q3: accept gap между Phase 3.1 и 3.4

* Default `connected-via-blood-graph` + sensitive fields owner-only
  через personAttributes — conservative enough.
* Юзеры не получат worse-than-current state: сейчас escape hatch'а
  на чужие деревья нет вообще.
* Рисковый случай (deceased ancestor которого хотят owner-only)
  встретится у мизерного числа юзеров. Если жалоб не будет —
  вообще не делаем admin escape.

### Nice-to-have: pre-flight count check в migrateTreesToGraphAndBranches

Перед write проверяет:
* `graphPersons.length === uniqueIdentitiesWithLinkedPersons + personsWithoutIdentity`
* `graphRelations.length === dedup(relations)` (учитывая orphan-drop)
* `branches.length === trees.length`

Если расхождение — **abort** с clear error сообщением, **не write**.
Это страховка от тихого data loss при переписывании canonical-picking
логики.

**Принято**: Артём (user) 2026-05-10.

**Следующий шаг**: implementation в порядке из CURRENT-PHASE.md
(EMPTY_DB → migration → store helpers → tests → dry-run → diff).
Diff на показ перед коммитом — обязательно.

---

## Roadmap после Phase 3.1

После implementation 3.1 backend и migration done, schema заморожена.
Дальше:
* **Phase 3.2** — owner-model permissions enforcement (route gates,
  edit-grants UI flow на стороне backend).
* **Phase 3.4** — UI для visibility/edit grants на клиенте.
* Порядок: любой, Артём подскажет.

---

## 2026-05-10: Phase 3.2 first, не 3.4 — schema без enforcement = corruption surface

**Контекст**: после approve Phase 3.1 (commit 0d5acec) встал
выбор приоритета: 3.2 (route enforcement) vs 3.4 (Flutter UI).

**Решение**: 3.2 first. Никаких вариантов.

Логика:
* Schema 3.1 без enforcement = любой client может писать
  `graphPerson.visibility` что угодно через curl/Postman, обходя
  любые UI ограничения. Это не «permission feedback в runtime» —
  это data corruption surface.
* 3.4 без 3.2 = security theater: красивый toggle в UI который
  ничего не enforce'ит на сервере. Ничему не учит, лживо
  обещает privacy.
* 3.2 standalone testable end-to-end через API tests без UI.
  Faster validation cycle.

**Cutover plan**:
1. 3.1 → pre-prod уже сейчас (миграция + schema, ничего не ломает).
2. 3.2 → pre-prod (enforcement gates + новые grants endpoints).
   Старые UI продолжают работать на anonymous (`graphPerson.userId
   === null`) persons. Claimed получают 403 на edit-as-stranger —
   правильное поведение, не regression.
3. 3.4 → pre-prod + prod (Flutter UI для visibility, grants, wizard).

Между 3.2 и 3.4 — NO user-visible regression на anonymous persons.
Claimed-edit-as-stranger 403 — ровно тот случай, что уже частично
fixнул `additive: true` коммит, теперь финально enforced.

**Принято**: Артём (user) 2026-05-10.

---

## 2026-05-10: Phase 3.2 — Q1/Q3 + nice-to-have pre/post-claim test

После approve PHASE-3.2-ENFORCEMENT-PROPOSAL.md.

### Q1: keep backward-compat для anonymous persons

**Решение**: anonymous (`graphPerson.userId === null`) — edit через
`requireTreeAccess` (creator + memberIds). Claimed (`userId !=
null`) — только owner или active grant per scope.

**Обоснование Артёма**: «семьи строят дерево совместно — Артём
создал слот "прабабушка Лида", Дарья добавила её девичью фамилию
которую она помнит лучше, кто-то ещё фотографию загрузил. Если
запретим — collaboration ломается, RFC модель «общими усилиями»
теряет смысл».

`additive: true` фикс предотвращал DATA-CORRUPTION (затирание
полей чужого слота). Phase 3.2 закрывает orthogonal surface —
editorial vandalism на claimed карточках. Это **не regression**,
а целевой behavior из RFC.

### Q3: 30 days revoked window для /v1/me/edit-grants

**Решение**: 30 дней OK, и **намеренно совпадает** с
`hardDeleteScheduledAt` window из Phase 3.1. Один TTL на оба
audit-флоу = simpler mental model для юзера: «всё что произошло
с моими правами / моими записями за последний месяц видно».

Если потом UX покажет что 30 шумно — снизим до 14, но не больше.

### Nice-to-have: explicit pre-claim/post-claim regression test

**Решение**: в `owner-model-enforcement.test.js` явный test:
1. Member-of-tree (не creator) делает PATCH на person которая
   anonymous (graphPerson.userId === null) → success.
2. Кто-то отдельно claim'ит эту person через invite/relation-request
   flow → graphPerson.userId становится claimer.
3. Тот же member делает PATCH снова → 403.

Это самый болевой regression risk и Артём явно хочет видеть его
зафиксированным test'ом, не только в комментарии.

### Self-resolved Q2/Q4/Q5

* Q2 (create new person) — keep as-is, member может создать
  anonymous → становится owner.
* Q4 (`tree.memberIds` после 3.2) — не удаляем, фейдится в
  Phase 5/6.
* Q5 (`merge-consent` отдельный scope) — keep отдельным от `edit`.

Если что-то из этих окажется неочевидным при implementation —
surface как новая DECISION, не молча решать.

**Принято**: Артём (user) 2026-05-10.

---

## 2026-05-10: Phase 3.2 implementation surfaced edge — createPerson-with-userId followed by createRelation as creator

**Контекст**: при wiring enforcement gates всплыл legitimate
use-case в existing api.test.js:

```
Alice (owner of tree-a) creates person with `userId: bob.user.id`
  → person.userId = bob (claimed by Bob through this single POST)
  → graphPerson.userId = bob (after _syncPersonToGraph)
  → owner of graphPerson = Bob

Alice immediately creates relation:
  POST /v1/trees/tree-a/relations {person1Id: alicePerson, person2Id: bobPerson, ...}
  → mid Phase 3.2 gate: person2 claimed by Bob, Alice has no grant
  → 403
```

Это паттерн «Alice invites Bob через создание linked-person'а +
relation' к нему за один flow». Pre-Phase-3.2 работало (route не
проверял claim'нутость на relation creation). После — reject как
claimed-edit-as-stranger.

Конкретные failing tests на момент implementation:
* `tree graph snapshot syncs profile fields and normalizes family
  units` (api.test.js:9271) — Alice создаёт spouse через
  `userId: bob.user.id` + relation alice↔spouse spouse.
* `branch chat endpoint reuses branch thread and limits participants
  to that branch` (api.test.js:11011) — same shape: Alice creates
  Bob person through `userId: bob.user.id` + relation.
* `auto circles follow tree relations and filter audience content`
  (api.test.js:7747) — same.

### Решение

Эти тесты отражают **legacy invite-via-creation flow** который
Phase 3 RFC явно депрекейтит (см. tree_model_overhaul_rfc.md Phase
3 «invite semantics»). Правильный flow — Bob receive invite,
claim'ит slot из своего аккаунта, тогда graphPerson.userId
обновляется через consent'ный path. Alice создаёт **anonymous**
slot, Bob его потом claim'ит.

Поэтому **adjust expectations** в тестах: либо убрать
`userId: bob.user.id` из POST /persons (создаём anonymous и Bob
claim'ит позже), либо явно ожидать 403 как новое правильное
поведение enforcement'а.

Это **не add auto-grant exemption** для creator. Auto-grants
противоречат ответу C («без auto-extension по hops, только
explicit grants»). Если pre-claim creation + immediate relation
понадобится — Phase 3.4 UI добавит «Создать как anonymous» как
default для unfamiliar email/userId.

### Альтернатива (отвергнут)

Auto-issue limited grant Alice'е при `POST /persons` с `userId`:
* Pro: backward-compat with one-shot invite-via-creation flow.
* Con: нарушает Артёмову Q1/C invariant «без auto-extension». Любая
  exemption «creator получает initial grant» легко становится
  vandal vector — особенно если creator потом revoke'ит и не
  ставит новые grants. Пусть pre-claim Alice работает как
  anonymous; claim — explicit consent step, как в RFC.

**Принято**: Claude (implementation), документирую как DECISION
для review Артёмом. Если он не согласен — поправим до commit'а.
Не молчу — surface как просили.

---

## 2026-05-10: Phase 3.2 follow-up — POST/DELETE relations = tree-level, не двойной edit-gate

**Контекст**: при wiring двойного edit-gate на `POST /relations`
+ `DELETE /relations/:id` всплыли legitimate failures на:
* `auto circles follow tree relations and filter audience content`
  (api.test.js:7747) — Alice (tree-creator) creates relations
  alice↔Bob (Bob claimed his own person), alice↔Carol, partner↔Bob.
* `branch chat endpoint` (11011) — same pattern.
* `tree graph snapshot syncs profile fields` (9271) — same.

Это паттерн «tree-creator расставляет родственные связи между
participants дерева» — Bob и Carol уже в дереве с claimed
self-persons, Alice прокладывает kinship structure. По исходному
proposal'у двойной edit-gate этот flow blocking — Alice не owner
Bob'а / Carol'ы.

### Решение

**Relation creation/deletion — tree-level STRUCTURAL операция,
не editorial mutation на конкретных persons.** Per Артёмовой Q1
(«семьи строят дерево совместно — кто-то добавил девичью фамилию,
кто-то фотографию, ... запретим — collaboration ломается»), эта
философия распространяется и на построение связей: один член семьи
часто знает структуру лучше других, но это не значит что он должен
получить explicit grant от каждого relative'а сначала.

`POST /v1/trees/:treeId/relations` + `DELETE .../:relationId` —
требуют только `requireTreeAccess(treeId)`, без gate per-person.

### Защита от identity-merge vandalism

Опасный case — «vandal link'ает Alice'ин self-person к чужой
бабушке как identity»:
* Это **identity merge**, не relation. Делается через
  `POST /v1/trees/:treeId/persons/:personId/link-identity` —
  отдельный endpoint, который Phase 3.2 gates'ит **двусторонним
  merge-consent**.
* Простой POST /relations пишет только parent/child/sibling/spouse
  edge между **двумя existing person rows**. Identity link'ом не
  становится; viewer не может через relation создать «Alice = моя
  чужая бабушка». Identity-merge surface — отдельный, защищён.

Так что dropping relation gates **не открывает identity-merge
vandalism vector**. Editorial-on-claimed остаётся защищённым через
`PATCH person`. Visibility — через `PATCH /v1/graph-persons/:id/
visibility` (owner-only-всегда). Sensitive contacts — через field
gate. Все три остаются enforced.

### Альтернатива (отвергнут)

Двойной edit-gate с per-person check на относительных endpoints:
* Pro: theoretically tighter.
* Con: ломает collaborative tree-building flow. Tree-creator не
  может расставить родственные связи между already-claimed members
  своей семьи без сбора N grants. UX-катастрофа.

### Что остаётся в Phase 3.2 enforcement (для ясности)

* `PATCH /v1/trees/:treeId/persons/:personId` — claimed = owner/grant.
* `DELETE /v1/trees/:treeId/persons/:personId` — soft-delete scope.
* `POST/PATCH/DELETE /v1/trees/:treeId/persons/:personId/media` —
  edit scope.
* `POST /v1/trees/:treeId/persons/:personId/link-identity` —
  двусторонний merge-consent.
* `PUT /v1/trees/:treeId/persons/:personId/attributes` — edit scope
  + sensitive (contacts) owner-only-всегда.
* `PATCH /v1/graph-persons/:id/visibility` — owner-only-всегда.
* Cross-tree READ paths — visibility filter.

**Принято**: Claude (implementation), документирую для review
Артёмом. Это conservative loosening от первоначального proposal'а
— surface потому что это narrowing of enforcement, не expansion.

### Caveat для будущей фазы (Артём 2026-05-10 после approve)

DECISION 2 верна для **current-scope**: relations в Phase 3.1
branch-scoped через `legacyRelationIds`. Каждый legacy relation
живёт внутри одного `tree`/`branch`, и tree-creator имеет
структурную authority внутри своего branch'а — collaborative,
но не propagating across branches.

Если в будущей фазе `graphRelations` станут **truly cross-branch
propagating** (Артём рисует ребро в своей ветке → Дарья видит
его в своей), модель «односторонняя tree-authority» может
потребовать пересмотра — возможно через **conflict log
per-relation** аналогичный Phase 1.3 для canonical fields.
Сценарий: Артём создаёт relation `мама spouse Иван`, Дарья
утверждает что `мама spouse Пётр` — нужен flow «edit-time
divergence» и user-resolution.

**Re-evaluate в Phase 6** (где branch sharing proectируется).
До тех пор — current-scope tree-authority валидна, потому что
relations не cross-branch propagate.

---
