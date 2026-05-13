# Phase 6 proposal — onboarding wizard + «мы родственники?» BFS

**Дата**: 2026-05-13
**Source ветка**: `claude/serene-fjord-8b4d62` от `5fb1d3c` (Phase 4
observation, flag default `true`).
**Ссылки**:
* `tree_model_overhaul_rfc.md` — Phase 6 listed как «onboarding +
  social discovery».
* `PHASE-4-PROPOSAL.md` — extended-network surface, reused для
  «уже подтверждённые родственники» display после BFS consent.
* `DECISIONS.md` 2026-05-12 «privacy fence respected» (Q1.B) —
  applies к BFS results: target nodes filtered per-target через
  `_userCanSeeGraphPerson`.
* Existing backend pieces — see §3:
  - `/v1/graph/relation` (Phase 2) — shortest blood-path BFS.
  - `/v1/identity-claims/*` (Phase 1.2) — bilateral pending consent
    pattern.
  - `/v1/identity-discovery/search` — public identity lookup.

---

## 0. TL;DR + scope summary

### Что Phase 6 делает

Phase 6 — финальный chunk перед public launch readiness. Закрывает
**two critical funnel leaks** для new users:

1. **Onboarding wizard** — guided first-time experience: profile +
   minimum 2-3 first-relatives seed → land на /tree с уже-видимым
   деревом. Без wizard'а юзер открывает пустое дерево, не понимает
   что делать → exits within 30 seconds.

