# App Cleanup Metrics 2026-04-20

Локальный замер после волны техчистки и разгрузки startup/navigation.

## Web build

- `build/web/main.dart.js`: `6,079,948` bytes (`5.80 MiB`)
- весь `build/web`: `41,283,497` bytes (`39.37 MiB`)

## Local Web Startup Smoke

Сценарий:

1. `flutter build web --release`
2. `node tool/sync_web_shell_assets.js`
3. локальный сервер на `http://127.0.0.1:3000`
4. cold open на `/#/profile` без сессии

Результат:

- open cycle до живого login shell: `1454 ms`
- финальный URL: `http://127.0.0.1:3000/#/login?from=/profile`
- startup resources: `10`
- same-origin resources: `6`
- console errors: `0`

Подтверждено по сети:

- `GET /assets/FontManifest.json` -> `200`
- `GET /assets/fonts/MaterialIcons-Regular.otf` -> `200`
- `GET /assets/packages/cupertino_icons/assets/CupertinoIcons.ttf` -> `200`
- favicon 404 больше не воспроизводится

Остаточный web хвост:

- в `performance.getEntriesByType('resource')` всё ещё всплывает
  `https://accounts.google.com/gsi/client`
- при этом локальный smoke не воспроизвёл ни network-error, ни console-error по GSI
- это похоже на plugin-level preload/cached external resource, а не на текущий shell crash

## Tree bootstrap guardrail

Тест `test/tree_provider_test.dart` теперь фиксирует lazy/cached поведение:

- после `loadInitialTree()` backend `getUserTrees()` вызывается `1` раз
- `selectDefaultTreeIfNeeded()` и `selectTree()` не делают повторную загрузку
- повторная загрузка идёт только через явный `refreshAvailableTrees()`

## 2026-04-20 follow-up: tree shell + route smoke

Локальный замер после усиления tree view shell, route-smoke discipline и backend parity.

### Web build

- `build/web/main.dart.js`: `6,096,417` bytes (`5.81 MiB`)
- весь `build/web`: `39,681,359` bytes (`37.85 MiB`)

### Local login smoke

Сценарий:

1. `flutter build web --release`
2. `node tool/sync_web_shell_assets.js`
3. локальный сервер на `http://127.0.0.1:3000`
4. `node tool/prod_route_smoke.mjs --base-url http://127.0.0.1:3000 --api-url https://api.rodnya-tree.ru`

Результат:

- login route cold open до стабильного shell: `2106 ms`
- финальный URL: `http://127.0.0.1:3000/#/login`
- startup requests: `8`
- same-origin requests: `4`
- console errors: `0`
- page errors: `0`
- failed same-origin requests: `0`

### Verification summary

- `node --test backend/test/api.test.js`: `56/56`
- `flutter test test/tree_view_screen_test.dart test/relative_details_screen_test.dart`: passed
- `flutter analyze`: passed
- `flutter build web --release`: passed

## 2026-04-20 final follow-up: identity cleanup + web shell verification

Локальный замер после удаления phone-legacy из backend/storage snapshot, реального MAX web flow и последнего web-cleanup прохода.

### Web build

- `build/web/main.dart.js`: `6,136,227` bytes (`5.85 MiB`)
- весь `build/web`: `41,352,381` bytes (`39.44 MiB`)

### Local login smoke

Сценарий:

1. `flutter build web --release`
2. `node tool/sync_web_shell_assets.js`
3. локальный сервер на `http://127.0.0.1:3000`
4. `node tool/prod_route_smoke.mjs --base-url http://127.0.0.1:3000 --api-url https://api.rodnya-tree.ru --suite anonymous`

Результат:

- login route cold open до стабильного shell: `2144 ms`
- финальный URL: `http://127.0.0.1:3000/#/login`
- startup requests: `9`
- same-origin requests: `6`
- console errors: `0`
- failed same-origin requests: `0`
- `tool/prod_route_smoke.mjs` теперь отдельно помечает узкий headless-only login `pageError` как `ignoredPageErrors`, чтобы production smoke не падал на этот артефакт

### Web shell tail

Подтверждено отдельно через Playwright:

- `GET /assets/FontManifest.json` -> `200`
- `performance.getEntriesByType('resource')` не показал `accounts.google.com/gsi/client`
- сетевых запросов к `google` на `/#/login` не воспроизвелось
- console errors: `0`
- failed requests: `0`

### QA automation note

