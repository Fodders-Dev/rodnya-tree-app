# Текущая фаза рефакторинга

> ⚠️ Важно: PLAN.md этой папки SUPERSEDED. Источник правды —
> [`docs/tree_model_overhaul_rfc.md`](../tree_model_overhaul_rfc.md).
> См. [DECISIONS.md](DECISIONS.md) от 2026-05-09.

**Phase**: 1.3 — edit-time conflict surfacing (по RFC) — **CLOSED**
**Статус**: complete (полностью реализован в коде до этой сессии,
2026-05-09 audit + verify завершён)
**Следующая фаза**: Phase 3 (TREE → BRANCH миграция) — **BLOCKED**
до ответов на 4 RFC-вопроса (см. [DECISIONS.md](DECISIONS.md))

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

Ничего. Phase 1.3 закрыт. Phase 3 заблокирован.

## Чего НЕ делать

* НЕ лезть в Phase 3 (TREE → BRANCH миграция) — заблокировано 4
  нерешёнными вопросами в DECISIONS.md.
* НЕ депрекейтить graph-слой (он остаётся).
* НЕ принимать архитектурные решения без записи в DECISIONS.md.
