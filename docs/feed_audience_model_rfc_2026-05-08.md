# Feed Audience Model — RFC

Дата: 2026-05-08
Контекст: пользователь обнаружил «тихую потерю» постов — переключив активную
ветку, он перестаёт видеть посты из других веток, в которых он тоже состоит.
Это ломает основной value-prop проекта («меньше шума, больше близких»):
адресат поста не получил его.

## Цель

Перевести **ленту, уведомления и таргетирование постов** с модели
«one selected branch» на **audience-based модель**:

- Лента по умолчанию = всё, к чему я причастен (объединение веток, в которых
  я состою как member).
- Ветка превращается из «контекста приложения» в **тег для таргетинга поста**
  и **фильтр для просмотра**.
- Уведомления опираются на audience поста, а не на активную ветку получателя.

Активная ветка остаётся как «фокус» для дерева (canvas) и опционально как
default-аудитория composer'а — но **не фильтрует ленту**.

## Phased plan

### Step 1 — Audience-based feed (сейчас)

**Backend:**
- Эндпоинт фида (вероятно `GET /v1/posts` или `GET /v1/feed`):
  - было: `WHERE branchId = :selectedBranchId`
  - стало: `WHERE branchIds && :myBranchIds` (PostgreSQL `&&` для array
    overlap; в file-store — фильтр в JS).
- Audience поста = `union(branch.memberIds for each branchId in post.branchIds)`.
- Notification fan-out при создании поста — по audience, дедуп по userId.

