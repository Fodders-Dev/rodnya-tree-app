# Текущая фаза рефакторинга

> ⚠️ Важно: PLAN.md этой папки SUPERSEDED. Источник правды —
> [`docs/tree_model_overhaul_rfc.md`](../tree_model_overhaul_rfc.md).
> См. [DECISIONS.md](DECISIONS.md) от 2026-05-09.

**Status update**: 2026-05-22 (post Phase 3.4 branch abandon + worktree cleanup follow-up + Phase 6 observation early peek + **Phase 6.5 revocation shipped**, см. DECISIONS 2026-05-22).

## Shipped к production

| Phase | Status | Main commit | Notes |
|---|---|---|---|
| Phase 0 | ✅ closed 2026-05-09 | (audit, no code) | AUDIT.md + IDENTITY-MATCHER.md + SCHEMA.md |
| Phase 1.3 | ✅ closed 2026-05-09 | (already реализован in code) | edit-time conflict surfacing — DoD достигнут |
| Phase 3.1 | ✅ closed 2026-05-10 | `0d5acec` | schema graph + migration v1→v2 |
| Phase 3.2 | ✅ closed 2026-05-10 | `a40a429` | owner-model enforcement gates + grants/visibility endpoints |
| Phase 3 squash | ✅ shipped 2026-05-11 | `cb67b0b` | Phase 3 connected per-user trees squash |
| Phase 4 | ✅ shipped 2026-05-12 | `028d1d2` | extended-family network (BFS view) |
| Phase 4 flag flip | ✅ flag-on 2026-05-13 | `5fb1d3c` | `useExtendedRenderPath` default true — observation week closed 2026-05-18 cleanup `baa75d5` |
| Phase 4 cleanup | ✅ closed 2026-05-18 | `baa75d5` | flag + legacy renderer + override removed; extended-network permanent. См. DECISIONS.md 2026-05-18 |
| Phase 6 | ✅ shipped 2026-05-14 | `414b218` | onboarding wizard + kinship-check «мы родственники?» |
| Phase 6 hotfix | ✅ closed 2026-05-18 | `b4dcb47` + `40202a1` | `/v1/auth/session` requiresOnboarding gap (chunk 4a follow-up) — DECISIONS.md 2026-05-18 hot-path fix |
| Phase 3.6 | ✅ shipped 2026-05-18 + activated 2026-05-19 | `253efaf` | Hard-delete background job. Live в проде с 2026-05-19 03:03 UTC (env flip `RODNYA_HARD_DELETE_ENABLED=true` + `_FIRST_RUN_DRY=false`). First live run 0/0/0 deletions. DECISIONS.md 2026-05-18 ship + 2026-05-19 activation. |
| Phase 3.4 | ✅ shipped 2026-05-11 | `cb67b0b` | UI: visibility toggle + grants + branch wizard + sensitive contacts + conflict badges. Squash of branch `claude/infallible-pike-41360c` (16 commits, ~15400 insertions). Branch cleaned up 2026-05-22 (см. DECISIONS 2026-05-22). |

## Parked (готово к merge, ждёт Артёмова call)

(пусто — ничего не parked)

## Observation windows (active)

* **Phase 6 observation**: 2026-05-14 → 2026-05-28 (2 weeks).
  Метрики per MERGE-CHECKLIST-PHASE-6 §5:
  * register → wizard finish >70%
  * wizard finish → tree view >90%
  * discover funnel (FAB → submit) >40%
  * kinship acceptance rate (informational)
  * 5xx rate <0.1%
  Flagless (additive feature) — observation = passive metric monitoring,
  no code flip needed.

  > ⚠️ Day 8 peek (2026-05-22): organic adoption минимальный
  > (1 real user из 5 registrations, hit chunk 4a bug before fix
  > deploy). Server-side state correct (`currentStep: "welcome"` для
  > всех 5), automatic retry slot ready на next login. Review window
  > likely inconclusive — sample too small. См. DECISIONS 2026-05-22
  > "Phase 6 observation early peek".

## Pending — нужен Артёмов design call

* **Phase 6.5** (post-observation, conditional):
  * Identity-suggestions push notification (DECISIONS
    2026-05-14 «identity-suggestions push deferred»).
  * ~~Revocation UX для kinship-checks (PHASE-6-PROPOSAL §2.6).~~
    ✅ Shipped 2026-05-22 — initiator может отозвать pending
    request, target gets `kinship_check_revoked` notification.
    См. DECISIONS 2026-05-22.
  * Native notification action buttons (Подтвердить/Отклонить
    inside notification body).

## Cutover plan (Артёмов 2026-05-10, original)

```
3.1 (done)  → pre-prod (миграция + schema) — 0d5acec
3.2 (done)  → pre-prod (enforcement gates + grants endpoints) — a40a429
3.4 (shipped 2026-05-11 cb67b0b) → squash of branch which was cleaned up 2026-05-22
3.6 (activated 2026-05-19) → prod (hard-delete background job; shipped
              independently от 3.4, activated через env flip 24h после
              ship). 253efaf + manual env flip.
4 (done)    → prod (extended-family network) — 028d1d2 + 5fb1d3c flag-flip
6 (done)    → prod (onboarding wizard + kinship-check) — 414b218
```

Реальная последовательность: Phase 3.1 (05-10) → 3.2 (05-10) →
Phase 3 squash включая 3.4 UI (05-11 `cb67b0b`) → Phase 4
(05-12 `028d1d2`) → Phase 6 (05-14 `414b218`). Phase 3.4 branch
остался dangling как squash-merge artifact до 2026-05-22 cleanup
(см. DECISIONS 2026-05-22).

## Чего НЕ делать

* НЕ депрекейтить graph-слой (он остаётся).
* НЕ принимать архитектурные решения без записи в DECISIONS.md.
