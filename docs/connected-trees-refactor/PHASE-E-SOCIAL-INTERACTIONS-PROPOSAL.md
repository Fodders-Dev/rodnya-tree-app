# Phase E — Social Interactions Proposal

> **Status**: design proposal, awaiting Артёмов sign-off
> **Brainstorm**: Артём + Claude, 2026-05-26
> **Source vision**: Артёма statement о опросниках + приглашениях с RSVP + календарном координированиeс семьями
> **Prerequisite**: Phase C kickoff (feed unification ready) — Phase E builds on feed audience model
> **Estimated timeline**: 4-5 weeks Phase E work
> **Strategic positioning**: retention features + family coordination utility

---

## 1. Context

### 1.1 Артёма vision (brainstorm verbatim 2026-05-26)

> «Ввести в [ленту] опросники, приглашения, чтобы можно было семьи распрашивать что-то или приглашать куда-то и знать какое время лучше, куда приходить и придет ли гость...»

### 1.2 Use cases identified

**Опросники (polls)**:
- «Когда удобно встретиться в выходные?» (time-of-day selection)
- «Что приготовить на дачу?» (multiple choice voting)
- «Кто приедет на свадьбу?» (yes/no/maybe)
- «Какой подарок маме на день рождения?» (open-text suggestions)

**Приглашения (event invitations)**:
- «Шашлык на даче, суббота 5 июля, 14:00. Кто будет?»
- «День рождения папы, 12 сентября. Место: ресторан X»
- «Семейная встреча на майские. 1-10 мая, дача в Подмосковье»

**RSVP coordination**:
- «Кто придёт?» tracking
- «Сколько человек?» (для resource planning — еда, спальные места)
- «Кто что приносит?» (потluck coordination)
- Reminders before event

### 1.3 Strategic insight

Phase E = **retention + utility layer**. Phase A/B/C/D built personal memory hub. Phase E adds **active coordination**:

- Users return к app не только для memory browse, но для **active planning**
- Семейные events drive engagement (birthdays, anniversaries, gatherings)
- RSVP utility competes с group chat coordination (which loses in scrollback)
- Calendar-light feature without becoming Google Calendar competitor

### 1.4 Competitor landscape

| App | Polls | Events | RSVP | Family-scoped |
|---|---|---|---|---|
| Telegram | ✅ Basic | 🟡 Manual via chat | ❌ | ❌ |
| WhatsApp | ✅ Basic | ❌ | ❌ | ❌ |
| Facebook Events | ❌ | ✅ Strong | ✅ Yes/Maybe/No | ❌ (public-ish) |
| Doodle | ❌ | 🟡 Time scheduling | ❌ | ❌ |
| Google Calendar | ❌ | ✅ Strong | ✅ | ❌ |
| **Rodnya target** | **✅ Family-scoped** | **✅ Family-scoped** | **✅ Smart RSVP** | **✅ Семья/друзья tier** |

**Differentiation**: family-scoped events с relationship-aware audience targeting + integration с tree (invite via «вся семья мамы» macro).

### 1.5 Real-user motivation

- **Артёмов explicit ask** about coordination utility
- **Семейные events** are universal — every family has birthdays, holidays, gatherings
- **Currently scattered** — поиски «когда удобно» через WhatsApp групповой чат каждый раз
- **Memory integration** — events become memories post-fact (Phase D synergy)

---

## 2. Problem statement

### 2.1 Coordination friction в current apps

Family event coordination сейчас:
1. Someone proposes event via group chat
2. People reply: «можно», «не уверен», «когда?»
3. Chat scrollback loses information
4. Organizer manually tallies replies
5. Reminders sent manually либо forgotten
6. Day-of: «во сколько?», «где?» repeated questions

This pattern is **broken**. Each family event = hours of coordination friction.

### 2.2 Polls limitations в commodity apps

Telegram/WhatsApp polls:
- Anonymous либо public (binary, не nuanced)
- No multiple-time-slot selection
- No threading/discussion
- Get buried в scrollback
- Don't integrate с calendar либо reminders

### 2.3 Rodnya gaps к fill

