# «Спросить историю» MVP-1 — бриф волны агентов (13.09.2026)

> Основание: [STORY-REQUEST-SCENARIO.md](STORY-REQUEST-SCENARIO.md) и решения
> Артёма в DECISIONS.md от 2026-09-13. Два sonnet-агента параллельно
> (бэкенд и клиент), контракт ниже зафиксирован заранее, чтобы клиент писался
> против него без живого бэкенда. Интеграция, живая проверка, деплой и OTA —
> за ведущим (не за агентами).

## 0. Решения, принятые для MVP-1

1. Спрашивать можно **только участников своего дерева с аккаунтом**; гость по
   ссылке — MVP-2.
2. **Срок ожидания 30 дней**, истечение лениво при чтении (как у kinship).
   Напоминание на 7-й день — MVP-2: нужен планировщик с доступом к диспетчеру
   пушей, в MVP-1 его нет.
3. **Без расшифровки речи**: ответ голосом хранится как аудио, поле
   `transcript` остаётся пустым; текстовый ответ — обычный параграф.
4. **Виды ответа в MVP-1: аудио, текст, фото.** Видео — MVP-2: у статьи
   персоны нет блока `video`, добавлять тип блока в этой волне нельзя.
5. Тизер в ленту — **MVP-3**, здесь не делаем.

## 1. Общий контракт (источник истины для обоих агентов)

### Сущность `storyRequest` (коллекция `storyRequests` в блобе)

```json
{
  "id": "sreq_<uuid>",
  "treeId": "…", "personId": "…",
  "requesterUserId": "…", "targetUserId": "…",
  "question": {"text": "Как познакомились бабушка и дедушка?", "themeKey": null, "sourceQuestionId": "meeting-story"},
  "status": "pending | answered | declined | expired | revoked",
  "answer": null,
  "createdAt": "ISO", "updatedAt": "ISO", "expiresAt": "createdAt + 30 дней", "respondedAt": null
}
```

`answer` после ответа: `{"articleBlockId": "…", "kind": "audio | text | photo",
"answeredByUserId": "…", "answeredAt": "ISO"}`.

Блок статьи, созданный ответом, получает **аддитивное** поле верхнего уровня
`source: {"requestId", "question", "askedByUserId", "askedAt"}` — по нему
раздел «Истории» подписывает «На вопрос Артёма, 13 сентября». Существующие
блоки без `source` не меняются; `normalizeArticleBlockContent` не трогать —
`source` живёт рядом с `content`, не внутри.

### Маршруты (все `requireAuth`)

| маршрут | кто | тело / ответ | ошибки |
|---|---|---|---|
| `POST /v1/story-requests` | инициатор | `{treeId, personId, targetUserId, question:{text, themeKey?, sourceQuestionId?}}` → `201 {request}` | `400 SELF_REQUEST_FORBIDDEN` (target = сам), `400 INVALID_QUESTION` (текст после trim 3…500 символов), `404 PERSON_NOT_FOUND`, `403` если инициатор не может редактировать персону (`requireGraphPersonEdit(treeId, personId, 'edit')`), `404 TARGET_NOT_IN_TREE` (target не участник дерева/семьи), `409 DUPLICATE_PENDING` (уже есть pending на ту же тройку инициатор+адресат+персона), `429 TOO_MANY_PENDING` (>20 открытых у инициатора) |
| `GET /v1/me/story-requests?role=received\|issued&status=` | участник | `{requests:[…]}`, каждый с `person:{id,name,photoUrl}`, `requester:{id,displayName,photoUrl}`, `target:{…}`; ленивое истечение просроченных | `400` без role |
| `GET /v1/story-requests/:id` | инициатор или адресат | `{request}` (с теми же вложениями) | `404` |
| `POST /v1/story-requests/:id/answer` | адресат | `{kind:"audio", mediaUrl, durationSec}` \| `{kind:"text", text}` \| `{kind:"photo", mediaUrl, caption?}` → `200 {request, block}` | `403` не адресат, `409 NOT_PENDING`, `400 INVALID_ANSWER` |
| `POST /v1/story-requests/:id/decline` | адресат | → `200 {request}` | `403`, `409 NOT_PENDING` |
| `POST /v1/story-requests/:id/revoke` | инициатор | → `200 {request}` | `403`, `409 NOT_PENDING` |

Право на запись ответа: **инициатор** обязан иметь право редактировать
персону (проверяется при создании запроса), а **адресат** пишет блок в
статью без собственного права редактирования — сам запрос и есть выданное
разрешение на один ответ. Это осознанное правило, зафиксировать в
комментарии у `answerStoryRequest`.

### Уведомления (через `createAndDispatchNotification`, `backend/src/app.js:2765`)

