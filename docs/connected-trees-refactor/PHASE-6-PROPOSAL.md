# Phase 6 proposal v2 — onboarding wizard + «мы родственники?» BFS

**Дата**: 2026-05-13
**Source ветка**: `claude/serene-fjord-8b4d62` от `5fb1d3c` (Phase 4
observation, flag default `true`).
**Изменения от v1**: 8/10 questions approved + 2 critical push-backs
(Q9 → no matching during onboarding; Q10 → keep 4 hops universally)
+ Q2/Q3/Q4 sub-decisions. §7 open questions: 10 → 0 closed.
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

**Identity matching during wizard (Q9 closed — push back)**:

**NO identity-matching during wizard.** Wizard creates plain
person-records (anonymous, no identity link). Background matcher
job runs **post-onboarding**, surface'ит suggestions через
notification + Phase 1.2 identity-claim explicit confirm UX:

> Возможно, ваш Виктор Моздуков — тот же человек, что у Степы.
> Связать карточки?
> [Да] [Нет]

**Reasoning** (per Артёмов push back 2026-05-13):
* User в первый раз — наиболее vulnerable к false-positive
  identity links. Не имеет context чтобы оценить «это тот же
  человек что у меня?».
* Silent merge = irreversible bad first impression если false
  positive. Юзер открывает дерево после wizard'а и видит «у вас
  уже 50 родственников» — это feels like data theft, не magic.
* Clean slate onboarding + post-onboarding opt-in suggestions =
  consent preserved, no surprise.

**Implementation note**: post-onboarding identity-suggestion flow
NOT new — Phase 1.2 уже имеет `/v1/identity-claims` + review API.
Phase 6 chunk 1 backend wires existing `identity-suggestions`
endpoint (Phase 1.2) к post-wizard trigger.

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

**Empty-tree fallback** (Q2 sub-decision — Артёмов 2026-05-13):
Если юзер skip'нул screen 3 → landed с tree containing only
self-node. Post-onboarding empty-state ОБЯЗАН have prominent CTA
с illustration:

```
┌────────────────────────────────────────────────────────────┐
│                                                            │
│       [illustration: одинокий silhouette + dotted          │
│        connection lines reaching out]                      │
│                                                            │
│              У вас пока никого нет в дереве                │
│                                                            │
│         Начните с одного — добавьте родителя,              │
│              брата либо ребёнка                            │
│                                                            │
│             [+ Добавить первого родственника]              │
│                                                            │
│         Или [Найти родню через знакомого →]                │
└────────────────────────────────────────────────────────────┘
```

**Reasoning**: skip без strong CTA ведёт к user bounce — empty
tree без guidance = «зачем я тут?». Prominent illustration +
single primary action собирает funnel.

### 2.4 «Мы родственники?» entry point + flow

**Entry point** (Q3 closed): **FAB в `relatives_screen`** — «Проверить
связь с кем-то». Same context («моя родня»), discoverable without
navigation crowding. Tooltip + spotlight overlay при first visit
после onboarding'а — surface feature в день один.

**First-visit tooltip** (Q3 sub-decision — Артёмов 2026-05-13):

```
┌────────────────────────────────────────────────────────────┐
│                                                            │
│     [tree with arrow pointing к FAB at bottom-right]       │
│                                                            │
│      Нашли кого-то знакомого? Проверьте, родственники ли   │
│      вы — через эту кнопку.                                │
│                                                            │
│                          [Понятно]                         │
└────────────────────────────────────────────────────────────┘
```

* Dismissible через «Понятно» либо tap-outside.
* State в SharedPreferences `discover_fab_tooltip_shown` — one-
  shot global, not per-tree.
* Triggered после wizard finish либо first `relatives_screen`
  visit для existing users (Q6 — existing users get tooltip
  once even though wizard skipped).

**Не использовать**: settings (далеко), inline в profile (слишком
deep), bottom navigation (crowding), discovery feed (Phase 5+).

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
    с `maxDepth = 4` (Q10 closed — keep universal privacy fence).
  - On reject: server marks rejected, initiator получает «Иван
    отклонил».
  - Returns full result `{found, chain, edges, label, degree}` to
    BOTH parties (initiator + target see same result в их UIs).
