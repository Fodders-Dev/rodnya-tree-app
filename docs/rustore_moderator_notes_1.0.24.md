# RuStore Moderator Notes - 1.0.24

> Обновляет [rustore_moderator_notes_1.0.2.md](./rustore_moderator_notes_1.0.2.md). С версии 1.0.2 добавлены **голосовые и видеозвонки (в т.ч. групповые)** — они используют разрешения `CAMERA` и `RECORD_AUDIO`, которые нужно задекларировать в консоли вручную. Ниже — обоснование и сценарий проверки.

## Build Summary
- Приложение: `Родня`
- Package: `com.ahjkuio.rodnya_family_app`
- Store flavor: `rustore`
- Version: `1.0.24 (32)`
- Publish type: `MANUAL`
- Основной backend: `https://api.rodnya-tree.ru`

## Sensitive Permissions — обоснование
Все чувствительные разрешения запрашиваются только по действию пользователя и только для заявленных функций:
- `RECORD_AUDIO` — голосовые звонки, голосовые сообщения и видеокружки в чате. Запрашивается при инициации звонка/записи, не при старте приложения.
- `CAMERA` — видеозвонки и видеокружки. Запрашивается при включении камеры в звонке или записи кружка, не при старте приложения.
- `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` / `READ_MEDIA_AUDIO` / `READ_EXTERNAL_STORAGE` — прикрепление фото/видео/аудио к сообщениям.
- `POST_NOTIFICATIONS` — уведомления о входящих звонках и сообщениях.
Приложение не ведёт скрытую запись: индикаторы «микрофон выключен» и «говорит» видны в интерфейсе звонка, звонок держит foreground-сервис и виден в шторке.

## What To Check
- вход и навигация по приложению;
- семейное дерево и карточки родственников;
- **голосовой звонок** между двумя demo-аккаунтами;
- **видеозвонок** (проверка запроса CAMERA + RECORD_AUDIO по действию пользователя);
- **групповой созвон**: третий участник «залетает» в идущий звонок / добавление участника на ходу;
- личный чат, медиа-вложение и видеокружок;
- публичные legal/support страницы;
- встроенное удаление аккаунта.

## Demo Scenario
- Основной demo dataset уже развёрнут на production API.
- Secure credentials и готовый moderator comment лежат локально (НЕ в git):
  - `.tmp/rustore_moderation_credentials_2026-04-12.md` (актуализировать под 1.0.24, если менялись demo-аккаунты)
  - обновить moderator comment: `.tmp/rustore_moderator_comment_1.0.24.txt`
- Для проверки звонка нужны ДВА устройства/сессии (звонок — это связь между двумя аккаунтами). Второй demo-аккаунт — «Смоук Тест».

## Expected Review Flow
1. Войти под primary demo account.
2. Открыть дерево `Семья для модерации RuStore` — готовые карточки и связи.
3. Открыть direct chat demo account: текст + медиа-вложение + видеокружок.
4. Позвонить второму demo-аккаунту: сначала аудио, затем включить видео — убедиться, что CAMERA/RECORD_AUDIO запрашиваются по действию, а звонок виден в шторке.
5. (Опц.) Групповой чат: начать созвон, третьим аккаунтом «Войти» в идущий звонок.
6. Публичные страницы без авторизации:
   - `https://rodnya-tree.ru/#/privacy`
   - `https://rodnya-tree.ru/#/terms`
   - `https://rodnya-tree.ru/#/support`
   - `https://rodnya-tree.ru/#/account-deletion`

## Store/SDK Notes
- RuStore Review SDK — только запрос отзыва внутри приложения.
- RuStore Update SDK — только проверка доступности обновления.
- RuStore Push SDK — Android push path (входящие звонки/сообщения).
- Медиа-транспорт звонков — WebRTC/LiveKit (собственный сервер); контент звонка не хранится на сервере.
- Billing path не является функцией этого релиза и в `rustore` контуре не активен.

## Support Notes
- Support email: `ahjkuio@gmail.com`
- Privacy/security contact: `ahjkuio@gmail.com`

## Operational Notes
- Production backend: `postgres + s3`.
- Delete-account cascade проверен на production (удаляет state и media objects).
- Звонки/уведомления/сообщения на бэкенде переведены на атомарный store (гонки списка участников звонка закрыты).
