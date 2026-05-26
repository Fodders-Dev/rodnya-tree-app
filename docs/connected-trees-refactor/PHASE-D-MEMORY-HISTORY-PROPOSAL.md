# Phase D — Family History & Memory Proposal

> **Status**: design proposal, awaiting Артёмов sign-off
> **Brainstorm**: Артём + Claude, 2026-05-26
> **Source vision**: Артёма statement о памяти семьи + interview prompts for elders + voice input для accessibility
> **Prerequisite**: Phase C kickoff либо parallel track (Phase D mostly orthogonal to Phase B/C — profile/memory layer)
> **Estimated timeline**: 4-6 weeks Phase D work
> **Strategic positioning**: **strongest competitive moat** — generation-bridging memory preservation

---

## 1. Context

### 1.1 Артёма vision (brainstorm verbatim 2026-05-26)

> «Надо будет почистить и расширить редактирование профиля. Чтобы было удобно заполнять о себе информацию.»

> «Мб какие вопросы спросить у своих бабушек дедушек пока они живы (я такую фишку видел на маркетплейсах, они там книжки такие продают, вот и нам бы сподвигать пользователей заполнять информацию о своих родных).»

> «Мб завести туда какой голосовой ввод, чтобы было удобнее заполнять информацию, а не ручками все писать.»

### 1.2 Strategic insight

«Книжки про бабушек/дедушек» на маркетплейсах — это growing market segment. Examples:
- «Расскажи о себе, дедушка» / «Расскажи о себе, бабушка» — printable books с 100+ questions
- «Story of My Life» / «Living History» — international equivalents
- Memory journals, life story interview templates

**Market signal**: families WANT to preserve grandparent stories, but physical books are:
- Manual writing burden (elders often hands shaking, vision weak)
- One-copy artifact (lost if physical book damaged)
- Static (no audio/video)
- Hard to share (digitize manually?)
- No structured organization

**Rodnya opportunity**: digital implementation solves все these:
- Voice input — elders speak, не пишут
- Permanent storage — replicated, recoverable
- Multimedia — audio + photos + video с questions
- Shareable instantly с круг
- Auto-organized by person, theme, date

### 1.3 Competitive moat analysis

| Competitor | Family tree | Living memory | Voice capture | Inter-generational prompts |
|---|---|---|---|---|
| MyHeritage | ✅ Strong | 🟡 Bio fields | ❌ | ❌ |
| FamilySearch | ✅ Strong | 🟡 Memories tab | 🟡 Audio upload | ❌ |
| Ancestry | ✅ Strong | 🟡 Stories feature | 🟡 Audio upload | ❌ |
| Telegram/WhatsApp | ❌ | ❌ | 🟡 Voice messages | ❌ |
| Print «life story» books | ❌ | ✅ Static | ❌ | ✅ Pre-written |
| **Rodnya target** | **✅ via Phase B** | **✅ via Phase D** | **✅ via Phase D** | **✅ via Phase D** |

**No competitor unifies all 4 dimensions.** Rodnya could be first.

### 1.4 Real-user motivation (existing brainstorm evidence)

- **Мама** wants family memory preservation (Артёма observation про «альбомы семьи» в feed)
- **Степа** likely too (silent quit suggests engagement gap — content prompt could re-engage)
- **Future users**: «бабушка может рассказать историю войны voice-only, мы храним в Rodnya, дети слушают через 50 лет»

This is **generational value proposition** — Rodnya для families, not individuals.

---

## 2. Problem statement

### 2.1 Profile editing current state

(To be verified pre-implementation — assumed based on prior audit observations.)

- Profile fields likely сейчас: имя, фамилия, телефон, email, photo
- «О себе» либо bio field — limited либо absent
- Photos: avatar only либо basic gallery
- No structured biography
- No prompt-driven entry (user must figure out что писать)
- No voice input — text only

### 2.2 Memory capture gaps