Need:
- **Family-scoped polls** (relationship-aware audience)
- **Time-slot polls** («когда удобно?»)
- **Event с RSVP** (yes/maybe/no + headcount)
- **Reminders** (day-before, hour-before)
- **Place coordination** (map link, address, photos)
- **Bring-list coordination** («кто что приносит»)
- **Post-event memory** (photos auto-suggested к event memory)

---

## 3. Proposed architecture

### 3.1 Two primary entities

```
Phase E core entities
├── Poll
│   ├── Question (text)
│   ├── Options (single-choice / multiple-choice / time-slot / open-text)
│   ├── Audience (семья / друзья / specific users)
│   ├── Privacy (anonymous votes / public votes)
│   ├── Expiry (close at time X)
│   └── Results (aggregated либо per-user)
└── Event
    ├── Title + description
    ├── Date/time (single либо range)
    ├── Location (address, map link, optional photo)
    ├── Audience (семья / друзья / specific users)
    ├── RSVP responses (yes/maybe/no + headcount)
    ├── Bring-list (optional, per-item coordination)
    ├── Reminders (day-before, hour-before configurable)
    └── Post-event link (photos, memory prompts)
```

### 3.2 Poll entity schema

```javascript
{
  id: uuid,
  authorUserId: uuid,
  semyaId: uuid | null,  // bound to семя если family poll
  audienceUserIds: uuid[],  // explicit list либо derived from семя
  audienceTier: 'family' | 'friends' | 'specific',
  
  question: string,
  type: 'single_choice' | 'multiple_choice' | 'time_slot' | 'open_text',
  options: [
    {
      id: uuid,
      label: string,  // «суббота 14:00» либо «шашлык» либо «подарок мама»
      metadata: object | null  // {time: ISO} для time_slot, etc.
    }
  ],
  
  privacy: 'anonymous' | 'public',  // anonymous = aggregated counts only, public = per-user visible
  closesAt: timestamp | null,
  
  responses: [
    {
      userId: uuid,
      optionIds: uuid[],  // for multiple_choice
      openText: string | null,  // for open_text type
      submittedAt: timestamp
    }
  ],
  
  createdAt: timestamp,
  updatedAt: timestamp,
  hardDeleteScheduledAt: timestamp | null
}
```

### 3.3 Event entity schema

```javascript
{
  id: uuid,
  organizerUserId: uuid,
  semyaId: uuid | null,
  
  title: string,
  description: string | null,
  
  startAt: timestamp,
  endAt: timestamp | null,
  isAllDay: boolean,
  
  location: {
    address: string | null,
    mapUrl: string | null,
    photoUrl: string | null,
    coordinates: {lat: number, lng: number} | null
  },
  
  audienceUserIds: uuid[],
  audienceTier: 'family' | 'friends' | 'specific',
  
  rsvps: [
    {
      userId: uuid,
      status: 'yes' | 'maybe' | 'no' | 'no_response',
      headcount: number,  // включая self (1 = просто я, 3 = со мной 2 человека)
      responseNote: string | null,
      respondedAt: timestamp
    }
  ],
  
  bringList: [
    {
      id: uuid,
      itemName: string,
      assignedUserId: uuid | null,
      addedByUserId: uuid,
      notes: string | null
    }
  ] | null,
  
  reminders: {
    dayBefore: boolean,
    hourBefore: boolean,
    custom: timestamp[] | null
  },
  
  postEventMemoryPrompt: boolean,  // suggest memory prompt после event
  
  createdAt: timestamp,
  updatedAt: timestamp,
  hardDeleteScheduledAt: timestamp | null
}
```

### 3.4 Endpoints

#### Polls
- `POST /v1/polls` — create poll
- `GET /v1/me/polls` — my polls (authored + audience я в)
- `GET /v1/polls/:id` — poll details
- `POST /v1/polls/:id/respond` — submit response
- `PATCH /v1/polls/:id/close` — close early (author only)
- `DELETE /v1/polls/:id` — soft-delete (author only)

