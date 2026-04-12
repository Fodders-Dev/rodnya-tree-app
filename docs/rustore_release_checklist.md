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
```

### Linux
```bash
export LINEAGE_RELEASE_SIGNING_PROPERTIES=/absolute/path/to/release-signing.properties
export LINEAGE_BUILD_NAME=1.0.2
export LINEAGE_BUILD_NUMBER=10
./tool/build_rustore_release.sh
```

## Expected Artifact
- `build/app/outputs/bundle/rustoreRelease/app-rustore-release.aab`

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
  - cold start открывает login screen без startup failure
  - login реальным аккаунтом проходит
  - home screen открывается после входа
  - chats list screen открывается после входа
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
- Проверен backup/restore rehearsal backend data и media.
- После restart backend не теряются auth/session/media/chat path.
- Публичные media URL канонические и отдаются по HTTPS.

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

## RuStore API Upload
### Windows PowerShell
```powershell
$env:RUSTORE_KEY_ID="your-key-id"
$env:RUSTORE_PRIVATE_KEY_BASE64="base64-private-key-from-rustore-console"
powershell -ExecutionPolicy Bypass -File .\tool\publish_rustore_release.ps1 `
  -MinAndroidVersion 7 `
  -WhatsNewFile ".\docs\rustore_whatsnew_1.0.2.txt" `
  -ModeratorComment "Демо-аккаунт: moderation@rodnya-tree.ru / ChangeMeBeforeRelease2026!" `
  -PublishType MANUAL `
  -SubmitForModeration
```

- Предпочитать `-WhatsNewFile`, а не inline `-WhatsNew`, чтобы не ловить проблемы с кириллицей.
- Перед первой `AAB` публикацией в RuStore должен быть загружен app signing key в разделе `Подпись приложения`.

## Official References
- RuStore Console: https://www.rustore.ru/developer
- Publication modes: https://www.rustore.ru/help/en/developers/publishing-and-verifying-apps/app-publication/setting-up-publication/instant-app-publishing
- RuStore API overview: https://www.rustore.ru/help/work-with-rustore-api
- Upload via API: https://www.rustore.ru/help/en/work-with-rustore-api/api-upload-publication-app/
- API authorization: https://www.rustore.ru/help/en/work-with-rustore-api/api-authorization-process