| тип | кому | title / body | data |
|---|---|---|---|
| `story_request_received` | адресату при создании | «{Имя инициатора} хочет узнать историю» / текст вопроса | `{requestId, treeId, personId}` |
| `story_request_answered` | инициатору | «{Имя адресата} делится историей» / первые 80 символов вопроса | `{requestId, treeId, personId, articleBlockId}` |
| `story_request_declined` | инициатору | «{Имя} пока не может ответить» / вопрос | `{requestId, treeId, personId}` |
| `story_request_expired` | инициатору, один раз при ленивом истечении | «Вопрос остался без ответа» / вопрос | `{requestId, treeId, personId}` |
| `story_request_revoked` | адресату | «{Имя} отзывает свой вопрос» / вопрос | `{requestId}` |

Копирайт продуктового качества, обращение к пользователю на «вы» в
уведомлениях, как в остальных типах. Заголовки без рода и без склонения
имени: настоящее время («делится», «отзывает», «хочет узнать») не зависит
ни от пола, ни от падежа — имя всегда в именительном.

## 2. Агент A — бэкенд (ветка `feat/story-requests-backend`)

Образец 1:1 — `backend/src/routes/kinship-checks-routes.js` (277 строк) и
store-методы `createKinshipCheck` / `listKinshipChecksForUser` /
`findKinshipCheck` / `respondToKinshipCheck` / `revokeKinshipCheck`
(`backend/src/store.js` ~21892–22110, читать `grep -a`/`sed`, файл 22k строк).

Сделать:
1. `store.js`: коллекция `storyRequests` в `normalizeDbState` (по умолчанию
   `[]`), методы `createStoryRequest`, `listStoryRequestsForUser({userId, role,
   status})`, `findStoryRequest({requestId, viewerUserId})`,
   `answerStoryRequest({requestId, actorUserId, answer})` (внутри —
   `appendArticleBlock({personId, type, content, actorUserId})` + поле `source`
   на блоке + смена статуса + `respondedAt`), `declineStoryRequest`,
   `revokeStoryRequest`. Все записи через `_mutate` (STORE-RACE), без
   вложенных вызовов store внутри applyFn. Ленивое истечение — в list/find,
   как у kinship, с одноразовым уведомлением (флаг `expiredNotifiedAt`).
2. `backend/src/routes/story-request-routes.js`, регистрация рядом с kinship
   в `app.js`; уведомления по таблице выше; данные для пуша — как у
   `kinship_check_received` (действие «Ответить» на клиенте по `requestId`).
3. `_sweepUnboundedLogs` (`store.js` ~22130): терминальные запросы старше
   90 дней сметаются ежедневным джобом (новый ключ `storyRequestsTerminalDays`,
   по умолчанию 90, env `RODNYA_HARD_DELETE_STORY_REQUESTS_DAYS` в `config.js`
   по образцу соседних ключей).
4. PostgresStore: оверрайды не нужны (коллекция маленькая, живёт в блобе,
   `_write` её не дренирует) — но добавить тест на pg-mem, что запрос переживает
   `_write`/`_read` и `readSharedSnapshot()` (SPEED-11: оверлей кругов копирует
   ключи явно — проверить, что новая коллекция не теряется в
   `_writableCirclesViewForTree`).
5. Тесты: `backend/test/story-requests.test.js` по образцу
   `kinship-checks.test.js` (611 строк): создание/дубль/лимит/самому себе/не
   участник, списки received/issued, ответ каждого вида → блок в статье с
   `source` + уведомление инициатору, отказ, отзыв, истечение (подкрутить
   `expiresAt` в прошлое) с одноразовым уведомлением, права (третий участник
   не видит чужой запрос, адресат без права редактирования персоны всё равно
   отвечает). Плюс `postgres-story-requests.test.js` (п. 4).
6. `docs/connected-trees-refactor/STORY-REQUEST-SCENARIO.md` §3 — привести к
   реализованному контракту, если что-то разошлось; коротко.

Финал: `npm --prefix backend test` зелёный (базлайн 794), `git diff --stat
main..HEAD`, отчёт с таблицей маршрутов и кодов ошибок «как реализовано».

## 3. Агент B — клиент (ветка `feat/story-requests-client`)

Образцы: `lib/backend/interfaces/kinship_check_capable_family_tree_service.dart`
+ реализация в `lib/services/custom_api_family_tree_service.dart` (строка ~72,
`implements …`), тесты `test/kinship_check_test.dart`,
`test/kinship_check_controller_test.dart`; редактор статьи
`lib/screens/profile_article_editor_screen.dart` (test seams
`audioRecordOverride`, storage override; аудио: `showAudioRecordSheet` →
`CustomApiStorageService.uploadBytes(...)` → блок), `test/profile_article_editor_test.dart`.

Dart SDK ≥2.17 <4 — без records, patterns, sealed/class modifiers.

Сделать:
1. Модель `lib/models/story_request.dart` (парсинг контракта §1, включая
   вложения person/requester/target) + `lib/backend/interfaces/story_request_capable_family_tree_service.dart`:
   `createStoryRequest`, `listStoryRequests({role, status})`, `getStoryRequest`,
   `answerStoryRequest`, `declineStoryRequest`, `revokeStoryRequest`; коды
   ошибок контракта → понятные RU-сообщения через существующий путь
   `describeUserFacingError` (пример: «Такой вопрос уже ждёт ответа»).