- No interview-style prompts («Расскажи о своих родителях», «Какой был твой первый дом»)
- No voice answer storage
- No audio preservation (grandparent's actual voice)
- No theme-based organization («военные годы», «детство», «свадьба»)
- No multi-generational sharing UX (kid asks question, grandparent answers через app)
- No reminder/nudge для memory completion ongoing

### 2.3 Elder user accessibility

- Text input difficult для elders (small phone keyboards, shaky hands, weak vision)
- No voice-first UX path
- No large-text mode
- No prompt-driven simplicity (current profile = blank form, intimidating)

---

## 3. Proposed architecture

### 3.1 Three feature pillars

```
Phase D feature pillars
├── Pillar 1 — Profile redesign
│   ├── Structured biography sections
│   ├── Photo gallery с tagging
│   ├── «О себе» free-form + structured fields
│   └── Privacy controls per section
├── Pillar 2 — Memory prompts (interview system)
│   ├── Curated question library (100+ prompts)
│   ├── Theme categories («детство», «семья», «работа», «любовь», «война», ...)
│   ├── Inter-generational prompts (kid sends к grandparent)
│   ├── Answer storage (text + voice + photo combined)
│   └── Auto-organization by theme + date
└── Pillar 3 — Voice input
    ├── On-device STT (privacy-first)
    ├── Cloud STT fallback (Yandex SpeechKit для русский)
    ├── Audio storage (original voice preserved)
    ├── Transcript editing post-recording
    └── Accessibility — large buttons, simple flow
```

### 3.2 Pillar 1 — Profile redesign

#### 3.2.1 Sections schema

Profile splits в structured sections:

```javascript
{
  userId: uuid,
  
  // Basic identity (existing)
  displayName: string,
  photoUrl: string,
  birthDate: date | null,
  
  // Phase D: structured biography
  biography: {
    sections: [
      {
        id: uuid,
        type: 'childhood' | 'family' | 'work' | 'education' | 'love' | 'war' | 'travel' | 'hobby' | 'custom',
        title: string,  // displayed title (RU)
        content: {
          text: string | null,
          audioUrl: string | null,
          transcript: string | null,  // if audio, auto-transcribed
          photoIds: uuid[],
          createdAt: timestamp,
          updatedAt: timestamp
        },
        visibility: 'public_to_круг' | 'family_only' | 'friends_only' | 'specific_users' | 'private',
        specificUserIds: uuid[]  // for 'specific_users' visibility
      }
    ]
  },
  
  // Phase D: completion progress (gamification + nudging)
  biographyCompleteness: {
    sectionsTotal: number,  // available section types
    sectionsFilled: number,
    lastNudgeShownAt: timestamp | null,
    dismissedSections: string[]  // user explicitly said «not interested»
  }
}
```

#### 3.2.2 Profile screen layout

```
┌─────────────────────────────────┐
│  [Photo]  Артём Иванов          │
│           +7 (912) 345-67-89    │
│                                 │
│  📊 Профиль на 35% (3/9 секций) │
│  [Заполнить ещё →]              │
│                                 │
│  📖 Биография                   │
│  ┌─────────────────────────────┐│
│  │ 👶 Детство          [➕]    ││
│  │ 👨‍👩‍👧 Семья           [✏️ 250]││
│  │ 🎓 Образование      [➕]    ││
│  │ 💼 Работа           [✏️ 100]││
│  │ ❤️ Любовь           [skip] ││
│  │ ✈️ Путешествия      [➕]    ││
│  │ 🎨 Хобби             [➕]    ││
│  │ ⚔️ Война            [hidden]││
│  │ ➕ Своя категория            ││
│  └─────────────────────────────┘│
│                                 │
│  📷 Фотогалерея (12 фото)       │
│  [grid 3×3]                     │
└─────────────────────────────────┘
```

Affordances:
- `[➕]` — пустая section, tap to add
- `[✏️ 250]` — filled section с word count, tap to edit
- `[skip]` — user dismissed section, hidden from progress
- `[hidden]` — sensitive category, user explicitly hidden

### 3.3 Pillar 2 — Memory prompts (interview system)

#### 3.3.1 Curated prompt library

100+ pre-written questions organized by theme:

**Theme: Детство**
- Где ты родился? Какой это был город/деревня?
- Расскажи о своем доме в детстве. Как он выглядел?
- Какие были твои любимые игры?
- Кто были твои лучшие друзья в школе?
- Какое твое самое яркое воспоминание из детства?
- Какие праздники ты любил больше всего и почему?
- Что ты обычно делал летом?
- Кто был твоим самым любимым учителем?
- Чем занимались твои родители?
- Какие у тебя были обязанности по дому?

**Theme: Семья**
- Расскажи о своих родителях. Какими они были людьми?
- Какие истории из жизни родителей тебе запомнились?
- Расскажи о своих бабушках и дедушках.
- Какие семейные традиции были в вашей семье?
- Расскажи о своих братьях и сестрах.
- Какой был твой самый запоминающийся семейный праздник?
- Какие рецепты передавались в вашей семье?

**Theme: Работа**
- Расскажи о своей первой работе.
- Чем ты любишь заниматься в работе больше всего?
- Кто был твоим самым важным учителем/наставником?
- Какое достижение в работе ты больше всего ценишь?

**Theme: Любовь**
- Как ты познакомился с супругом/супругой?
- Какой была ваша свадьба?
- Что ты больше всего любишь в своём партнёре?

**Theme: Война** (for elders)
- Где ты был во время войны?
- Какие воспоминания о войне ты хочешь сохранить?
- Расскажи о фронтовиках/тружениках тыла в семье.

**Theme: Путешествия**
- Куда ты ездил отдыхать в детстве?
- Какое путешествие тебе запомнилось больше всего?

**Theme: Хобби**
- Чем ты увлекался в молодости?
- Какие книги ты любил читать?
- Какая твоя любимая музыка?

**Theme: Своя категория** — user-defined custom prompts

#### 3.3.2 Prompt suggestion engine

Backend serves prompts based on:
- Sections user not yet filled
- Age-appropriate themes (war prompts to elder users only)
- Recent activity (after photo upload — «расскажи об этом фото»)
- Seasonal (May 9 → war memories prompts surface)
- Anniversary (user added relative с birthDate → prompt «расскажи о {name}»)

Endpoint: `GET /v1/me/prompts/suggested?limit=5` — returns top 5 prompts user hasn't answered.

#### 3.3.3 Inter-generational prompts

```
┌─────────────────────────────────┐
│  Спросить бабушку               │
│                                 │
│  Выбери вопрос для:             │
│  [Photo] Бабушка Лида           │
│                                 │
│  📖 Темы:                       │
│   • Детство (5 вопросов)        │
│   • Семья (8 вопросов)          │
│   • Война (3 вопроса)           │
│   • ...                         │
│                                 │
│  ИЛИ: задать свой вопрос        │
│  [Написать свой вопрос ✏️]      │
└─────────────────────────────────┘
```

Flow:
1. User taps «Спросить бабушку» в её profile
2. Select theme либо custom question
3. Send → бабушка получает notification «Артём хочет узнать о твоём детстве»
4. Бабушка opens notification → prompt screen с vocal/text answer option
5. Answer saves к её profile + Артём notified «бабушка ответила»

#### 3.3.4 Voice-first answer UX

```
┌─────────────────────────────────┐
│  Вопрос от Артёма:              │
│                                 │
│  «Расскажи о своих родителях.   │
│  Какими они были людьми?»       │
│                                 │
│              🎤                 │
│         [Записать ответ]        │
│                                 │
│  или:                           │
│  [Написать текстом ✏️]          │
│  [Прислать фото 📷]              │
│                                 │
│  [Пропустить пока]              │
└─────────────────────────────────┘
```

Recording flow:
- Tap 🎤 → recording starts immediately (no «press to talk» — too fiddly для elders)
- Visual feedback: audio level indicator, time counter
- [Stop] button large, easy reach
- Auto-transcript appears after recording
- Edit transcript optional (бабушка может ignore if happy with default)
- Save → audio + transcript + linked к prompt + к profile section

### 3.4 Pillar 3 — Voice input

#### 3.4.1 STT (speech-to-text) options

**Option A: On-device STT** (Android: `SpeechRecognizer`, iOS: Speech framework)
- **Pros**: privacy-first (audio stays on device), no cloud cost, works offline
- **Cons**: limited Russian language accuracy, smaller vocabulary, может choke on dialects
- **Mama-test**: works in pure privacy

**Option B: Cloud STT** (Yandex SpeechKit для русский)
- **Pros**: best Russian accuracy, vocabulary trained on Russian dialects, fast
- **Cons**: audio uploaded к Yandex (privacy concern), API cost per minute
- **Cost estimate**: Yandex SpeechKit ~₽0.20 per minute = ~₽1 per typical answer

**Option C: Hybrid (recommended)**
- Try on-device first
- If quality low (confidence threshold) либо user requests, fallback к cloud STT
- User controls в settings — «использовать облако для лучшего распознавания»

**Recommendation: Option C** — privacy default, quality available on-demand.

#### 3.4.2 Audio storage

Audio files preserved separately от transcript:
- Original voice = irreplaceable artifact (бабушкин голос через 50 лет)
- Stored в backend media (existing `/v1/media/upload` infrastructure)
- Format: AAC at 96kbps mono (~700KB per minute)
- Retention: forever (по умолчанию). Backup includes audio.
- Streaming playback: existing audio player widget

#### 3.4.3 Transcript editing

После recording:
1. Transcript displays под audio playback bar
2. User can edit transcript (fix STT errors)
3. Original audio always preserved (transcript = editable layer)
4. Save → both stored

#### 3.4.4 Accessibility features

- **Large buttons** (≥56dp touch targets)
- **High contrast** mode toggle
- **Text-to-speech** для prompt readback (бабушка может listen к question)
- **Slow speech setting** для elderly hearing
- **Larger transcript text** option

---

## 4. User journeys

### 4.1 Journey 1 — Артём interviews бабушку

1. Артём opens бабушкин profile in Rodnya
2. Tap «📖 Биография» section
3. See progress: «25% filled (2/9 секций)»
4. Tap «Спросить бабушку»
5. Select theme «Война» → 3 prompts shown
6. Pick «Где ты была во время войны?»
7. Send → бабушка получает push notification
8. Бабушка opens app → prompt screen
9. Бабушка taps 🎤 → speaks для 3 minutes
10. STT transcribes
11. Бабушка taps «Сохранить» (либо leaves auto-save)
12. Артём notified «бабушка ответила»
13. Артём opens → listens к бабушкиному голосу + reads transcript
14. Forever preserved в her profile, linked к «Война» section

### 4.2 Journey 2 — Бабушка fills profile (self-driven)

1. Бабушка opens app, sees nudge: «Заполнить биографию (25%)»
2. Tap → profile sections list
3. Pick «Детство»
4. Auto-suggested prompts: «Где ты родилась?», «Расскажи о своем доме»
5. Pick «Расскажи о своем доме»
6. Tap 🎤, speaks
7. STT transcribes
8. Saves
9. Next prompt auto-surfaces: «Какие были твои любимые игры?»
10. Бабушка can continue либо stop
11. Section now «📖 Детство ✏️ 1 ответ»

### 4.3 Journey 3 — Мама uploads photo + asks who's in it

1. Мама в feed → uploads photo from her childhood
2. Post composer: «Кто на этом фото?»
3. Tag people via face detection либо manual pick from семя tree
4. Untagged people: prompt «Это твой родственник? Кто это?»
5. Артём sees post → recognizes uncle in photo
6. Tap «дядя Коля?» → confirms tag
7. Photo + identification automatically added к дяди Коли's profile photo gallery
8. Prompt suggested к мама: «расскажи об этом дне» (memory prompt)
9. Optional voice answer

### 4.4 Journey 4 — Generation handoff («сохранить пока живы»)

1. Артём sees nudge: «Бабушка Лида не отвечала 6 месяцев. Хочешь ей задать вопрос?»
2. Tap → prompt suggestions specifically для elders («война», «детство», «свадьба»)
3. Choose 3 prompts via «Курс из 3 вопросов» (mini-program)
4. Бабушка получает 3 prompts spread over week (не overwhelm)
5. Each answer preserved
6. Через 1 year: «Бабушка Лида заполнила 50% биографии. Распечатать книгу?» (premium feature future?)

### 4.5 Journey 5 — Profile completion gamification

1. New user (Степа scenario) opens profile
2. Sees: «Профиль 0% заполнен»
3. Tap → onboarding wizard within profile («Начнём с детства?»)
4. 3-question mini-prompt: имя родителей, место рождения, школа
5. After 3 answers → «10% заполнено, продолжим завтра?»
6. Reminder notification next day («Заполнить ещё немного?»)
7. Gradual completion вместо overwhelm

---

## 5. Migration plan

### 5.1 Existing data

- 70+ users с existing profiles (минимум displayName + photo + birthDate)
- No biography sections currently
- No memory prompts answered

### 5.2 Migration steps

#### Step 5.2.1 — Backfill biography schema
- Each user's profile gets empty `biography.sections: []` + `biographyCompleteness: {sectionsTotal: 9, sectionsFilled: 0}`
- No data loss, additive

#### Step 5.2.2 — Curated prompt library load
- 100+ prompts seeded в backend at deploy time
- Versioned (prompt_v1, prompt_v2 — admin can add позже)
- No user data affected

#### Step 5.2.3 — Voice infrastructure
- Audio upload endpoint (extends existing media upload)
- STT integration (Yandex SpeechKit либо on-device)
- Storage budget planned

#### Step 5.2.4 — Profile screen rewrite
- New profile screen (frontend rewrite, ~30% existing screen replaced)
- Old «edit profile» modal preserved для backward compat либо retired

### 5.3 Backwards compat

- Old client versions: see basic profile fields only, не biography sections
- Backend supports both reads: legacy + Phase D structured
- Gradual mobile rollout

---

## 6. Implementation phases (4-6 weeks Phase D)

### Week 1 — Backend profile schema + prompt library
- Profile.biography.sections data model
- 100+ curated prompts seeded
- `GET /v1/me/prompts/suggested` endpoint
- `POST /v1/me/biography/:sectionId` create/update endpoint
- Tests

### Week 2 — Voice infrastructure
- Audio upload extension в media endpoint
- Yandex SpeechKit integration (либо on-device STT path)
- Transcription endpoint
- Audio storage (s3-compatible либо existing media path)
- Tests

### Week 3 — Frontend profile redesign
- New profile screen layout (sections list, progress badge)
- Section detail view (text + audio + photos combined)
- Edit/add UI per section
- Privacy controls (section-level visibility)

### Week 4 — Memory prompts UI
- «Спросить» button on relative profile
- Prompt suggestion sheet
- Voice answer screen (large buttons, simple flow)
- Transcript editor

### Week 5 — Inter-generational + nudges
- Push notification template («Артём хочет узнать о твоём детстве»)
- Progress nudges («заполнить ещё?»)
- Mini-course UX («3 вопроса за неделю»)
- Reminder logic

### Week 6 — Polish, accessibility, rollout
- Large text mode
- TTS readback для prompts
- A/B test prompt engagement
- 10% production rollout
- Observation week
- 100% rollout либо rollback

---

## 7. Risk assessment

| Risk | Severity | Mitigation |
|---|---|---|
| Voice input STT accuracy для elders | 🟠 Medium | Hybrid on-device + cloud, user can edit transcript |
| Audio storage costs grow unbounded | 🟡 Low | AAC compression + retention policy + premium tier для unlimited |
| Privacy backlash on voice cloud upload | 🟠 Medium | On-device default, cloud opt-in, clear consent |
| Prompt content offensive либо inappropriate | 🟡 Low | Curated library, no user-generated prompts initially, moderation queue для custom |
| Elder user can't navigate UX | 🟠 Medium | Accessibility-first design, mama-test iterations, simple voice-first flow |
| Inter-generational prompts feel intrusive | 🟡 Low | Frequency limits, opt-out, recipient can ignore |
| Profile completion gamification creates pressure | 🟢 Low | Soft nudges only, dismissible, никаких deadlines |
| Multi-language support (Ukrainian, Belarusian) | 🟡 Low | Russian-first, others Phase D+1 |
| Photo face recognition privacy | 🟠 Medium | On-device, opt-in, manual tagging primary |
| Transcript errors lose meaning | 🟡 Low | Audio always preserved, transcript = editable layer |

---

## 8. Out of scope (Phase D+1 либо deferred)

- **Printable book export** — premium feature future (PDF generation, paid tier)
- **Family timeline visualization** — events plotted на shared timeline (Phase E territory possibly)
- **AI-generated prompts** — LLM suggests based на context (privacy + cost concern initially)
- **Video answers** — voice + photo enough для now, video adds storage + complexity
- **Translation between languages** — Russian-first
- **Public sharing of memories** — private-first stays
- **Sentiment analysis либо emotional tagging** — premature
- **Voice biometric identification** — privacy nightmare
- **Music auto-suggestion для memories** («что играло в детстве?») — feature creep
- **Genealogy historical records integration** — MyHeritage territory, не их game

---

## 9. Decision questions для Артёма (pre-Phase D)

### Q1 — Voice STT default

- **On-device default** + cloud opt-in (privacy-first, accuracy compromised для русский)
- **Cloud default** + on-device opt-in (accuracy-first, audio uploaded)
- **User chooses at first voice attempt** (explicit consent)

**Recommend**: cloud default с explicit consent on first use, privacy guarantee «audio не shared с advertisers, used только для transcript».

### Q2 — Prompt library curation

- **Pre-built 100+ prompts** at launch (curated by us)
- **User-submitted prompts** allowed (community contributions, moderation needed)
- **AI-generated prompts** based context (future feature)

**Recommend**: pre-built launch с category «своя категория» для custom user prompts. Community contributions Phase D+1.

### Q3 — Inter-generational nudge frequency

- **Daily** — too pushy
- **Weekly** — reasonable cadence
- **Event-driven** (no nudges, only when user opens profile section)
- **Adaptive** based engagement

**Recommend**: weekly default + event-driven on photo upload либо relative profile open. User can disable.

### Q4 — Audio storage budget

- **Unlimited free** — generous, costly
- **5GB free + paid expansion** — freemium model
- **1 hour audio limit free** — tight
- **Retention 5 years free, then archive** — temporal tier

**Recommend**: unlimited free initially (audio compresses well, even 100 hours/user = 70GB across 1000 users). Monetization Phase D+2 if needed.

### Q5 — Profile completion gamification intensity

- **Soft progress badge** (35% complete) — informational
- **Reward badges** («Семейный историк» за заполнение 50%) — gamification
- **Comparison к relatives** («бабушка заполнила больше тебя») — social pressure
- **No gamification** — pure functional

**Recommend**: soft progress badge + optional achievement badges. Skip social pressure (anti-pattern, mama-fear «не хочу соревноваться»).

### Q6 — Prompt theme «Война»

- **Always available** (universal Russian context)
- **Age-gated** (only users 60+)
- **Opt-in** (user explicitly enables sensitive themes)
- **Hidden by default** (privacy-cautious)

**Recommend**: opt-in via «показать все темы» toggle. Defaults hide. User chooses depth.

### Q7 — Voice answer privacy default

- **Семья only** — conservative
- **Семья + друзья** — inclusive
- **Owner choice per answer** — explicit
- **Private (only self)** then promote

**Recommend**: «Семья only» default. Per-answer override available. Mama-friendly conservative.

### Q8 — Transcript editing UX

- **Manual edit available** but optional
- **Required edit before save** (forces correction)
- **Auto-save raw transcript** (no edit step)
- **AI suggestions during edit** (Phase D+1)

**Recommend**: auto-save raw transcript + edit available but optional. Bear in mind elder users won't edit. Audio always preserved as source of truth.

---

## 10. Phase D + Phase C interaction

Phase D **mostly orthogonal** к Phase B/C — profile/memory layer separate от tree/семя/друзья structure.

Overlap points:
- **Profile visibility** uses Phase 3.4 visibility model (семья only, friends only, specific users)
- **Photo tagging** uses Phase B person references
- **Inter-generational prompts** target relatives (Phase B семя) либо friends (Phase C)
- **Feed integration** — memory answers can post к feed (Phase C feed unification)

**Implementation order considerations**:
- Phase D could ship parallel к Phase B Week 5-8 (frontend work)
- Phase D could ship after Phase C
- **Recommend**: Phase D after Phase B Week 8 production rollout, parallel к Phase C Week 1-3 backend work

---

## 11. Strategic positioning impact

Phase D = **the defining differentiator** для Rodnya:

**Before Phase D**: Rodnya = family chat + tree app. Lots of competitors.

**After Phase D**: Rodnya = «семейная память». Unique:
- Voices preserved forever
- Stories structured by theme
- Inter-generational engagement built-in
- Print/share opt-in (future)

**Marketing tagline shift**:
- Before: «Семейная социальная сеть»
- After: «Сохрани истории родных пока они с нами»

Это **emotional value proposition** что reaches families каждой возрасти. Конкуренты не доберут.

---

## 12. Принято

- **Brainstorm**: Артём + Claude, 2026-05-26
- **Source vision**: Артёма «книжки про бабушек/дедушек», voice input ask, profile cleanup
- **Strategic positioning**: family memory preservation, generation-bridging, voice-first elder UX
- **Phase D timeline**: 4-6 weeks, parallel к Phase C либо after Phase B Week 8
- **Three pillars**: profile redesign + memory prompts + voice input
- **Defensive moat**: strongest competitive differentiation in roadmap
- **Decision answers pending**: 8 questions Section 9 awaiting Артёмов sign-off
- **Curated prompt library**: ~100 prompts across 9 themes, needs Артёмов content review либо linguistic editor pass

**Doc status**: design proposal awaiting Артёмов sign-off перед Phase D kickoff. Открытые вопросы Section 9 решить first.

When Артём confirms direction + answers 8 decision questions → doc finalized + Phase D kickoff dispatched (parallel либо after Phase B Week 8).

---

_End of PHASE-D-MEMORY-HISTORY-PROPOSAL.md_