#### Events
- `POST /v1/events` — create event
- `GET /v1/me/events` — my events (organizer + invited)
- `GET /v1/events/:id` — event details
- `POST /v1/events/:id/rsvp` — submit RSVP
- `POST /v1/events/:id/bring-list` — add bring-list item
- `PATCH /v1/events/:id/bring-list/:itemId` — claim либо update item
- `PATCH /v1/events/:id` — edit event (organizer only)
- `DELETE /v1/events/:id` — cancel event (organizer only)

### 3.5 UI integration

**Composer extension** (feed post composer extends):
```
What's on your mind?
[text input]

[📷 Photo]  [📊 Poll]  [📅 Event]  [Send]
```

Tap «📊 Poll» либо «📅 Event» → branches into respective creation flow.

**Feed entry types** extend:
- Existing: text post, photo post, video post
- New: poll post, event invitation post

Polls/events render как rich cards в feed:

```
┌─────────────────────────────────┐
│  Артём • 2 ч назад              │
│                                 │
│  📊 Когда соберёмся на даче?    │
│                                 │
│  ○ Суббота 5 июля 14:00 (3✓)   │
│  ● Воскресенье 6 июля 12:00 (5✓)│
│  ○ Не получится (1)             │
│                                 │
│  9 ответов • до 1 июля          │
└─────────────────────────────────┘
```

```
┌─────────────────────────────────┐
│  Артём • 2 ч назад              │
│                                 │
│  📅 Шашлык на даче              │
│  Суббота 6 июля, 14:00          │
│  📍 Дача (пос. Сосновка)        │
│                                 │
│  Пойдут: 5  Может: 2  Нет: 1   │
│                                 │
│  [Я пойду]  [Может быть]  [Нет]│
└─────────────────────────────────┘
```

### 3.6 Notifications

- **Poll created** → audience notified «Артём добавил опрос: {question}»
- **Poll closes soon** → reminder 24h before closesAt
- **Event RSVP changes** → organizer notified
- **Event reminder** day-before + hour-before (per event config)
- **Event cancellation** → audience notified

### 3.7 Memory integration (Phase D synergy)

Post-event:
- Auto-suggest memory prompt: «Расскажи об этом дне» (24h после event ends)
- Auto-create album: «Шашлык 6 июля 2025» с tagged photos
- Surface в feed как memory: «Год назад: шашлык на даче»

---

## 4. User journeys

### 4.1 Journey 1 — Артём creates poll «когда собираемся?»

1. Feed → tap composer → tap «📊 Poll»
2. Form:
   - Question: «Когда удобно собраться на даче?»
   - Type: time_slot
   - Options: 3 dates added («Сб 5 июля 14:00», «Вс 6 июля 12:00», «Пн 7 июля 18:00»)
   - Audience: «Вся семья»
   - Closes: 1 июля 23:59
3. Save → poll posted к feed
4. Семья receives push «Артём добавил опрос»
5. Каждый votes
6. Артём sees realtime results aggregated

### 4.2 Journey 2 — Бабушка votes (mama-friendly)

1. Бабушка opens app, sees feed
2. Poll card appears с large touch targets
3. Reads question via text либо TTS (Phase D synergy)
4. Taps option «Воскресенье 6 июля 12:00»
5. ✓ checkmark animation confirms
6. Card updates с current count

### 4.3 Journey 3 — Артём creates event

1. Feed → composer → «📅 Event»
2. Form:
   - Title: «Шашлык на даче»
   - Date: Saturday 6 July 14:00
   - Location: «Дача (пос. Сосновка)» + map link auto-suggested
   - Audience: «Вся семья + друзья универ» (selectable circles)
   - Bring list: enabled
   - Reminders: day-before + hour-before
3. Save → event posted
4. Audience receives push + email (optional)
5. RSVP responses come в

### 4.4 Journey 4 — Bring-list coordination

1. Артём opens event
2. Bring-list section: «Что взять?»
3. Tap «Добавить» → «Мангал» — claimed by Артёма
4. Тётя Маша sees event → opens → bring-list shows «Мангал ✓ Артём»
5. Тётя Маша adds «Шашлык» — claimed by себя
6. Others see realtime updates
7. Coordination без чатового шума

