# План: rich profiles, visibility и cleanup identity/delete-account

## Цель
- Превратить профиль из короткой карточки в живое семейное досье: человек должен уметь рассказать о себе больше, чем имя и город.
- Сделать это безопасно: каждое содержательное поле должно иметь управляемую видимость.
- Сохранить MVP-темп: сначала foundation и совместимость текущего backend, потом точечное расширение UI и privacy rules, без big-bang rewrite.

## Что должен уметь профиль

### Базовые поля
- Имя, фамилия, отчество
- Username
- Фото
- Пол
- Дата рождения
- Девичья фамилия
- Страна и город
- Основной номер телефона с подтверждением

### Rich profile поля
- `bio`: кратко о себе
- `familyStatus`: семейное положение
- `aboutFamily`: что человек хочет рассказать семье о доме, близких и традициях
- `education`: учёба, школа, вуз, курсы
- `work`: работа, дело, проекты
- `hometown`: родной город или место, с которым человек себя ассоциирует
- `languages`: языки, на которых говорит человек или которые важны семье
- `values`: ценности, принципы, что важно в жизни
- `religion`: религия или мировоззрение
- `interests`: интересы и увлечения, которые помогают родственникам лучше понимать человека

### Дальше по roadmap
- Несколько мест учёбы и работы с периодами
- Дети, браки, переезды как структурированные события
- Любимые семейные традиции, памятные даты, языки, интересы
- История фамилии/ветки/рода

## Visibility model

### Слои доступа
- `private`: вижу только я
- `shared_trees`: видят пользователи, у которых со мной есть общее дерево
- `public`: видят все авторизованные пользователи Родни

### Следующий шаг после foundation
- `specific_trees`: показывать конкретным деревьям
- `specific_branches`: показывать ветке внутри дерева
- `specific_users`: показывать выбранным людям

### Разделы профиля и их видимость
- `contacts`: email, телефон, страна, город
- `about`: bio, familyStatus, aboutFamily
- `background`: education, work, hometown, languages, maidenName, birthDate, gender
- `worldview`: values, religion, interests

### Принцип отдачи данных
- Self-view всегда получает полный профиль и полные visibility settings.
- Другие пользователи получают только разрешённые поля.
- Search/discovery/contacts import не должны возвращать полный профиль. Только preview-поля: имя, username, фото, id.

## Фазы реализации

### Phase 1. Foundation
- Расширить backend profile schema новыми rich profile полями.
- Добавить `profileVisibility` как section-based map.
- На `GET /v1/users/:userId/profile` применить visibility-aware sanitization.
- На `search` и `discover-by-phones` перейти на минимальный preview payload.
- Во Flutter добавить редактирование rich profile полей и базовый выбор видимости по секциям.
- Во Flutter на экране чужого профиля показать видимые блоки и сообщение, что часть профиля скрыта.
- Убрать web tail: после `delete-account` не слать анонимный stories request.

Статус на `2026-04-17`:
- foundation slice полностью живёт и на production, не только локально
- `/#/profile/edit` уже рендерит `aboutFamily`, `hometown`, `languages`, `interests` внутри существующих секций без отдельного UI-экрана
- live API smoke подтвердил, что новые поля сохраняются и проходят через section visibility rules
- live browser smoke подтвердил outsider-view на `/#/user/:userId`: публичный `background` показывает `Родной город` и `Языки`, а приватные `about/worldview` блоки остаются скрыты

### Phase 2. Tree-aware privacy
- Добавить `specific_trees` в backend и UI.
- Ввести серверный резолвер "есть ли у viewer доступ через конкретное дерево".
- Отобразить в UI, кому именно откроется блок.

Статус на `2026-04-17`:
- `specific_trees` уже работает в backend visibility sanitization.
- Flutter `/#/profile/edit` уже умеет выбирать конкретные деревья для section visibility.
- Live production smoke подтвердил, что section с `specific_trees` реально видят только участники выбранного дерева.

