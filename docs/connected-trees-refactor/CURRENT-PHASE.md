# Текущая фаза рефакторинга

> ⚠️ Важно: PLAN.md этой папки SUPERSEDED. Источник правды —
> [`docs/tree_model_overhaul_rfc.md`](../tree_model_overhaul_rfc.md).
> См. [DECISIONS.md](DECISIONS.md) от 2026-05-09.

**Phase**: 3.1 — Schema design (graphPersons / branches /
graphPersonEditGrants / branch.includeRules расширение)
**Статус**: design proposal готов, **ожидает review Артёма**
**Phase 1.3**: closed (2026-05-09)
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
* ✅ [PHASE-3.1-SCHEMA-PROPOSAL.md](PHASE-3.1-SCHEMA-PROPOSAL.md)
  — design proposal по schema changes готов. Ожидает review.

## Что делаем дальше (после approve proposal'а)

В указанном порядке:
1. Расширить `EMPTY_DB` + `normalizeDbState` новыми полями.
2. Переписать `pickCanonicalPerson` → `pickCanonicalFieldsAndCollectConflicts`.
3. Дописать `migrateTreesToGraphAndBranches` под answer B (per-field
   selection + conflict generation + lastPropagatedFields).
4. Обновить incremental sync helpers с новыми полями.
5. Написать `_userCanSeeGraphPerson` + `_userCanEditGraphPerson` helpers.
6. Написать `_buildBranchVisiblePersonIds` helper (D).
7. Расширить тесты (см. proposal §6).
8. Dry-run миграции на синтетических данных + reset → re-run idempotency check.
9. Показать diff + test results Артёму перед commit.

Никакого кода до approve [PHASE-3.1-SCHEMA-PROPOSAL.md](PHASE-3.1-SCHEMA-PROPOSAL.md).

## Чего НЕ делать

* НЕ лезть в Phase 3 (TREE → BRANCH миграция) — заблокировано 4
  нерешёнными вопросами в DECISIONS.md.
* НЕ депрекейтить graph-слой (он остаётся).
* НЕ принимать архитектурные решения без записи в DECISIONS.md.