2. **«Мы родственники?» BFS** — viral discovery mechanism: юзер
   вводит handle/phone/email знакомого → backend computes shortest
   blood-path → bilateral consent → result visible обоим. Это
   distribution multiplier (user invites friend specifically для
   «check if we're related»).

### Scope summary

* New screen: `OnboardingWizardScreen` — 4-5 шагов linear flow с
  skip-ability на non-required steps.
* New screen либо surface: «Мы родственники?» discovery flow.
  Likely новый route `/discover/relatives` либо inline в
  `/find-relative` (existing).
* New backend endpoint(s) для BFS consent workflow (extends
  identity-claim pattern).
* Existing-user detection: skip wizard если `tree.persons.length >
  0`.

### DoD Phase 6

* New user (fresh signup → no tree) проходит wizard → ends с tree
  containing self + 2-3 родственников.
* Existing user (Артём, Степа): unchanged login flow, никакого
  wizard prompt.
* BFS «мы родственники?» entry point findable (≤ 2 taps от main
  navigation).
* BFS flow: search → request → bilateral consent → result display.
* Privacy: BFS surface'ит только nodes visible viewer'у per Phase
  3 fence; hidden nodes anonymized в chain (`?` placeholder).
* `flutter analyze` clean; widget tests + integration tests
  covering wizard linearity + BFS consent state machine.

---

## 1. Existing baseline — current new-user experience

### Current flow (без Phase 6)

1. New user signs up → `/profile/edit` (Phase 1 onboarding sheet
   exists — profile name + photo).
2. Lands на `/` (home feed) либо `/tree/view/<freshly-created tree>`.
3. Tree empty (no persons). User sees «Добавить родственника» FAB.
4. User abandons либо struggles через add-relative form.

**Funnel leaks**:
* Profile edit sheet **optional** — может skip и landed на empty tree.
* No guidance что добавить first. User не понимает: «я родственник
  кого? Мне ввести родителей? Себя?».
* No seed sample data. Empty canvas frustrates.
* Identity-graph value (= cross-tree linking) invisible без other users.

### Existing wizard pieces

* `lib/screens/profile_screen.dart` имеет «4-step bottom sheet
  (showProfileEditSheet)» (per Phase 3.4 comments) — это profile
  data wizard, не tree onboarding.
* `lib/screens/find_relative_screen.dart` — separate invite-by-
  email/username/profileCode screen. Не reusable для blood-path
  discovery, semantic mismatch.

### What breaks

* New user `/tree/view/<empty>` → no person cards → InteractiveFamilyTree
  shows empty state «Граф готов к просмотру» либо placeholder.
* Sensible default: «Добавьте себя first?» — но это **already**
  available action, just not guided.
* No seed: zero opportunity для Phase 4 extended-network demo'а на
  fresh account.

---

## 2. Per-feature wireframes

### 2.1 Onboarding wizard — экраны, последовательность, skip-ability, validation

**Linear 4-screen flow** (Q1 reasoning ниже):

```
┌─── Screen 1: Welcome ──────────────────────────────────────┐
│                                                            │
│                    [hero illustration]                     │
│                                                            │
│            Добро пожаловать в Родню                        │
│                                                            │
│    Соберите семейное дерево вместе с родственниками        │
│    Найдите дальних родных через цепочку знакомых           │
│                                                            │
│                       [Начать]                             │
│                                                            │
│         (no skip — value prop intro, ≤ 5 sec read)         │
└────────────────────────────────────────────────────────────┘

┌─── Screen 2: Profile completion ───────────────────────────┐
│                                                            │
│    Расскажите о себе                                       │
│    Это будет ваша карточка в дереве                        │
│                                                            │
│    [Avatar upload (optional)]                              │
│                                                            │
│    Имя        [_____________]  ← required                  │
│    Фамилия    [_____________]  ← required                  │
│    Дата рожд. [DD.MM.YYYY]    ← required (≥ 13 лет)        │
│    Пол        ○ муж ○ жен ○ не указывать                   │
│                                                            │
│    [Назад]                          [Далее →]              │
└────────────────────────────────────────────────────────────┘

┌─── Screen 3: First relatives (seed) ───────────────────────┐
│                                                            │
│    Добавьте 2-3 близких родственников                      │
│    Это поможет начать дерево и найти родню через них       │
│                                                            │
│    [Мама]       [_____________]  +photo  +DOB              │
│    [Папа]       [_____________]  +photo  +DOB              │
│    [Брат/Сестра] [____________]  +photo  +DOB (optional)   │
│                                                            │
│    + Добавить ещё одного                                   │
│                                                            │
│    Заполнено: 1/2 минимум                                  │
│                                                            │
│    [Назад]   [Пропустить]            [Далее →]             │
│                                                            │
│    (Пропустить available — Q2 reasoning ниже)              │
└────────────────────────────────────────────────────────────┘

┌─── Screen 4: Finish ───────────────────────────────────────┐
│                                                            │
│                  ✓ Дерево создано                          │
│                                                            │
│   Ваше дерево с 3 людьми. Теперь можно:                    │
│                                                            │
│   • Добавлять ещё родных                                   │
│   • Прикреплять фото к карточкам                           │
│   • Искать дальних родных                                  │
│                                                            │
│   [Подключите Telegram / VK для быстрого поиска родни?]    │
│   (optional, Phase 5 social pre-stub)                      │
│                                                            │
│                  [Открыть дерево]                          │
└────────────────────────────────────────────────────────────┘
```

**Linearity / step-back**:
* Screen 2 → 3 → 4 → linear. Each accepts `[Назад]` (no branching).
* Screen 1 → 2: no back (only forward through onboarding).
* `[Пропустить]` появляется только на screen 3 — first-relatives
  optional per Q2 reasoning.

**Validation**:
* Screen 2: name + дата рожд. required; gender optional default
  «не указывать»; avatar optional.
* Screen 3: minimum 0 (если skip), maximum 5 (UI cap для wizard;
  пользователь добавит больше позже).
* Per-relative validation: only name required, дата рожд. optional
  (родителей точно не помнит часто).

**Skip / abandon recovery (Q8)**:
* SharedPreferences keys: `onboarding_step_${userId}` = `'welcome'
  | 'profile' | 'relatives' | 'finish' | 'done'`.
* App launch (post-auth) checks: if `done` → tree view; if any
  other → resume в той же step screen.
* No mid-step partial save (form data lives в memory; abandon =
  re-enter form). Wizard короткий enough что re-enter trivial.

### 2.2 First-relatives seeding — detail

**Default суggestion** (screen 3):

| Slot | Required? | Pre-filled relation type |
|---|---|---|
| Slot 1 | Yes (если minimum пройдено) | Мама либо Папа (default Мама — статистически чаще known) |
| Slot 2 | Yes | The other parent (Папа если slot 1 = Мама) |
| Slot 3 | Optional | Брат / Сестра |
| + Add | Optional | Свободный выбор: parent / sibling / child / grandparent |

**Identity matching during wizard (Q9)**:
* После каждого add-relative — backend's `searchByCanonicalFields`
  may match existing graphPerson (e.g. виде «Иванов И. И., 1955»
  matches someone в чужом дереве).
* Wizard surface'ит match НЕ как «о, тебя кто-то знает» (privacy
  violation), а как **silent enrichment**: created person.identityId
  attaches к existing graphPerson (with appropriate gate). Юзер
  видит только «сохранено» — не «вы связаны с N других trees».
* Surface visibility только **после wizard'а** через Phase 4
  extended-network mode либо BFS feature (where consent flows
  apply).

### 2.3 Post-onboarding state

