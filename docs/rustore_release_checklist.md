# RuStore Release Gate

## Release Scope v1
- В релиз входят только `auth + onboarding + tree CRUD/view + relatives + direct/branch chat + media + notifications + settings/legal/support`.
- Новые крупные фичи не добавляем, пока не пройдены все release gates ниже.
- RuStore billing не является blocker'ом v1 и по умолчанию скрыт через `RODNYA_ENABLE_RUSTORE_BILLING=false`.

## Build Inputs
- Signing настроен через `RODNYA_RELEASE_SIGNING_PROPERTIES` или `RODNYA_KEYSTORE_*`.
- Для релизной сборки используется flavor `rustore`.
- Build-time defines:
  - `RODNYA_RUNTIME_PRESET=prod_custom_api`
  - `RODNYA_ENABLE_LEGACY_DYNAMIC_LINKS=false`
  - `RODNYA_APP_STORE=rustore`
  - `RODNYA_ENABLE_RUSTORE_BILLING=false`
  - `RODNYA_ENABLE_RUSTORE_REVIEW=true`
  - `RODNYA_ENABLE_RUSTORE_UPDATES=true`
- Перед реальным релизом заданы `RODNYA_BUILD_NAME` и `RODNYA_BUILD_NUMBER`.
- Если нужны нестандартные RuStore IDs, заданы `RODNYA_RUSTORE_APPLICATION_ID` и `RODNYA_RUSTORE_PUSH_PROJECT_ID`.

## Build Commands
### Windows
```powershell
$env:RODNYA_RELEASE_SIGNING_PROPERTIES="C:\path\to\release-signing.properties"
$env:RODNYA_BUILD_NAME="1.0.2"
$env:RODNYA_BUILD_NUMBER="10"
powershell -ExecutionPolicy Bypass -File .\tool\build_rustore_release.ps1
# Для smoke APK:
powershell -ExecutionPolicy Bypass -File .\tool\build_rustore_release.ps1 -ArtifactKind apk
```

### Linux
```bash
export RODNYA_RELEASE_SIGNING_PROPERTIES=/absolute/path/to/release-signing.properties
export RODNYA_BUILD_NAME=1.0.2
export RODNYA_BUILD_NUMBER=10
./tool/build_rustore_release.sh
# Для smoke APK:
./tool/build_rustore_release.sh apk
```

## Expected Artifact
- `build/app/outputs/bundle/rustoreRelease/app-rustore-release.aab`
- `build/app/outputs/flutter-apk/app-rustore-release.apk` для device/emulator smoke

## Code Gate
- `flutter analyze` зелёный.
- Flutter тесты проходят через `tool/flutter_safe.ps1 test` на Windows.
- `backend/npm test` зелёный.
- `rustoreRelease` AAB собирается из clean checkout.
- GitHub Actions workflow `.github/workflows/rustore-verify.yml` зелёный.

## Android Smoke Gate
- Fresh install, cold start, register/login/logout.
- Session restore после restart и после протухшей сессии не ломает приложение.
- Создание дерева, открытие дерева, добавление и редактирование родственников.
- Открытие direct chat и branch chat.
- Отправка `text / image / video / voice`.
- Открытие media viewer, external open/download path.
- Получение push и открытие нужного экрана по нажатию.
- Блокировка пользователя, список блокировок, жалоба на сообщение.
- Удаление аккаунта.

### Текущий статус smoke
- `2026-04-12` подтверждено на `rustoreRelease` APK в Android Emulator API 36:
  - APK собирается и подписывается release keystore; `apksigner verify --print-certs` проходит
  - итоговый `APK` содержит `package=com.ahjkuio.rodnya_family_app`, `targetSdkVersion=36`, `ru.rustore.sdk.ApplicationId`, `ru.rustore.sdk.pushclient.project_id` и `rodnya.notification.icon`
  - cold start не падает; приложение открывает рабочий home screen
  - update check в release APK отрабатывает без краша и корректно логирует `RuStore not installed`
  - review CTA больше не считает вызов успешным при ошибке `RuStore not installed`
  - crash buffer пустой после startup и review smoke
