# Current Next Steps

> ⚠️ Single source of truth — [`docs/connected-trees-refactor/CURRENT-PHASE.md`](docs/connected-trees-refactor/CURRENT-PHASE.md).
> Этот файл сохраняется как entry-point pointer; история priorities ниже
> сохранена для контекста, но не отражает текущий план.

## Текущее состояние (2026-05-18)

Connected-trees-refactor шипанул через Phase 0 → 3.1 → 3.2 → 3 squash →
4 → 6 → 3.6. Подробности с commit-ссылками — в
[`docs/connected-trees-refactor/CURRENT-PHASE.md`](docs/connected-trees-refactor/CURRENT-PHASE.md)
и [`PROGRESS.md`](docs/connected-trees-refactor/PROGRESS.md).

Active observation windows:
* **Phase 6** observation до ~2026-05-28 (метрики per
  [`MERGE-CHECKLIST-PHASE-6.md`](docs/connected-trees-refactor/MERGE-CHECKLIST-PHASE-6.md) §5).

Recently closed:
* **Phase 4** observation closed 2026-05-18 cleanup `baa75d5` —
  flag removed, extended-network permanent. См.
  [`DECISIONS.md`](docs/connected-trees-refactor/DECISIONS.md)
  2026-05-18 entry.

Pending design / Артёмов call:
* Phase 3.4 branch merge decision (parked на `claude/infallible-pike-41360c`).
* Phase 6.5 polish items (identity-suggestions push, revocation UX,
  native notification action buttons — все conditional на observation
  signal).

Pending production action (code shipped, awaiting env flip):
* **Phase 3.6** hard-delete job — `253efaf` deployed 2026-05-18, master
  toggle `RODNYA_HARD_DELETE_ENABLED=false` default. Артём flip → restart
  → 60s dry run → review log → flip `FIRST_RUN_DRY=false` для live.
  См. [DECISIONS.md](docs/connected-trees-refactor/DECISIONS.md)
  2026-05-18 entry rollout sequence.

## Архив — original April plan (~2026-04-29)

Зафиксирован для контекста; не отражает реальную последовательность
работы. Большая часть пунктов superseded by connected-trees-refactor
work либо все ещё actual но deprioritized vs production observation.

Original execution order:
1. ~~Закрепить phased rebrand в docs и agent-context~~ (выполнено).
2. ~~Закрыть `like` как server-driven flow~~ (выполнено в pre-Phase-3
   баckend work).
3. Ужать Home, Tree, Profile и Relatives до action-first UX —
   частично выполнено через Phase 6 empty-state polish; остальное
   pending Артёмова UX call.
4. Расширить events/calendar — pending.
5. Доделать relative gallery, tree history, wiki-style collaboration —
   tree history частично адресовано в Phase 3.4 (parked branch).
6. `24h stories` — pending.

## Опорные документы

* [`docs/connected-trees-refactor/CURRENT-PHASE.md`](docs/connected-trees-refactor/CURRENT-PHASE.md) — текущая фаза и pending items.
* [`docs/connected-trees-refactor/PROGRESS.md`](docs/connected-trees-refactor/PROGRESS.md) — phase-by-phase history.
* [`docs/connected-trees-refactor/DECISIONS.md`](docs/connected-trees-refactor/DECISIONS.md) — все architectural decisions с rationale.
* [`docs/active_execution_plan.md`](docs/active_execution_plan.md) — общий exec plan (legacy reference).