После tap «Открыть дерево» — land на `/tree/view/<freshly-created
tree id>`. State:

* Tree contains **self + 2-3 relatives** (если skip — only self).
* Mode = «Моё дерево» legacy.
* Extended mode toggle visible (Phase 4 live, flag=true) но slice
  initially `myCount == seed size` since нет cross-tree links yet.

**Onboarding tip overlay** (first 1-2 sessions):
* «Тапни на карточку — добавить родственника. Или ищи дальних
  родных через [иконка discovery] здесь.»
* Dismissible. State в SharedPreferences `onboarding_tip_shown`.

### 2.4 «Мы родственники?» entry point + flow

**Entry point** (per Q3 reasoning — option A top-level discovery
tab):

* Add new tab/icon в bottom navigation: «Найти родню» (либо integrate
  в `relatives_screen` через secondary tab).
* Alternative: floating action button в `relatives_screen` —
  «Проверить связь с кем-то».

**Не использовать**: settings (далеко), inline в profile (слишком
deep), discovery feed (feed not exists yet — Phase 5+).

**Flow** (full sequence):

```
┌─── Step 1: Search target ──────────────────────────────────┐
│  Введите username, телефон или email человека,             │
│  чтобы узнать, родственники ли вы                          │
│                                                            │
│  [Поиск __________________]                                │
│                                                            │
│  Результаты:                                               │
│  ┌────────────────────────────┐                            │
│  │ [avatar] Иван Сидоров      │                            │
│  │          @ivansid          │                            │
│  └────────────────────────────┘                            │
│  ┌────────────────────────────┐                            │
│  │ [avatar] Иван Петров       │                            │
│  │          @ipetrov          │                            │
│  └────────────────────────────┘                            │
└────────────────────────────────────────────────────────────┘

User taps result →

┌─── Step 2: Request reveal ─────────────────────────────────┐
│  [avatar] Иван Сидоров                                     │
│           @ivansid                                         │
│                                                            │
│  Чтобы узнать вашу связь, нужно подтверждение Ивана.       │
│  Он получит запрос:                                        │
│                                                            │
│    Артём хочет узнать, родственники ли вы.                 │
│    [Подтвердить] [Отклонить]                               │
│                                                            │
│  [Отправить запрос]    [Отмена]                            │
└────────────────────────────────────────────────────────────┘

User taps «Отправить запрос» → backend creates pending
relation-check claim. UI shows:

┌─── Step 3: Pending ────────────────────────────────────────┐
│  Запрос отправлен                                          │
│  Иван получит уведомление. Мы покажем результат, когда     │
│  он подтвердит.                                            │
│                                                            │
│  [Готово]   (can leave; result arrives via notification    │
│              когда Иван responds)                          │
└────────────────────────────────────────────────────────────┘

When target user responds (accept):

┌─── Step 4: Result ─────────────────────────────────────────┐
│  Вы родственники!                                          │
│                                                            │
│         Артём → Мама → Бабушка → ? → Иван                  │
│        (you)                  (hidden)                     │
│                                                            │
│  Вы – двоюродные брат и сестра                             │
│                                                            │
│  ИЛИ если не родственники:                                 │
│                                                            │
│  Мы не нашли прямой связи между вами                       │
│  Это не значит, что её нет — может быть, не хватает данных │
│  в одном из деревьев.                                      │
│                                                            │
│  [Открыть Иван в дереве]   [Закрыть]                       │
└────────────────────────────────────────────────────────────┘
```

### 2.5 BFS computation — backend endpoint + privacy

**Reuse**: `/v1/graph/relation?from=<viewerSelf>&to=<targetSelf>`
existing (Phase 2). **New wrapper endpoint** для consent flow:

* `POST /v1/relation-requests` — initiator creates pending request:
  - Body: `{targetUserId}` либо `{targetGraphPersonId}`.
  - Server creates relation-request row (pending state).
  - Server pings target through notification system (existing
    push/in-app).
* `GET /v1/me/relation-requests/pending` — target lists incoming.
* `POST /v1/relation-requests/:id/respond` — target accepts/declines:
  - On accept: server computes BFS via existing `findBloodRelation`
    с `maxDepth = 8` (per Q10 reasoning — bigger чем Phase 4
    fence=4, since both parties consented).
  - On reject: server marks rejected, initiator получает «Иван
    отклонил».
  - Returns full result `{found, chain, edges, label, degree}` to
    BOTH parties (initiator + target see same result в их UIs).
* `GET /v1/me/relation-requests/issued` — initiator's outgoing
  history.

