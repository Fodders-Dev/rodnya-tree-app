# Shared Tree Proposal — Federated Семьи Architecture

> **Status**: design proposal, brainstorm-captured 2026-05-22. Awaits
> Артёмов confirm перед Phase B implementation. NOT shipped, NOT
> coded. Supersedes connected-per-user-trees mental model — preserves
> infrastructure (graphPersons/personIdentities/edit-grants) but
> repackages presentation за explicit «семья» group entity.

---

## 1. Context

### 1.1 Current state

Phase 3 (shipped 2026-05-11 commit `cb67b0b`) поставила архитектуру
«**connected per-user trees**»: каждый юзер имеет своё дерево с
собой как корнем, cross-tree связи через `personIdentities`. Phase 4
(`028d1d2`) добавила extended-network BFS view. Phase 6 (`414b218`)
поставила onboarding wizard + kinship-check «мы родственники?».
Phase 6.5 (`662b0aa`) добавил revocation.

Технически это работает. Production state:
* **70 users** на connected-per-user-trees
* **15 trees** total
* **351 graphPersons** in graph layer
* **75 personIdentities** linking persons across trees

См. [DECISIONS.md 2026-05-09 «фундаментальное направление»][1] для
исходных trade-offs которые привели к этой архитектуре.

[1]: ./DECISIONS.md#2026-05-09-фундаментальное-направление

### 1.2 Brainstorm-captured real-user evidence

Артём поделился деревом с мамой. Через несколько дней feedback
получился такой:

> **Мама** (verbatim): «Куда тут жмать? Что делать дальше? Что
> можно делать, что нельзя? Как все не сломать?»

Мама когда открыла «дерево» в app увидела свой пустой self-tree
(автоматически созданный при registration). Потом каким-то
unknown action случайно попала в Артёма tree (через extended
network view либо через notification). Не understood что
произошло, не знала что делать.

**Степа** (брат Артёма): после initial confusion больше не
залезал в дерево. Silent quit — самый dangerous user feedback
signal.

**Артём** (verbatim observations):
> «никто пока не понимает как коллективно пользоваться деревом»
>
> «хотелось бы просматривать деревья родственников, но на своем
> добавлять лишь избранных»
>
> «не смешивать прям всех людей дерева (папиных и маминых
> родственников, родственников партнеров)»
>
> «посмотреть родственников девушки, зятя, но не чтобы им мои
> фотографии показывались»

Pattern: **mental model юзеров не совпадает с current architecture**.
Юзеры ожидают:
* Один shared canvas, где близкая семья collaborate
* Возможность peek в чужие семьи без двусторонней shareности
* Селективный pull людей из чужой семьи в свою

Не получают:
* «Связанные personal trees» — слишком granular, требует понимания
  identity-linking
* «Делиться» = «открыть свой tree гостю» — а не «работать вместе
  в одном пространстве»

### 1.3 Три interaction modes от Артёма

Из brainstorm Артём сформулировал 3 fundamental modes которые
архитектура должна поддерживать:

1. **Семейная канва** (collaborative editing внутри одной семьи)
   * All members add relatives, photos, stories
   * All see all (within семья boundary)
   * Personal hide filter если что-то лично не интересно
   * Owner = family elder либо первый создатель (TBD design call)

2. **Browse other семьи** (read-only)
   * User opens чужую семью tree (если invited как viewer)
   * Sees их relatives + history
   * НЕ автоматически добавляет в свою канву
   * НЕ показывает свои photos в обмен

3. **Pull selectively** (copy person к моей канве)
   * User видит интересного person в чужой семье
   * Tap «добавить в мою семью» → copy person + relationships в
     моей канве с identity link
   * **Twin person concept**: один человек = две copies, linked

---

## 2. Problem statement

### 2.1 Почему current model не matches user mental model

| Mental model | Current architecture |
|---|---|
| «У нас общее семейное дерево» | У каждого своё с собой в центре |
| «Я добавляю — все видят» | Я добавляю только в свой tree |
| «Мама видит то же что я» | Мама видит свой пустой self-tree |
| «Можно скрыть не интересного» | Нет soft-hide, только hard-delete |
| «У меня одна семья» | У меня 1 tree, у мамы 1, у Степы 1 — три tree обзора |
| «Семья жены — отдельная вещь» | Architecture не различает мою семью vs семью жены |

