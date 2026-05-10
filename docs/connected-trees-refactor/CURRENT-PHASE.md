# Текущая фаза рефакторинга

> ⚠️ Важно: PLAN.md этой папки SUPERSEDED. Источник правды —
> [`docs/tree_model_overhaul_rfc.md`](../tree_model_overhaul_rfc.md).
> См. [DECISIONS.md](DECISIONS.md) от 2026-05-09.

**Phase**: 3.2 — Owner-model enforcement gates на routes
**Статус**: design proposal готов, **ожидает review Артёма**
**Phase 1.3**: closed (2026-05-09)
**Phase 3.1**: closed (2026-05-10, commit `0d5acec`) — schema +
migration + helpers + 28 new branch-include-rules tests + dry-run script
**Phase 3 разблокирован**: 2026-05-10 ответы A–D в [DECISIONS.md](DECISIONS.md)

## Что уже сделано

* Phase 0 audit (artefacts: AUDIT.md, IDENTITY-MATCHER.md, SCHEMA.md).
* Запись decisions от 2026-05-09 в DECISIONS.md.
* PLAN.md помечен SUPERSEDED.
* **Phase 1.3 закрыт** — audit показал что полностью реализован в
  коде (включая UI bottom-sheet для resolve, который RFC помечал
  как «отложить»). См. [PROGRESS.md](PROGRESS.md) от 2026-05-09.
  * Backend: 100/101 тест зелёных (один Windows-flake unrelated).
  * Flutter: analyze на main 8 pre-existing issues, ничего из 1.3.

## Что делаем сейчас

* ✅ Phase 1.3 закрыт.
* ✅ Phase 3 разблокирован (ответы A–D от Артёма 2026-05-10).
* ✅ Phase 3.1 закрыт (commit `0d5acec`).
* ✅ [PHASE-3.2-ENFORCEMENT-PROPOSAL.md](PHASE-3.2-ENFORCEMENT-PROPOSAL.md)
  — design proposal по enforcement gates готов. Ожидает review.

## Cutover plan (Артём 2026-05-10)

```
3.1 (done)  → pre-prod (миграция + schema, legacy clients work)
3.2 (this)  → pre-prod (enforcement, новые grants endpoints)
3.4         → pre-prod + prod (Flutter UI для visibility, grants, wizard)
```

Между 3.2 и 3.4 — NO user-visible regression. Legacy UI продолжает
работать на anonymous persons; claimed получают 403 на edit-as-stranger
(это правильное поведение, не regression).

## Что делаем дальше (после approve proposal'а 3.2)

В указанном порядке:
1. Helpers `requireGraphPersonEdit` + `requireGraphPersonRead` + store-side
   `findGraphPersonByLegacy`.
2. Gating всех existing routes из §1 proposal'а.
3. Новые endpoints `POST/GET/DELETE /v1/graph-persons/:id/grants` +
   `PATCH /v1/graph-persons/:id/visibility` + `GET /v1/me/edit-grants`.
4. Sensitive attributes filter на READ + WRITE.
5. Audit existing api.test.js — adjust expectations для claimed-edit-as-stranger.
6. Новый `owner-model-enforcement.test.js`.
7. Smoke benchmark на per-row visibility cost.
8. Diff на показ перед commit.

Никакого кода до approve [PHASE-3.2-ENFORCEMENT-PROPOSAL.md](PHASE-3.2-ENFORCEMENT-PROPOSAL.md).

## Чего НЕ делать

* НЕ лезть в Phase 3 (TREE → BRANCH миграция) — заблокировано 4
  нерешёнными вопросами в DECISIONS.md.
* НЕ депрекейтить graph-слой (он остаётся).
* НЕ принимать архитектурные решения без записи в DECISIONS.md.
