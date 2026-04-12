# Lineage Minimal Backend

Минимальный self-hostable backend contract для dev-переключения Flutter-приложения на `customApi` без Firebase Auth/Profile bootstrap.

## Что реализовано

- `POST /v1/auth/register`
- `POST /v1/auth/login`
- `POST /v1/auth/logout`
- `GET /v1/auth/session`
- `POST /v1/auth/password-reset`
- `DELETE /v1/auth/account`
- `POST /v1/auth/google` с явным `501 Not Implemented`
- `GET /v1/profile/me/bootstrap`
- `PUT /v1/profile/me/bootstrap`
- `PATCH /v1/profile/me`
- `POST /v1/profile/me/verify-phone`
- `GET /v1/users/:id/profile-notes`
- `POST /v1/users/:id/profile-notes`
- `PATCH /v1/users/:id/profile-notes/:noteId`
- `DELETE /v1/users/:id/profile-notes/:noteId`
- `GET /v1/users/search`
- `GET /v1/users/search/by-field`
- `GET /v1/users/:id/profile`
- `PATCH /v1/users/:id/profile`
- `POST /v1/invitations/pending/process`
- `POST /v1/media/upload`
- `DELETE /v1/media`
- `GET /v1/posts`
- `POST /v1/posts`
- `DELETE /v1/posts/:postId`
- `POST /v1/posts/:postId/like`
- `GET /v1/posts/:postId/comments`
- `POST /v1/posts/:postId/comments`
- `DELETE /v1/posts/:postId/comments/:commentId`
- `POST /v1/trees`
- `GET /v1/trees`
- `DELETE /v1/trees/:treeId`
- `GET /v1/trees/selectable`
- `GET /v1/trees/:treeId/persons`
- `POST /v1/trees/:treeId/persons`
- `GET /v1/trees/:treeId/persons/:personId`
- `PATCH /v1/trees/:treeId/persons/:personId`
- `DELETE /v1/trees/:treeId/persons/:personId`
- `GET /v1/trees/:treeId/relations`
- `POST /v1/trees/:treeId/relations`
- `POST /v1/trees/:treeId/invitations`
- `GET /v1/trees/:treeId/relation-requests`
- `POST /v1/trees/:treeId/relation-requests`
- `GET /v1/tree-invitations/pending`
- `POST /v1/tree-invitations/:invitationId/respond`
- `GET /v1/relation-requests/pending`
- `POST /v1/relation-requests/:requestId/respond`
- `GET /v1/chats`
- `GET /v1/chats/unread-count`
- `POST /v1/chats/direct`
- `GET /v1/chats/:chatId/messages`
- `POST /v1/chats/:chatId/messages`
- `PATCH /v1/chats/:chatId/messages/:messageId`
- `DELETE /v1/chats/:chatId/messages/:messageId`
- `POST /v1/chats/:chatId/read`
- `GET /v1/blocks`
- `POST /v1/blocks`
- `DELETE /v1/blocks/:blockId`
- `POST /v1/reports`
- `GET /v1/admin/reports`
- `POST /v1/admin/reports/:reportId/resolve`
- `GET /v1/notifications`
- `GET /v1/notifications/unread-count`
- `POST /v1/notifications/:notificationId/read`
- `GET /v1/push/devices`
- `GET /v1/push/web/config`
- `POST /v1/push/devices`
- `DELETE /v1/push/devices/:deviceId`
- `GET /v1/push/deliveries`
- `GET /media/*`
- `GET /health`
- `GET /ready`
- `WS /v1/realtime?accessToken=...`

## Запуск

```powershell
cd backend
npm install
npm start
```

По умолчанию сервер поднимается на `http://127.0.0.1:8080`.

## Переменные окружения