### 4.5 Journey 5 — Reminder + post-event memory

1. Day before event: notification «Завтра шашлык на даче в 14:00»
2. 1 hour before: notification «Через час шашлык. Адрес: ...»
3. После event (24h later): notification «Как прошёл шашлык? Расскажи»
4. Tap → memory prompt («Что было интересно?», «Кто пришёл?»)
5. Optional voice answer + photos
6. Auto-album «Шашлык 6 июля 2025» created
7. Год спустя: memory feed «Год назад: шашлык на даче»

### 4.6 Journey 6 — Friend event (мама invites all family + close friends)

1. Мама creates event «день рождения папы»
2. Audience: «Вся семья» + «Близкие друзья» (multiple groupTags)
3. RSVP tracking + bring-list shared
4. Post-event memories preserved

---

## 5. Implementation phases (4-5 weeks)

### Week 1 — Backend polls
- Poll entity + endpoints
- Response submission logic
- Audience resolution (reuse Phase C audience logic)
- Notification dispatch
- Tests

### Week 2 — Backend events + RSVP
- Event entity + endpoints
- RSVP tracking
- Bring-list logic
- Reminder scheduling (extends notification infrastructure)
- Tests

### Week 3 — Frontend polls
- Composer poll button
- Poll creation form (4 types: single/multi/time/open-text)
- Poll rendering в feed
- Vote interaction
- Results visualization

### Week 4 — Frontend events
- Composer event button
- Event creation form
- Event card rendering в feed
- RSVP UI (Я пойду / Может / Нет + headcount picker)
- Bring-list UI
- Map integration (existing либо deeplink)

### Week 5 — Polish + memory integration
- Reminders system
- Post-event memory prompts (Phase D integration)
- Auto-album creation после event
- A/B test engagement
- 10% production rollout
- Observation week
- 100% rollout

---

## 6. Risk assessment

| Risk | Severity | Mitigation |
|---|---|---|
| Polls spam (too many polls) | 🟡 Low | Per-семья rate limit (e.g., 1 poll per day per user) |
| Event privacy leak (location, photos) | 🟠 Medium | Per-event audience strict, no public sharing |
| RSVP fatigue (constant invites) | 🟡 Low | Per-user mute event-invites option, frequency limits |
| Calendar competitor drift | 🟠 Medium | Stay focused на семейные events, не general calendar |
| Bring-list conflicts (2 users claim same) | 🟡 Low | Last-write-wins либо «contested» state UI |
| Reminder notification fatigue | 🟠 Medium | Configurable per event, smart defaults |
| Location privacy (sharing address) | 🟡 Low | Audience-scoped (семя only), opt-in map share |
| Time zone confusion | 🟠 Medium | Display events в user's timezone, organizer's TZ stored |
| Event cancellation grief | 🟡 Low | Clear «event cancelled» notification + reason field |
| Anonymous poll abuse | 🟡 Low | Author can disable anonymous if needed |

---

## 7. Out of scope (Phase E+1 либо deferred)

- **Full calendar app** — focus on event coordination, не calendar replacement
- **Cross-семья polls** — polls bounded к single семя либо friend list, не cross-tier
- **Event ticketing/payment** — out of scope (стриптокол free-only)
- **Group video calls для event** — existing call system serves
- **Repeat events** (weekly, monthly) — Phase E+1 feature
- **Calendar sync (Google, Apple)** — Phase E+1 if needed
- **Event public sharing URL** — privacy-first, no public events
- **Live event streaming** — out of scope
- **Polls с photo options** — text options first, photos Phase E+1
- **AI suggestions для poll questions** — premature
- **Sentiment analysis на open-text** — too invasive

---

## 8. Decision questions для Артёма (pre-Phase E)

### Q1 — Poll default privacy

- **Anonymous default** (private votes, aggregated only)
- **Public default** (voters visible)
- **Author choice each poll**

**Recommend**: author choice each poll, default «anonymous» for sensitive questions, «public» для casual coordination. UI prompts «показать кто как проголосовал?» при создании.

### Q2 — Event RSVP granularity