### Phase 3. Branch and people targeting
- Ввести `specific_branches` и `specific_users`.
- Добавить picker деревьев/веток/людей.
- Вынести privacy editor в отдельный переиспользуемый bottom sheet/dialog.

Статус на `2026-04-17`:
- `specific_users` уже поддержан в backend visibility rules и во Flutter UI через picker конкретных людей.
- `specific_branches` теперь тоже выкачен: backend считает branch access только сервером через `sharedTreeIds + branchRootMatches`, а Flutter `/#/profile/edit` уже умеет выбирать конкретные ветки без отдельного экрана.
- Live production API smoke подтвердил, что `profileVisibility.contacts.scope = specific_branches` сохраняется и отдаётся текущим backend build.

### Phase 4. Structured life data
- Множественные записи по учёбе и работе.
- Хронология жизненных этапов.
- Отдельные семейные факты, которые можно прикреплять к дереву и людям.

## Identity / account linking хвосты, которые обязаны идти рядом

### Native identity parity
- Текущая duplicate/identity parity на production всё ещё держится на runtime shim.
- Нужно довести production backend до native состояния и убрать временный shim path.
- Минимальный критерий готовности:
  - `claim` без дублей работает без shim
  - `identityId` стабильно возвращается в accept/claim responses
  - повторный claim в другом дереве переиспользует тот же identity

Статус на `2026-04-17`:
- Production backend синхронизирован с текущим repo state.
- Активный Caddy admin override на `:8081` снят через reload из `/etc/caddy/Caddyfile`.
- Runtime `claim_merge_shim` остановлен, `:8081` больше не слушает.
- Live claim smoke после выключения shim прошёл успешно: дублей нет, relation remap корректный, `identityId` стабилен и повторно используется между деревьями.

### Primary phone как dedupe anchor
- Подтверждённый телефон должен стать главным merge-signal между соцлогинами.
- Источником доверия становится `provider identity + email + invite/claim/profile code`.
- Смена контактного телефона больше не считается security-событием уровня trust model.
- Следующий обязательный шаг после foundation: довести provider-based linking и primary trusted channel UX до production-polish.

Статус на `2026-04-20`:
- SMS/phone verification удалены из активного продукта и backend контракта.
- Trusted channels в профиле теперь опираются на `Telegram / VK / MAX / Google`.
- Поиск и связывание родственников идут через `username`, `profile code`, `invite`, `claim`, `QR`.
- MAX mini-app flow уже реализован на backend и web; отдельный Android return-to-app остаётся follow-up.

## Delete-account хвост
- После удаления аккаунта web всё ещё ловил хвостовой `401` на stories teardown.
- Это должно быть устранено на клиенте: при отсутствии access token stories-запрос вообще не уходит в сеть.

Статус на `2026-04-17`:
- Repo-side guard уже выкачен на production web.
- Live disposable-account smoke подтвердил, что delete-account возвращает пользователя на `/#/login` без runtime console errors и без воспроизводимого stories `401`.

## Что делается в этом проходе
- [x] План вынесен в отдельный документ
- [x] Delete-account stories teardown закрывается локально без сетевого `401`
- [x] Первый foundation slice rich profiles и section visibility начинается в backend/client
- [x] Native identity parity без runtime shim
- [x] `specific_trees` и `specific_users` выведены в production UI
- [x] `specific_branches` targeting в UI/backend
- [x] Реальный OTP flow на backend/client
- [ ] Production SMS provider config

## Риски
- Слишком ранний вывод полного rich profile в search/discovery даст privacy leakage.
- Visibility без server-side enforcement бессмысленна, поэтому сервер остаётся источником истины.
- Branch-level privacy нельзя делать на клиенте: доступ должен резолвиться только на backend.
- Реальный SMS/OTP остаётся инфраструктурно зависимым: без SMS provider credentials production может только честно блокировать отправку, но не доставлять код.
