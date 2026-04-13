# Гибридный workflow Codex для `Родни`

## Зачем гибрид
Для этого проекта выгодно разделять работу:
- `local Codex` берёт всё, что зависит от локального окружения, Android-устройств, секретов, сервера и грязного worktree;
- `cloud Codex` берёт изолированные задачи по GitHub-ветке: аудит, рефакторинг, тесты, документацию, отдельные фичи без доступа к локальным секретам.

Такой режим особенно полезен для `Родни`, потому что:
- есть Android `physical-device` smoke;
- есть production backend и deploy path;
- есть RuStore и другие внешние учётки;
- есть большие волны UX-полировки, которые удобно дробить на независимые куски.

## Что делать локально
Локально оставляем только то, что реально требует текущей машины или секретов:
- Android emulator / USB device smoke;
- backend deploy, server shell, production QA;
- RuStore console / moderation / signing;
- любые задачи на грязном рабочем дереве;
- финальная интеграция нескольких параллельных кусков;
- прогон `flutter analyze`, релевантных `flutter test`, web smoke и release build перед merge.

## Что отдавать в cloud
В облако стоит отдавать изолированные задачи, которые живут на ветке и не требуют локальных секретов:
- rebrand sweep по UI-строкам и docs;
- review и уплотнение конкретного экрана;
- чистые backend API-изменения без deploy;
- widget/unit tests;
- новые сервисы и модели;
- tree/chat/feed-polish, если scope чётко ограничен;
- grep-аудиты и поиск остаточного legacy.

## Рабочая схема
1. Локально доводи ветку до состояния, которое можно пушить без стыда.
2. Пушь отдельную ветку под волну, например `wave/home-events` или `wave/rodnya-rebrand`.
3. Для cloud-задачи заводи короткий spec в `docs/cloud_tasks/<date>_<slug>.md`.
4. В cloud Codex давай ссылку на репозиторий/ветку и prompt ниже.
5. Пусть cloud Codex делает только свой узкий кусок и возвращает PR/commit diff.
6. Локально подтягивай изменения, интегрируй, прогоняй Android/web/backend проверки и только потом merge.

## Хорошее разбиение задач для cloud
Подходят такие куски:
- `Home declutter без изменения backend contracts`
- `server-driven likes + tests`
- `stories backend + service layer без UI`
- `родня rebrand в docs и UI copy, без Android applicationId`
- `tree history API + unit tests`
- `event service: праздники + годовщины + tests`

Не подходят такие куски:
- `зайди на мой сервер и выкати`
- `проверь на моём телефоне по USB`
- `залей в RuStore и прожми permissions`
- `поработай по локальным незакоммиченным файлам, которых нет в GitHub`

## Базовые правила синхронизации
- Не отдавай в cloud незапушенные локальные изменения: cloud их не увидит.
- Не смешивай в одном cloud-таске и UI, и backend, и deploy.
- Один cloud-task = одна цель = один reviewable diff.
- Секреты, токены, `.env`, серверные пароли и личные данные оставляй только локально.
- Для этой кодовой базы не меняй Android `applicationId`, даже если идёт rebrand в `Родню`.

## Prompt для cloud Codex
Используй такой prompt почти без изменений:

```text
Ты работаешь с репозиторием Родни на GitHub.

Прочитай и соблюдай:
- AGENTS.md
- CODEX.md
- Codex_rules.md
- PROMPT.md

Контекст проекта:
- Родня — семейное дерево + приватная семейная соцсеть.
- Основной приоритет: Android + web MVP, RuStore-first.
- Firebase-hosted paths считаем legacy.
- Android applicationId НЕ менять, даже если в UI и docs идёт rebrand в «Родню».

Текущая задача:
<вставь один узкий scope>

Ограничения:
- не трогай unrelated файлы;
- не делай deploy;
- не используй секреты;
- не меняй store identifiers;
- сохраняй сильный русский UX copy;
- если задача затрагивает web UI, проверь compile path и краткий smoke;
- если задача затрагивает backend, добавь/обнови тесты.

Результат:
- внеси изменения в код;
- коротко опиши, что изменил;
- перечисли проверки;
- явно назови оставшиеся риски.
```

## Prompt для local Codex
Локально используй prompt другого типа: меньше про изоляцию, больше про интеграцию и реальные проверки.

```text
Работаем локально по проекту Родня.

Прочитай и соблюдай:
- AGENTS.md
- CODEX.md
- Codex_rules.md
- PROMPT.md

Действуй автономно. Сначала изучи текущий код и уже существующие изменения в worktree.

Текущая задача:
<вставь интеграционную или device/deploy задачу>

Особенно важно:
- учитывай грязный worktree;
- не ломай RuStore path и текущий Android applicationId;
- используй локальные проверки: flutter analyze, релевантные flutter test, Android/device smoke, web smoke, backend tests;
- если нужно, работай с сервером, эмулятором или физическим Android-устройством;
- не останавливайся на анализе, если можешь безопасно довести задачу до конца.
```

## Рекомендованный ритм именно для этого проекта
- `cloud`: искать и фиксить самостоятельные куски волны `Родни`
- `local`: сливать, проверять, добивать device/deploy/store хвосты

Практичная схема на ближайшее время:
- cloud task 1: `rebrand UI/docs from Lineage to Родня, without package id changes`
- cloud task 2: `stories backend + service layer`
- cloud task 3: `event service expansion + tests`
- local task 1: `Android media and voice UX on physical device`
- local task 2: `server deploy + production parity bugs`
- local task 3: `RuStore release integration and console actions`

## Мини-чеклист перед отправкой задачи в cloud
- ветка запушена;
- scope узкий;
- нет зависимости от локального сервера/телефона;
- нет секретов;
- есть понятный definition of done.

## Мини-чеклист перед локальным merge
- изменения подтянуты;
- конфликтов нет;
- `dart format` по изменённым файлам;
- `flutter analyze`;
- релевантные `flutter test`;
- если менялся web UI: короткий Playwright smoke;
- если менялся Android path: emulator или physical-device smoke.