* `GET /v1/me/relation-requests/issued` — initiator's outgoing
  history.

**Depth cap = 4 hops universally (Q10 closed — Артёмов push back)**:

`findBloodRelation` invoked с `maxDepth: 4` — **same Phase 4
visibility fence**. Single privacy invariant easier to explain,
audit, defend.

* Chain length > 4 → result `{found: false, label: "Слишком
  далёкое родство"}`. UI shows «Связь слишком далёкая, не
  показана».
* Practical family graph fits в 4 hops (parent → grandparent →
  great-grandparent → cousin) — happy path covered.
* «Через пра-пра-пра-прадеда» — intellectually interesting, но
  privacy surface слишком широкий для marginal value.
* Future expansion fence (e.g., public-figures Phase 5+) — only
  via explicit relaxation framework, не piecewise через BFS.

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

**State machine** (Q4 closed — STRONG APPROVE bilateral, Артёмов
2026-05-13):

```
pending (initiator created) →
  ↓
  ├── accepted (target consented; BFS computed, both see result)
  ├── rejected (target declined; initiator gets notice, no result)
  └── expired (14 days no response → auto-rejected, silently)
```

**Why bilateral** (vs auto-publish):
* Privacy default правильный — это safeguard против social
  engineering vector. Без bilateral consent BFS становится attack
  surface («шутник создаёт fake person и проверяет родство»).
* Auto-publish что мы родня — violates target's privacy агентность.
* Bilateral mirrors existing identity-claim pattern (Phase 1.2):
  `/v1/identity-claims` + `/v1/identity-claims/:id/review`. Familiar
  shape.

**Sub-decisions** (Артёмов 2026-05-13):

* **Pending timeout = 14 days** (changed from v1 30 days). После
  — auto-expire silently (no initiator notification на expire;
  notification noise reduced).
* **Revocation** — либо сторона может undo через relations
  manager screen. **Defer на Phase 6.5** (post-merge follow-up;
  не критично для v1).
* **Notification copy** (no «BFS» / «граф» / «hops»):

> «Артём отправил вам запрос на подтверждение родственной связи.
> Подтверждаете?»

  Buttons inside notification body: `[Подтвердить] [Отклонить]`.

**Idempotency**:
* If same (initiatorUserId, targetUserId) pending request exists —
  return existing instead of creating duplicate.
* If previous request **rejected** — initiator can re-request только
  после 30 days (anti-harassment cooldown, longer чем pending
  timeout).

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

### 5.X Identity-matching gating in onboarding (Q9 closed)

**Wizard НЕ trigger'ит identity-matcher.** Created persons attach
к **independent graphPersons** (no cross-tree link).

**Reasoning** (per Артёмов push back 2026-05-13):
* User в первый раз не имеет context для оценки false-positive
  match.
* Silent merge = irreversible — bad first impression если
  matcher ошибается. Юзер не expects «у вас 50 родственников
  после wizard'а» → feels like data theft.
* Identity-suggestion должно быть explicit consent flow ПОСЛЕ
  wizard'а:

```
                wizard creates plain persons
                            │
                            ▼
              (post-onboarding background job)
                            │
                            ▼
           identity-matcher runs на seeded persons
                            │
                            ▼
              suggestions saved per-person
                            │
                            ▼
                 notification к юзеру:
        «Возможно, ваш Виктор Моздуков — тот же
         человек, что у Степы. Связать?»
                  [Да] [Нет] [Не сейчас]
                            │
                            ▼
               opt-in confirm per match
                            │
                            ▼
              graphPerson identity-linked
              (visible в Phase 4 extended view)
```

**Existing surface to reuse**: Phase 1.2 `/v1/identity-suggestions/*`
endpoints already имеют этот flow (поверхностно). Phase 6 chunk 1
backend wiring:
* Post-wizard async trigger runs identity-matcher на seeded
  persons.
* Existing suggestions returned через existing endpoint.
* UI surfaces via notification → existing identity-claim review
  screen.