- `2026-04-12` подтверждено на физическом Android `SM-G780F` с установленным `RuStore 1.98.0.1`:
  - release APK ставится поверх production-like install и не имеет `DEBUGGABLE`
  - cold start и session restore открывают рабочий экран без startup failure
  - `RuStore update` на устройстве отвечает без краша и логирует `availableVersionCode=7`, `updateAvailability=1`
  - review CTA на живом устройстве корректно обрабатывает `RuStoreReviewExists` и переводит UI в `Спасибо за отзыв!`
  - `RuStore Push` возвращает токен на устройстве, а backend регистрирует physical device как `provider=rustore`
  - end-to-end push подтверждён на production API и в системной шторке устройства: delivery для `rustore` device имеет `status=sent` и `responseCode=200`
- Emulator note: RuStore `push/update/review` в эмуляторе без установленного host RuStore app закономерно возвращают `RuStore not installed` / `Need to install host push app`; этот сценарий должен закрываться только на физическом Android-устройстве с RuStore.
- `2026-04-16`: новый physical-device pass на `SM-G780F` подтвердил Android UI polish после theme fixes:
  - session restore поднимает приложение сразу в авторизованный state
  - dark theme на `Auth`, `Home`, `Relatives`, `Chats`, `Tree`, `Profile`, `Settings` читается без white-on-light регрессов
  - `Тёмная тема` в `Settings` переключается одним нажатием и не заедает при повторном входе в экран
  - отдельный regression fix для app bars в dark theme повторно подтверждён на живых `Chats` и `Tree`
  - нижняя навигация на узкой мобильной ширине больше не режет подписи: compact mode скрывает текст и оставляет читаемые иконки

## Trust Gate
- Публичные маршруты без логина живы:
  - `/privacy`
  - `/terms`
  - `/support`
  - `/account-deletion`
- In-app ссылки в `Auth / Settings / About` ведут именно на эти страницы.
- Жалобы и блокировки работают end-to-end через `/v1/reports` и `/v1/blocks`.
- Есть moderator note и demo account для проверки RuStore moderation.

### Текущий trust status
- `2026-04-16`: после свежего web deploy на production повторно подтверждены `/#/privacy`, `/#/terms`, `/#/support`, `/#/account-deletion` без console errors.
- `2026-04-16`: in-app `Settings` route надо smoke'ить как `/#/profile/settings`; прямого `/#/settings` маршрута нет.
- `2026-04-16`: на production web прошли `settings -> create post -> publish -> delete account` на disposable аккаунте.
- `2026-04-16`: после успешного delete-account redirect в `/#/login` остаётся один хвостовой `401` на stories-запросе; UX-флоу не ломается, но этот teardown стоит зачистить перед финальным RC.
- `2026-04-16`: repo-side fix для этого хвоста уже добавлен:
  - `CustomApiStoryService` больше не отправляет stories-запросы без активной сессии и локально режет teardown раньше сети
  - до следующего production web deploy публичный smoke note выше остаётся актуальным

## Ops Gate
- `/health` отвечает `200` и показывает состояние push/admin config.
- `/ready` на production backend отвечает `200`.
- Проверен backup/restore rehearsal backend data и media.
- После restart backend не теряются auth/session/media/chat path.
- Публичные media URL канонические и отдаются по HTTPS.

### Текущий ops status
- `2026-04-12` production backend реально переведён на `postgres + s3`.
- `2026-04-12` production host поднял локальные `PostgreSQL` и `MinIO`, а Caddy теперь публикует media через `/storage/*`.
- `2026-04-12` migration подтверждена:
  - snapshot hash source/target совпал при переносе `dev-db.json -> PostgreSQL`
  - migrated media читаются по `https://api.rodnya-tree.ru/storage/rodnya-media/...`
  - legacy `https://api.rodnya-tree.ru/media/...` отдают redirect на новый storage path
  - свежий upload/delete smoke на production API прошёл end-to-end
  - backup script теперь сохраняет `rodnya-postgres.dump` и `minio-data.tar.gz`
- `2026-04-12` delete-account cascade отдельно подтверждён на production `postgres + s3`:
  - временный владелец загрузил profile photo, post image и chat attachment
  - `DELETE /v1/auth/account` удалил state из `PostgreSQL`
  - все три media URL после удаления вернулись как `404`
  - peer account больше не видел direct chat после удаления владельца
- `2026-04-16`: `https://api.rodnya-tree.ru/ready` всё ещё отвечает `200` и показывает `storage=postgres`, `media=s3`.
- `2026-04-16`: production web bundle повторно выкачен на `rodnya-tree.ru`; legal/support routes теперь работают после router fix в клиенте.
- `2026-04-16`: `https://rodnya-tree.ru/last_build_id.txt` снова отвечает `200` и показывает актуальный deploy label после свежей web-активации.
- `2026-04-20`: phone-based trust model закрыта и убрана из активного продукта:
  - обычное сохранение профиля больше не несёт `isPhoneVerified`
  - trusted channels строятся вокруг `Telegram / VK / MAX / Google`
  - linking/discovery проверяется через `username`, `profile code`, `invite`, `claim`, `QR`