2. Реализация в `CustomApiFamilyTreeService` (+ `implements`), маршруты §1.
3. Лист «Спросить историю» (`lib/widgets/family_story_questions_sheet.dart`,
   вызов `_askFamilyStory` в `lib/screens/relative_details_screen_sections.dart:661`):
   если `service is StoryRequestCapableFamilyTreeService` — после выбора
   вопроса шаг «Кого спросить»: чипы «сам(а) {имя}» (когда у персоны есть
   `userId` и это не я), затем участники дерева с аккаунтом (существующий
   способ получить участников/семью — найти в коде, не изобретать), кнопка
   «Отправить» → `createStoryRequest` → SnackBar «Вопрос отправлен {имя}».
   «Поделиться текстом» остаётся второй кнопкой (для родных без приложения до
   MVP-2). Без capability — поведение как сейчас, без изменений.
4. Экран ответа `lib/screens/story_request_answer_screen.dart`, маршрут
   `/story-requests/:id/answer` в `lib/navigation/app_overlay_route_module.dart`
   (по образцу соседних GoRoute), открывается из уведомления и из списка
   «Мне задали вопрос». Voice-first (Phase D §3.3.4): вопрос ≥20sp, «{Имя}
   спрашивает о {Имя персоны}», одна крупная кнопка микрофона 72dp → запись
   стартует сразу (`showAudioRecordSheet`, seam для тестов), после записи —
   прослушать / перезаписать / «Сохранить»; ниже «Написать текстом»
   (многострочное поле, ≥16sp), «Прислать фото» (существующий пикер +
   `uploadImage`), «Пропустить пока» (просто закрыть), «Не хочу отвечать»
   (диалог подтверждения → decline). Успех: экран «Спасибо! {Имя} получит
   вашу историю» с кнопкой «К странице {персоны}». Все цели ≥44dp (микрофон
   72), без `VisualDensity.compact`, без рамок-в-рамках, тексты через токены
   `AppTheme`/`RodnyaDesignTokens`.
5. Уведомления: `lib/services/custom_api_notification_service.dart` — пять
   типов по образцу `kinship_check_*` (иконка, заголовок, действие): тап по
   `story_request_received` → экран ответа; по `story_request_answered` →
   страница персоны `/relative/details/:personId` (существующий маршрут).
6. Страница персоны: блоки статьи с `source` рендерятся с подписью «На
   вопрос {Имя}, {дата}» (`lib/widgets/article_audio_block.dart` и
   read-view — найти общий рендер блоков и добавить подпись один раз, не
   в каждом типе). Для инициатора над разделом — строка статуса своих
   открытых вопросов по этой персоне («Ждём ответа {имя} · Отозвать»).
7. Тесты: модель (парсинг, статусы), сервис-адаптер с фейковым HTTP (как
   `kinship_check_test.dart`), лист с шагом «Кого спросить» (capability
   есть/нет), экран ответа (аудио через seam → вызов `answerStoryRequest` с
   `kind: audio`; текст; отказ), маппинг уведомлений, подпись `source` в
   рендере блока. Probe плотности экрана ответа (`physicalSize=Size(412*3,915*3)`,
   dpr 3): микрофон ≥72dp, тексты ≥16sp, всё в первом экране без скролла.

Запреты агенту B: не трогать `backend/`, `pubspec.yaml` (бамп версии — за
ведущим), `deploy/`, `.github/`. Финал: `flutter analyze` чисто, полный
`flutter test` зелёный (базлайн 1535), `git diff --stat main..HEAD`, отчёт.

## 4. Общие гардрейлы обоих агентов

- Worktree, своя ветка от `main`, коммит после каждого шага (сессии агентов
  обрываются). Никаких `git push`, правок `main`, ssh/прода/OTA/workflow.
- Без `--no-verify`, `--force`, amend чужих коммитов.
- Комментарии — инварианты и «почему»; RU-копирайт продуктового качества.
- Правильное решение важнее дешёвого; если контракт §1 мешает правильному
  решению — сделать правильно и **явно написать в отчёте, что изменилось**,
  чтобы второй агент/ведущий подстроились при интеграции.
- Не печатать личные данные из копий прод-блоба (`backend/.scratch/`).

## 5. Интеграция (ведущий)

1. Ревью ветки A → `npm --prefix backend test` → слияние no-ff → локальный
   бэкенд на копии блоба (порт 8095).
2. Ревью ветки B → `flutter analyze` + полный `flutter test` → слияние.
3. Живая проверка цикла на эмуляторе и в вебе против локального бэкенда:
   два аккаунта (инициатор и адресат), вопрос → пуш/уведомление → ответ
   голосом и текстом → блок с подписью на странице персоны → уведомление
   инициатору; отказ и отзыв; истечение (подкрутка `expiresAt` в копии).
4. CURRENT-PHASE, push (деплой бэкенда и веба), затем бамп `pubspec` и OTA.
5. Наблюдение: журнал ошибок и первые реальные запросы; MVP-2 (гостевая
   ссылка) — следующая волна после отклика.
