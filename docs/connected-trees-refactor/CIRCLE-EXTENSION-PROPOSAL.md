# Phase C — «Круг» Extension Proposal

> **Status**: design proposal, awaiting Артёмов sign-off
> **Brainstorm**: Артём + Claude, 2026-05-26
> **Source evidence**: real-user feedback (мама calls + Степа silent quit) + Артёма positioning statements
> **Prerequisite**: Phase B Week 8 done (federated семьи production rollout)
> **Estimated timeline**: 8 weeks Phase C work
> **Risk profile**: medium-high (privacy decisions, identity model extension, migration complexity)

---

## 1. Context

### 1.1 Current state (после Phase B done)

К концу Phase B (planned Week 8 production rollout, ~2026-08-01):

- Federated семьи architecture live в production
- 70+ users migrated к «Моя семья» с opt-in upgrade flow
- Семя CRUD + membership + invitations + tree binding + pull-selectively + browse + hide filter live
- Frontend FE1-FE10 shipped (Phase B Week 5-6 рewrite)
- Mama-friendly onboarding live (Phase B Week 7)
- Production migration completed (Phase B Week 8)
- Hard-delete background job protecting GDPR-compliance (Phase 3.6 active с 2026-05-19)
- 6+ user-trust fixes shipped (Q1 wizard skip, Q2 Google dialog, Q3 sign-out confirm + reg validation + provider hide, Q4 tree action sheet + safe delete, Q3a backend auth provider gate, Q4a soft-delete + restore — pending fresh session)

### 1.2 Brainstorm evidence (2026-05-26)

**Артёма positioning statements (verbatim)**:

> «Хочу, чтобы больше семьями тут общались, но и чтобы с друзьями можно было тоже созвониться (мы же там еще деревья друзей могли делать).»

> «В ленте хочется собирать альбом семьи получается и друзей, чтобы вся наша информация не терялась в кучи каналов и групп как в тг.»

> «Это точно не fail!» — на вопрос «если 50% users никогда не trogают tree feature».

> «Найти родственника в моей семье» (родственник should already be in tree) + «Добавить нового родственника быстро и позвонить» — оба paths мама-friendly.

> «Норм сканировать номера, да» — phone book scan permission OK.

### 1.3 Real-user feedback evidence (carried from prior sessions)

- **Мама** (Samsung S20 FE call 2026-05-25): «Куда тут жмать? Что делать дальше? Что можно делать, что нельзя? Как все не сломать?» — fear of breaking things, app not UI-friendly. Видела свой empty self-tree вместо Артёмов tree. Wizard заблокировал звонок.
- **Степа** (after initial confusion): silent quit, больше не залезает в дерево.
- **Артёма observation**: «никто пока не понимает как коллективно пользоваться деревом», «не смешивать прям всех людей дерева (папиных и маминых родственников, родственников партнеров)».

### 1.4 Strategic insight

Артёма vision **не «family messenger competitor»** — это **«personal information hub с relationship structure»**. Anti-Telegram positioning:

| Telegram | Rodnya (Артёмов vision) |
|---|---|
| Контент scattered по N групп/каналов/чатов | Контент aggregated в одном hub |
| Identity = phone + handle | Identity = «мой круг» (семья + друзья) |
| Generic messenger | Семейно-friendly information storage |
| Channels = broadcast | Лента = personal/family content archive |
| Photos lost в scrollback | Альбомы organized by people + relationships |
| Calls + chats commodity | Calls + chats + tree + albums = unified «круг» |

Это **defensible positioning** — competitors не serve «private personal information hub с relationship structure»:

- **Telegram** has speed но no structure
- **Facebook** has structure но public + algorithmic + ads
- **MyHeritage** has structure но no daily-use chat
- **Instagram** has photos but public + creator economy
- **WhatsApp** has phones but no metadata

---

## 2. Problem statement

### 2.1 Tension surface'нувшаяся в brainstorm