- `2026-04-16`: production media/CORS cleanup перепроверен на живом backend и web:
  - backend now rewrites legacy first-party `http://api.rodnya-tree.ru/...` media URLs to `https://...` in public API payloads
  - identity shim on `/v1/trees/:treeId/persons*` now returns proper CORS headers for both `OPTIONS` and `GET`
  - fresh Playwright smoke on `/#/profile/edit` finished with `0` console errors; the old mixed-content avatar noise is closed
- `2026-04-16`: raw live backend parity по offline claim всё ещё неполная:
  - без промежуточного shim relation request acceptance и последующий claim всё ещё дают `3` persons и relation target на auto-created duplicate
  - `acceptIdentityId` и `claimIdentityId` в этом raw smoke остаются `null`
- `2026-04-16`: public production identity path закрыт targeted runtime shim:
  - shim обслуживает `relation respond`, `claim`, `persons list`, `person details`
  - live smoke через публичный домен вернул `x-rodnya-claim-shim: 1` и `x-rodnya-identity-shim: 1`
  - shim перенёс relation target обратно на offline card, удержал дерево на `2` persons и отдал стабильный `identityId` на accept/claim/person endpoints
  - повторный live smoke на втором дереве подтвердил reuse того же `identityId` для того же пользователя
  - это снимает user-facing duplicate blocker и внешний identity parity blocker, но не заменяет полноценный backend rollout
- `2026-04-16`: следующий profile/privacy rollout formalized in repo:
  - [docs/profile_visibility_and_identity_plan_2026-04-16.md](./profile_visibility_and_identity_plan_2026-04-16.md) фиксирует phases для rich profiles, visibility scopes, native identity parity, phone dedupe и final delete-account cleanup
- `2026-04-17`: production profile/privacy slice реально выкачен:
  - активный web build marker: `https://rodnya-tree.ru/last_build_id.txt -> 20260417-profile-visibility-native`
  - live `/#/profile/edit` рендерит расширенные rich-profile секции и visibility chips для `specific_trees` и `specific_users`
  - live API smoke на disposable аккаунтах подтвердил section privacy для `specific_trees` и `specific_users`
- `2026-04-17`: расширение rich-profile полей тоже уже выкачено на production:
  - активный web build marker обновлён до `20260417-profile-rich-fields`
  - live production API smoke подтвердил сохранение `aboutFamily`, `hometown`, `languages` и `interests`
  - live browser smoke подтвердил, что `/#/profile/edit` рендерит все четыре новых поля, а outsider-view на `/#/user/:userId` показывает публичные `Родной город` и `Языки` без утечки приватных `about/worldview` секций
- `2026-04-17`: native identity parity больше не держится на runtime shim:
  - `app.js` и `profile-utils.js` production backend синхронизированы с repo и `rodnya-backend.service` перезапущен
  - активный Caddy config перезагружен из `/etc/caddy/Caddyfile`, stale admin override на `127.0.0.1:8081` убран
  - `claim_merge_shim` остановлен, `:8081` больше не слушает, active proxy config больше не содержит маршрутов на shim
  - повторный live smoke после shutdown shim прошёл: offline claim даёт `2` persons, relation target на offline card и стабильный `identityId`
- `2026-04-17`: delete-account web teardown перепроверен на disposable аккаунте:
  - flow `/#/profile/settings -> Удалить аккаунт -> /#/login` проходит без runtime console errors
  - хвостовой stories `401` больше не воспроизводится в проверенном production web сценарии
- `2026-04-20`: branch-level privacy остаётся, а old phone OTP branch снята:
  - активный профильный сценарий использует trusted channels вместо SMS
  - live/disposable smoke теперь должен проверять provider linking, invite/claim и ordinary profile edit без phone fallback
- `2026-04-17`: VK ID web auth включён на production:
  - активный web build marker: `https://rodnya-tree.ru/last_build_id.txt -> 20260417-vk-auth`
  - production backend reports `vkAuthEnabled=true` on `/health` and `/ready`
  - `GET https://api.rodnya-tree.ru/v1/auth/vk/start` redirects to live VK ID authorize with `scope=phone email`
  - fresh browser smoke confirmed `VK ID` is visible on `/#/login` with `0` console errors
  - Android return-to-app for VK ID is still not wired in this pass and remains a separate release tail