**Privacy gating на chain nodes** (Q5):
* `chain` previews go through `previewGraphPersonsByIds(viewerUserId)`
  same as `/v1/graph/relation`.
* Nodes invisible to viewer (per Phase 3 fence) anonymized: avatar
  placeholder + «?» label.
* Edge sequence preserved (parent/child/sibling) — chain length
  carries information даже когда intermediate hidden.
* BOTH parties see the chain anonymized **for their own viewpoint**
  (Артём sees his hidden nodes as «?», Иван sees his hidden nodes
  as «?»). Backend computes two views, returns appropriate per
  request.

### 2.6 Consent workflow — bilateral pending

**State machine** (Q4 — chose bilateral pending):

```
pending (initiator created) →
  ↓
  ├── accepted (target consented; BFS computed, both see result)
  ├── rejected (target declined; initiator gets notice, no result)
  └── expired (30 days no response → auto-rejected, initiator notified)
```

**Why bilateral** (vs auto-publish):
* «Auto-publish что мы родня» violates target's privacy агентность.
  Pre-consent, target may not want связь revealed to initiator
  (e.g., estranged family).
* Bilateral mirrors existing identity-claim pattern (Phase 1.2):
  `/v1/identity-claims` + `/v1/identity-claims/:id/review`. Familiar
  shape.

**Notification mechanics**:
* On request — push + in-app notification to target.
* On response — push + in-app to initiator.
* Notification copy: «Артём хочет узнать, родственники ли вы».
  NOT «Артём ищет связь через ваш граф» — too technical.

**Idempotency**:
* If same (initiatorUserId, targetUserId) pending request exists —
  return existing instead of creating duplicate.
* If previous request **rejected** — initiator can re-request only
  after 30 days (anti-harassment).

### 2.7 Empty-state guidance (post-onboarding zero connected)

**Scenario**: user completed wizard с 3 relatives. Toggles
«Расширенная сеть». Slice contains only own seed → no foreign
nodes.

**State copy**:

```
┌────────────────────────────────────────────────┐
│                                                │
│       [illustration: silhouettes connecting]   │
│                                                │
│   Пока никого не нашлось через ваше дерево     │
│                                                │
│   Расширенная сеть появится, когда кто-то из   │
│   ваших родных тоже соберёт своё дерево или    │
│   подтвердит связь через «Найти родню».        │
│                                                │
│         [Поделиться приглашением →]            │
│         [Найти родню →]                        │
└────────────────────────────────────────────────┘
```

**Don't force loneliness**: NOT «У вас нет родственников» (sad);
phrased as «появится, когда» (future-positive).

**CTAs**:
* «Поделиться приглашением» — copies invite link для отправки
  семье через WhatsApp / Telegram (existing invite flow Phase 1).
* «Найти родню» — direct to BFS «мы родственники?» entry.

### 2.8 Existing-user migration

**Skip wizard logic** (Q6):

```dart
// In app launch (post-auth) → routing decision.
final hasExistingTree = await store.userHasNonEmptyTree(userId);
if (!hasExistingTree) {
  router.go('/onboarding');
} else {
  router.go('/tree');
}
```

**Detection criteria** (server-side либо client-side):
* User has at least 1 tree where they're creator OR member.
* That tree has at least 1 person beyond auto-created self-node.

**For Артём + Степа**:
* They have multi-person trees → silent skip, land directly на
  `/tree/view/<their primary tree>`.
* **No opt-in retroactive wizard prompt** в Phase 6 v1 (Q6 reason
  — Phase 4 features already accessible; wizard would be
  patronizing). Opt-in tour `/onboarding?revisit=1` deferred to
  later if user research demonstrates value.

---

## 3. Architecture

### 3.1 New screens / widgets (Flutter)

* `lib/screens/onboarding/onboarding_wizard_screen.dart` —
  stateful, holds step + form state.
* `lib/screens/onboarding/onboarding_welcome_step.dart` (screen 1).
* `lib/screens/onboarding/onboarding_profile_step.dart` (screen 2).
* `lib/screens/onboarding/onboarding_relatives_step.dart` (screen 3).
* `lib/screens/onboarding/onboarding_finish_step.dart` (screen 4).
* `lib/screens/discover_relatives/discover_relatives_screen.dart` —
  «мы родственники?» entry + 4 steps (search → request → pending →
  result).
* `lib/widgets/relation_chain_strip.dart` — re-usable horizontal
  strip rendering `BloodRelation.chain` с anonymous placeholders.
* `lib/providers/onboarding_controller.dart` — step state +
  persistence + skip detection.

### 3.2 New backend endpoints

