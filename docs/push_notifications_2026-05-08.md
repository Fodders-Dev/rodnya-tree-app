# Push notifications — как это работает

Дата: 2026-05-08
Контекст: ответ на вопрос пользователя «как RuStore SDK на устройстве
получить?» и почему пуши не приходят.

## Двухканальная схема

У Rodnya два канала пушей. Один на твоём устройстве работает в
зависимости от того, ОТКУДА оно открывает приложение:

- **Web (rodnya-tree.ru)** — Web Push API через VAPID. Browser
  спрашивает разрешение, мы регистрируем PushSubscription на
  бэке. Push идёт через стандартный Web Push protocol через
  Mozilla / Apple / Google FCM (для Chrome).
- **Android (apk)** — RuStore Push SDK через VK Push Notification
  Service (`vkpns.rustore.ru`). Не требует Google Play Services
  (важно: на устройствах без GPS работает), не требует чтобы
  RuStore-приложение было установлено.

Код одинаковый со стороны бэкенда — `PushGateway.dispatchNotification`
смотрит на `provider` зарегистрированного `pushDevice` и
переключается на нужный путь:
- `provider: 'webpush'` → Web Push protocol
- `provider: 'rustore'` → POST на `vkpns.rustore.ru`

## Что нужно чтобы Android-пуши работали

Три предусловия (все три должны выполниться):

### 1. Backend знает credentials

В `/etc/rodnya-backend.env` на проде должны быть:
```
RODNYA_RUSTORE_PUSH_PROJECT_ID=...
RODNYA_RUSTORE_PUSH_SERVICE_TOKEN=...
```
Берутся в RuStore Console → Push → твой проект → Service token.

**Проверка:** `curl https://api.rodnya-tree.ru/ready | jq .rustorePushEnabled`
должен вернуть `true`. Сейчас на проде стоит `true` ✓.

### 2. APK собран с тем же projectId

`android/app/build.gradle` стампит project ID в манифест как
manifest-placeholder при сборке:
```gradle
def rustorePushProjectId = (readEnv("RODNYA_RUSTORE_PUSH_PROJECT_ID")
        ?: findProperty("rodnyaRustorePushProjectId")
        ?: "q9oXlaEo25nBYnMe2cn3BtGpaBVWH0Mb").toString()

manifestPlaceholders += [
    rustoreApplicationId : rustoreApplicationId,
    rustorePushProjectId : rustorePushProjectId,
]
```

То есть **SDK уже зашит в APK** (`flutter_rustore_push 6.5.0`,
`ru.rustore.sdk:pushclient:6.5.0`). Юзеру ничего не надо
устанавливать отдельно — SDK живёт внутри установленного APK.

**ОЧЕНЬ ВАЖНО:** projectId на бэке (env) и в APK (gradle build
arg / default) должны быть ОДНИМ И ТЕМ ЖЕ. Если они разные,
RuStore вернёт `INVALID_TOKEN`.

### 3. На устройстве app зарегистрировал push-token

В `lib/services/custom_api_notification_service.dart`:
- `startForegroundSync` → `_registerPushDevicesSafely` →
  `_registerRemotePushDevice` →
- `rustoreService.getRustorePushToken()` →
  `RustorePushClient.getToken()` (через `flutter_rustore_push`)
- POST `/v1/push/devices` с `{provider: 'rustore', token, platform: 'android'}`
- Бэк сохраняет в `db.pushDevices`

Код уже есть, работает после логина. Если не работает — копать
в логах телефона: `[RuStore Push v6.5.0] New token received: ...`.

## Что делать если push не приходит

### Шаг 1: Проверь конфиг бэка
```bash
curl -fsS https://api.rodnya-tree.ru/ready | jq '.rustorePushEnabled, .webPushEnabled'
```
Оба `true` — конфиг ок.

### Шаг 2: Проверь зарегистрировано ли устройство
Залогинься в приложении, потом из терминала:
```bash
curl -fsS https://api.rodnya-tree.ru/v1/push/devices \
  -H "Authorization: Bearer <твой access token>" | jq
```
Если массив пустой — клиент не зарегистрировал push device.
Возможные причины:
- RuStore SDK не смог получить токен (нет интернета при первом
  запуске? Permission denied?)
- `_registerRemotePushDevice` упал на чём-то — проверь в logcat

### Шаг 3: Проверь deliveries
```bash
curl -fsS https://api.rodnya-tree.ru/v1/push/deliveries \
  -H "Authorization: Bearer <token>" | jq '.deliveries[] | {provider, status, lastError}'
```
- `status: 'sent'` — бэк отправил push в RuStore. Если телефон
  тихо — проблема на стороне RuStore / устройства.
- `status: 'failed'` + `lastError` — есть конкретная причина.
- `status: 'queued'` + `lastError: 'rustore_not_configured'` — env
  vars на бэке не выставлены.

### Шаг 4: Что какая ошибка означает

| `lastError` | Причина | Что делать |
|---|---|---|
| `rustore_not_configured` | Нет env vars | Прописать в `/etc/rodnya-backend.env` |
| `webpush_not_configured` | Нет VAPID keys | То же |
| `invalid_webpush_subscription:...` | Браузер отозвал permission или сменил endpoint | Юзер заходит в браузер, отключает и заново включает уведомления |
| `INVALID_TOKEN` (rustore) | Токен в `pushDevices` устарел / projectId mismatch | Юзер делает logout / login, app перерегистрирует токен |
| `RUSTORE_RATE_LIMIT` | Превысили квоту RuStore | Подождать |

## Permissions на Android 13+

`POST_NOTIFICATIONS` стоит в манифесте. При первом запуске app
показывает permission-prompt. Если юзер отказался — система
никогда не покажет уведомление, даже если push дошёл.

Проверка на устройстве: Настройки → Приложения → Родня →
Уведомления → должно быть включено.

## ОТСЮДА → как тестить

1. Собрать APK: `flutter build apk --flavor rustore --release`
   (или `--flavor dev` для dev-сборки с другим packageId).
2. Установить на телефон.
3. Залогиниться.
4. Дать permission на уведомления.
5. С другого аккаунта (или с web) — выложить пост / отправить
   сообщение / позвонить.
6. На устройстве должна прилететь нотификация.

Если не приходит — проходимся по шагам 1-3 диагностики выше.
