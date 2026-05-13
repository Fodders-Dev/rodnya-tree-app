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

## 2026-05-10: два независимых maxHops

**Контекст**: при wiring chunk 2 visibility toggle UI всплыл
вопрос — какое значение писать в russianHint для visibility
варианта `connected-via-blood-graph`. Initial draft указывал
«до 5 колен» (по аналогии с `branch.includeRules.maxHops`
default'ом), но backend visibility BFS использует 4.

В системе **СОЗНАТЕЛЬНО** используются **два разных
hop-limit'а** для разных целей:

* `FileStore._connectedVisibilityMaxHops = 4` — для
  `_userCanSeeGraphPerson` через blood-graph BFS. Контроль
  «кто может видеть карточку при visibility=connected-via-blood-graph».
  **Tight (4 поколения)**, потому что privacy: ширина видимости
  должна быть стабильно узкой, не configurable юзером.

* `branch.includeRules.maxHops` — default 5, slider 3..8 в
  Phase 3.4 wizard'е. Для `_buildBranchVisiblePersonIds` при
  `type === "blood-from-me" / "descendants-of" / "ancestors-of"`.
  Контроль «кто показывается в ветке». **Шире (5 default,
  до 8)**, потому что юзер сам выбирает scope своей ветки —
  это его UX choice, не privacy invariant.

### Не путать. Не unify'ить.

* Visibility — privacy gate, server-side, **не expose**'нуть в UI.
  Если когда-то понадобится ослабить (5 hops) — это change в
  privacy semantics, требует отдельного DECISION.
* Branch maxHops — UX dial. Юзер двигает slider 3..8.

Тесты cover'ят **обе границы отдельно**:
* `branch-include-rules.test.js` — visibility BFS на 4 hops.
* `migration-utils.test.js` + `owner-model-enforcement.test.js`
  — branch maxHops boundaries (3, 8, 0→1, 100→20, undefined→5).

### Зачем эта запись

Без неё через 3 месяца кто-то (включая Артёма / Claude)
увидит «4 vs 5» в коде и попробует «починить inconsistency»
— сломает либо privacy (если расширит visibility до 5), либо
UX (если сузит branch default'ом). Эта DECISION фиксирует:
inconsistency **deliberate**.

### russianHint строка

UI hint для visibility-варианта говорит «до 4 поколений»
(`lib/backend/models/visibility_choice.dart`). Branch wizard'у
slider показывает 3..8 (`lib/screens/family_tree/create_tree_screen.dart`).
Числа в UI **разные**, потому что концепции разные.

**Принято**: Артём (user) 2026-05-10 (после chunk 2 verify-2
review).

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

## 2026-05-10: Phase 3.4 — answers Q1-Q5 + backend addendum strategy + migration conservative

**Контекст**: после approve PHASE-3.4-UI-PROPOSAL.md (commit
`30d8415`). Артём ответил на 5 open questions + дал scope для
backend addendum.

### Q1: `/tree/view` URL → KEEP

Legacy invite-link'и в дикой природе ходят минимум 3 месяца.
Ломать URL = ломать конкретных юзеров. Согласовано с RFC
«Совместимость» (старый treeId API живёт 6 месяцев минимум).
URL-migration в `/branch/view` отложен до Phase 6 cleanup.

### Q2: `auth_screen` «семейное дерево» → KEEP

Marketing-poetry в onboarding hero — не nav-element. Замена
«семейная ветка» в маркетинговом контексте звучит как
тех-жаргон, обратная задача от цели «human-readable».

### Q3: `GET /v1/me/issued-grants` → ADD

Без него outgoing-таб edit-grants screen = N+1 round-trip'а:
плохо UX (slow load) и плохо ops (нагрузка). Симметрия с
`/v1/me/edit-grants` чистая. Добавляется в backend addendum
до Phase 3.4 UI commits.

### Q4: Branch edit с warning'ом → YES

`PATCH /v1/trees/:treeId` с расширенным `includeRules` shape.
Warning-формулировка: «Некоторые родственники могут исчезнуть
из ветки или появиться» + **preview affected count** перед
apply. Юзеры делают мисклики при создании ветки; force-recreate
= bad UX. Preview endpoint — `GET /v1/trees/:treeId/include-rules-preview`
с `?type=...&maxHops=...&anchorPersonId=...` query, возвращает
counts (added / removed / total) для UX warning.

### Q5: Per-row + header conflict badge → BOTH с fallback note

Per-row = «где конкретно», header = «сколько в этой ветке».
Оба полезны для разных моментов user attention.

**Fallback note для post-deploy**: после первой недели в pre-prod
подавать метрику «conflict count per branch». Если медиана > 5,
**отключаем per-row**, оставляем header-only — слишком noisy.
Добавить в operational checklist.

### Backend addendum strategy

**SEPARATE pre-3.4 backend commit**, не часть UI.

Reasons:
* Phase 3.2 был 100% backend, Phase 3.4 должен быть 100% UI с
  минимальным backend touch. Чистая ментальная модель «фазы по
  слоям, не по фичам».
* Backend deployed first → UI build тестирует против реального
  endpoint'а, не stub'а.
* Atomic rollback — если UI commit вызывает проблему, backend
  не нужно откатывать.
* ~20 строк = low risk, отдельный commit не replace blocker'ом.

Commit name: `feat(phase-3.4-prep): tree includeRules in POST +
issued-grants endpoint`. Сразу после него — Phase 3.4 UI commits.

Что делает backend addendum:
* `POST /v1/trees` принимает `includeRules` в payload (validate
  type ∈ {manual, blood-from-me, descendants-of, ancestors-of},
  maxHops 1..20, anchorPersonId optional).
* `PATCH /v1/trees/:treeId/include-rules` — owner edit с
  расширенным includeRules. Owner-only (tree.creatorId).
* `GET /v1/trees/:treeId/include-rules-preview` — query params,
  возвращает `{addedCount, removedCount, totalAfterCount,
  totalBeforeCount}` без mutate'а. Для Q4 warning UX.
* `GET /v1/me/issued-grants` — список grants выписанных viewer'ом
  (group by graphPersonId), включая revoked-since-30d (TTL
  совпадает с Q3).

### Migration strings → CONSERVATIVE

Per Артёмовому правилу «если в каком-то месте сомневаешься —
оставь "дерево"»:

**Rename** только в:
* Navigation/wizard/actions UI: «Создать ветку», «Переключить на
  ветку», «Ветка X из Y».
* Settings → «Мои ветки» (вместо «Мои деревья»).
* Sheet bottom-action «Создать ветку».
* Tree-edit screen → «Параметры ветки».

**KEEP**:
* URL'ы (`/tree/view`).
* `auth_screen` poetic context («семейное дерево» в onboarding hero).
* Kind toggle («Семья / Круг»).
* Legacy переменные в коде (`treeId`, `TreeProvider`) — не rename,
  чтобы не плодить мега-diff'ы.

**Aggressive pass отложен** — потом проще добавить migration в
один коммит, чем откатывать misnamed strings когда юзер пожалуется.

**Принято**: Артём (user) 2026-05-10.

---

## 2026-05-10 (chunk 3 follow-ups) — TODO list

Зафиксированы по итогам chunk 3 review (edit-grants screen).
Не блокеры для самого chunk 3, но обязаны быть закрыты до
финального cut-off Phase 3.4.

### TODO 1 — backend: hydrate grantor preview в /v1/me/edit-grants

Сейчас `/v1/me/edit-grants` возвращает grants с
`graphPerson` preview, но БЕЗ `grantor` preview. Симметрия с
`/v1/me/issued-grants` нарушена — там grantee hydrate'ится, а
здесь grantor нет. Incoming-таб экрана «Доступы» из-за этого
показывает «вы можете редактировать карточку X» без context'а
«потому что Y разрешил».

**Объём**: ~30 строк в `backend/src/routes/graph-person-routes.js`
(`/v1/me/edit-grants` handler) — собрать `Set<grantorUserId>`,
`store.findUserById(...)` для каждого, добавить `grantor` поле в
response payload. Frontend часть готова: `EditGrant.fromJson`
уже парсит `grantor` field (см. lib/backend/models/edit_grant.dart
строки 119–121, 142–145), `_IncomingCard` нужно расширить чтобы
показать «X разрешил» row выше chips'ов.

**Когда**: до выпуска Phase 3.4. Не блокер для chunk 3 commit'а,
но «functional → обоснованный» — UX gap.

**Тесты**: расширить `backend/test/owner-model-enforcement.test.js`
секцию /v1/me/edit-grants чтобы проверить что grantor включён.

### TODO 2 — extract russian plural helpers

`_pluralDays` / `_pluralWeeks` / `_revokedAgoLabel` сейчас дублируются
в `lib/widgets/access_grants_outgoing_tab.dart` и
`lib/widgets/access_grants_incoming_tab.dart` (3 функции × 2 файла).

**Когда extract**: при следующем месте использования. Кандидаты:
* notifications screen (timestamp'ы «N минут назад»)
* history view / activity log (когда добавим audit trail для
  graphPerson edit'ов)
* comments timeline (Phase 4+)

**Куда**: `lib/utils/russian_plural.dart` (или `russian_dates.dart`
если набирается critical mass функций про даты).

**Аргумент против преждевременного extract**: chunk 3 уже
~1370 LOC новых widgets + tests, не размывать. Дублирование двух
файлов — приемлемая цена за tighter chunk diff. Третий call-site
делает extract естественным — копировать в третий раз начинает
явно болеть, и дисциплина вытаскивает helper.

**Принято**: Артём (user) 2026-05-10 (chunk 3 review).

---

## 2026-05-11 (chunk 4 review): ownership ≠ creator для privacy data

**Универсальный invariant**: для любых sensitive / private fields
gate должен быть на `userId == viewer` (актуальный owner), а не
`createdBy == viewer` (исторический создатель).

**Сценарий**: Алиса создаёт anonymous person'а для своего деда.
Дед потом регистрируется и claim'ит карточку — `userId` shift'ится
с null на `bob.id`, `createdBy` остаётся `alice.id`. После claim'а
Алиса теряет privacy access к дедовым contacts'ам. Это **deliberate**,
не bug — creator's role «инициатор записи», а не «вечный custodian».

**Применяется к**:
* Sensitive contacts (chunk 4) — phone/email/address gate'ятся
  на `_isViewerOwnPerson`, который checks `userId == currentUserId`.
* Visibility toggle (chunk 2) — `effectiveOwnerUserId =
  userId ?? createdBy` для anonymous case, но после claim — userId.
* Phase 3.6 hard-delete background job — actor должен быть
  актуальный owner, не creator.
* Phase 4+ notification-feed privacy filters — кому показывать
  «X обновил Y's профиль».

**Anonymous case (userId == null)**:
* Creator в роли owner для privacy data — это temporary state до
  момента claim'а. После claim — owner shifts. До тех пор —
  `createdBy` это и есть «текущий» owner на отсутствие userId'а.
* `effectiveOwnerUserId` formula (chunk 2 helper) уже отражает
  это правильно: `userId ?? createdBy`.

**Не-применяется к**:
* Tree-level structural data (relations, branches) — те остаются
  под `tree.creatorId` (DECISION 2 follow-up 2026-05-10).
* Audit trail (kто и когда menjal) — creator там остаётся
  навсегда как historical record, это не privacy data.

**Принято**: Артём (user) 2026-05-11 (chunk 4 review).

---

## 2026-05-11 (chunk 5 review) — TODO list

Зафиксированы по итогам chunk 5 review (conflict badges на не-canvas
screens). Не блокеры для chunk 5 commit'а, но обязаны быть
закрыты до Phase 4 cut-off.

### TODO 3 — cache invalidation strategy для conflict counts

**Где**: `lib/screens/relatives_screen.dart` (`_conflictCounts` +
`_treeConflictsCache`) — кэш не invalidate'ится автоматически
если юзер resolve'нул конфликт через sheet и вернулся на
relatives_screen. Sheet onChoice вызывает `_refreshConflictCounts`,
но **только когда sheet открыт из relatives_screen**. Если юзер
открыл sheet с relative_details (тот же widget, тот же
endpoint), вернулся на relatives_screen pull'ом back — там cache
stale.

**Симптом**: «5 карточек требуют внимания» banner, реально уже 4.
Confusing.

**Простой fix**: добавить refresh-on-resume на focus event
(`WidgetsBindingObserver.didChangeAppLifecycleState` либо
`RouteAware.didPopNext`). Альтернатива — global event bus
«conflictsChanged» что подписываются и canvas, и relative_details,
и relatives_screen.

**Когда**: Phase 4 либо когда первый юзер feedback'нет. Не
блокер для Phase 3.4 cut-off — pull-to-refresh пока работает.

### TODO 4 — performance audit при большом дереве

**Симптом**: у юзера 200+ persons, у 50 из них конфликты. На
mid-range Android (e.g. Redmi 9A class) build per-row badge x 50 +
`getIdentityConflictsForTree` fetch + JSON parse → возможно
заметные janks при scroll.

**Где будет хуже**: Phase 4 (extended-family network через identity
граф) — там дерево 500+ persons.

**Когда**: измерить на Phase 4 testing pass. Если slow:
* **Lazy badge fetch** — count'ы только для visible viewport
  (`ScrollController` + `RenderSliver` viewport check).
* **Skip render if count > threshold** — header banner показывает
  «50+ карточек», per-row badges suppressed.
* **Server-side aggregation** — `/v1/trees/:id/identity-conflict-counts`
  endpoint, который вернёт `Map<personId, count>` плоско, без
  full conflict bodies. Эконом ~10x payload, parse быстрее.

**Не блокер** для Phase 3.4 cut-off. Sub-100ms build на синтетике
50 badge'ей измерен (Material standard cost).

**Принято**: Артём (user) 2026-05-11 (chunk 5 review).

---

## 2026-05-12 — Phase 4 архитектурные answers

Закрыты review-revise циклом с Артёмом по итогам Phase 4 proposal
v1 (`docs/connected-trees-refactor/PHASE-4-PROPOSAL.md` baseline
commit `32a8f8d`). Принципы — для всех Phase 4 implementation
chunks; cross-reference'аются из proposal v2 §5/§6/§7.

### Q1.B — privacy fence respected

Phase 4 = **visualization layer** на том, что юзер уже может
видеть через `_connectedVisibilityMaxHops = 4`. Никакого
relaxation'а fence'а.

**Reasoning**: если Phase 4 relax'ает fence, мы получаем privacy
regression — viewer видит бабушек friends'ов которых не должен.
Расширенная сеть = красивая визуализация existing visibility, не
extension её scope'а. Fence остаётся фундаментальным privacy
invariant'ом из Phase 3.1.

### Q1.A — emergent property из Q1.B

Public-frontier walk **за fence** фундаментально невозможен.

**Сценарий**: node X с `visibility=public`, его родитель Y с
`visibility=connected-via-blood-graph`, viewer вне connected
set'а Y. Можно ли BFS-walk «прыгнуть X→Y» через public node X?

**Ответ**: нет. `Y.visibility` resolves **per-target-node**, не
per-path. Public node X не служит как «портал» к приватному Y —
fence режет render самого Y (или его sensitive fields)
независимо от того, через что walker к нему пришёл. Это
**emergent property** Q1.B, не отдельное решение.

### Q6.A — depth slider == privacy fence

Range **`2..4`**, default `4`. Точно совпадает с
`_connectedVisibilityMaxHops = 4` как hard cap.

**Reasoning**:
* Slider за пределы fence misleading — юзер тянет до 6/10,
  ничего нового не появляется, frustration.
* `min = 2` (не 1) — hop 1 = self + immediate (parents/kids/
  spouse) = 3-5 nodes; feels broken, не focused.
* `2 hops`: + grandparents + siblings + niblings (≈ 7-10 typical).
* `3 hops`: + great-grandparents + cousins.
* `4 hops`: full extended (default).

Расширение fence за 4 hops — Phase 5+ feature с consent flow,
не Phase 4.

### Q3.A — node tap для relation sheet

**Edge tap НЕ используется**. Sheet «как этот человек связан со
мной» открывается через tap на **node**.

**Reasoning**: edges на mobile микроскопические, попасть пальцем
сложно. Tap на node открывает sheet с identity + relation-to-me
(lazy compute via existing `/v1/trees/:id/relation-path`,
Phase 2). Edge tap технически интересен, UX-вред.

### Q4.A — нет «Попросить доступ» stub в Phase 4

Foreign node tap-sheet **не** включает «Попросить доступ»
button до Phase 5+.

**Reasoning**: lure без выполнения = ложное обещание UX. Юзер
тапает foreign node → sheet с owner identity row + «Написать»
button (chat existing flow) + «Открыть карточку» (read-only
person card). Real edit-request flow — Phase 5+ когда есть
real implementation на backend'е (notification ping owner'у +
inbox для request'а).

### Q5.A — client-side search filter ≤ 1000 persons

Search в extended view фильтрует **client-side по уже-fetched
slice'у**. Server-side search endpoint и пагинация — **Phase 5+**.

**Reasoning**: у тестовых users < 100 persons. Production случаев
slice > 1000 не будет в обозримом времени. Premature optimization
сейчас. Document'ируем limit в proposal'е, если real data покажет
slice > 1000 в realistic flow — Phase 4.1 addendum.

### Q7.A — chips horizontal scrollable

Filter chips для branches / generations — горизонтально
scrollable container (`SingleChildScrollView(scrollDirection:
Axis.horizontal)` либо `Wrap` с overflow). Standard Material
Design Filter Chips pattern.

**Reasoning**: dropdown для filters compact'нее, но скрывает
options. Chips более скан'абельны и tap-friendly на mobile.
Scrollable обходит cramping на narrow. Dropdown как fallback —
только если 5+ filters и clearly hierarchical (сейчас 3-4 filter
— chips OK).

### Q8.A — per-tree persist для mode toggle

View mode (`mine` / `extendedNetwork`) сохраняется **per-tree**
через SharedPreferences с key'ом `extended_mode_${treeId}`.
Default «Моё дерево» при отсутствии preference'а — opt-in явный.

**Reasoning**: у разных tree'ев (family vs friends vs round)
могут быть разные предпочтения. Friends-tree вряд ли нужен
extended (там мало identity-cross-link'ов); blood-tree —
наоборот, главное место использования. Global preference
теряет per-tree intent.

### Q8.B — URL shareability deferred

Phase 4 v1 не реализует shareable URL для extended slice
(`/tree/view/:treeId?mode=extended&depth=N`). **Phase 5+ если
понадобится**.

**Reasoning**: дополнительная surface — routing + permission
check на recipient'е (если recipient вне privacy fence —
fallback на default view + warning). Сценарий «look at my
tree this way» пока гипотетический, не блокирует Phase 4.

### Q8.C — narrow mobile layout test in implementation

AppBar segmented control «Моё / Все» (short labels, font
scaling). Layout testing откладывается до implementation chunk —
не reschedule заранее.

**Fallback**: если на 320dp выглядит cramped → icon-only
(`mode_outlined` / `network_check_outlined`) с tooltip'ами.
Decide on actual implementation, не блокер для proposal'а.

**Принято**: Артём (user) 2026-05-12 (Phase 4 proposal v1 review).

### Chunk 1 implementation decisions (2026-05-12, follow-up)

Принятые внутри chunk 1 implementation (по Артёмову «think about»
блоку в approve message'е, surfaced before coding):

**Sparse ownerMap (nice-to-have #1, IMPLEMENTED)**:
* Response payload содержит entries в `ownerMap` **только для
  foreign nodes** (owner !== viewer). Viewer-owned nodes — implicit,
  resolve через `slice.getOwnerInfo(id) == null` client-side.
* На 90%+ typical viewer'а экономит payload + memory.
* DTO helper `ExtendedNetworkSlice.isForeignNode(id)` + `getOwnerInfo(id)`
  делает sparse pattern API-clean для UI.

**Cache 60s TTL без invalidation (nice-to-have #2, IMPLEMENTED)**:
* In-memory Map в route closure scope; key = `${treeId}:${viewerId}:${maxHops}:${includeAnonymous}:${branchIds}`.
* 60s window после mutation acceptable: Phase 4 — view layer, **не**
  edit canvas. Edit чужих nodes — only через grants и через my-only
  view (relative_details), где cache не релевантен.
* GC: каждые 200+ entries старые expired удаляются. Простая
  protection от unbounded memory growth.
* Без invalidation hooks на mutation endpoints — invalidation
  через event bus / pub-sub был бы over-engineering для текущей
  storage layer (JSONB + lazy postgres-store).

**`branchIds` query param**:
* В chunk 1 — placeholder для cross-branch filtering. v1 ignored
  unless explicitly matches treeId (current schema mirror'ит trees
  1:1 на branches).
* Phase 4.1+: при наличии truly cross-branch graphPersons (e.g.
  юзер участвует в Машиной branch'е через grant) — этот param
  будет filter'ить по branch ID.

**Test coverage (nice-to-have #3, IMPLEMENTED)**:
* `backend/test/extended-network-endpoint.test.js` — 10 tests:
  auth (401 no token, 403 non-member, 200 member), maxHops clamp
  (1→2, 10→4, garbage→default), privacy isolation (stranger's
  tree persons not in slice), sparse ownerMap, cap behavior (cap=3
  fixture → capReached=true), cache 60s TTL functional.
* `test/extended_network_slice_test.dart` — 10 DTO tests: fromJson
  full payload, sparse helpers, defensive parsing, malformed
  entries, isAlive default, hopDistance coercion, nullable strings,
  round-trip, stats coercion.

**Принято**: Claude (chunk 1 implementation, surface'нуто к Артёмову
review в commit'е chunk 1).

### Chunk 3 visual design (2026-05-12, follow-up)

Reviewer Артём после chunk 2 push'а surface'ил визуальный design
chunk 3 в **per-element table** вместо v1 «colour tint + 18×18 badge
+ dashed edges» blanket. Каждое из 5 элементов — независимый
approval gate, чтобы «не подкидывать всё вместе» (комплект может
«протащиться» через одобрение). Полная developer-facing reference
в **PHASE-4-PROPOSAL.md §5.A**.

**Element 1 — Colour tint own vs foreign nodes**: **APPROVED**
(essential). My nodes — warm beige (`primaryContainer`, current
default); foreign — cool grey-blue (low saturation
`surfaceContainerLow`). Контраст ≥ 3:1, читаем без eye strain на
≥10 nodes distance. Это **signal, не шум**. Без него extended mode
бессмыслен.

**Element 2 — Edge color tint (cross-tree)**: **APPROVED as
replacement for dashed**. My-to-my edges — `primary` palette
(current). Cross-tree — `surfaceVariant` (muted). Solid lines both,
no dashed pattern. Дешевле рендер, лучше viewability на 1-2px
strokes. Замена dashed (см. dropped).

**Element 3 — Owner avatar badge**: **APPROVED as on-tap only,
NOT always-visible**. По умолчанию foreign node только с tint'ом,
без badge'а. Tap → foreign node sheet (chunk 4) рендерит owner
avatar full size. Reasoning: 50+ foreign nodes × 18×18 badge =
visual noise, на 320dp может overlapping с text.

**Element 4 — Conflict ⚠ badge**: **APPROVED (existing, no change)**.
Phase 3.4 chunk 5 уже реализовал. Продолжает работать для both my
и foreign nodes в chunk 3.

**Element 5 — Deleted state**: **APPROVED (existing, no change)**.
Existing UI остаётся; в practice deleted-state в extended mode не
появится (backend filter'ит `deletedAt != null`), но defensive
code path сохраняется.

**DROPPED** (chunk 3 visual review):
* **Dashed cross-tree edges** — replaced Element 2 edge color tint.
  Dashed на тонкой 1-2px line почти не виден; рендеринг dashed Path
  в Flutter Canvas дороже solid (extra path operations × per
  frame).
* **Always-visible owner badge на foreign nodes** — replaced
  Element 3 on-tap. Always-visible = noise на 50+ foreign nodes
  + risk overlap на narrow viewport.

**Chunk 3 implementation gates** (per Артёмов request, обязательны
перед coding):
1. **Perf baseline** на legacy mine view — synthetic fixture'ы
   100/500/1000 persons, first paint + scroll FPS. Если new
   render path regress'нёт legacy mine — halt chunk 3.
2. **Visual snapshot tests** — golden files per state (own / foreign
   tint / own+conflict / foreign+conflict / deleted).
3. **Feature-flag `useExtendedRenderPath`** — `false` daje legacy
   bit-identical path. Защита от regression во время review.
   Удаляется после chunk 4 либо +1 prod week.

**Принято**: Артём (user) 2026-05-12 (chunk 3 prep visual review).

---