* `POST /v1/onboarding/seed` — wizard's bulk-create endpoint:
  `{relatives: [{name, gender, birthDate, relationToMe}]}`. Atomic
  — either creates all либо rolls back. Returns created
  `treeId + personIds`.
* `GET /v1/me/onboarding-state` — returns `{completed: bool,
  treeId: string?, currentStep: enum?}` для resume detection.
* `POST /v1/me/onboarding-state` — wizard updates progress
  (idempotent; client may call after each step).
* **Relation-request endpoints** (per §2.5):
  - `POST /v1/relation-requests` — initiator create.
  - `GET /v1/me/relation-requests/pending` — target list.
  - `GET /v1/me/relation-requests/issued` — initiator list.
  - `POST /v1/relation-requests/:id/respond` — target accept/reject.

### 3.3 Capability mixins

Phase 4 pattern: each new feature gated через capability mixin.

* `lib/backend/interfaces/onboarding_capable_family_tree_service.dart`
  — `OnboardingCapableFamilyTreeService` методы `seedRelatives`,
  `getOnboardingState`, `setOnboardingState`.
* `lib/backend/interfaces/relation_request_capable_family_tree_service.dart`
  — `createRelationRequest`, `listPendingRelationRequests`,
  `listIssuedRelationRequests`, `respondToRelationRequest`.

Старый сервер без endpoint'ов → caps detection → UI gracefully
скрывает features либо показывает «обновите приложение».

### 3.4 Routing

* `/onboarding` — new route, gated через router guard «if
  hasExistingTree → redirect /tree».
* `/discover/relatives` — new route, available после auth.
* Existing routes unchanged.

### 3.5 Notification integration

Notification surface уже есть (Phase 1 push gateway + in-app
notifications). New notification types:

* `relation_request.received` — target gets «X хочет узнать, родственники ли вы».
* `relation_request.accepted` — initiator gets «X подтвердил, вот ваша связь».
* `relation_request.rejected` — initiator gets «X отклонил запрос».
* `relation_request.expired` — initiator gets «Запрос к X истёк (30 дней)».

All routed через existing `CustomApiNotificationService` (Phase 3.4
chunk 3 paired with edit-grants pattern).

---

## 4. Privacy language matrix

Bedrock rule: **no technical terms in UI**. Никаких «hops», «BFS»,
«identity-graph», «graphPerson», «privacy fence».

| Concept | UI string |
|---|---|
| BFS path | «связь», «цепочка родства» |
| Shortest path | «ближайшая связь» |
| Hops / depth | «поколений», «шагов по родне» |
| Identity-graph (foreign person matched) | «человек, уже добавленный в другую семью» |
| Privacy fence (4 hops cap) | «доступно только в пределах семьи» (implicit, не surfaced; just respected) |
| graphPerson visibility = owner-only | «приватная карточка» |
| Cross-tree link | «общий родственник», «через знакомого» |
| Identity-claim pending | «запрос подтверждения», «ожидает подтверждения» |
| Relation-request consent | «согласие на показ связи» |

**Privacy explainer copy для BFS flow** (показывается one-time
при first BFS request):

> Чтобы посмотреть, родственники ли вы с другим человеком,
> мы спрашиваем у него разрешения. Так каждый сам решает,
> кому показывать свои семейные связи.

Single sentence, declarative, no technical vocab.

---

## 5. Trust model — кто видит чьи данные при BFS

### Data flow при BFS check

```
Initiator (Артём)              Server                   Target (Иван)
       │                          │                          │
       ├── POST /relation-requests┤                          │
       │   {targetUserId: ivan}   │                          │
       │                          │                          │
       │                          ├── notify ivan ──────────►│
       │                          │                          │
       │                          │                          │
       │                          │                          ├── GET /me/.../pending
       │                          │◄─────────────────────────┤   sees Артём's request
       │                          │                          │
       │                          │                          │
       │                          │                          ├── POST .../respond
       │                          │◄─────────────────────────┤   {decision: accept}
       │                          │                          │
       │                          │── findBloodRelation()    │
       │                          │   (between selves)       │
       │                          │                          │
       │                          │── previewGraphPersonsByIds (for both viewers separately)
       │                          │                          │
       │  ◄── notify Артём ───────┤── notify Иван ──────────►│
       │   chain (Артёмов view)   │   chain (Иванов view)    │
       │                          │                          │
       │── GET .../<id>           │                          ├── GET .../<id>
       │   sees result            │                          │   sees result
```

### What each party sees in chain

* Both see **same chain length** + **same edge sequence** (parent/
  child/sibling).