Connected-per-user-trees правильно решает inversed scenario: «**у
каждого юзера своё уникальное дерево, иногда связи между**». Это
genealogist's use case (FamilySearch users). НЕ matches casual
family-network use case (Telegram/VK users).

### 2.2 Specific failing journeys

**Journey: «Мама открывает app первый раз»**

Current:
1. Мама регистрируется по invitation link
2. App открывает её personal self-tree (pустой кроме self)
3. Мама недоумевает: «А где Артёмово дерево?»
4. Не находит — confused, либо случайно навигирует через extended
   network view (но это discoverable только если знаешь как)
5. Если попадает в Артёмова tree — это его view, не shared
   collaboration

Should be:
1. Мама регистрируется по invitation
2. App открывает **семью Ивановых** (либо как они называются)
3. Видит дерево которое Артём начал, всех уже добавленных
4. Welcome overlay: «Артём пригласил тебя в семью. Можешь
   добавлять родственников, фото, истории. Не бойся сломать —
   всё откатывается»
5. Single-clear-action путь forward

**Journey: «Артём хочет посмотреть семью девушки»**

Current:
* Если у девушки есть аккаунт + она его invited — он видит её
  tree (через extended view либо через personIdentity links)
* Но invitation двусторонняя — она тоже получает access к его
  tree
* Photos/stories видны взаимно (нет granular control)

Should be:
* Девушка sends Артёма «view» invitation к её семье
* Артём opens — sees её родственников read-only
* Девушка НЕ автоматически видит его tree
* Артём может selectively pull person (дядя Коля) в свою семью
* Photos девушки остаются в её семье, не leak

### 2.3 Multi-family fundamental

Артём explicitly:
> «не смешивать прям всех людей дерева (папиных и маминых
> родственников, родственников партнеров)»

Это значит **один user = N семей одновременно**, не одно общее
дерево. Типичный case:
* «Семья Ивановых» — Артёма родители + sibs + grandparents
* «Семья Петровых» — жены семья
* «Семья друзей семьи» — друзья родителей которые «как родные»
* «Профессиональная семья» — coworkers/mentors (edge case)

Current architecture может симулировать через identityLinks
между deeds разных юзеров, но это invisible на UI level — у
Артёма всё smeared в один Big Family tree через extended network.

### 2.4 Privacy nuance

Артём (verbatim): «посмотреть родственников девушки, зятя, но не
чтобы им мои фотографии показывались».

Текущая privacy модель — per-tree visibility toggle (Phase 3.4).
Это работает для «hide weakly» но не для «show me yours, don't
show them mine asymmetrically». Federated семьи делает это
boundary natural: семья = privacy boundary. Photos в семье X
видны только members семьи X.

---

## 3. Proposed architecture: Federated Семьи

### 3.1 Core entity: Семья

**Семья** — explicit group entity. Single noun, lowercase в JSON,
Russian в UI:

```
семья {
  id: string,
  name: string,        // «Семья Ивановых»
  ownerId: string,
  createdAt: timestamp,
  members: [
    { userId, role: 'owner' | 'editor' | 'viewer', joinedAt }
  ],
  tree: <shared canvas — persons + relations>,
}
```

**Один tree per семья**. Все members editing видят same canvas
(modulo personal hide filters).

**User может быть в multiple семей** — fundamental design feature
Day 1. Top-level navigation = семья switcher.

### 3.2 Membership model

**Roles**:

| Role | Read tree | Edit persons/relations | Invite others | Promote/demote | Delete семья |
|---|---|---|---|---|---|
| **owner** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **editor** | ✅ | ✅ | only with owner-grant | ❌ | ❌ |
| **viewer** | ✅ | ❌ | ❌ | ❌ | ❌ |

**Invitation flow**:

1. Owner либо editor (с invite grant) → «Пригласить в семью»
2. Choose: phone number / email / invitation link
3. Default role for invitee — **viewer** (safer per Артёмов
   open question #1 hint — но flag это в open questions)
4. Invitee receives notification + опционально SMS/email
5. Invitee opens app → welcome banner «X пригласил тебя в семью
   Y. Принять?» → tap → join

**Role transitions**:
* Owner может promote editor → owner (multiple owners allowed)
* Owner либо editor (с grant) может promote viewer → editor
* Self-demote: editor → viewer допустимо. Owner → editor требует
  AT LEAST one other owner оставаться.
* Кick member: owner либо co-owner only.

**Leave семья**:
* Любой member может leave добровольно
* Если last owner leaves — семья orphaned (см. open question #4)
* Persons added by leaving member НЕ удаляются (preserve family
  history)

### 3.3 Tree within семья

**Shared canvas** — все editors могут add/edit persons и relations.
Источник истины — single tree document per семья (либо normalized
schema, см. implementation).

**Personal hide filter** — per-user opaque flag «не показывать
person X в семье Y в моём view». Не мутирует canonical tree, не
видно другим members. Реализация — separate table
`сemya_member_hidden_persons`:
```
{ семьяId, userId, personId, hiddenAt }
```

UI affordance: long-press person → menu → «Скрыть у меня». Show
hidden count в settings: «Скрыто 3. Показать список → восстановить».

**Conflict resolution** when two editors edit one person:
* Last-write-wins per field (simplest, ship-able)
* Если опасно (e.g. имена + биография concurrently) — show diff
  prompt: «Мама редактирует одновременно. Применить твоё либо её?»
* Defer fancy CRDT — overkill для семейного app, не Google Docs

### 3.4 Cross-семья interactions

**Browse mode**:
* User в семье X получает invite-link от user в семье Y
* Tap link → opens семья Y в read-only view (не joining as member)
* Sees persons + relations + photos (если photos shared в семье Y)
* Cannot add, edit, comment
* Browse session = ephemeral, не creates persistent membership
* Optional: «Запросить полноправный доступ» button → escalates к
  invite

**Pull selectively mode**:
* User в browse mode видит интересного person в семье Y
* Tap person → «Добавить в мою семью» dialog → choose seven которое
  получит copy
* Backend creates new person в target семье + identity link к
  original
* Twin: person X1 (semья Y) и X2 (моя семья) — same identity, two
  representations
* If person X1 later updated в семье Y — X2 НЕ auto-updates (нет
  realtime sync), но shows badge «Из семьи Y — есть обновления.
  Применить?»

**Identity linkage**:
* Подходит существующий `personIdentities` infrastructure (Phase 3)
* Каждый twin = separate person row, identity link = explicit
  relationship row
* Prevents duplicate person across семей (e.g. дядя Коля который
  родственник в маминой семье + Артёма семье — один identity,
  два twins)

### 3.5 Privacy model

**Семья membership = privacy boundary**.

| Resource | Visibility |
|---|---|
| Person attributes (name, dates, photo) | Only members of семья where added |
| Person photos | Only members of semья where uploaded |
| Person stories | Same |
| Comments на person | Same |
| Relations | Visible if both endpoints visible |
| Identity link itself | Visible к both sides — signal «связаны», без data |

**Cross-family identity link не leaks data**. Если Артём pull'нул
дядю Колю из маминой семьи, и мама edits дядю Колю (новое фото),
photo НЕ автоматически появляется в Артёма семье. Артём sees
notification «Мама обновила дядю Колю в семье Ивановых. Применить
изменения к копии в твоей семье?» — explicit opt-in.

---

## 4. User journeys (mama-friendly design)

Mama = primary test persona. Every journey должен pass «может ли
мама это сделать без instructions» test.

### Journey 1: Мама invited к семье

Артёма action:
1. Settings → My семьи → «Семья Ивановых» → «Пригласить»
2. Choose contact: мама (либо phone +7…)
3. Choose role: editor (Артёма deliberately picks — он хочет чтобы
   мама добавляла)
4. App sends SMS «Артём пригласил тебя в семью Ивановых в app
   Rodnya. Скачай: <link>»

Мама action:
1. Получает SMS, кликает link → opens RuStore (либо app uже
   installed)
2. App opens → если first time, welcome screen «Артём пригласил
   тебя в семью Ивановых» → «Войти и принять» (single primary CTA)
3. Login (phone+SMS либо whatever auth flow)
4. App автоматически opens **семья Ивановых tree view**, NOT
   пустой self-tree
5. Welcome banner overlay сверху tree:
   > «Артём пригласил тебя в семью Ивановых.
   >
   > Здесь можно добавлять родственников, ставить фото, писать
   > истории. Все, кого добавишь — увидит Артём и другие члены
   > семьи.
   >
   > Не бойся сломать — каждое действие можно отменить.
   >
   > [Показать дерево] [Добавить родственника]»
6. Tap «Показать дерево» → banner dismisses, мама видит tree as
   Артём его построил. Можно tap persons чтобы прочитать
   bio/photos.

**Critical fix vs current**: app lands directly на shared семья
view, не на пустой self-tree. Removes «куда тут жмать» confusion.

### Journey 2: Мама adds дядю Колю

Мама action (editor mode):
1. Mama в семья Ивановых view, видит tree
2. Tap «Добавить родственника» (либо long-press на empty area)
3. Form:
   * Имя: «Николай»
   * Фамилия (optional): «Иванов»
   * Отношение к: dropdown — «брат Артёма», «брат меня», «дядя
     Артёма», etc. (relations relative к user либо к existing
     person — design call в open questions)
   * Дата рождения (optional)
   * Фото (optional)
4. Tap «Сохранить» → person появляется в shared canvas, animated
5. Toast: «Дядя Коля добавлен в семью. Артём увидит уведомление.»
6. **Undo button** в toast (10 sec window) — «Отменить» → person
   removed

Артёма action (notification arrives):
1. Push: «Мама добавила дядю Колю в семью Ивановых»
2. Tap push → opens person details
3. Если Артём не интересен в этом дяде Коле (например edge
   relative) → tap menu → «Скрыть у меня» → person hidden in
   Артёма view, мама все ещё видит

**Confidence builder**: mama's add was undoable + low-stakes.
Confidence builds через small successful actions.

### Journey 3: Артём starts new семья для жены

Артёма action:
1. Top-level семьи switcher → «+ Создать семью»
2. Form:
   * Name: «Семья Петровых» (жены фамилия)
   * Initial member: «Артём» (auto-add как owner)
   * Description (optional): «Семья жены»
3. Create → empty tree с Артёмом в центре (NB: tree starts с
   creator, но это можно изменить — Артём может тут же добавить
   жену как root либо себя remove если он не «relative»
   в семье жены)
4. Артём adds жену → invites her: phone, default role editor
5. Жена joins → они collaborate в семье Петровых canvas
6. Жена adds свою sister, тёщу, тестя — все появляются в shared
   tree

Артём опытен с UI, ему не нужны wizards. Power-user path:
быстро.

**Top-level switcher**: AppBar header → tap семьи name → dropdown:
* «Семья Ивановых» ✓ (current)
* «Семья Петровых»
* «+ Создать семью»

Tap switches context, tree view rebuilds.

### Journey 4: Артём browse'ит семью девушки

Девушка (не Артёма жена, это пример браузинга friend's family)
action:
1. В её семья «Семья Сидоровых» → settings → «Открыть для
   просмотра» → generate link
2. Link permission level: «browse only» (не invite, не join)
3. Link expires 7 дней (либо настраивается)
4. Sends Артёма link через chat / SMS / whatever

Артёма action:
1. Receives link → opens app → app prompts «Хочешь посмотреть
   семью Сидоровых? Они дали тебе доступ только просмотр.»
2. Tap «Посмотреть» → opens их tree в **read-only view**
   * Persons clickable но show «read-only» badge
   * No add buttons
   * No edit menus
   * Subtle visual indicator (border либо background tint) что
     это чужая семья
3. Артём scrolls tree, видит дядю Колю который ему интересен
4. Tap дядю Колю → person sheet → «Добавить в мою семью» button
5. Tap → modal: «В какую семью добавить дядю Колю?»
   * «Семья Ивановых»
   * «Семья Петровых»
6. Артём choses «Семья Ивановых» → person + identity link
   created. Toast: «Дядя Коля скопирован в семью Ивановых.
   Дальше можешь редактировать у себя — он останется связан
   с оригиналом в семье Сидоровых.»
7. Девушка's семья НЕ изменилась
8. Девушка НЕ автоматически видит Артёмовы семьи (browse был
   one-way)

**Photo privacy preserved**: Артёма photos в семье Ивановых не
shared в семью Сидоровых. Devушки photos в семье Сидоровых не
shared в Ивановых даже после pull (только базовые attributes).

---

## 5. Migration plan

### 5.1 Existing data

| Resource | Count |
|---|---|
| Users on connected per-user trees | 70 |
| Trees (`db.trees`) | 15 |
| `graphPersons` | 351 |
| `personIdentities` | 75 |

Plus existing supporting tables (`graphRelations`, `branches`,
`graphPersonEditGrants`, etc.) per Phase 3.1 schema.

### 5.2 Migration approach

**Default — preserve mode**:
* Each existing user → один автоматически созданный «Моя семья» group
* User = owner
* Tree = существующий user's tree (members = [user])
* No data loss, no behavior change for solo users
* Users continue editing своё дерево как раньше

**Identity-link consolidation**:
* Existing `personIdentities` (75 entries) become twin relationships
  across newly-created семей
* Если user A's person X linked к user B's person X' — оставляем
  identity link, два persons продолжают в их respective семьях

**Opt-in upgrade flow («Объединить семьи»)**:
* После migration, app shows banner для users у кого есть
  существующие person identity links: «У вас есть общие
  родственники с N людьми. Создать общую семью?»
* Tap → wizard: choose users + name семьи → backend:
  - Creates new семья
  - Asks all chosen users to confirm (push + notification)
  - On unanimous accept — merges their respective subtree's persons
    into shared семья
  - Existing per-user trees become «My private branch» (still
    accessible, но primary семья = новая shared)
* НЕ автоматически объединяем — explicit consent от каждого
  member required (privacy)

**Multi-stage migration с verification**:
* Stage 1 (week 4): backend schema migration — add `семьи` table
  + membership table. NO data migration yet.
* Stage 2 (week 4): dry-run script — для каждого user generate
  what their default «Моя семья» would look like. Output JSON
  for verification. Manual sanity check на test data subset.
* Stage 3 (week 4): production migration — для каждого user
  create «Моя семья», populate from existing tree. Identity
  links preserved.
* Stage 4 (week 4): verification queries — sum check
  (count persons before = count persons after), no orphaned
  graphPersons, all personIdentities still resolve, etc.
* Stage 5 (week 5+): frontend deployed → users see new UI с
  свой «Моя семья» как default seed. No behavior break.

### 5.3 Backwards compat

**Dual-codebase период (~3 months)**:
* Backend supports BOTH connected-trees endpoints (`/v1/trees/...`)
  AND new семьи endpoints (`/v1/semyi/...`)
* Old mobile app versions (1.0.2 etc) continue using
  connected-trees endpoints
* New app versions use семьи endpoints
* Backend dual-write: when person added через семья endpoint,
  also write к compatible tree document so old clients see it
* Backend dual-read: connected-trees endpoint reads either source

**Sunset connected-trees endpoints**:
* After ~3 months observation, when 95%+ users on new app version
* Remove old endpoints в single backend release
* App store force-update minimum version

**Feature flag**:
* Global env var `RODNYA_FEDERATED_SEMYI_ENABLED=true/false`
* Backend respects flag — if false, dual-write disabled, only
  connected-trees endpoints respond
* Allows emergency rollback during early rollout

---

## 6. Implementation phases (8 weeks)

**Realistic estimate** — это full architecture rewrite, not полировка.

### Week 1: Investigation + design refinement

* Read backend `store.js` (~2200 LOC) полностью — map all persons /
  relations / trees code paths
* Read all `backend/src/routes/*.js` calling tree mutations
* Plan identity layer integration — какие existing tables remain,
  какие superseded
* Backend `семьи` entity schema draft (SQL либо JSON-doc schema
  depending on current persistence choice)
* Migration dry-run script — produces report «N users, M семей
  будут созданы, K identity-links preserved»
* Document edge cases (orphan persons, dangling relations, etc.)
* **Output**: Week 1 design memo + migration script (not yet run)

### Week 2-3: Backend rewrite (~50% rewrite)

* `семья` entity CRUD endpoints
  * POST `/v1/semyi` — create
  * GET `/v1/semyi/:id` — read with members + tree
  * PATCH `/v1/semyi/:id` — name / metadata
  * DELETE `/v1/semyi/:id` — owner-only, cascade либо orphan (open
    question)
* Membership endpoints
  * POST `/v1/semyi/:id/members` — invite/add
  * PATCH `/v1/semyi/:id/members/:userId` — role change
  * DELETE `/v1/semyi/:id/members/:userId` — kick либо leave
* Person/relation endpoints scoped к семье
  * Existing `/v1/trees/:id/persons` patterns adapted к
    `/v1/semyi/:id/persons`
  * Permission gates based on member role
* Browse endpoint — `/v1/semyi/:id/browse?token=...` (ephemeral
  token-based access)
* Pull-selectively endpoint — `/v1/semyi/:targetId/pull` body
  `{sourceSemyaId, personId}` → creates twin + identity link
* Personal hide endpoint — `/v1/semyi/:id/hidden-persons`
  POST/DELETE
* Backend tests:
  * ~50% rewrite — existing tree mutation tests adapt к семья
    scope
  * New tests for membership permissions
  * New tests for browse/pull edge cases
  * Migration script integration test

### Week 4: Migration tooling

* Migration script (Node.js либо SQL depending on persistence)
  * Idempotent — повторный run не дублирует данные
  * Dry-run mode (prints what would change, doesn't write)
  * Stage-by-stage option (--stage=schema, --stage=data,
    --stage=verify)
* Production runbook
  * Pre-migration backup (already standard — `rodnya-backup.service`)
  * Migration order: schema first, then data, then verify, then
    enable feature flag
  * Rollback procedure (restore from backup + flag off)
* Verification queries
  * `count(persons in trees) == count(persons in semyi)`
  * `count(personIdentities) == count(семейные twin relationships)`
  * No orphaned graphPersons (every graphPerson has owner семья)
  * No dangling relations (both endpoints resolve)

### Week 5-6: Frontend rewrite

* **Семья switcher UI** — top-level navigation
  * AppBar header → tap семья name → dropdown
  * «+ Создать семью» entry
  * Switch tree context на selection
* **Shared tree view с personal hide**
  * Same interactive tree widget как сейчас (preserve gesture
    handling, layouts)
  * Adapt data source — load from семья endpoint, not tree
  * Long-press person → «Скрыть у меня» menu item
  * Hidden persons not rendered, но badge «3 скрыто» в settings
* **Pull person UI**
  * In browse mode — person sheet has «Добавить в мою семью»
    button
  * Modal с семьи picker
  * Twin badge в shared semya view (small icon: «Из семьи Y»)
* **Browse other семья view**
  * Read-only variant of tree view (different visual treatment)
  * Browse link handler — deep link routing
  * Ephemeral session indicator («Просмотр семьи Сидоровых.
    Истекает через 7 дней.»)
* **Семья creation wizard**
  * Step 1: name
  * Step 2: invite initial members (optional, skip allowed)
  * Step 3: tree seeding — «начать с себя» либо «копировать
    из существующего»

### Week 7: Mama-friendly onboarding

* **Invitation landing flow**
  * Deep link from SMS → app opens на acceptance screen, не на
    generic home
  * Auto-fill invitation context («Артём приглашает тебя в семью
    Ивановых»)
  * Single-CTA design
* **Tutorial overlays**
  * First-time семья open — coach-mark tour (3-4 hotspots:
    «Это твоё дерево, тут добавляй, тут переключайся»)
  * Dismissible, won't show again
* **Undo для actions**
  * Add person → 10s undo toast
  * Edit person → undo via revision history (separate spec)
  * Hide person → restore из hidden list
* **Draft mode**
  * Persons могут быть saved as «черновик» — visible только
    автору пока не «Опубликовано»
  * Reduces fear «сразу всем покажется кривое»
* **Confidence indicators**
  * «Не бойся сломать — всё откатывается» banner на first edit
  * Empty state copy на семья view (если new семья пустая):
    «Это твоя семья. Тут будут все твои родственники. Начни
    с добавления родителей.»

### Week 8: Testing + staged rollout

* **Dev cohort testing (мама + Степа + immediate family)**
  * Mama and Степа install dev build
  * Run through journeys 1-4 без instructions
  * Capture friction (video record screen, ask «что ты сейчас
    хочешь сделать?»)
  * Iterate copy/UX based on findings
* **Production rollout staged**
  * 10% rollout via feature flag (random userId hash)
  * Observation 3 days (crash rate, key metric: time to first
    person added by invited user)
  * If clean → 50% rollout
  * If clean for 3 days → 100% rollout
  * If issues → flag off, rollback feature
* **Sunset old endpoints** (separate ship после observation week)

---

## 7. Risk assessment

| Risk | Severity | Mitigation |
|---|---|---|
| **Data migration corruption** | 🔴 HIGH | Pre-migration backup mandatory (existing runbook). Dry-run + verification queries. Staged migration. Rollback procedure tested before run. |
| **User confusion during transition** | 🟠 MEDIUM | Опытные users могут resist «зачем меняли». Mitigation: explainer banner first time after upgrade, «What's new» modal, in-app help. Power-user opt-out — preserve «classic view» если возможно (но adds maintenance burden). |
| **Backwards compat complexity** | 🟠 MEDIUM | Dual-codebase 3 months. Each endpoint двойная implementation. Risk: bug в одной branch не reflected в другой → desync between old + new app users. Mitigation: comprehensive integration tests covering both endpoints + reconciliation queries running nightly. |
| **Mobile app rollout lag** | 🟡 LOW | iOS app review may delay (~1-2 weeks). Android via RuStore faster. Mitigation: ship backend feature-flagged off → enable when both stores have updated app. Existing users on old app continue via connected-trees compat. |
| **Scope creep** | 🔴 HIGH | Architecture rewrites tempt feature additions («раз уж переписываем, давайте добавим X»). Mitigation: explicit «out of scope» list (см. §8). Weekly progress checkpoints. Если new feature surface → write follow-up ticket, не add к Phase B. |
| **Performance regression** | 🟡 LOW | Sharded canvas per семья может быть faster (smaller per-семья data sets) чем current cross-tree extended network views. Test с realistic data sizes (100 persons per семья × 5 семей per user). |
| **Multi-семья UI complexity** | 🟠 MEDIUM | Switcher between семьи adds cognitive load. Risk: users confuse «which семья I'm in» → edit wrong canvas. Mitigation: prominent семья name in app bar, color-code per семья, confirmation prompt on first action в новой семье. |
| **Browse mode privacy bugs** | 🟠 MEDIUM | Critical: photo leak between семьи would be reputation-destroying. Mitigation: comprehensive permission tests, privacy review by Артёма pre-rollout, automated regression test «browse mode cannot access edit endpoints». |
| **Identity link conflict** | 🟡 LOW | Two семьи add «дядя Коля» с разной biography — current `personIdentities` already handles. New: explicit «merge» UX когда browse mode user pulls already-twin person. |

---

## 8. Out of scope (deferred к after Phase B)

Запрещено add'ить в Phase B scope (сохраняй для follow-up):

* **Group chat внутри семьи** — use existing chat system, можно
  add семья-context channel в Phase B+1
* **Audio/video calls в семья context** — use existing call system,
  семья membership = call group в future
* **Notification preferences per семья** — separate config feature,
  user-settings level (e.g. «мутить notifications от семьи Y»)
* **Public семейный tree** — privacy nightmare, не делаем. Sharing
  remains explicit per-семья.
* **Federated sync across instances** — single-instance backend,
  не делаем self-hosted/federation in current scope
* **AI-suggested family additions** — separate feature, can use
  existing identity-suggestion infrastructure later
* **Семейный chat history sync** — chats remain separate from
  семья entity для now, может integrate в Phase B+2
* **Premium семья tiers** — monetization questions deferred
* **Семейные events/photos timeline** — feature creep, отдельный
  spec потом
* **Family group VKontakte integration** — privacy + scope creep,
  no
* **Семья wiki/notes** — separate feature, не connector к tree

---

## 9. Open questions для Артёма pre-implementation

Решить ДО Week 1 implementation start:

### Q1: Default role новых invitees — viewer (safer) либо editor (collaborative)?

**Trade-off**:
* `viewer` default — privacy-conservative, prevents accidental
  edits by curious invitee. Но adds friction — owner должен
  promote после accept, два steps.
* `editor` default — collaborative-first, matches Telegram «join
  group, you can chat». Risk — invitee edits в первый minute
  до того как поняли context, могут add дубликаты.

**Recommendation**: viewer default, но invitation UI gives owner
explicit option «Пригласить как редактор сразу». Default safer,
explicit power available.

### Q2: Семья name editable later либо immutable after create?

**Trade-off**:
* Editable — natural (people change family names, add detail).
  Risk — owner renames, members confused.
* Immutable — predictable identity. Но stuck с typo «Семя
  Иванвоых» если miss-typed.

**Recommendation**: editable by owner only, notify all members
on rename.

### Q3: Can user быть в семье without being relative в её tree?

E.g. family friend who maintains tree для elderly relative who
can't use app. Либо professional genealogist.

**Trade-off**:
* Yes — flexibility, many real cases.
* No — simpler model, «семья = ты + твои родственники».

**Recommendation**: yes. Membership entity separate от tree
persons. User может быть owner of семья где он не appears в tree
at all. Edge но valid use case.

### Q4: Семья deletion — cascade либо orphan persons?

When owner deletes семья:
* **Cascade**: all persons + relations + photos deleted. Clean.
  Destructive for members.
* **Orphan**: persons remain в db, identity-links preserve.
  Members who pulled persons retain copies. Original семья
  disappears.

**Recommendation**: orphan. Add confirmation dialog: «Семья
будет удалена. Скопированные в другие семьи родственники
останутся. Photos в этой семье удалятся. Подтверждаешь?».
Pre-deletion: notify all members «X собирается удалить семью.
Скачать copy?»

Cascade option может быть later для «полное удаление с историей»
если GDPR/right-to-be-forgotten requirement.

### Q5: Identity link conflict — мама adds дядю Колю c разной biography vs Артёма existing дядя Коля — auto-merge либо ask?

Конкретный сценарий:
* В семье Ивановых уже есть «дядя Коля Иванов, 1955 г.р., Москва»
* Мама pull'нула из семьи Кузнецовых «дядя Коля Иванов, 1955 г.р.,
  СПб» — same identity, different biography fields
* Что происходит?

**Options**:
* **Auto-merge LWW** (last-write-wins): newer field overwrites
  older. Risk — silent data loss.
* **Auto-merge multi-value**: both biographies preserved в person
  attributes (array of values). Risk — UI complexity (which
  to show?)
* **Ask user**: «Эти два человека похожи на одного. Объединить?
  [Применить твоё / Применить мамино / Хранить оба / Отменить]»
  Best UX но adds friction.

**Recommendation**: ask user. Conflict resolution dialog с
side-by-side diff. Default selected «keep оба» (safest).

### Q6: Tree root vs семья owner — relationship?

В current connected-trees model — каждый user = root своего tree.
В federated семьи — кто root? Семья owner? Семья creator?
Initial added person?

**Trade-off**:
* **Семья owner = root** — natural если owner создаёт семью с
  собой как первым person.
* **No fixed root** — tree рендерится с любого angle (zoom-к-person
  feature уже exists). Root = current focus, not identity.
* **Family elder = root** — semantic «семейное дерево с самого
  старого» convention. But auto-detect elderly tricky.

**Recommendation**: no fixed root. Tree layout = relationship
graph, не tree DAG с root. Current Phase 4 extended-network
rendering уже supports this. Семья owner — administrative role,
not tree-structural.

### Q7: Permission tier для «invite другие в семью»?

Mentioned в §3.2 — «editor с invite grant». Кто grants?

**Recommendation**: owner grants per-editor explicitly. Default
editor cannot invite. Owner toggles в member settings. Reduces
unconsented expansion of семья.

### Q8: Migration timing — push to всех existing users immediately либо staged opt-in?

**Trade-off**:
* Immediate — clean cut, no dual UX. Risk — confused existing
  users.
* Staged — users opt-in to upgrade («Перейти на новую модель?»).
  Risk — long-term dual codebase.

**Recommendation**: immediate (with sunset old endpoints over
3 months). Existing users get автоматически created «Моя семья»
matching their existing tree — seamless from data POV. UI change
explained via «What's new» modal.

---

## Принято

* **Brainstorm**: Артём + Claude, 2026-05-22
* **Source evidence**: real-user feedback (мама + Степа) captured
  verbatim
* **Architecture direction**: federated семьи, multi-family Day 1,
  Telegram-channel mental model
* **Phase A polish skipped** — rewrite straight (no Band-aid
  current model)
* **Timeline**: 8 weeks realistic, gated на Артёма confirm
* **Testers**: мама + Степа + immediate family primary cohort

**Doc status**: design proposal awaiting Артёмов sign-off перед
Week 1 implementation start. Открытые вопросы §9 решить first.

Когда Артём confirm — worker dispatched Week 1 task с этим doc
as primary reference.