- **Simple**: Yes / No
- **Standard**: Yes / Maybe / No (current proposal)
- **Detailed**: Yes / Maybe / No / Late / Early leave / Unsure

**Recommend**: Standard (Yes/Maybe/No) + optional headcount + optional note. Simple enough для mama, detailed enough для planning.

### Q3 — Bring-list visibility

- **Always shown** (default visible if enabled)
- **Optional toggle per event**
- **Always hidden until requested**

**Recommend**: optional toggle per event, default OFF (don't add complexity к simple events).

### Q4 — Reminder defaults

- **Day-before + hour-before** (current proposal, balanced)
- **Hour-before only** (minimal)
- **Configurable per event** (max control)

**Recommend**: day-before + hour-before defaults, configurable per event.

### Q5 — Time-slot poll vs separate event

- **Time-slot poll auto-creates event** when most-voted option crosses threshold
- **Manual conversion** (organizer таps «создать event from результат»)
- **Separate features always**

**Recommend**: manual conversion. Organizer reviews results, taps «создать event», pre-filled с winning option. User control.

### Q6 — Cross-семья events

- **Allowed** (audience can include multiple семей + friends)
- **Limited к single семя** (simpler)
- **Allowed но clear UX warning**

**Recommend**: allowed, audience selector shows all available круг с individual tier toggling. Mama-friendly с clear preview «приглашены 12 человек».

### Q7 — Bring-list integration с external lists (Wishlist, Amazon)

- **Internal only** (текст items)
- **External links allowed** (Amazon, marketplaces)
- **Wishlist integration** (Phase E+1)

**Recommend**: internal text only initially. External links Phase E+1.

### Q8 — Anonymous poll vote visibility к author

- **Author sees aggregated only** (true anonymous)
- **Author sees per-user** (semi-private)
- **Per-poll choice** (author decides upfront)

**Recommend**: true anonymous (aggregated only к author too). If author needs per-user knowledge, they should use public poll explicitly.

---

## 9. Phase E + Phase D + Phase C integration

Phase E **builds on**:
- **Phase C feed audience** — polls/events use same audience model (семья / друзья / specific)
- **Phase D memory prompts** — post-event auto-prompts «расскажи об этом дне»
- **Phase B семя relationships** — audience targeting via «вся семья X»

Phase E **enables**:
- Better feed content (polls/events more engaging than static posts)
- Active coordination utility (returns users daily)
- Memory creation via events (Phase D synergy)

**Implementation order**:
- Phase E mostly orthogonal к Phase B/D backend
- Frontend depends на Phase C feed unification (audience selector)
- Recommend: Phase E after Phase C Week 5 (feed unified)

---

## 10. Strategic positioning

Phase E completes Rodnya's **engagement loop**:

```
Phase A — Calls (real-time talking)
Phase B — Семья tree (relationship structure)
Phase C — Круг + feed (information aggregation)
Phase D — Memory prompts (preservation)
Phase E — Polls/Events (active coordination) ← THIS
```

After Phase E: Rodnya covers entire spectrum от real-time interaction (calls) → coordination (events) → memory preservation (Phase D) → relationship structure (tree).

**No single competitor** covers all 5 dimensions. Strategic moat = comprehensive personal hub.

---

## 11. Принято

- **Brainstorm**: Артём + Claude, 2026-05-26
- **Source vision**: Артёма «опросники + приглашения с RSVP + время + место + кто придёт»
- **Strategic positioning**: retention + utility layer completing engagement loop
- **Phase E timeline**: 4-5 weeks, after Phase C Week 5 (feed audience model ready)
- **Two entities**: Poll + Event с shared audience model
- **Memory integration**: post-event prompts via Phase D
- **Decision answers pending**: 8 questions Section 8 awaiting Артёмов sign-off

**Doc status**: design proposal awaiting Артёмов sign-off перед Phase E kickoff. Открытые вопросы Section 8 решить first.

Phase E completes 5-phase product vision: calls → tree → круг → memory → coordination. Comprehensive personal information hub positioning.

---

_End of PHASE-E-SOCIAL-INTERACTIONS-PROPOSAL.md_