* Each sees **own visible nodes** unmasked (their own ancestors,
  Phase 3 visibility).
* Each sees **other side's invisible nodes anonymized**: «?»
  placeholder, no avatar, no birth date.
* **No leak**: Артём не видит chain'е Ивана private details, и
  vice versa.

### Special case: shared ancestor

Если chain содержит общего предка которого видят оба:
* Both see same avatar + name + dates (shared visibility).
* This is the «aha moment» moment — concrete connection точка.

### What metadata leaks

* Chain length (degree) — both know how distant the relation is.
* Edge directionality (you-up, target-up) — both know which side
  the common ancestor is on.

Это **deliberate** — это и есть answer на «мы родственники?». Не
leak; это feature.

---

## 6. UX considerations

### 6.A: Mobile-first

* Wizard screens — single-column, full-screen, large tap targets
  (44pt minimum per iOS HIG).
* «Мы родственники?» search — same as Phase 4 search sheet pattern,
  DraggableScrollableSheet либо full-screen route.
* Tab bar для main navigation — wizard vs discover vs tree should
  not crowd existing tabs. Если bottom nav уже full — discover
  как FAB в `relatives_screen` либо secondary action.

### 6.B: Edge cases

* **Wizard interrupted** (Q8 resume): user closes app mid-step 3
  (relatives) → next launch resumes step 3, but form data lost
  (memory only). Sensible: re-enter slot data takes < 30s.
* **Wizard skipped entirely** (`Пропустить` на screen 3): user
  lands на `/tree` с tree containing only self-node. Empty-state
  guidance per §2.7 applies.
* **Target uninstalled app**: relation-request notifications
  fail silently; auto-expire after 30 days.
* **Target deleted account**: backend should reject `respond`
  call; UI shows «пользователь больше не доступен».
* **Initiator deleted account**: target receives request но
  cannot accept (initiator gone). UI shows «отправитель удалил
  аккаунт».

### 6.C: Accessibility

* Wizard step indicator (1/4, 2/4, ...) — visible + announced
  via Semantics.
* Skip button announced as «пропустить этот шаг (необязательно)».
* Search results have proper Semantics labels for screen readers.

### 6.D: Localization

All UI strings в Russian per existing app. No multi-locale в
Phase 6 v1.

---

## 7. Open questions для design pass

### Q1. Wizard length — 3 screens vs 5+?

**Surfaced**: trade-off conversion (shorter → higher complete-
rate) vs data quality (longer → more seeded relatives → richer
tree).

**Proposal recommendation**: **4 screens** as outlined в §2.1
(welcome / profile / relatives / finish). Reasoning:
* 3 screens (drop welcome либо finish) — too abrupt; value prop
  upfront matters.
* 5+ screens (split relatives into per-relation guided flow) —
  drop-off compounds; user fatigue.

**Need explicit answer**: 4 vs 3 vs 5.

### Q2. First-relatives required vs suggested?

**Surfaced**: required (minimum 2) prevents drop-off into empty
tree; suggested allows users without known relatives.

**Proposal recommendation**: **suggested (skip available)**.
Required = paternalistic; user knows their family situation.

Reasoning:
* Adopted / orphaned users may not know relatives.
* Required + skip-blocked = funnel drop on screen 3.
* Better: skip allowed, but UI strongly encourages («Заполненное
  дерево помогает найти родню»).

**Need explicit answer**: required-with-minimum vs suggested-skip.

### Q3. BFS entry point — bottom nav tab / FAB / settings / inline?

**Surfaced**: discovery vs visibility trade-off.

**Proposal recommendation**: **secondary tab в `relatives_screen`
либо prominent FAB**. NOT settings (too deep), NOT inline в profile
(disconnected context).

Reasoning:
* Bottom nav tab — high visibility но crowds existing tabs.
* FAB в relatives — same context («моя родня»), surfaces feature
  exactly где user думает про relations.

**Need explicit answer**: bottom-nav tab / FAB / inline secondary
tab.

### Q4. BFS consent — auto-publish vs bilateral pending?

**Surfaced** per Артёмов explicit critical decision point.

**Proposal recommendation**: **bilateral pending** (§2.6 detail).
Mirror existing identity-claim pattern.

Reasoning:
* Auto-publish violates target's agency.
* Privacy regression risk — target may not want связь revealed.

**Need explicit answer** (this is critical, не self-resolve per
constraint).

### Q5. BFS privacy — invisible nodes показывать как hidden / masked / placeholder?

**Surfaced**: chain shows shortest blood-path. Some intermediate
nodes may be invisible to viewer (Phase 3 fence).