**Frontend:**
- Главный экран не зависит от `selectedBranchId` для запроса фида.
- Сверху ленты горизонтальная полоска чипов: `[Все]` (default) `[Кузнецовы]`
  `[Мама]` ... — фильтр-чипы, серверный фильтр (см. проблему #9 ниже).
- BranchSwitcher на feed-экране **меняет смысл**: остаётся как навигация в
  дерево этой ветки, но **не фильтрует** ленту. (Возможно скроем на feed
  совсем — уточним по ходу.)

**Notifications:**
- При создании поста backend пушит событие в audience поста.
- Push больше не зависит от того, какую ветку выбрал получатель в момент.

### Step 2 — Lasso + selection-mode на дереве (после Step 1)

Selection-mode на canvas-е, чтобы из «Семьи Кузнецовых» выделить мамину
половину и одной кнопкой сделать ветку «По маминой линии».

### Step 3 — Шаблоны веток в онбординге

«По маминой линии», «По папиной линии», «Семья жены», «Близкие друзья» —
готовые пустые ветки с подсказкой «выдели на холсте кого добавить».

### Step 4 — Phone-matching (deferred)

Подтверждение «вот этот Иван из контактов = твой дядя Ваня в дереве».
Если обе стороны в Rodnya и подтверждают, графы аккуратно сшиваются.
Только для родни, не для друзей. Детально пишем когда дойдём.

## Потенциальные проблемы Step 1 (и решения)

Заполняем по ходу — каждая проблема либо «решена», либо помечена «открыто».

### 1. Цена вычисления audience

Naive: для каждого поста загрузить ветки, юнионить memberIds, проверять
юзера. Это O(branches × members) на запрос.

**Решение:**
- На стороне запроса один раз вычислить `myBranchIds` (Set<String>) для
  текущего юзера и переиспользовать.
- На read-time фильтровать `posts WHERE branchIds && myBranchIds`. В
  PostgreSQL — GIN-индекс по `posts.branchIds`. В file-store — простой
  `Array.some(...)` фильтр в памяти, т.к. размер коллекции терпит.

### 2. Пагинация по объединению

Курсор `(createdAt, postId)` остаётся валидным, потому что фильтр
применяется до сортировки. Главное — индекс по `(createdAt DESC)` плюс
ARRAY-фильтр.

**Решение:** проверить, что существующий курсор не зависит от branchId.
Если зависит — переписать.

### 3. Дубликаты в выдаче

Пост в `branchIds = [A, B]` и юзер в обеих ветках — пост должен прийти
**один раз**.

**Решение:** в Phase 3.4 пост — единая запись с `branchIds[]`, никакой
денормализации «one row per branch». **Проверить:** что фид не делает
JOIN с таблицей-перебором веток, который может дать дубль.

### 4. Личные посты (профильные)

Не привязаны к ветке. Видны в ленте автора и его подписчикам. Это
отдельный поток.

**Решение для Step 1:** не трогаем. Если у поста `branchIds` пустой —
он профильный и должен показываться по другому правилу (например,
«в моей ленте если автор — мой родственник в любой моей ветке»).
Но пока в основном кейсе все посты с branchIds — фокусируемся на нём.

### 5. Уведомления fan-out

Сейчас вероятно по `tree.memberIds`. Должно стать по audience поста.

**Решение:** найти notification-creator (искать `notification` или
`tree_post_created`), переписать на:
```js
const audience = await computePostAudience(post); // union by branchIds
const recipients = audience.filter(uid => uid !== post.authorId);
for (const uid of recipients) {
  await createNotification({ userId: uid, type: 'post_created', postId });
}
```

### 6. Удаление ветки / выход из ветки

Юзер вышел из «Кузнецовых» — старые посты «Кузнецовых» должны исчезнуть
из его ленты при следующем рефреше.

**Решение:** естественно через filter на read-time (
`post.branchIds && myBranchIds`). Уже-отрисованные посты на клиенте не
пропадают мгновенно — это нормально (refresh on next fetch).

### 7. Подмена audience уже опубликованного поста

Автор удаляет ветку из `post.branchIds[]` — пост частично «отзывается»
у тех, кто перестал быть в audience. Сложный edge case.

**Решение Step 1:** оставляем on hold. UI пока не даёт это делать.

### 8. Composer: «этот пост увидят X человек»

Composer должен пересчитывать audience на лету, чтобы автор понимал
кому пишет.

**Решение:** не кэшируем `audienceUserIds[]` на посте (сложно
поддерживать). Считаем при отправке для счётчика. На клиенте можно
дёшево показать `union(branch.memberIds for selected branches).size`.

### 9. Чип-фильтр: серверный или клиентский?

Если лента пагинируется лимитом 50, и юзер фильтрует «Кузнецовы»,
клиентский фильтр может выдать 0 постов из 50 загруженных, хотя
в ветке Кузнецовых посты есть, просто ниже по фиду.

**Решение:** серверный фильтр. Параметр `?branch=<id>`. При выборе
чипа — отдельный запрос с этим параметром. Default `[Все]` — без
параметра, по audience-mode.

### 10. BranchSwitcher на feed-экране

Был полезен. Сейчас фильтрует фид (это и есть баг). Нельзя просто
убрать — он же навигационный.

**Решение:** оставить чип, но **сменить семантику** — это «активная
ветка для дерева/composer'а», не фильтр для фида. Тап на чип → попадает
в дерево этой ветки. На feed-экране при необходимости показать другим
визуальным языком (отличить от filter-чипов сверху).

### 11. Поиск в ленте

Сейчас, вероятно, ищет внутри активной ветки. Должен — внутри всего, к
чему юзер причастен.

**Решение Step 1:** вне scope. Проверить как сейчас работает, отметить
для следующей итерации, если не задержит.

### 12. Empty state

Юзер новый, нет постов в audience. Показать «выложите первый пост, или
добавьте родню чтобы увидеть их посты».

**Решение:** обновить existing empty-state на feed-экране — без
привязки к «active branch is empty».

### 13. Существующая home-screen логика «На этой неделе в семье» (Phase 6.3)

Этот digest строится из активной ветки (`getBranchDigest(branchId)`).
После Step 1 надо решить: digest — на все ветки сразу, или остаётся
по активной?

**Решение pending:** оставляю как сейчас (per-branch digest). Это «срез
для дерева, что у меня в этой ветке на неделе». Плюс не ломаем существующий
UX. Если придумаю объединить с лентой — отметим в Step 2/3.

### 14. Тесты

Скорее всего, есть тесты, которые ассертят «фид показывает ровно
N постов из active-branch». После переписки они сломаются.

**Решение:** после первого прогона тестов аккуратно обновить ассерты
под audience-mode. Не править вслепую — каждое падение разобрать.

## Acceptance criteria для Step 1

1. Открываю фид → вижу посты из ВСЕХ веток, в которых я состою. Не
   только из «активной».
2. Сверху ленты чипы веток. Тап на чип → лента сужается до этой ветки.
   Тап на «Все» → расширяется обратно.
3. Создаю пост — composer показывает в какие ветки уйдёт + счётчик
   уникальных получателей. Дефолт = активная ветка.
4. Получаю push при создании поста в любой моей ветке.
5. Все существующие тесты адаптированы под новую модель и проходят.
   Новый тест на audience-фид.

## Open questions, проверяем по ходу

- Где живёт feed query? `backend/src/routes/post-routes.js`? Найти первой
  задачей.
- Где fan-out уведомлений? Найти.
- Где BranchSwitcher на feed экране? Уже знаю — `home_screen.dart`,
  но что именно дёргает фид по `selectedBranchId`?
- Schema posts — `branchIds[]` уже везде, или часть кода смотрит на
  старый `branchId`? Аудит.

## Status journal

(заполняем по ходу выполнения)

- 2026-05-08: RFC создан. Старт Step 1 с аудита.
- 2026-05-08: Аудит закончен.
  - Backend feed: `GET /v1/posts → store.listPosts({treeId, …})`. При
    `treeId=null` tree-фильтр снимается, но per-post visibility
    (`_canUserViewCirclePost`) смотрит ТОЛЬКО на `post.treeId`, не
    итерируется по `post.branchIds[]`. **Это и есть audience-баг на
    уровне данных.**
  - Push-уведомления при создании поста сейчас НЕ fan-out'ятся
    (нет ни FCM, ни in-app notification). Только реакции/реплики
    дают notification. → Step 1 не трогает уведомления.
  - Frontend `home_screen._loadPosts(treeId)` всегда шлёт активную
    ветку. Это симптом — пост из другой ветки не приходит.
  - Schema: `post.treeId` (primary, всегда), `post.branchIds[]`
    (Phase 3.4, всегда включает treeId), `post.circleId` (defaults
    to all_tree).
  - PostsCache ключуется по `treeId` — добавлю спец-ключ
    `__audience__` для общего фида.

- 2026-05-08: Step 1 implementation
  - Backend: `_canUserViewCirclePost` итерирует все ветки в
    `[post.treeId, ...post.branchIds]`, primary честит circleId,
    secondary — implicit all_tree (circles per-tree, не propagation).
  - Backend route `/v1/posts`: фильтр доступа смотрит на
    `post.treeId OR any branchIds[]` — раньше дропал посты, у
    которых viewer был в secondary branch.
  - Backend test: `audience-mode feed: viewer in secondary branch
    sees fan-out post even when not in primary branch` — зелёный.
  - Frontend: `_loadPosts(branchId: null)` стартует в audience-mode.
    `_handleTreeChange` больше не reload'ит фид. PostsCache
    использует sentinel `__audience__` как ключ для общего фида.
  - Frontend chips: новый `_buildFeedBranchStrip` рендерится над
    существующим `_feedFilters` стрипом. Показывается только при
    >1 ветке (иначе noise). `[Все]` + по chip-у на ветку.
  - Frontend test: home_screen_test поправлен под новый redirect
    `/tree?selector=1&tab=invitations` (баннер «Открыть приглашения»).

### Обнаруженные проблемы и принятые решения

- **Race condition на быстром переключении chip-ов:** пользователь
  тапнул Branch A, потом сразу Branch B. Network для A может
  прилететь после B. → guard `_selectedFeedBranchId == branchId`
  перед коммитом setState — стоит на месте.
- **PostsCache ключ для audience-mode:** sentinel `__audience__`
  не коллидирует с реальными UUID branchId. Документировано.
- **BranchSwitcher больше не дёргает фид:** UX отклонение от
  привычного поведения. Раньше переключатель = переключатель
  ленты. Сейчас → переключатель = фокус для дерева/digest, лента
  своя. Это решает основной баг, но юзер может удивиться. На
  prod-е смотрим как принимают; если потеряются, добавим subtle
  «sync chip с текущей веткой» при первом тапе на switcher.
- **Чип-strip теряется при 1 ветке:** прячем strip когда у юзера
  только одна ветка. Иначе появляется бессмысленный `[Все]
  [Single Branch]`, у которого оба стейта показывают одно. Когда
  он сделает вторую ветку — strip появится автоматически.
- **NOT in Step 1 scope:** уведомления при создании поста
  (currently not wired anywhere — no FCM, no in-app notification
  для posts). Composer audience picker (нет multi-branch UI пока,
  фронт всегда шлёт `[treeId]`). Поиск по фиду (всё ещё работает
  по выбранной ветке через старый код). Эти три → отдельные
  итерации.

- 2026-05-08: Step 1.5 + Step 2 implementation
  - **Composer audience counter:** «Этот пост увидят: 17 человек в
    2 ветках». Считает union memberIds по выбранным веткам (primary
    + cross-branch toggles). Включён автор — это «размер аудитории»,
    не «количество других». Pluralization helpers под русскую
    грамматику. Падает gracefully когда primary tree meta не
    подгрузилась (просто не показывает badge).
  - **Снёс legacy chip strip** (Семья/Близкие/Архив/Истории). Они
    были рудиментом другого мышления и шумели поверх branch-чипов.
    Новый канон: одна полоса, branch-чипы, и всё. Тест на content-
    type filter переписан под audience-mode.
  - **Step 2 selection-mode на canvas:** новый toolbar action
    «Выбрать несколько человек». Пока активен:
    - tap по карточке → toggle selection (вместо открытия inspector)
    - long-press connector выключен (selection mode владеет жестом)
    - на карточке accent-кольцо + check-badge при выделении
    - вместо обычного person bottom-sheet — toolbar «Выбрано: N •
      [В ветку…] • [Закрыть]»
  - **Bulk «Добавить в ветку…»:** тап на кнопку → bottom sheet с
    другими ветками юзера → выбор → для каждого selected personId
    POST `/v1/trees/:targetId/persons` с `sourcePersonId` (re-uses
    Phase 0 cross-tree picker code path; identityId шарится автоматом).
    Связи между скопированными карточками НЕ копируются — это
    отдельная итерация (нужен domain-смысловый «копировать вместе с
    edges»).
  - **Lasso (drag по пустому месту)** отложен. Tap-to-toggle на
    мобильном — самый прямой способ; lasso потребует разрешать
    конфликт с pan/zoom InteractiveViewer и отдельным polygon
    hit-test'ом. Сделаю если юзер запросит.

- 2026-05-08: Step 2 follow-up — bulk-import endpoint
  - **Баг 1 (пустая карточка):** старый legacy-путь
    `POST /v1/trees/:treeId/persons` с `{sourcePersonId, name,
    gender}` даже при merge не дотягивал photoUrl до новой
    карточки — `mergePersonDataFromSource` срабатывал, но
    `normalizePersonPhotoGallery` интерферировал с моими
    явными name/gender. → Один новый эндпоинт, чистый путь.
  - **Баг 2 (нет связи с тобой):** релейшены вообще не
    переносились. Для канонического кейса «копирую девушку → она
    должна быть моим партнёром на новом дереве» — не опционально.
    → Эндпоинт `POST /v1/trees/:treeId/persons/import` теперь
    автоматически:
    - копирует людей с полным набором полей через тот же
      `mergePersonDataFromSource`-merge,
    - bridge'ит каждый source-релейшен, у которого хотя бы
      один конец среди выбранных,
    - транслирует endpoint personIds через два словаря:
      sourceToNewMap (свежеимпортированные) и
      targetPersonsByIdentity (уже есть в target через
      `identityId` — канонический «ты сам»),
    - идемпотентен: повторный запуск с теми же sourcePersonIds
      не дублирует ни людей, ни связи.
  - Тест `bulk-import: copies persons with full data + bridges
    relations to existing target persons via identity` — зелёный.
  - Frontend: `BulkImportCapableFamilyTreeService` mixin +
    `BulkImportResult{persons, bridgedRelationCount}`. Snackbar
    теперь различает: «уже все есть» / «K людей + R связей» /
    просто «K людей».

- 2026-05-08: Step 3 — smart selection + branch templates
  - **Smart-expand на selection-mode toolbar:** новая кнопка
    «Расширить» (волшебная палочка). Popup'ом предлагает:
    - Все предки выделенных
    - Все потомки выделенных
    - Вся эта линия (предки + потомки + якоря)
  - BFS по parent/child эджам в `_relationsData`.
    Sibling/spouse/in-law эджи специально игнорю — иначе при
    «по маминой линии» подцепится муж мамы и его клан, что
    редко то, чего хочет юзер.
  - Snackbar: «Добавлено в выбор (вся линия): 23» либо «Никого
    нового не нашлось».
  - **Branch templates на CreateTreeScreen:** ChoiceChip-strip
    между сегментом семьи/друзей и инпутом названия. Тап на
    чип префиллит и название и описание. Шаблоны:
    - семейные: «По маминой линии», «По папиной линии»,
      «Семья жены/мужа», «Кровная родня»
    - дружеские: «Близкие друзья», «Школа», «Универ», «Работа»
  - Юзер может потом править оба поля — чип это head start, не
    замок. При смене kind (семья↔друзья) выбор шаблона сбрасывается.
  - Toolbar copy в selection-mode подкручен — упоминает «Палочка
    — расширить по линии» чтобы smart-expand был discoverable.

- 2026-05-08: Step 4 — lasso + audience-mode search
  - **Lasso (drag-on-empty в selection-mode):** drag в пустом
    месте canvas'а в selection-mode рисует translucent
    accent-rounded rectangle через `_LassoRectPainter`. Все
    карточки, чей bounding box (centered на nodePositions)
    пересекается с lasso-rect'ом — подсвечиваются мягким
    accent-кольцом (1.6px, 65% alpha) пока drag активен. На
    pointer-up все они **строго аддитивно** добавляются в
    селекшен через `onPersonSelectionToggle` (не делает untoggle
    тех, кто уже был выбран — это inflate, не toggle).
  - Чтобы не подраться с InteractiveViewer'ом за drag-жест:
    `panEnabled = false` когда `_isSelectionLassoEnabled`
    (selectionMode + onPersonSelectionToggle != null), внешний
    GestureDetector на onPanStart/Update/End перехватывает
    pointer-stream. Cards с `HitTestBehavior.opaque` забирают
    себе tap-жест первыми, так что drag-on-card по-прежнему НЕ
    стартует lasso — drag-on-card в selection-mode просто
    становится no-op (тап остаётся как был — toggle).
  - Координаты конвертируются через
    `_transformationController.toScene(localPosition)` — lasso-
    rect живёт в canvas-space и не уплывает при пинч-зуме.
  - `_personsInsideLassoRect` итерирует `nodePositions.entries`
    и проверяет `Rect.overlaps` — O(N) на frame, при 200
    карточках это копейки.

  - **Search across audience:** `post_search_screen` больше не
    шлёт `treeId: selectedTreeId` в запрос. Search теперь
    audience-mode по дефолту: ищет по всем веткам, в которых
    юзер состоит. Зеркало того, что мы сделали с feed'ом — для
    того же самого юзкейса: «вспомнил, что бабушка постила
    свадебное фото — типаю «свадьба» в search и нахожу» вне
    зависимости от того, какая ветка активна в BranchSwitcher.
    Бэкенд `searchPosts` уже умел audience-mode (фильтр по
    branchIds + legacy treeId), нужно было только перестать
    клиенту самому себя ограничивать.

- 2026-05-08: Что осталось в RFC
  - **Step 4 phone-matching** — намеренно НЕ трогаю автономно.
    Privacy-чувствительная фича: разрешения на контакты,
    matching по номеру с identity-claims, two-way confirm. Нужно
    обсудить с юзером дизайн перед кодом.

- 2026-05-08: Step 5 — in-app notifications fan-out
  - Раньше пост создавался — и НИКТО не получал ни единого
    уведомления (ни in-app, ни push). Можно было замешкать,
    кто-то выложил свадебное фото — и оно ушло в feed без
    звонка. Это анти-тезис всему «меньше шума, больше близких»:
    не shum'a — но и НЕ доходило что вообще что-то случилось.
  - Теперь `createPost` после `db.posts.push(post)` фанаутит
    `post_created` notification по всему audience'у:
    union(`tree.memberIds` для каждой ветки в
    `[post.treeId, ...post.branchIds]`), за вычетом самого
    автора. Дедуп: один человек в нескольких ветках поста
    получит ОДНУ запись.
  - Coalesce'имся на pop-up retry: если у получателя уже
    лежит unread `post_created` для этого `postId` — не плодим
    дубль. (Работает в случае повторного клика «Опубликовать»
    с того же черновика.)
  - `sanitizeNotificationData` расширен: `authorId` (string) и
    `branchIds` (string array) теперь проходят через сериализатор.
    Раньше они дропались allow-list'ом.
  - Frontend: иконка для `post_created` (post_add_outlined),
    лейбл в инбоксе («Новый пост»), deep-link при тапе ведёт на
    home (`/`). Полноценного `/post/:postId` экрана пока нет,
    home показывает фид в audience-mode и свежий пост по
    конструкции уже наверху списка.
  - Test: `post creation fans out in-app notifications to
    audience members` — проверяет что (а) член любой из
    branchIds'ов получает уведомление, (б) автор НЕ получает,
    (в) посторонний (не в audience'е) НЕ получает,
    (г) `data.authorId` и `data.branchIds[]` проходят через
    sanitizer'а нетронутыми.

  - **Notification fan-out по audience** — закрыто in-app.
    Push-инфра (FCM/RuStore) когда будет подключена — пойдёт
    через те же `db.notifications` записи, что мы только что
    фанаутим, без доп. изменений в посте.

- 2026-05-08: Step 6 — push fan-out для постов / реакций / историй
  - **Аудит push-инфры:** на самом деле PushGateway уже был
    готов (RuStore + WebPush), endpoint `/v1/push/devices` для
    регистрации работает, мобильный клиент через
    `flutter_rustore_push` действительно регистрирует токен
    после логина. Что НЕ работало — половина серверных
    notification-сайтов создавала запись в `db.notifications`
    но **не вызывала** `pushGateway.dispatchNotification`.
    Поэтому юзер видел inbox-row на следующем pull'е, но
    телефон не звенел в реальном времени.
  - Какие types работали правильно (через
    `createAndDispatchNotification`): `chat_message`,
    `call_invite`, `tree_invitation`, `relation_request`,
    `merge_proposal`. Push доезжал.
  - Какие НЕ работали: `post_created` (только что добавил),
    `post_reaction`, `comment_reaction`, `comment_reply`,
    `story_reaction`. Все они шли через
    `store.addXxxNotification(...)` → создавали row → return,
    но push-gateway никто не дёргал.
  - **Refactor:** перенёс post_created fan-out из
    `store.createPost` в роутер `POST /v1/posts`. В store
    осталось `resolvePostAudienceUserIds(postId)` — чисто
    вычисление audience-set'а. Роутер берёт список и
    итерирует через `createAndDispatchNotification` (тот же
    helper что чат и звонки используют), который создаёт row,
    публикует realtime-событие И вызывает push-gateway.
  - Для post_reaction / comment_reaction / comment_reply /
    story_reaction логика осталась в store (там coalesce-логика
    «не плодить дубль если есть unread от того же актора»),
    но routes теперь после возврата notification-record'а
    вызывают `pushGateway.dispatchNotification(notif)`. Минимум
    изменений в store, push покрытие закрыто.
  - На клиенте `_registerRemotePushDevice()` уже регистрирует
    RuStore токен на `/v1/push/devices` после логина (в
    `startForegroundSync`). Если телефонные пуши всё ещё не
    идут — проверить prod env'ы:
    `RUSTORE_PUSH_PROJECT_ID` и `RUSTORE_PUSH_SERVICE_TOKEN`.
    Без них `rustorePushEnabled = false` и
    `_deliverRustorePush` тихо помечает delivery как
    `not_configured`.
