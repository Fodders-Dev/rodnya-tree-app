# Текущая фаза рефакторинга

> ⚠️ Важно: PLAN.md этой папки SUPERSEDED. Источник правды —
> [`docs/tree_model_overhaul_rfc.md`](../tree_model_overhaul_rfc.md).
> См. [DECISIONS.md](DECISIONS.md) от 2026-05-09.

**Phase**: 3.4 — Flutter UI для visibility / grants / branch wizard
**Статус**: design proposal готов, **ожидает review Артёма**
**Phase 1.3**: closed (2026-05-09)
**Phase 3.1**: closed (2026-05-10, commit `0d5acec`)
**Phase 3.2**: closed (2026-05-10, commit `a40a429`) — owner-model
enforcement gates на routes + grants/visibility endpoints +
18 new tests включая pre/post-claim regression + 100-person smoke
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

* ✅ Phase 1.3 / 3.1 / 3.2 закрыты.
* ✅ [PHASE-3.4-UI-PROPOSAL.md](PHASE-3.4-UI-PROPOSAL.md) — design
  proposal по Flutter UI для visibility / grants / branch wizard +
  conflict badge surface + sensitive contacts section + migration
  strings story «Дерево» → «Ветка». Ожидает review.

## Cutover plan (Артём 2026-05-10)

```
3.1 (done)  → pre-prod (миграция + schema)
3.2 (done)  → pre-prod (enforcement gates + grants endpoints)
3.4 (this)  → pre-prod + prod (Flutter UI — visibility, grants, wizard,
              conflict surface, migration strings)
3.6         → pre-prod + prod (hard-delete background job; can ship
              independently после 3.4)
```

Между 3.2 и 3.4 — NO user-visible regression на anonymous persons.
В 3.4 юзер получает UI handle к Phase 3.1+3.2 механикам.

## Что делаем дальше (после approve proposal'а 3.4)

В указанном порядке:
1. Backend addendum (если approved) — `includeRules` в `POST /trees`,
   `GET /v1/me/issued-grants`.
2. Flutter services / models (capability mixin, DTO).
3. Migration strings story (single commit «UI: Дерево → Ветка»).
4. Visibility toggle section на relative card.
5. Sensitive contacts section (`Видно тебе` badges).
6. Branch creation wizard (расширение CreateTreeScreen).
7. Edit-grants screen + routing `/profile/access`.
8. Conflict badge surface на не-canvas screens (relative_details,
   relatives_screen).
9. flutter analyze + flutter test (расширенные).
10. Diff на показ перед commit.

Никакого кода до approve [PHASE-3.4-UI-PROPOSAL.md](PHASE-3.4-UI-PROPOSAL.md).

## Чего НЕ делать

* НЕ лезть в Phase 3 (TREE → BRANCH миграция) — заблокировано 4
  нерешёнными вопросами в DECISIONS.md.
* НЕ депрекейтить graph-слой (он остаётся).
* НЕ принимать архитектурные решения без записи в DECISIONS.md.