**Proposal recommendation**: **anonymized placeholder** («?» +
generic avatar). Chain length preserved.

Reasoning:
* Hidden (skip node entirely) — confuses chain semantics («through
  whom?»).
* Masked (initials only) — partial leak.
* Placeholder — chain count visible, no PII.

**Need explicit answer**: placeholder vs alternative.

### Q6. Pre-existing users без wizard — opt-in tour или silent skip?

**Surfaced**: Артём + Степа уже active. Phase 6 ships → они не
прошли wizard. Surface'ить им новые features tour?

**Proposal recommendation**: **silent skip в Phase 6 v1**.
`/onboarding?revisit=1` route placeholder для future, не shown
в v1.

Reasoning:
* Phase 4 features уже accessible.
* Tour feels patronizing для active users.

**Need explicit answer**: silent-skip vs opt-in-tour-snackbar.

### Q7. Onboarding step-back — linear vs branching?

**Surfaced**: from screen 4 can user go back to 2/3?

**Proposal recommendation**: **linear с back button**. Branching
adds complexity без clear UX gain.

**Need explicit answer**: linear-back vs free-jump-between-steps.

### Q8. Wizard mid-flow abandon — resume или restart?

**Surfaced**: user closes app на screen 3 → relaunches.

**Proposal recommendation**: **resume on same step** (SharedPreferences
`onboarding_step_${userId}`). Form data lost (memory only) —
acceptable trade-off (re-enter < 30s).

**Need explicit answer**: resume-at-step (form lost) vs resume-
with-form-data (heavier persistence) vs restart-from-welcome.

### Q9. First-relatives identity matching — surface or silent?

**Surfaced**: wizard creates «Иванова Татьяна 1955-XX-XX».
Identity-matcher (Phase 1.2) probably matches existing graphPerson
в чужом tree (e.g., Степина бабушка).

**Proposal recommendation**: **silent enrichment**. graphPerson
attached к existing. User не sees «вы связаны с другими trees»
до Phase 4 extended view либо BFS feature explicit use.

Reasoning:
* «о, тебя кто-то знает» surface во время wizard = creepy.
* Silent matching + later explicit feature discovery = consent
  preserved.

**Need explicit answer**: silent vs surface-during-wizard.

### Q10. BFS depth — Phase 4 fence=4 либо relaxed?

**Surfaced**: Phase 4 has `_connectedVisibilityMaxHops = 4`
fence для extended view. BFS «мы родственники?» — consent-gated;
relax to 8 hops? 10?

**Proposal recommendation**: **relax to 8 hops для BFS through
consent path**. Why:
* Both parties consented → relaxed visibility scope justified.
* 4 hops too tight для «дальние родственники» discovery
  (8-degree cousins = realistic blood-relation discovery
  scenario).
* Existing `/v1/graph/relation?maxDepth=10` already supports it
  (server clamp 16).

**Need explicit answer**: keep-4 vs relax-8 vs relax-10 vs match-
fence-strictly-per-target.

---

## 8. Out of scope

Explicitly **NOT** in Phase 6:

* **Phase 3.6 hard-delete background job** — separate work
  (полдня per Артёмов roadmap). Schedule independently.
