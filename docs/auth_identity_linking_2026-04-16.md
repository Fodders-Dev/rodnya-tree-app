# Auth identity linking - 2026-04-16

## Цель
- Добавить вход через `Telegram`, `VK ID`, `MAX`, `Google` без размножения аккаунтов.
- Сохранить текущий `email/password` flow как базовый и восстановительный.
- Не делать небезопасные "фейковые" привязки без server-side валидации провайдера.

## Текущая опорная модель
- У каждого пользователя остаётся основной аккаунт приложения.
- К аккаунту можно привязать несколько `auth identity`.
- `auth identity` хранит:
  - `provider`
  - `providerUserId`
  - `linkedAt`
  - `lastUsedAt`
  - вспомогательные claims: `email`, `phoneNumber`, `normalizedPhoneNumber`, `displayName`
- Для обратной совместимости остаётся `providerIds`, но источником истины становится список `authIdentities`.

## Порядок дедупликации
1. Точное совпадение `provider + providerUserId`.
2. Совпадение по email.
3. Ручной merge через invite/claim/profile code, если автоматического матча нет.
4. Только если совпадений нет и сценарий это допускает - создание нового аккаунта.

## Новая модель доверия
- `Telegram`, `VK ID`, `MAX`, `Google` теперь считаются подтверждёнными каналами и способами входа.
- UI больше не обещает `подтверждённый номер`; вместо этого продукт показывает:
  - `Аккаунт подтверждён через ...`
  - `Связь подтверждена через ...`
  - `Основной канал: ...`
- Поиск и связывание родственников больше не завязаны на телефон: основной путь теперь `username`, `profile code`, `invite`, `claim`, `QR`.

## Что уже заложено в код
- Backend foundation для `authIdentities`, `linkAuthIdentity`, `findUserByAuthIdentity`, `resolveAuthIdentityTarget`.
- Сервисный route `GET /v1/profile/me/account-linking-status` для trusted channels, primary channel и merge-стратегии.
- `MAX` mini app flow уже реализован на backend и web:
  - `GET /v1/auth/max/start`
  - `POST /v1/auth/max/complete`
  - `POST /v1/auth/max/exchange`
  - `POST /v1/auth/max/link`
- Логика поиска/связывания уже ориентирована на `provider identity + email + invite/claim/profile code`, а phone-based discovery удалён из активного продукта.

## Что ещё нужно для real provider activation

### Google
- Android: перейти на `Credential Manager` / `Sign in with Google`, а не новый legacy GSI.
- Web: использовать `Google Identity Services`.
- Backend: проверка `id_token`, `aud`, `iss`, `exp`, nonce и сопоставление с `providerUserId=sub`.
- Нужны реальные `Android client ID`, `Web client ID`, SHA-1/SHA-256 и consent setup.

### Telegram
- Для web/app login использовать актуальный `Log In With Telegram`:
  - либо новый `OIDC Authorization Code Flow with PKCE`
  - либо legacy login widget только там, где он действительно уместен
- Нужны:
  - bot
  - allowed URLs / redirect URIs
  - client id / secret
  - server-side валидация `id_token`
- Для mini app сценариев можно отдельно использовать Telegram Mini Apps, но это другой контекст, не замена standalone login.

### VK ID
- Использовать официальный `VK ID SDK` / `OAuth 2.1` flow.
- Нужны `APP_ID`, redirect URL, scope policy и server-side обмен/валидация.
- В качестве `providerUserId` использовать стабильный subject из VK ID, а не username или телефон.

### MAX
- В repo уже работает реальный `MAX mini app / webapp inside MAX` flow с server-side валидацией `WebAppData` через bot token.
- На текущем этапе это production-ready путь для web-based linking/login handoff.
- Отдельный standalone mobile deep-link return для Android остаётся follow-up задачей; он не нужен для web auth внутри MAX, но нужен для полноценного native mobile UX.

## Практический rollout порядок
1. Держать `provider identity + email + invite/claim/profile code` как единую trust/linking модель.
2. Доделать production parity для `Google`, `Telegram`, `VK ID`.
3. Довести native return-to-app для `MAX` на Android, не ломая уже работающий web/mini-app flow.
4. После этого усиливать merge UX и ручное объединение дублей, но без возврата к phone-based discovery.