Артёма actual ask captured 2 contradictions:
1. «Хочется просто созвониться без дерева» (push for lightweight access)
2. «Не скатиться в WhatsApp/Viber» (защитить tree-first differentiation)

Phase B alone (Семьи only) does НЕ address:
- Non-family contacts (друзья, knaкомые) — currently no path
- Phone book discovery — manual entry only
- Mixed feed (семья + друзья posts in one timeline) — not supported
- Albums organized by people across tiers — not supported

### 2.2 «50% might never trogать tree» reality

Артём confirmed: it's not failure if half users skip tree feature. This is **product framing shift**:

- Tree = **optional power feature**, не required engagement
- Calls + chats + feed = **core daily use**
- Tree visualizes relationships для users who care, ignored для others

This permission unlocks design freedom:
- Lightweight contacts без forced tree binding
- Mama can join through «найти близких» without wizard wall
- Tree feature retains all power for users who engage

### 2.3 Multi-tier identity need

Users have **distinct relationship categories**:

- **Семья** = blood/marriage, structured tree, biography, photos archive
- **Друзья** = знакомства (work, university, neighbors, hobby groups), lightweight, sometimes group-organized
- **Возможно: «знакомые»** = casual contacts, calls/chats работают, but tier secondary

Current Phase B only handles семья. Phase C extends к include friends.

---

## 3. Proposed architecture: «Круг» model

### 3.1 Core concept

```
Круг (User's personal network)
├── Семья (existing Phase B)
│   ├── Tree (existing — blood/marriage DAG)
│   ├── Members (owner/editor/viewer)
│   └── Photos/posts albums
├── Друзья (NEW Phase C)
│   ├── Friend graph (NEW — optional closeness viz)
│   ├── Lightweight contacts (phone/name/note)
│   └── Optional group tagging
└── Feed (aggregated content from both tiers)
```

User имеет **один Круг** (single primary instance). Multiple семей possible inside (Phase B Семя model). Multiple friend groups possible inside (Phase C).

### 3.2 Tier 1 — Семья (Phase B preserved)