**Не reinventing** — Phase 6 wires existing pieces, не creates
new identity-matching path.

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

## 7. Open questions — все закрыты (review-revise 2026-05-13)

Review-revise цикл с Артёмом закрыл все 10 questions. **0 open**
в v2. Cross-reference table:

| Q# | Topic | Decision | Notes |
|---|---|---|---|
| Q1 | Wizard length | **4 screens** (welcome / profile / relatives / finish) | Approved |
| Q2 | First-relatives required/suggested | **Suggested + skip + prominent empty-state CTA** | §2.3 mandates illustration + «Добавьте первого родственника» button |
| Q3 | BFS entry point | **FAB в `relatives_screen`** | §2.4 — first-visit tooltip обязателен для discoverability |
| Q4 | Consent model | **Bilateral pending** (STRONG APPROVE) | §2.6 — privacy safeguard против social engineering. Timeout 14d. Notification copy: «...запрос на подтверждение родственной связи». Revocation deferred to Phase 6.5 |
| Q5 | Invisible chain nodes | **Anonymized placeholder** («?») | §2.5/§5 — generic, не leak'ает имя/avatar |
| Q6 | Existing users | **Silent skip** | Phase 4 features уже accessible; tour deferred |
| Q7 | Step-back | **Linear с back button** | Approved |
| Q8 | Mid-flow abandon | **Resume-at-step (form lost)** | Tradeoff accepted — re-enter < 30s |
| Q9 | Identity-matching | **NO matching during wizard** (push back) | §5.X — post-onboarding suggestion flow вместо silent enrichment. Existing Phase 1.2 /v1/identity-suggestions reused |
| Q10 | BFS depth | **4 hops universally** (push back) | §2.5 — same fence as Phase 4 visibility. «Слишком далёкое родство» fallback при > 4 hops |

**Status**: ready для approve v2 → chunk 1 implementation.

---

## 7.A. v1 → v2 changes detail

Original v1 questions (для audit trail):

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

**v1 recommendation**: silent enrichment.

**~~Silent~~ → REJECTED (Артёмов push back 2026-05-13)**.

**v2 decision**: **NO identity-matching during wizard**.

**Reasoning** (Артёмов):
* User в первый раз — наиболее vulnerable к false-positive
  identity links. Не имеет context для оценки.
* Silent merge irreversible — bad first impression если ошибка.
  «У вас 50 родственников» = data theft feel.
* Clean slate + post-onboarding opt-in suggestions = consent
  preserved.

**v2 implementation** (§5.X):
* Wizard creates plain persons (no identity link).
* Background matcher job post-wizard surface'ит suggestions.
* Existing Phase 1.2 `/v1/identity-suggestions` flow reused для
  explicit per-match confirm.

### Q10. BFS depth — Phase 4 fence=4 либо relaxed?

**v1 recommendation**: relax to 8 hops.

**~~Relax 8 hops~~ → REJECTED (Артёмов push back 2026-05-13)**.

**v2 decision**: **keep 4 hops universally — same as visibility
fence**.

**Reasoning** (Артёмов):
* Single privacy invariant easier to explain, audit, defend.
* Consent gives access, не expands scope. BFS с consent в 4
  hops = «мы родственники до 4 поколений» — purpose practical
  family graph.
* 8 hops = «мы родственники через пра-пра-пра-прадеда» —
  intellectually interesting, но privacy surface слишком
  широкий для marginal value.
* Future fence expansion (Phase 5+ public-figures) — только через
  explicit relaxation framework, не piecewise через BFS path.

**v2 implementation** (§2.5):
* `findBloodRelation(maxDepth: 4)` для все BFS invocations.
* Chain length > 4 → `{found: false, label: "Слишком далёкое
  родство"}`. UI shows «Связь слишком далёкая, не показана».
* Юзеры с тесными цепочками (2-3 hops) — happy path.
* Дальние — false-negative acceptable (rare case).

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
* **BFS depth slider в UI** — server-clamped, fixed 4 hops для
  BFS flow (per Q10 v2). No user-facing depth control.
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