- `PORT` - порт сервера, по умолчанию `8080`
- `LINEAGE_BACKEND_DATA_PATH` - путь к JSON-файлу dev-хранилища, по умолчанию `backend/data/dev-db.json`
- `LINEAGE_BACKEND_STORAGE` - backend storage adapter, по умолчанию `file`; поддерживаются `file` и `postgres`
- `LINEAGE_BACKEND_CORS_ORIGIN` - CORS origin, по умолчанию `*`
- `LINEAGE_BACKEND_MEDIA_ROOT` - папка для сохранения media-файлов, по умолчанию `backend/data/uploads`
- `LINEAGE_MEDIA_BACKEND` - media storage adapter, по умолчанию `local`; поддерживаются `local` и `s3`
- `LINEAGE_MEDIA_PUBLIC_BASE_URL` - публичная HTTPS-база для object storage media URL, например `https://cdn.rodnya-tree.ru/media`
- `LINEAGE_PUBLIC_API_URL` - публичная база backend API для генерации media URL, например `https://api.rodnya-tree.ru`
- `LINEAGE_PUBLIC_APP_URL` - публичный URL web-приложения, по умолчанию `https://rodnya-tree.ru`
- `LINEAGE_POSTGRES_URL` / `DATABASE_URL` - строка подключения к PostgreSQL, обязательна для `LINEAGE_BACKEND_STORAGE=postgres`
- `LINEAGE_POSTGRES_SCHEMA` - PostgreSQL schema для state snapshot, по умолчанию `public`
- `LINEAGE_POSTGRES_STATE_TABLE` - таблица для state snapshot, по умолчанию `lineage_state`
- `LINEAGE_POSTGRES_STATE_ROW_ID` - ключ строки со state snapshot, по умолчанию `default`
- `LINEAGE_S3_ENDPOINT` - endpoint S3-compatible object storage
- `LINEAGE_S3_REGION` - region object storage, по умолчанию `ru-msk`
- `LINEAGE_S3_BUCKET` - bucket для media объектов
- `LINEAGE_S3_ACCESS_KEY_ID` - access key для object storage
- `LINEAGE_S3_SECRET_ACCESS_KEY` - secret key для object storage
- `LINEAGE_S3_FORCE_PATH_STYLE` - path-style addressing для S3 client, по умолчанию `true`
- `LINEAGE_S3_PREFIX` - префикс объектов в bucket, по умолчанию `lineage`

### Migration toolkit

- `npm run migrate:state:postgres` - переносит snapshot из file store в `PostgreSQL` и сверяет SHA-256 source/target snapshot.
- `npm run migrate:media:s3` - переносит local media tree в `S3-compatible object storage`.
- Полезные флаги:
  - `--dry-run` - прогоняет source/summary без записи.
  - `--source=/path/to/dev-db.json` для state migration.
  - `--source-root=/path/to/uploads` для media migration.
  - `--create-bucket` для media migration, если bucket ещё не создан.
  - `--public-read` вместе с `--create-bucket`, если object storage должен отдавать media URL напрямую по HTTPS.
- Рекомендуемый production cutover path:
  1. сделать backup текущего `dev-db.json` и `uploads/`;
  2. прогнать `migrate:state:postgres` и `migrate:media:s3` на тех же production данных;
  3. переключить backend env на `LINEAGE_BACKEND_STORAGE=postgres` и `LINEAGE_MEDIA_BACKEND=s3`;
  4. проверить `/ready`, chat/media open, media delete и auth/account delete.
- `LINEAGE_WEB_PUSH_PUBLIC_KEY` - публичный VAPID key для browser push
- `LINEAGE_WEB_PUSH_PRIVATE_KEY` - приватный VAPID key для browser push
- `LINEAGE_WEB_PUSH_SUBJECT` - VAPID subject, по умолчанию `https://rodnya-tree.ru`
- `LINEAGE_RUSTORE_PUSH_PROJECT_ID` - ID проекта RuStore Push из RuStore Console
- `LINEAGE_RUSTORE_PUSH_SERVICE_TOKEN` - сервисный токен RuStore Push из RuStore Console
- `LINEAGE_RUSTORE_PUSH_API_BASE_URL` - базовый URL RuStore Push API, по умолчанию `https://vkpns.rustore.ru`
- `LINEAGE_BACKEND_ADMIN_EMAILS` - список email модераторов через запятую для admin endpoints `/v1/admin/reports`
- `LINEAGE_RATE_LIMIT_WINDOW_MS` - окно rate limiting в миллисекундах, по умолчанию `60000`
- `LINEAGE_RATE_LIMIT_DEFAULT_MAX` - лимит для read-heavy трафика в окне, по умолчанию `600`
- `LINEAGE_RATE_LIMIT_AUTH_MAX` - лимит для login/register/password-reset, по умолчанию `30`
- `LINEAGE_RATE_LIMIT_MUTATION_MAX` - лимит для mutating API в окне, по умолчанию `180`
- `LINEAGE_RATE_LIMIT_UPLOAD_MAX` - лимит для media upload, по умолчанию `40`
- `LINEAGE_RATE_LIMIT_SAFETY_MAX` - лимит для reports/blocks, по умолчанию `20`