## Publication Gate
- Первый релиз идёт через `manual release`, не `instant publish`.
- Store card готова:
  - short description
  - full description
  - screenshots
  - icon
  - release notes
  - privacy URL
  - support URL
  - account deletion URL
- Moderator notes готовы и содержат demo credentials.
- Основные публикационные файлы:
  - [docs/rustore_store_card_1.0.2.md](./rustore_store_card_1.0.2.md)
  - [docs/rustore_screenshot_shotlist_1.0.2.md](./rustore_screenshot_shotlist_1.0.2.md)
  - [docs/rustore_moderator_notes_1.0.2.md](./rustore_moderator_notes_1.0.2.md)
  - [docs/rustore_whatsnew_1.0.2.txt](./rustore_whatsnew_1.0.2.txt)
- Secure local files с реальными moderation credentials и готовым moderator comment лежат в `.tmp/` и не коммитятся в git.

## RuStore API Upload
### Windows PowerShell
```powershell
$env:RUSTORE_KEY_ID="your-key-id"
$env:RUSTORE_PRIVATE_KEY_BASE64="base64-private-key-from-rustore-console"
powershell -ExecutionPolicy Bypass -File .\tool\publish_rustore_release.ps1 `
  -MinAndroidVersion 7 `
  -WhatsNewFile ".\docs\rustore_whatsnew_1.0.2.txt" `
  -ModeratorComment (Get-Content ".\.tmp\rustore_moderator_comment_1.0.2.txt" -Raw) `
  -PublishType MANUAL `
  -SubmitForModeration
```

- Предпочитать `-WhatsNewFile`, а не inline `-WhatsNew`, чтобы не ловить проблемы с кириллицей.
- Перед первой `AAB` публикацией в RuStore должен быть загружен app signing key в разделе `Подпись приложения`.
- Для текущего приложения `-MinAndroidVersion 7`, потому что RuStore API ждёт номер версии Android, а не `minSdkVersion=24`.
- В реальном API `developerContacts` принимается объектом, а не массивом, несмотря на спорные примеры в документации.

### Screenshot Upload
```powershell
$env:RUSTORE_KEY_ID="your-key-id"
$env:RUSTORE_PRIVATE_KEY_BASE64="base64-private-key-from-rustore-console"
powershell -ExecutionPolicy Bypass -File .\tool\upload_rustore_screenshots.ps1 `
  -VersionId "<draft-version-id>" `
  -ScreenshotDir ".\.tmp\rustore_screenshots_1.0.2\final"
```

- Локальный raw PNG набор для `1.0.2` хранится в `.tmp/rustore_screenshots_1.0.2/final/`.
- Файлы собраны по shot list из [docs/rustore_screenshot_shotlist_1.0.2.md](./rustore_screenshot_shotlist_1.0.2.md).
- Порядок загрузки идёт по имени файла и превращается в `ordinal 0..N` внутри RuStore API.
- `2026-04-12`: raw PNG успешно загружены в draft `versionId=2064564541` через новый full-access API key.

### Current Release Status
- До финального RC остаются уже не новые фичи, а release-polish хвосты:
  - branch-level profile visibility (`specific_branches`) уже реализована и выкачена
  - реальный OTP flow для primary phone уже выкачен, но живая SMS-доставка всё ещё ждёт provider credentials на production backend
  - RuStore upload по-прежнему требует manual console declaration для sensitive permissions
- `2026-04-12`: RuStore API больше не режет draft creation, auth и screenshot upload.
- `AAB` upload сейчас упирается только в store policy:
  - `APK/AAB contains new sensitive permissions`
  - список: `RECORD_AUDIO`, `READ_EXTERNAL_STORAGE`, `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_MEDIA_AUDIO`
  - RuStore требует загрузить сборку через development console и задекларировать эти permissions вручную

## Official References
- RuStore Console: https://www.rustore.ru/developer
- Publication modes: https://www.rustore.ru/help/en/developers/publishing-and-verifying-apps/app-publication/setting-up-publication/instant-app-publishing
- RuStore API overview: https://www.rustore.ru/help/work-with-rustore-api
- Upload via API: https://www.rustore.ru/help/en/work-with-rustore-api/api-upload-publication-app/
- API authorization: https://www.rustore.ru/help/en/work-with-rustore-api/api-authorization-process
