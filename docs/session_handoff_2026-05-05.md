# Session handoff — 2026-05-05

Длинная UX-волна, разбитая на четыре подволны: реакции/нотификации,
web layout, post search, и финальный polish-пасс. Каждый коммит в
`main`, тесты suite-wide зелёные (Flutter 336/336 + backend
focused), `flutter analyze` чисто.

## Коммит-карта (новейшие сверху)

| SHA | Темa | Краткое описание |
|---|---|---|
| `a8eff7d` | post composer | Top-align body — был вертикально центрирован, на десктопе оставлял 250px пустоты сверху |
| `4890f23` | notifications | Empty/loading state центрирован + cap 480 |
| `4096564` | snackbar | Floating + rounded + leading icon — премиальный look |
| `8d2e1b9` | desktop | Keyboard shortcuts: `/` для search, ESC + arrows в lightbox |
| `209fee7` | post video | Camera plugin для post video — закрывает iOS quality жалобу end-to-end |
| `648e565` | search | Полноценный post search — backend store + route + UI + entry в topbar |
| `aa8e4ee` | profile | Wide 2-col layout — dossier+posts слева, sidebar справа |
| `b70bd9e` | home | Sidebar events вертикально — раньше на 340dp был тесный horizontal rail |
| `973fe6e` | chats | Side panel buttons fix — green-on-green превратились в filled+outlined hierarchy |
| `45d2063` | stories | Story archive skeleton grid вместо одинокого spinner |
| `e1af274` | profile | Outer width cap 760 — посты не стрейчатся 1500px |
| `bafa2ea` | chats | Re-enabled wide-layout side panel «Связь» |
| `97f6c5c` | home | 2-column wide layout — feed + sidebar (Истории / События) |
| `359ad52` | polish | RodnyaAvatar в chats list + haptic story navigate |
| `5679a1f` | polish | Shared RodnyaAvatar + haptic + softer empty states |
| `44a56f0` | stories | Smart-presets + virtualized picker для stories (паритет с постами) |
| `cf12b56` | audience | Virtualized PersonMultiPickerSheet — масштабирование на 200+ людей |
| `860b1e2` | audience | Phase 1 audience-presets — «Моя семья» / «Близкие» tiles |
| `d42994d` | reactions | Story reactions + viewer wire + notification |
| `b4bc9e7` | notifications | Reaction notifications для постов и комментов |
| `082f31d` | reactions | Backend post + comment reactions API |
| `473e96c` | reactions | Posts + comments emoji reactions UI |
| `ede9be2` | docs | Branches/circles UX план |
| `8725ee6` | profile | Completion meter — onboarding nudge |
| `9673fd9` | comments | Count badge + avatar fallback chain |

## Главные вехи в этой сессии

### 🎨 Web layout — больше не «растянутый телефон»
Все три ключевых экрана получили desktop layout:
- **Home** (`97f6c5c` + `b70bd9e`): feed колонка ~720 + sidebar 340 с панелями «Истории» (rail) и «События» (вертикальный stack из 5 карточек + «и ещё N»)
- **Chats** (`bafa2ea` + `973fe6e`): chat list + side panel «Связь» с filled CTA + 2 outlined buttons (был unreadable green-on-green)
- **Profile** (`aa8e4ee`): dossier + contributions + posts слева, sidebar справа (tree-card, completion meter, stories rail, connection)

Архитектурный паттерн:
- `MediaQuery.of(context).size.width >= 1180` для home/profile, `>= 1100` для chats
- Outer `ConstrainedBox(maxWidth: 1180)` чтобы не растягивалось
- `Stack` или `Row` для two-column на wide
- На narrow phone-shape capped layout

### ❤️ Reactions everywhere
Три поверхности (posts, comments, stories) × notifications + дедуп + frontend optimistic-state. Backend coalesce-on-actor-and-target — спам-тапы пикера не фанаут в инбокс. Скоупится через `ReactionPicker` + `ReactionChipStrip`.

### 🔍 Post search
Полнотекстовый поиск через backend `/v1/posts/search?q=&treeId=`:
- Russian-locale tokenisation, AND-match
- Фильтр по доступным деревьям + circle visibility
- Frontend: 320ms debounce, fullscreen с TextField в AppBar
- Entry: search icon в home topbar + `/` shortcut на десктопе

### 🎥 iOS quality fix end-to-end
Все 4 capture surfaces бекап на camera plugin (вместо image_picker medium-quality default):
- Chat кружочки (`7405e58`)
- Story photo (`599f68a` — image_picker maxWidth 1920 + quality 95)
- Story video (`365efb5`)
- Post video (`209fee7`)

### ⌨️ Desktop polish
- `/` для поиска (Twitter-style), skip когда EditableText в фокусе
- ESC закрывает lightbox
- Arrow Left/Right — навигация в lightbox
- Floating rounded snackbar с leading icon + width-cap на wide

## Архитектурные знаки

- **`camera` plugin** теперь обслуживает 4 capture surfaces. KruzhokRecorderScreen параметризован — один UI, разные формы (`circle` для kruzhok, rect для stories/posts).
- **`HardwareKeyboard.instance.addHandler`** pattern для CanvasKit-friendly key events (Focus.onKeyEvent ненадёжен на web).
- **`RodnyaAvatar`** widget с fallback chain (URL → инициалы → person icon) переиспользуется в chat list + post card + comment sheet + profile.
- **Audience presets** computed на бэке от relations graph — `core_family` / `close` зависят от позиции anchor person в дереве.
- **`PersonMultiPickerSheet`** виртуализирован через `ListView.builder` — линейно масштабируется на 200+ людей.

## Что осталось в backlog

- **Tree view edge cases на десктопе** — общий вид ОК, могут быть мелочи
- **Profile sidebar 2-col на wide** — sticky-feeling sidebar в profile уже есть, но можно полировать
- **Settings / About wide layouts** — 980 cap, базово ОК
- **Comment threading** (replies inside comments) — большая фича
- **Hover states** на custom GestureDetector wrappers (большая часть Material widgets уже имеют hover)
- **Onboarding tutorial** — для первых юзеров
- **Storefront / RuStore release prep** — docs готовы, ждёт keystore + screenshots

## Тесты

- Flutter: 336/336 pass
- Backend: focused tests pass (post search, audience-presets, reactions, notifications)
- `flutter analyze` clean

## Что дальше

Жду фидбэк от user'а. Из открытого backlog следующая логичная волна
— либо comment threading (большая фича), либо мелкий polish по
конкретным жалобам после физтеста.