**No changes from Phase B design.** Сохраняем existing:
- Семя entity (multiple per user — мама's семья, папа's семья, future жена's семья)
- Membership с roles (owner, editor, viewer)
- Tree bound к семья
- Visibility, edit-grants, sensitive contacts (Phase 3.4)
- Pull-selectively (Phase B Ship 6)
- Browse mode (Phase B Ship 7)
- Hide filter (Phase B Ship 8)

### 3.3 Tier 2 — Друзья (NEW)

#### 3.3.1 Friend entity

```javascript
{
  id: uuid,
  userId: uuid,  // owner — every friend belongs к single user
  name: string,  // displayed name
  phone: string | null,  // primary phone (E.164 format)
  photoUrl: string | null,  // от phone book либо manual upload
  notes: string | null,  // «работа», «универ», «соседи», free-form
  groupTags: string[],  // ['работа', 'универ'] — для clustering
  matchedUserId: uuid | null,  // если этот friend = registered Rodnya user
  addedFrom: 'phone_book' | 'manual' | 'shared_invite',
  closenessHint: 'close' | 'casual' | 'professional' | null,
  createdAt: timestamp,
  updatedAt: timestamp,
  hardDeleteScheduledAt: timestamp | null
}
```

#### 3.3.2 Membership semantics

**Different from семя model** — друзья are **personal** не shared:

- Each user manages OWN friend list
- No «invite friend» concept (friends don't see each other's friend lists)
- Друг X в Артёма friend list ≠ Артём в Друга X friend list automatically
- Bilateral friend status emerges когда both add each other (UI shows badge «взаимный друг»)

This is **simpler than Семя** intentionally. Lower complexity = lower mama-confusion.

#### 3.3.3 Operations

- `POST /v1/me/friends` — create friend (manual либо from phone book match)
- `GET /v1/me/friends` — list my friends (filter by groupTags, search by name)
- `PATCH /v1/me/friends/:id` — update name, notes, groupTags, closeness
- `DELETE /v1/me/friends/:id` — soft-delete (30-day restore window, Q4a pattern)
- `POST /v1/me/friends/:id/promote-to-family` — move friend → семья (creates семя member если matched user)

#### 3.3.4 Privacy

- Друг list private к owner only
- Друг X never sees их own «friend status» в Артёма list
- Optional «следы»: friend can see «Артём is also на Rodnya» (via matched users), но не sees Артёма's friend list

### 3.4 Phone book integration (Q4 OK'd)

#### 3.4.1 Onboarding step

После Phase B's mama-friendly wizard (либо skip с Q1), нового onboarding шаг:

```
┌─────────────────────────────────────┐
│  Найти близких в Rodnya             │
│                                     │
│  Мы можем найти твоих друзей и      │
│  родственников по номеру телефона.  │
│  Никто не получает уведомлений,     │
│  пока ты сам не добавишь.           │
│                                     │
│  [Разрешить доступ к контактам]    │
│  [Пропустить]                       │
└─────────────────────────────────────┘
```

Permission rationale **clear**: «никто не получает уведомлений, пока ты сам не добавишь» — addresses mama's «как не сломать» fear.

Skippable per Q1 pattern. Можно permission запросить позже из settings.

#### 3.4.2 Match flow

После permission granted:

```
┌─────────────────────────────────────┐
│  Найдено 3 человека в Rodnya:       │
│                                     │
│  [photo] Артём Иванов               │
│           +7 (912) 345-67-89        │
│           [✅ В моей семье]          │
│                                     │
│  [photo] Маша Петрова               │
│           +7 (912) 222-33-44        │
│           [Это родственник? Да|Нет] │
│                                     │
│  [photo] Иван Сидоров               │
│           +7 (912) 555-66-77        │
│           [Это родственник? Да|Нет] │
│                                     │
│  [Пропустить остальных]             │
└─────────────────────────────────────┘
```

Per-match user choice:
- «Да, родственник» → семя add flow (existing Phase B)
- «Нет, друг» → друзья add (lightweight, Phase C)
- «Не сейчас» → ignore, can revisit

#### 3.4.3 Non-matched contacts

Contacts where phone не matches any Rodnya user:

```
┌─────────────────────────────────────┐
│  Пригласить в Rodnya?               │
│                                     │
│  У этих людей нет Rodnya. Можешь    │
│  отправить им приглашение по СМС.   │
│                                     │
│  ☐ Маша работа       (выбрать всех) │
│  ☐ Иван универ                      │
│  ☐ Тётя Люся                        │
│                                     │
│  [Отправить 0]    [Пропустить]      │
└─────────────────────────────────────┘
```

SMS invite content:
```
Привет от Артёма!

Артём пользуется Rodnya — личный архив семьи и друзей.
Хочет добавить тебя в свой круг.

Скачать: https://rodnya-tree.ru/invite/{token}
```

Token-based invite — opens app deeplink, registration flow с pre-filled phone.

#### 3.4.4 Privacy guardrails

- Phone numbers hashed before sending к backend (privacy by design)
- Backend matches только hashed phones, не stores raw phone book
- User can revoke permission anytime — existing matches preserved, no future scans
- Опт-аут setting: «не появляться в чужих phone book searches» — для users who want privacy

### 3.5 Feed unification (NEW либо extension)

#### 3.5.1 Per-post audience

Posts gain **audience selector** (extends existing Phase 3.4 visibility):

```
Audience selector when posting:
○ Вся семья
○ Друзья
○ Семья + друзья
○ Конкретные люди (Phase 3.4 sensitive contacts pattern)
○ Только я (private journal)
```

#### 3.5.2 Feed view

Existing feed shows posts visible к viewing user. После Phase C — viewer sees:
- Posts where они are в audience (семя member, друг tagged, либо explicit person)
- Posts от people they care about (filterable by семя либо друг tier)

UI tabs либо filter chips на feed:
- «Все» — combined feed
- «Семья» — только семья posts
- «Друзья» — только друзья posts
- «{Конкретный круг}» — saved filter (e.g. «Семья Ивановых» либо «Универ группа»)

#### 3.5.3 Albums organized by people

Existing posts с photos already tagged by people (via existing Person references). Phase C extends:

- **People view**: tap person в семя tree либо друг list → all posts featuring them
- **Album auto-creation**: «Фото с дядей Колей за 2025» auto-aggregated
- **Search**: «фото семья отпуск 2025» либо «друзья работа июнь»
- **Memory**: «3 года назад: семейный пикник» surfaces in feed

### 3.6 Friend graph (optional viz)

#### 3.6.1 Concept

«Friend tree» mentioned by Артёма — но different from family tree:

- **Family tree** = blood/marriage DAG (parent-child relationships, marriage edges)
- **Friend graph** = closeness/groups (cluster-based, не tree structure)

Visualization:
- **Nodes**: friends
- **Edges**: «знают друг друга» (если оба добавили each other)
- **Clusters**: groupTags from friend entity ('работа', 'универ', 'соседи')
- **Layout**: force-directed либо radial, не tree DAG

#### 3.6.2 When to activate

- Optional feature — friend graph hidden until user requests
- Triggered by: «показать дерево друзей» button в друзья list
- Empty при <5 friends, becomes useful при 10+
- Per Phase 4 extended-network pattern — graph rendering уже exists

#### 3.6.3 Defer detailed design

Friend graph = Phase C Week 4 territory. Full design в separate sub-proposal после Phase C kickoff. **Минимально viable** для Phase C v1: friend list + groupTags + filter. Visual graph = nice-to-have.

---

## 4. User journeys

### 4.1 Journey 1 — Мама onboarding (post Phase B + C)

1. Мама opens app first time
2. Лancing screen: «Артём пригласил тебя в семью Ивановых. Посмотреть дерево?» (existing Phase B Welcome banner)
3. Tap → tree view с Артёма tree displayed (existing)
4. **NEW Phase C step** — popup: «Найти других знакомых в Rodnya по контактам?»
5. «Разрешить» → phone book scan → matches shown
6. Per-match choice (родственник либо друг)
7. Семья tier + друзья tier populated automatically
8. Mama happy — calls Артёма, sees feed, не stuck в wizard wall

**Improvement vs Phase B alone**: mama gets full social network active immediately, не just one семя.

### 4.2 Journey 2 — Артём adds friend manually

1. Артём opens app
2. Bottom nav → «Друзья» (новый tab либо section в settings)
3. Tap «Добавить друга» FAB
4. Form:
   - Имя: Маша Петрова
   - Телефон: +7 (912) 222-33-44
   - Заметка: «работа, проект X»
   - Группа: «работа»
5. Save → friend appears в list
6. Если матчит Rodnya user → «Маша в Rodnya, отправить запрос?» (optional bilateral)

### 4.3 Journey 3 — Quick call к non-friend

1. Артём wants to call Маша (друг)
2. Bottom nav → «Друзья» → tap Маша
3. Friend details screen: photo + phone + groupTags + actions
4. Tap «Позвонить» → call initiated (uses existing call infrastructure)
5. Tap «Чат» → chat opens (uses existing chat infrastructure)
6. No tree required — Маша lives только в friend list

### 4.4 Journey 4 — Mixed feed browsing

1. Артём opens app → feed (default tab)
2. Sees:
   - Tree post от мамы («новое фото дяди Коли») — семья tier
   - Photo post от Маши («с конференции») — друзья tier
   - Memory: «3 года назад с друзьями универ» — auto-resurfaced
3. Tap photo → album view → all photos featuring person
4. Tap person tag → either семя tree (if родственник) либо friend details (if друг)

### 4.5 Journey 5 — Friend promotes к family

1. Артём has Маша в friends. Discovers Маша — троюродная сестра.
2. Tap Маша → friend details → «...» menu → «Это родственник, добавить в семью»
3. Семя add flow opens (existing Phase B)
4. Маша теперь appears в both friend list (legacy) и семя (new). UI shows «в семье» badge.
5. Optional «убрать из друзей» если duplicate confusing.

### 4.6 Journey 6 — Photo album from past

1. Артём ищет photo с дядей Колей с отпуска 2024
2. Search bar: «дядя Коля 2024»
3. Auto-filtered album shown
4. Tap photo → full view → all metadata (date, location, people tagged, original post)
5. Memory: «вспомни этот день» — surfaces full event posts

---

## 5. Migration plan

### 5.1 Existing data (post Phase B Week 8)

К Phase C kickoff (~2026-08-01):
- ~70-200 users migrated к семя model (Phase B completion)
- ~15-50 семей created (depending на adoption)
- Trees bound к семя
- Posts existing с current visibility model

### 5.2 Migration steps

#### Step 5.2.1 — Friend collection bootstrap
- Add `friends` collection к state document (empty per user)
- No data to migrate — друзья tier is new
- Backend: extend store with friend entity + endpoints

#### Step 5.2.2 — Feed audience extension
- Existing posts retain current visibility (семя-bound либо global)
- New posts gain audience selector
- Backwards compat: posts без explicit audience → семья tier default

#### Step 5.2.3 — Phone book opt-in
- New onboarding step добавлен (post wizard либо в settings)
- Existing users see banner: «Найти других знакомых в Rodnya?»
- Per-user opt-in, не auto-scan

#### Step 5.2.4 — Feature flag staged rollout
- `RODNYA_FRIENDS_ENABLED` env var
- Phase C Week 6: dev environment enable
- Phase C Week 7: 10% production rollout
- Phase C Week 8: 100% rollout либо rollback

### 5.3 Backwards compat

- Old clients without Phase C support: friend tier hidden, семя tier unchanged
- Backend serves both API surfaces temporarily (~3 month sunset)
- Mobile app gradual rollout — web first, mobile after testing

---

## 6. Implementation phases (8 weeks Phase C)

### Week 1 — Backend Друзья entity
- friend collection в store
- 5 endpoints (POST/GET/PATCH/DELETE/PROMOTE)
- Phone hashing utilities
- Tests (~30 cases)

### Week 2 — Phone book integration backend
- Match endpoint (hashed phone vs Rodnya users)
- Permission gate / privacy guardrails
- Rate limiting (avoid scraping)
- Tests (~20 cases)

### Week 3 — Frontend Друзья tier (basic)
- Bottom nav «Друзья» entry либо section
- Friend list screen
- Add friend form
- Friend details (photo, phone, notes, groupTags)
- Soft-delete + 30d restore (Q4a pattern)

### Week 4 — Friend graph (basic viz)
- Minimal cluster visualization (groupTags as clusters)
- Не tree DAG — different from family tree
- Optional toggle, hidden empty
- Defer advanced graph (force-directed) к Phase C+1

### Week 5 — Feed unification
- Audience selector на post composer
- Feed filter tabs (Все / Семья / Друзья / custom)
- Backwards compat для existing posts
- Tests (visibility coverage)

### Week 6 — Albums organized by people
- Person tag aggregation
- Album auto-creation
- Album view (all posts featuring person)
- Memory surfacing («3 года назад»)

### Week 7 — Search + memory features
- Search bar accepts «дядя Коля 2024» либо «друзья работа»
- Backend search index (либо leverage existing)
- Memory feed entries (date-based resurfacing)

### Week 8 — Polish + staged rollout
- mama-friendly UX iteration
- Performance pass (большие friend lists)
- 10% production rollout
- Observation week
- 100% rollout либо rollback

---

## 7. Risk assessment

| Risk | Severity | Mitigation |
|---|---|---|
| Privacy backlash from phone book scan | 🟠 Medium | Opt-in only, hashed phones, clear copy, revocable permission |
| Scope creep (friend graph rabbit-hole) | 🟠 Medium | Defer advanced viz к Phase C+1, ship minimal cluster first |
| Tree-first identity erosion | 🟡 Low (per Артёма «не fail») | Position tree as power feature, друзья as separate tier |
| Migration complexity | 🟠 Medium | Additive (no existing data touched), feature flag staged |
| Backwards compat (mobile lag) | 🟡 Low | Web-first rollout, mobile follows |
| WhatsApp commodity drift | 🔴 High | Strict positioning discipline, tree retains central identity in Семья tier, friend tier explicit secondary |
| Friend list explosion (1000s of contacts) | 🟡 Low | Per-user limit либо tiered storage, search-first UI |
| Bilateral friend status complexity | 🟡 Low | Simple model: «взаимный друг» badge if both added. No friend requests/accepts needed. |
| Albums tagging accuracy | 🟠 Medium | User-driven tags via Phase 3 existing person references. Auto-detect deferred. |

---

## 8. Out of scope (Phase C+1 либо deferred)

- **Public sharing** — posts oriented к private круг, не public broadcast
- **Group chats внутри Круга** — existing chat system already supports
- **Calendar/events integration** — Phase D либо later
- **Voice messages enhancement** — existing voice messaging works
- **Stories** — already exists, no integration needed
- **Public profile pages** — privacy-first positioning excludes this
- **Monetization (ads, subscriptions)** — strategic decision, не technical
- **Federation across instances** — single-instance backend
- **Advanced friend graph algorithms** — closeness scoring, community detection — Phase C+1
- **Cross-Rodnya friend visibility** — if Маша в both Артёма's и Петра's friend lists, do they see each other? Default: no (privacy preservation). Phase C+1 consider explicit «cross-introduction» feature.

---

## 9. Decision questions для Артёма (pre-Phase C)

### Q1 — Friend tier ownership

User имеет single friend list (current proposal) либо multiple lists (mirror Семя «multiple семей»)?

- **Single list**: simpler, friends categorized by groupTags
- **Multiple lists**: «Универ друзья», «Работа коллеги», parallel к семей
- **Recommend**: single list с groupTags. Multiple lists adds complexity без clear value (groupTags handle clustering).

### Q2 — Phone book scan timing

When prompt user для phone book permission?

- Onboarding (after Phase B wizard): immediate exposure, mama might be overwhelmed
- Deferred to first call/chat attempt: contextual but adds friction
- Settings only: explicit opt-in, slowest discovery
- **Recommend**: onboarding skippable banner + settings always available. Mama can defer.

### Q3 — Friend «закрытость» / privacy

Default friend visibility:
- **Private** (current proposal): friend list visible только к owner. Friends don't know they're friends.
- **Bilateral confirmed**: friends see each other's friend status, no list visibility
- **Public круг**: friends see whole list of mutual connections
- **Recommend**: private default с opt-in bilateral confirmation. Mama-friendly.

### Q4 — SMS invite copy ownership

SMS invite text:
- **Personalized**: «{InviterName} приглашает тебя в Rodnya» — feels human
- **Generic**: «Скачай Rodnya — приложение для семьи» — feels spam
- **Hybrid с control**: user can edit SMS text per-invite
- **Recommend**: personalized с fixed template, no edit (prevents misuse, spam, fraud).

### Q5 — Friend graph default visibility

Friend graph (Week 4):
- **Always shown в друзья tab**
- **Hidden by default, expand on tap**
- **Disabled below 10 friends threshold**
- **Recommend**: hidden until tap, disabled при <5 friends.

### Q6 — Feed audience default

When posting, default audience:
- **Вся семья**: family-first default, conservative
- **Все** (семья + друзья): максимально inclusive
- **Last used**: remembers user preference per session
- **Recommend**: last-used с initial default = «Вся семья». User explicit control on first post.

### Q7 — Cross-tier promotion (друг → родственник)

When user promotes friend к семя:
- **Remove from friend list**: clean (no duplication)
- **Keep in both**: legacy preserved, шев semantic redundancy
- **User choice**: ask «оставить в друзьях?» при promotion
- **Recommend**: user choice. Mama might want both initially, can clean up позже.

### Q8 — Existing user migration к friend tier

For existing 70+ users с only семя tier today:
- **No friend list pre-populated**: user adds friends from scratch
- **Suggest «найти друзей в Rodnya»**: prompt phone book на first login post Phase C rollout
- **Pre-populate matched users**: existing matched contacts auto-suggested
- **Recommend**: prompt suggestion (option 2) — explicit user choice, не silent auto-add.

---

## 10. Competitor analysis (PENDING)

### 10.1 Why this section pending

Артём's request: «competitor rodnya.app strategic response — brainstorm session нужен». Артёма investigation pending (this draft без access к rodnya.app site).

### 10.2 Hypotheses (без data)

`rodnya.app` could be:
- **Direct competitor**: same name, same positioning (family tree + chat). High threat.
- **Adjacent product**: same name, different positioning (genealogy либо messaging). Medium threat.
- **Parking domain / squatter**: held for sale либо future launch. Low immediate threat.
- **Foreign launch**: international company using «Rodnya» trademark. Variable threat depending на jurisdiction.

### 10.3 Research questions для Артёма

When Артём investigates rodnya.app:

1. **What they offer**: family tree? genealogy? messaging? combination?
2. **Positioning copy**: marketing language used. «семейная сеть» либо «генеалогия» либо «мессенджер»?
3. **Founder/company**: russian startup? international? backed by кем?
4. **Trademark status**: registered «Родня» товарный знак где?
5. **Domain/branding**: rodnya.app vs Артёма rodnya-tree.ru — different brand or attempt confusion?
6. **Pricing model**: free? freemium? subscription?
7. **Mobile apps**: existing iOS/Android apps? screenshots?
8. **Differentiation opportunity**: что они не делают, что Артём может?

### 10.4 Strategic responses (matrix — fill после competitor data)

| Competitor scenario | Артёма response option |
|---|---|
| Direct competitor с family tree focus | Differentiate via «Круг» concept (Phase C) + speed of execution |
| Genealogy-only focus | Lean into family-as-living-experience (current direction) |
| Messaging-only | Lean into tree + albums combination (current direction) |
| Squatter / parked | Focus on execution, ignore (low threat) |
| International / foreign company | Trademark защита через российские каналы. RuStore presence. |

### 10.5 Action items pending Артёмов research

- [ ] Screenshot rodnya.app landing page
- [ ] Capture positioning copy verbatim
- [ ] Identify founder/company через WHOIS либо site footer
- [ ] Check trademark status (рос. реестр, USPTO)
- [ ] Sign up для their product если possible — see flow firsthand
- [ ] Compile findings, add к этому doc Section 10.6

### 10.6 Findings (PENDING Артёмов research)

_To be filled by Артём + Claude после rodnya.app investigation._

---

## 11. Принято

- **Brainstorm**: Артём + Claude, 2026-05-26
- **Source evidence**: real-user feedback (мама + Степа) + Артёма positioning statements
- **Vision direction**: «personal information hub с relationship structure», anti-Telegram positioning
- **Architecture**: «Круг» model — Семья (Phase B) + Друзья (Phase C) tiers + Feed unification
- **Phase C timeline**: 8 weeks после Phase B Week 8 done (~2026-08-01 kickoff)
- **Privacy stance**: opt-in phone book scan с hashed numbers, revocable permission
- **Доминирующий tier**: Семья (tree-first preserved). Друзья = supporting secondary tier.
- **Decision answers pending**: 8 questions Section 9 awaiting Артёмов sign-off
- **Competitor analysis**: pending Артёмов rodnya.app research

**Doc status**: design proposal awaiting Артёмов sign-off перед Phase C kickoff. Открытые вопросы Section 9 + Competitor data Section 10 решить first.

Когда Артём confirms direction + completes competitor research → доcument finalized + Phase C kickoff dispatched (~2026-08-01 либо когда Phase B Week 8 done).

---

_End of CIRCLE-EXTENSION-PROPOSAL.md_