* **Phase 5 public layer** (Pushkin'ы, исторические фигуры) —
  отдельная неделя; out of scope.
* **Bug-bash session** — accumulated user complaints. Separate
  schedule.
* **Multi-locale** — Russian only в v1.
* **In-app browser tour для existing users** — Q6 deferred.
* **Group/family invite mass-onboarding** — Phase 6 v1 focuses
  single-user onboarding.
* **BFS depth slider в UI** — server-clamped, fixed 8 hops для
  BFS flow.
* **Telegram / VK integration на screen 4** — placeholder text
  только; actual OAuth flow Phase 5+.

---

## 9. Tests strategy

### 9.1 Backend

* `backend/test/onboarding-seed.test.js`:
  - POST /seed atomic (rollback on partial failure).
  - Wizard creates self-node + 2 relatives + relations.
  - Idempotency (same wizard run twice → no duplicate).
  - Onboarding state persisted.
* `backend/test/relation-request.test.js`:
  - Create pending request → target sees в /me/.../pending.
  - Accept → BFS computed → result returned to both views.
  - Reject → pending state cleared, initiator notified.
  - Expiry simulation (artificially aging row → auto-rejected).
  - Idempotency (duplicate request before response).
  - Anti-harassment (re-request after rejection requires 30d gap).

### 9.2 Flutter

* `test/onboarding_wizard_test.dart`:
  - Step linearity (1→2→3→4 forward).
  - Step-back available except from 1.
  - Required field validation.
  - Skip на screen 3 → land на finish с self-only tree.
  - Resume from `onboarding_step_${userId}` SharedPreferences.
  - Existing-user detection → router redirect /tree.
* `test/discover_relatives_test.dart`:
  - Search → results render.
  - Request → pending state.
  - Mock incoming accepted response → result screen.
  - Anonymized placeholder rendering for invisible chain nodes.
  - Privacy explainer one-shot (first time only).
* `test/relation_chain_strip_test.dart`:
  - Render with mixed visible/hidden nodes.
  - Chain length + edge labels.
  - Tap on visible node → opens person card (existing route).
  - Hidden nodes non-tappable.

### 9.3 Integration

* `test/onboarding_to_tree_flow_test.dart`:
  - Fresh user → wizard → finish → land /tree with seeded tree.
* `test/discover_relatives_consent_flow_test.dart`:
  - Initiator request → target's pending list → target accept →
    initiator + target both see result with respective chain
    views.

### 9.4 Visual

* No new golden tests в Phase 6 v1 (Phase 4 set sufficient
  coverage для extended view). Может быть деferred follow-up
  если visual review surface'ит need.

---

## 10. Risks

### R1. Funnel data quality

Wizard skipped → empty tree → юзер leaves before second session.
**Mitigation**: encouraging copy на screen 3 («Дерево с 2-3 людьми
помогает найти родню»). Tracking: completion rate (analytics
event per step).

### R2. BFS consent fatigue

Если активный initiator посылает много requests, target gets
spam'нутый notifications.
**Mitigation**: rate-limit per-(initiatorUserId) → max 5 outgoing
pending requests at any time. Anti-harassment 30d cooldown post-
rejection.

### R3. Privacy leak в anonymized chain

«?» placeholder reveals chain length → metadata leak (degree of
separation). Если this matters → escalate restriction.
**Mitigation**: this is **deliberate** per §5. Phase 6 v1 accepts
metadata leak; if user research shows discomfort, revisit Phase 7.

### R4. Identity-matcher false positives during wizard

Если wizard's «Иванов Иван 1955» matches existing graphPerson
incorrectly → graphPerson linked across two unrelated families.
Identity drift.
**Mitigation**: confidence threshold tightening (existing Phase
1.2 matcher) — birth year + full name + at least one parent name
match required для auto-link. Otherwise create independent
graphPerson (no link).

### R5. Onboarding length friction

Per Q1: 4 screens may still be too long. Drop-off measurement
post-launch.
**Mitigation**: track step completion rate; if screen 3 drop >
40%, A/B test 3-screen variant (welcome → combined profile+
relatives → finish).

### R6. Re-introducing Phase 4 id translation bug pattern

Per constraint: «verify trace 'id flowing here matches what
consumer expects'». Onboarding endpoint creates persons → returns
`personIds` (legacy tree-scoped). UI must use legacy ids consistently
для каrtочек, identity ids для identity-graph features. Trace
checked в §3.

---

## 11. Implementation outline (chunks)

After v2 approval, phased implementation parallel Phase 4 pattern.

### Chunk 1 — backend

* `POST /v1/onboarding/seed` endpoint + atomic transaction.
* `GET/POST /v1/me/onboarding-state`.
* `POST /v1/relation-requests` + state machine + 4 list/respond
  endpoints.
* Notification routing 4 new types.
* Backend tests 9.1.

### Chunk 2 — wizard UI

* `OnboardingWizardScreen` + 4 step screens.
* `OnboardingController` с persistence.
* Router guard для skip-existing.
* Tests 9.2 part one (wizard).

### Chunk 3 — discover UI

* `DiscoverRelativesScreen` + 4 step flow.
* `RelationChainStrip` widget.
* Notification handling для request responses.
* Tests 9.2 part two (discover).

### Chunk 4 — integration + polish

* End-to-end onboarding → tree flow test.
* End-to-end discover consent test.
* Empty-state guidance для Phase 4 extended view (post-onboarding
  zero connected).
* Privacy explainer one-shot logic.

### Chunk 5 — observation + merge

* MERGE-CHECKLIST-PHASE-6.md.
* Squash to main с feature flag `usePhase6Onboarding` (default
  false initially).
* Observation week → cleanup commit (per Phase 4 pattern).

---

**Status v1**: ready для review-revise цикл. Single approve →
revisions → v2 → approve → chunk 1 implementation.

**Open questions count**: 10 (Q1-Q10). После Артёмова answers
все cross-reference в DECISIONS.md как «Phase 6 architectural
answers».
