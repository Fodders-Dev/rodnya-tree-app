# RuStore Release Gate

## Release Scope v1
- В релиз входят только `auth + onboarding + tree CRUD/view + relatives + direct/branch chat + media + notifications + settings/legal/support`.
- Новые крупные фичи не добавляем, пока не пройдены все release gates ниже.
- RuStore billing не является blocker'ом v1 и по умолчанию скрыт через `LINEAGE_ENABLE_RUSTORE_BILLING=false`.

## Build Inputs
- Signing настроен через `LINEAGE_RELEASE_SIGNING_PROPERTIES` или `LINEAGE_KEYSTORE_*`.
- Для релизной сборки используется flavor `rustore`.
- Build-time defines:
  - `LINEAGE_RUNTIME_PRESET=prod_custom_api`
  - `LINEAGE_ENABLE_LEGACY_DYNAMIC_LINKS=false`
  - `LINEAGE_APP_STORE=rustore`
  - `LINEAGE_ENABLE_RUSTORE_BILLING=false`
  - `LINEAGE_ENABLE_RUSTORE_REVIEW=true`
  - `LINEAGE_ENABLE_RUSTORE_UPDATES=true`
- Перед реальным релизом заданы `LINEAGE_BUILD_NAME` и `LINEAGE_BUILD_NUMBER`.
- Если нужны нестандартные RuStore IDs, заданы `LINEAGE_RUSTORE_APPLICATION_ID` и `LINEAGE_RUSTORE_PUSH_PROJECT_ID`.

## Build Commands
### Windows
```powershell
$env:LINEAGE_RELEASE_SIGNING_PROPERTIES="C:\path\to\release-signing.properties"
$env:LINEAGE_BUILD_NAME="1.0.2"
$env:LINEAGE_BUILD_NUMBER="10"
powershell -ExecutionPolicy Bypass -File .\tool\build_rustore_release.ps1
# Для smoke APK:
powershell -ExecutionPolicy Bypass -File .\tool\build_rustore_release.ps1 -ArtifactKind apk
```

### Linux
```bash
export LINEAGE_RELEASE_SIGNING_PROPERTIES=/absolute/path/to/release-signing.properties
export LINEAGE_BUILD_NAME=1.0.2
export LINEAGE_BUILD_NUMBER=10
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
  - итоговый `APK` содержит `package=com.ahjkuio.lineage_family_app`, `targetSdkVersion=36`, `ru.rustore.sdk.ApplicationId`, `ru.rustore.sdk.pushclient.project_id` и `lineage.notification.icon`
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

## Trust Gate
- Публичные маршруты без логина живы:
  - `/privacy`
  - `/terms`
  - `/support`
  - `/account-deletion`
- In-app ссылки в `Auth / Settings / About` ведут именно на эти страницы.
- Жалобы и блокировки работают end-to-end через `/v1/reports` и `/v1/blocks`.
- Есть moderator note и demo account для проверки RuStore moderation.

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

### Current Release Blocker
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
