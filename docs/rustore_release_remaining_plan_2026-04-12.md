# RuStore Remaining Plan - 2026-04-12

Цель: довести Rodnya до релизного кандидата для первого `manual release` в RuStore без расползания scope.

## Уже закрыто
- `done` public legal surface: `/privacy`, `/terms`, `/support`, `/account-deletion`
- `done` in-app legal/support links в `Auth / Settings / About`
- `done` safety layer MVP: `reports`, `blocks`, admin moderation path, `Blocked users`
- `done` server-side block enforcement для direct chat create/send
- `done` Rustore flavor и release tooling под `rustoreRelease`
- `done` Rustore CI verify workflow
- `done` release gate документ в `docs/rustore_release_checklist.md`

## Осталось до release candidate

### Track A. Backend Production Readiness
- `done` ops hardening для текущего custom backend
  - request id
  - `health` и `ready`
  - basic rate limiting
  - структурные error/access logs
- `done` production storage migration plan
  - `done` backend startup отвязан от прямого `new FileStore(...)` через storage factory
  - `done` заменить file-backed store на реальный `PostgreSQL` adapter через state snapshot table
  - `done` заменить local media root на `S3-compatible object storage` adapter
  - `done` подготовить env provisioning и migration/rehearsal path без big-bang rewrite
- `done` backup/restore rehearsal и runbook
- `done` production media policy
  - `done` canonical HTTPS media URL
  - `done` media upload/delete smoke на production `s3` path
  - `pending` retention/delete-account cascade validation на отдельном полном QA-проходе

### Track B. Android Release Quality
- `done` базовый `rustoreRelease` emulator smoke
  - cold start больше не падает в startup failure
  - login проходит на реальном release APK
  - home и chats screen открываются после входа
  - корневая причина Android startup blocker закрыта: notification icon теперь не вырезается из release resources
- `done` permission audit финализирован на реальном Android manifest merge report
  - `done` убрать неиспользуемый `google_sign_in`, который затягивал `com.google.android.gms.version` и `SignInHubActivity`
  - `done` убрать Google Play photo picker compatibility service из `rustore` flavor
- `done` Rustore push/review/update smoke на physical Android build
  - `done` physical device `SM-G780F` c установленным `RuStore 1.98.0.1` видит release APK как production-like build без `DEBUGGABLE`
  - `done` cold start и session restore на физическом устройстве не ломают приложение
  - `done` review CTA на реальном устройстве корректно обрабатывает `RuStoreReviewExists` и переводит экран в state `Спасибо за отзыв!`
  - `done` startup update check на физическом устройстве отрабатывает без шума про `.env` и логирует конкретный `updateAvailability=1`
  - `done` RuStore Push SDK на физическом устройстве возвращает токен и `Push available: true`
  - `done` backend production API зарегистрировал physical Android device как `provider=rustore`
  - `done` end-to-end push подтверждён до системной шторки: delivery `status=sent`, `responseCode=200`, уведомление видно в notification shade
- `done` проверить release keystore/signing и финальные IDs для RuStore Console
  - release APK подписывается реальным keystore
  - `package`, `targetSdkVersion`, `RuStore ApplicationId`, `RuStore push project id` и notification icon подтверждены из собранного APK
- `pending` release notes/demo account/moderator note довести до публикационного состояния

### Production Sync
- `done` production backend на `api.rodnya-tree.ru` синхронизирован с текущим backend-кодом
  - `done` live service `rodnya-backend.service` перезапущен на новом `/opt/rodnya/backend`
  - `done` live API теперь содержит `DELETE /v1/auth/account` и `DELETE /v1/chats/:chatId/messages/:messageId`
  - `done` `/ready` на production backend отвечает `200`
- `done` production backend storage переведён на `postgres + s3`
  - `done` `PostgreSQL` поднят на production host и snapshot мигрирован из `dev-db.json`
  - `done` `MinIO` поднят на production host, media bucket создан и сделан public-read
  - `done` старые `/media/...` URL продолжают работать через redirect на `/storage/...`

### Track C. UX / Product Quality
- `pending` закрыть chat `Wave 6`
  - density desktop/mobile
  - compact header
  - accessibility/semantics
  - font fallback cleanup
- `pending` tree / relatives polish
  - `done` declutter pass для tree view
    - убраны тяжёлые summary-блоки и длинные текстовые карточки
    - быстрые действия перенесены в app bar/menu
    - controls внутри полотна стали компактным floating chrome вместо массивной панели
  - empty/loading/error states
  - предсказуемая навигация
  - центрирование и визуальная плотность дерева
- `pending` session/offline/retry polish
  - no silent failure
  - понятные snackbar/error states
  - мягкое восстановление после 401/network loss

### Track D. Store Readiness
- `pending` карточка приложения для RuStore
  - short description
  - full description
  - screenshots
  - icon / feature visuals
  - privacy/support/delete-account URLs
- `pending` demo account для модерации
- `pending` moderator instructions для review team

## Порядок добивания
1. Собрать release assets и moderator pack.
2. Добить `Track C` только по реальным UX-блокерам.
3. Прогнать финальный RuStore release candidate smoke.
4. Затем выкатывать first moderation build.

## Текущий рабочий фокус
- Сейчас в работе: release assets, demo account и moderator notes.
- Следующий после него: финальный RuStore release candidate pass.