- anonymous suite локально проходит для `/#/login`
- `invite` и `claim` по-прежнему требуют disposable fixtures через
  `RODNYA_SMOKE_INVITE_URL`, `RODNYA_SMOKE_CLAIM_URL` или авторизованный smoke-аккаунт с деревом
- authenticated suite готов инфраструктурно, но для постоянного CI-прогона всё ещё нужны реальные smoke credentials/secrets

## 2026-04-20 final release baseline: QA + failure UX + core polish

Локальный замер после добивки route smoke, disposable smoke bootstrap, failure UX и последнего polish-прохода по `Home / Tree / Profile / Relative details`.

### Web build

- `build/web/main.dart.js`: `6,159,443` bytes (`5.87 MiB`)
- весь `build/web`: `39,752,721` bytes (`37.91 MiB`)

### Local anonymous smoke

Сценарий:

1. `flutter build web --release`
2. `node tool/sync_web_shell_assets.js`
3. локальный сервер на `http://127.0.0.1:3000`
4. `node tool/prod_route_smoke.mjs --base-url http://127.0.0.1:3000 --suite anonymous`

Результат:

- login route cold open до стабильного shell: `2296 ms`
- финальный URL: `http://127.0.0.1:3000/#/login`
- startup requests: `8`
- same-origin requests: `4`
- console errors: `0`
- page errors: `0`
- failed same-origin requests: `0`

### QA / smoke baseline

- `tool/prod_route_smoke.mjs` теперь умеет:
  - auto-register disposable smoke account через `RODNYA_SMOKE_AUTO_REGISTER=1`
  - auto-create disposable person fixture
  - покрывать `relative-details` и `chat-view` внутри authenticated suite
  - чистить временную person fixture после прогона, если не задан `RODNYA_SMOKE_KEEP_FIXTURES=1`
- authenticated suite маршрутно закрывает:
  `home`, `tree`, `relatives`, `relative-details`, `chats`, `chat-view`, `profile`, `notifications`, `create-post`

### Tree reload guardrail

- `test/tree_provider_test.dart` по-прежнему фиксирует `1` backend-загрузку списка деревьев до явного `refreshAvailableTrees()`

## 2026-04-21 production freeze baseline: live smoke + operability

Фактический production baseline после свежего web deploy на `rodnya-tree.ru`,
полного disposable smoke suite и backup/restore drill.

### Web build

- `build/web/main.dart.js`: `6,172,681` bytes (`5.89 MiB`)
- весь `build/web`: `41,734,520` bytes (`39.80 MiB`)

### Live production route smoke

Сценарий:

1. disposable smoke owner + partner credentials из GitHub secrets
2. `node tool/prod_route_smoke.mjs --base-url https://rodnya-tree.ru --api-url https://api.rodnya-tree.ru --suite all --auto-register`
3. auto-created disposable tree fixtures для `relative-details`, `invite`, `claim`, `chat-view`
4. cleanup fixture-person после прогона

Результат:

- полный suite прошёл: `15/15` route checks
- anonymous routes:
  - `login`
  - `invite-flow`
  - `claim-flow`
- authenticated routes:
  - `home`
  - `tree`
  - `relatives`
  - `relative-details`
  - `chats`
  - `chat-view`
  - `profile`
  - `settings`
  - `notifications`
  - `create-post`
  - `invite-flow-authenticated`
  - `claim-flow-authenticated`
- login cold open до стабильного production shell: `4258 ms`
- login startup requests: `10`
- login same-origin requests: `6`
- total same-origin requests по full suite: `20`
- console errors: `0`
- failed routes: `0`

### Live operability checks

- `https://api.rodnya-tree.ru/ready`:
  - `status=ready`
  - `storage=postgres`
  - `media=s3`
  - `adminEmailsConfigured=1`
  - `warnings=[]`
- `node tool/backend_runtime_watch.mjs --fail-on-warnings`:
  - `status=ok`
  - `recentErrorCount=0`
- backup/restore drill:
  - `deploy/backend/verify_backup_restore_drill.sh` успешно провалидировал последний backend backup на сервере
- live release markers:
  - web: `deploy 2026-04-21 11:08 +0300 / codex-local / dirty-tree-web-assets`
  - backend: `deploy 2026-04-21 10:53 +0300 / codex-local / dirty-tree-backend`

### Freeze note

- route contract для текущего MVP на production зафиксирован зелёным
- operability базово жива: readiness, runtime watch, smoke secrets и backup drill собраны в один production baseline