## Подключение Flutter dev-сборки

```powershell
flutter run `
  --dart-define=LINEAGE_AUTH_PROVIDER=customApi `
  --dart-define=LINEAGE_PROFILE_PROVIDER=customApi `
  --dart-define=LINEAGE_TREE_PROVIDER=customApi `
  --dart-define=LINEAGE_CHAT_PROVIDER=customApi `
  --dart-define=LINEAGE_STORAGE_PROVIDER=customApi `
  --dart-define=LINEAGE_NOTIFICATION_PROVIDER=customApi `
  --dart-define=LINEAGE_API_BASE_URL=http://127.0.0.1:8080 `
  --dart-define=LINEAGE_WS_BASE_URL=ws://127.0.0.1:8080 `
  --dart-define=LINEAGE_ENABLE_LEGACY_DYNAMIC_LINKS=false
```

## Ограничения

- Это dev bootstrap backend, а не финальный production backend.
- Backend теперь умеет подниматься и на `PostgreSQL`, и на file-backed JSON snapshot. JSON snapshot остаётся dev-path по умолчанию.
- `Google sign-in`, remote push и realtime/websocket здесь ещё не реализованы полноценно.
- Media upload теперь умеет работать и через S3-compatible object storage, и через локальный filesystem adapter.
- Tree API сейчас покрывает базовый MVP-срез: создание дерева, список деревьев, людей и прямые родственные связи.
- Tree invitations тоже покрыты в минимальном виде: backend умеет создать pending invite, показать его на вкладке приглашений и принять или отклонить.
- Relation requests и invite-link processing теперь тоже покрыты в минимальном виде для `customApi` dev-path.
- Chat API сейчас покрывает базовый MVP-срез: список чатов, историю сообщений, отправку и отметку как прочитанных через polling-stream на клиенте.
- Notification feed тоже покрыт в минимальном виде: backend создаёт unread-события для сообщений, заявок на родство и приглашений в дерево, а Flutter `customApi` path может забирать их polling-ом и показывать как локальные уведомления.
- Realtime-путь теперь тоже есть: backend поднимает `WS /v1/realtime`, а Flutter `customApi` chat/notification path может получать server-driven события для новых сообщений и уведомлений.
- Remote push теперь умеет реально доставлять browser push через Web Push API и RuStore push через `vkpns.rustore.ru`, если backend запущен с нужными ключами. Без `LINEAGE_RUSTORE_PUSH_*` или `LINEAGE_WEB_PUSH_*` переменных соответствующий канал остаётся в состоянии `*_not_configured`.
- Browser push теперь поддерживается отдельно через Web Push API и VAPID, если backend запущен с `LINEAGE_WEB_PUSH_*` ключами.
- Moderation layer теперь минимально покрыт: есть жалобы, блокировки и ручной admin resolve path, а direct chat не даст создать или отправить сообщение между заблокированными пользователями.
- Operational hardening тоже теперь есть в минимальном виде: `x-request-id`, `GET /ready`, базовый in-memory rate limiting и структурированный request/error log.
- Startup больше не прибит напрямую к `FileStore`: backend поднимает и state storage, и media storage через factory, так что `PostgreSQL + object storage` можно включать конфигом без big-bang rewrite.
