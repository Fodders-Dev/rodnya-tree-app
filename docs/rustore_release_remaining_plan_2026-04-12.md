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
- `pending` production storage migration plan
  - заменить file-backed store на `PostgreSQL`
  - заменить local media root на object storage / S3-compatible storage
  - подготовить migration/rehearsal path без big-bang rewrite
- `pending` backup/restore rehearsal и runbook
- `pending` production media policy
  - canonical HTTPS media URL
  - retention/delete-account cascade validation

### Track B. Android Release Quality
- `done` базовый `rustoreRelease` emulator smoke
  - cold start больше не падает в startup failure
  - login проходит на реальном release APK
  - home и chats screen открываются после входа
  - корневая причина Android startup blocker закрыта: notification icon теперь не вырезается из release resources
- `pending` permission audit финализировать на реальном Android manifest merge report
  - `done` убрать неиспользуемый `google_sign_in`, который затягивал `com.google.android.gms.version` и `SignInHubActivity`
  - `done` убрать Google Play photo picker compatibility service из `rustore` flavor
- `pending` Rustore push/review/update smoke на physical Android build
- `pending` проверить release keystore/signing и финальные IDs для RuStore Console
- `pending` release notes/demo account/moderator note довести до публикационного состояния

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
1. Закрыть `Track A / ops hardening` в текущем backend.
2. Закрыть physical-device RuStore smoke и manifest merge audit.
3. Затем добить `Track C` только по реальным UX-блокерам.
4. После этого собирать release assets и выкатывать first moderation build.

## Текущий рабочий фокус
- Сейчас в работе: manifest merge audit и physical-device RuStore smoke.
- Следующий после него: production storage migration plan для `PostgreSQL + object storage`.
