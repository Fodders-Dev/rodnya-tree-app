# Session handoff — 2026-05-04

Длинная фиче-волна по UX-фидбэку пользователя. Каждый конкретный
пункт фидбэка закрыт коммитом в `main`. Тесты suite-wide зелёные
(336/336), `flutter analyze` чистый.

## Коммит-карта (новейшие сверху)

| SHA | Темa | Краткое описание |
|---|---|---|
| `e1f3eca` | tests | Green-up suite: убрал auto-present для active-call (CallFloatingPip теперь отображается); поправил `Активное` count в tree_selector |
| `365efb5` | stories | In-app camera-plugin video recorder для stories — bypass image_picker medium-quality default. KruzhokRecorder теперь параметризован: круг/прямоугольник, длительность, filename prefix |
| `79779ca` | home | Photo/video иконки на «Поделиться с роднёй» теперь distinct CTAs (action=photo / action=video) |
| `7405e58` | chat | In-app Telegram-style кружок recorder (camera plugin), front-camera по дефолту, 60s cap, video_note_* filename |
| `fbb026a` | stories | Архив историй на `/profile/stories/archive` + entry в profile popup |
| `599f68a` | stories | Видео в истории больше не «в рамке» (Center → Positioned.fill) + photo quality bump 85→95 / 1440→1920 |
| `9673fd9` | comments | Счётчик в шапке + avatar fallback chain (URL → self profile → инициалы) |
| `b450762` | lightbox | Like / comment / share overlay внутри MediaLightbox с optimistic-heart |
| `57a5acd` | post | Видео в постах + visible empty-slot hint в composer (`_PostMedia`, `_VideoTilePoster`, `_PostVideoTile`) |
| `453aca7` | audience | Grouped sections (Главное / Ветви потомков / Линии предков) + поиск (>4 кругов) + auto-expand активной секции |

## Карта user-фидбэк → фикс

| Жалоба пользователя | Закрыто в |
|---|---|
| «тонна выбора» в audience picker | `453aca7` |
| «не интуитивно понятно где фото то прикладывается» | `57a5acd` |
| «А видео нельзя что-ли?» | `57a5acd` (gallery+camera) и `365efb5` (in-app capture для stories) |
| «не хватает лайк/комменты/переслать» в фото-вьювере | `b450762` |
| «нет счётчика комментариев» | `9673fd9` |
| «ава в комментариях не подсасывается с профиля» | `9673fd9` |
| «видео в рамке» в историях | `599f68a` |
| «качество съемки на айфоне упало» | `599f68a` (фото) и `365efb5` (видео через camera plugin) |
| «архив как в IG/TG?» | `fbb026a` |
| «чаты умерли при отправке кружка» | `6255d3f` (предыдущая волна) |
| «кружочки пишутся через файл отдельный» | `7405e58` |
| «кнопки фото и видео без смысла» в home teaser | `79779ca` |

## Архитектурные знаки

- **camera plugin** добавлен в pubspec (`^0.11.0+2`). Используется в
  KruzhokRecorderScreen для chat кружочков и для stories video capture.
  Web по-прежнему ходит через image_picker (HTML `<input type=file>`
  не умеет live preview loop).
- **KruzhokRecorderScreen параметризован**: `circularPreview`,
  `maxDuration`, `filenamePrefix`, `titleLabel`, `idleHint`. Два
  предустановленных варианта: `show()` (кружок) и `showStory()`
  (история). Один UI, две формы кадра.
- **Posts видео** мигрируют через `imageUrls` в Post (без schema
  changes). Storage service уже умеет в правильный Content-Type для
  видео. Detection — по расширению URL (`_isVideoUrl` в post_card).
- **MediaLightbox actions** — optional callbacks. Если caller не
  передал `onLike/onComment/onShare`, action-bar не рендерится (это
  важно для chat attachment viewer'а, где actions не нужны).
- **CallRuntimeHost auto-present** — теперь только для ringing, не
  active. Семантически правильно: active = user уже принял, должен
  видеть floating pip и сам решить открыть screen.

## Что осталось в backlog

- **iOS upstream image_picker quality knob** — не actionable из
  фронта. Workaround через camera plugin уже на месте для kruzhok и
  story video. Если надо для post video capture тоже — расширить
  KruzhokRecorderScreen ещё одной opt-in для post (без круглой формы,
  длительность 60s+, filename prefix `post_video`).
- **Profile final polish** — без конкретного фидбэка спекулятивно.
  Сейчас экран хорошо структурирован: hero/dossier, tree card,
  stories rail, profile connection card, contributions, posts list.
  Архив историй уже добавлен в popup (`fbb026a`).
- **Storefront / RuStore release kit** — в `docs/` уже лежит
  release_checklist, screenshot_shotlist, store_card, moderator_notes,
  whatsnew. Build pipeline и privacy policy in-app тоже на месте.
- **Кружок UX gestures** — long-press + slide-to-lock + slide-to-cancel
  (полный Telegram set) пока не реализованы. Текущий MVP — tap-to-
  toggle, что более accessibility-friendly. Если пользователь захочет
  именно Telegram-pattern — отдельная волна.
- **Story viewer reactions** — нет emoji-reactions внутри viewer'а,
  только pause/skip/restore. Нет swipe-up reply.
- **Comments threading + reactions** — комменты сейчас flat без
  reply-quote и без like.

## E2E чеклист для пользователя (на физтеле)

- [ ] Audience picker: 14+ веток теперь скрыты под секциями, поиск работает
- [ ] Post composer: empty-slot card видим, тап открывает picker; видео в превью с play-бейджем
- [ ] Post feed: видео-пост открывается в lightbox с play и actions
- [ ] Lightbox: heart реагирует мгновенно, comment closes lightbox + opens sheet, share ведёт в системный share
- [ ] Comment sheet: счётчик в шапке, аватар свой подтягивается из профиля
- [ ] Story viewer: видео заполняет экран (не в рамке)
- [ ] Story composer: «Снять видео» tile открывает in-app camera (на мобилке)
- [ ] Profile → меню → «Архив историй» → попадает на page
- [ ] Chat: тап на «Кружок» в picker'е открывает in-app recorder с круглым preview
- [ ] Home teaser: тап на photo иконку → composer + сразу gallery; на video → composer + сразу video gallery

## Тесты

- 336 / 336 pass
- `flutter analyze` clean

## Что дальше

Жду фидбэк от user'а после физического теста. Если всё ОК — можно
полировать профиль / тянуть к релизу. Если что-то сломалось — фикс по
конкретному скриншоту.
