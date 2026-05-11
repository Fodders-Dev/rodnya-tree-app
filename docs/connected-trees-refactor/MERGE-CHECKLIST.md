# Phase 3 → main merge checklist

**Цель**: финальная остановка перед merge'ем ветки
`claude/infallible-pike-41360c` в `main`. Phase 3.4 chunks 1-5
закрыты — больше Phase 3 работы не делаем, фокус на готовности
к раскатке. После прохождения checklist'а: PR review + merge.

**Не делать merge** пока хотя бы один обязательный пункт не
зелёный. «Обязательные» помечены ✅ — если красный, фиксим до
merge'а. «Информационные» (ℹ) — фиксируем для prod ops, не
блокируют.

---

## Содержимое ветки

Феаture-ветка `claude/infallible-pike-41360c` накопила:

* **Phase 0** — read-only audit (AUDIT, IDENTITY-MATCHER, SCHEMA,
  PLAN superseded).
* **Phase 1.3 closed** — edit-time conflict surfacing (3 теста
  Phase 1.3 уже были зелёные; не trogal'и).
* **Phase 3.1** — graph schema (visibility, edit grants, branch
  include-rules, per-field canonical migration).
* **Phase 3.2** — owner-model enforcement gates на routes +
  grants/visibility endpoints.
* **Phase 3.4-prep** — backend addendum (tree includeRules в
  POST + issued-grants endpoint).
* **Phase 3.4 UI** — chunks 1-5:
  - chunk 1: branch creation wizard (includeRules selector).
  - chunk 2: visibility toggle section на person card.
  - chunk 3: «Доступы» screen с outgoing/incoming табами.
  - chunk 4: sensitive contacts с «Видно тебе» badge.
  - chunk 5: conflict ⚠ badges на не-canvas screens.

15 commits, ~15400 строк insertions, ~440 deletions.

---

## 1. Тесты и static analysis

### ✅ Backend tests

```
ℹ tests       293
ℹ pass        291
ℹ fail          2   ← Windows ENOTEMPTY flake'и в test cleanup
ℹ cancelled     0
```

* 2 fail'а — `test/api.test.js` тесты, `ENOTEMPTY: directory not
  empty, rmdir` при cleanup'е temp папок. **Windows-specific
  flake**, не связан с Phase 3 — задокументирован в commit'е
  `d3cf7f4 docs(refactor): фиксация находок — backend regression
  baseline`. На Linux/CI не воспроизводится.
* **Allowed**: эти 2 теста должны фейлить с одним и тем же
  ENOTEMPTY message'ом. Если message другой — НЕ MERGE.

Команда: `cd backend && npm test`.

### ✅ Flutter tests

```
+456 -3: Some tests failed.
```

* 456 pass, 3 fail.
* 3 fail'а — `test/custom_api_notification_service_test.dart`:
  - `polls unread notifications and deduplicates delivered ids`
  - `suppresses muted chat notifications`
  - `forwards silent mode to chat notifications`
* Cause: `MissingPluginException(No implementation found for
  method read on channel
  plugins.it_nomads.com/flutter_secure_storage)` — отсутствие
  mock'а secure storage в test environment'е.
* **Allowed**: pre-existing, последнее изменение файла на main
  `ebac478` (deps batch 2 bump), не chunk 5. Если message
  другой — НЕ MERGE.

Команда: `flutter test`.

### ✅ Flutter analyze

```
warning - Unused import: '../widgets/branch_digest_strip.dart'
        — lib\screens\home_screen.dart:33:8
warning - The value of the field '_branchDigest' isn't used
        — lib\screens\home_screen.dart:70:17

2 issues found.
```

* 2 warnings, оба в `home_screen.dart` — pre-existing, не Phase 3.
* **Allowed**: zero ошибок, только эти 2 warnings. Если новые
  warnings — fix до merge'а.

Команда: `flutter analyze`.

### ℹ Phase 3.4 specific tests (тaxonomy)

| Chunk | Файл | Tests |
|---|---|---|
| 1 | `test/include_rules_test.dart` | 18 unit |
| 1 | `test/create_tree_screen_test.dart` (extended) | 5 widget |
| 2 | `test/visibility_choice_test.dart` | 12 unit |
| 2 | `test/visibility_toggle_section_test.dart` | 6 widget |
| 3 | `test/access_grants_outgoing_tab_test.dart` | 6 widget |
| 3 | `test/access_grants_incoming_tab_test.dart` | 5 widget |
| 3 | `test/access_grants_screen_test.dart` | 4 widget |
| 4 | `test/sensitive_contacts_section_test.dart` | 6 widget |
| 5 | `test/identity_conflicts_badge_test.dart` | 11 widget |
| 5 | `test/identity_conflicts_sheet_test.dart` | 6 widget |
| Backend | `test/owner-model-enforcement.test.js` | 30 unit |
| Backend | `test/branch-include-rules.test.js` | 28 unit |
| Backend | `test/migration-utils.test.js` (extended) | 24 unit |
| Backend | `test/identity-matcher.test.js` (extended) | 25 unit |

Итого новых tests: **186** (Flutter + Backend).

---

## 2. Manual smoke checklist

Прогнать на **dev cluster** (или staging) после deploy'а, до того
как PR будет merged в main. Каждый пункт — что юзер должен
видеть. Если расходится — НЕ MERGE.

### ✅ Phase 3.1 schema migration

* [ ] Свежий аккаунт регистрируется → backend создаёт graphPerson
  для user.id с `visibility: 'connected-via-blood-graph'`,
  `visibilityOverride: false`.
* [ ] Старый аккаунт login'ится → backend dry-run на проде делает
  per-field canonical resolution; если был conflict — пишет
  `identityFieldConflict` row (origin: "migration"); UI после
  login'а показывает ⚠ badge'и на canvas + relative_details.
* [ ] Старое дерево с anonymous предками открывается → каждый
  получает `identityId` через `backfillPersonIdentities`;
  `branch.includeRules` дефолтит на `{type: 'manual',
  personIds: [...]}` чтобы сохранить ровно тот же набор
  visible person'ов.

### ✅ Phase 3.2 enforcement

* [ ] Anonymous user пытается edit'ить чужой graphPerson → 403
  `NOT_OWNER`.
* [ ] User А создаёт person с `userId = userB.id` (не свой) →
  403 `CROSS_OWNER_CREATE_FORBIDDEN`. (DECISIONS.md рассказывает
  flow: use identity-claim instead.)
* [ ] Sensitive attribute (field === 'contacts') GET от не-owner
  → filter'ится из payload (не 403, тихо).
* [ ] Identity-claim flow: anonymous person'у user attach'ится
  через `acceptIdentityClaim` → graphPerson.userId обновляется,
  ownership shifts на claimant (DECISION «ownership ≠ creator»
  применяется).

### ✅ Phase 3.4-prep backend addendum

* [ ] `POST /v1/trees` принимает `includeRules` payload — `manual`
  / `blood-from-me` / `descendants-of` / `ancestors-of` валидны.
  `invalid-rule` → 400.
* [ ] `PATCH /v1/trees/:id/include-rules` — owner-only (creatorId),
  не-owner получает 403.
* [ ] `GET /v1/me/issued-grants` возвращает grants выписанные
  viewer'ом, включая revoked-since-30d.
* [ ] `GET /v1/me/edit-grants` возвращает grants мне (incoming).

### ✅ Phase 3.4 chunk 1 — branch wizard

* [ ] «Создать ветку» (родственники) → wizard показывает:
  - 4 radio варианта типа (Manual / Кровная родня / Потомки /
    Предки).
  - Slider 3..8 (по умолчанию 5) когда тип не Manual.
  - Anchor picker когда тип = Потомки / Предки.
* [ ] «Создать ветку» (друзья) → дефолт на Manual без slider'а.
* [ ] Submit с не-Manual + пустой anchor → snackbar refuse
  «Выберите якорь».
* [ ] Successful create → backend POST /v1/trees с правильным
  `includeRules`.

### ✅ Phase 3.4 chunk 2 — visibility toggle

* [ ] Owner смотрит свою карточку → видит section «Кому видна
  эта карточка?» с 3 radio:
  - «Моим родственникам» (default) с hint «...до 4 поколений».
  - «Только мне» с hint «...не публикуется автоматически».
  - «Всем» с hint «Открыта в общем поиске».
* [ ] Tap «Только мне» → backend PATCH с автоматическим
  `visibilityOverride: true`.
* [ ] Tap default «Моим родственникам» → DELETE
  visibility-override (delegate to time auto-resolve).
* [ ] Не-owner смотрит чужую карточку → section ПОЛНОСТЬЮ скрыта
  (не leak'ает «secret card exists»).
* [ ] Старый сервер (без capability mixin'а) → section скрыта
  (graceful degradation).

### ✅ Phase 3.4 chunk 3 — edit-grants screen

* [ ] Settings → «Уведомления и доступ» → tile «Доступы»
  «Кто редактирует ваши карточки» → переход на `/profile/access`.
* [ ] Tab «Кому я разрешил» → list grants выписанных юзером,
  группировка по graphPerson, tap close → confirm-dialog со
  scope-specific текстом → DELETE grant → optimistic re-fetch.
* [ ] Tab «Что мне разрешено» → list grants на чужие карточки,
  без revoke (informational).
* [ ] Revoked-since-30d grants показываются серым с «отозвано
  N дней/недель назад».
* [ ] Старый сервер → unsupported state с пояснением.

### ✅ Phase 3.4 chunk 4 — sensitive contacts

* [ ] Свой profile-card на дереве → section «Контакты» с phone /
  email / city+country, каждое поле с «🔒 Видно тебе» badge.
* [ ] Чужая карточка → section полностью скрыта.
* [ ] Свой profile-card без contacts → empty state «Контакты
  ещё не указаны. [Добавить]» → переход на /profile/edit.
* [ ] После claim'а карты другим user'ом (`userId` shifts) →
  creator теряет access к contacts (DECISION «ownership ≠
  creator»).
* [ ] Tooltip на badge при long-press показывает full message
  «Видно только тебе. Контакты родственники не видят, даже если
  карточка открыта всем.»

### ✅ Phase 3.4 chunk 5 — conflict badges

* [ ] Canvas (tree_view_screen) — все Phase 1.3 поведение
  сохранено (badge на узле → sheet с keep/overwrite).
* [ ] Relative_details_screen с unresolved conflicts → header
  banner «Найдено N расхождений с другими ветками. Посмотреть
  и решить» → tap → IdentityConflictsSheet.
* [ ] Relatives_screen list-item с conflict'ом → compact ⚠ icon
  в trailing Row + Semantics label «у карточки есть N
  расхождений».
* [ ] Relatives_screen header → banner «N карточек требуют
  внимания» → tap → sheet со всеми tree conflict'ами.
* [ ] Resolve conflict через sheet → refresh-on-success counts
  обновляются на том же screen.

---

## 3. v1→v2 migration dry-run

### ✅ Synthetic fixture verified

Script: `backend/scripts/dry-run-phase31-migration.js` — читает
JSONB snapshot, прогоняет `backfillPersonIdentities` +
`migrateTreesToGraphAndBranches` in-memory, печатает diff. **Не
пишет в исходный файл.**

* [ ] Прогнать на synthetic fixture (`test/fixtures/` или
  ad-hoc): 1 user, 5 persons (mixed claimed/anonymous), 1 tree,
  3 relations. Ожидаемо: 5 graphPersons, 1 branch, 5
  graphRelations (или dedupe'нутые если symmetric).
* [ ] Pre-flight count check throws **только** на драфт invalid
  rule, не на missing/empty (DECISIONS.md «applyIncludeRulesToBranch
  defensive») — verify запуском с corrupted snapshot'ом.
* [ ] Перфорированный per-field canonical conflict записывается
  в `identityFieldConflicts` с `origin: "migration"`, не
  блокирует migration.

### ⚠ Production dry-run перед deploy

**Обязательно** запустить dry-run на копии prod JSONB ДО того,
как cluster прокатывается:

```bash
node backend/scripts/dry-run-phase31-migration.js \
  --source=/path/to/prod-db-snapshot.json --verbose
```

* [ ] Diff output: новые `graphPersons.length`, `branches.length`,
  `graphRelations.length` совпадают с ожидаемым (не «потеряли»
  половину people).
* [ ] Если pre-flight count check throws → НЕ deploy, разобрать
  причину (corrupted include rule, или edge case в matcher'е).
* [ ] Зарегистрированные `identityFieldConflicts` (origin:
  "migration") — приемлемое кол-во (< 5% от total persons
  обычно). Если 20%+ — manual review.

---

## 4. Backward-compat verification

### ✅ Legacy invite-link'и

Phase 3.2 commit consolidated 3 legacy invite flows в один
identity-claim flow:

* [ ] Старая invite-link URL (`/invite/...?treeId=X&personId=Y`) →
  не падает, redirect'ит на identity-claim flow с pre-filled
  значениями. Backward-compat по prefer'у А (см. DECISIONS.md).
* [ ] User'ы которые получили email с link'ом 3 недели назад →
  link открывается, claim flow проходит.

### ✅ Capability mixin pattern (graceful degradation)

Старый сервер без Phase 3.2/3.4-prep:

* [ ] Visibility section на person card → скрыта (widget
  gates через `GraphPersonAccessCapableFamilyTreeService`
  is-check).
* [ ] «Доступы» screen → показывает unsupported state.
* [ ] Conflict badges (Phase 1.3) → продолжают работать (Phase
  1.3 capability отдельная, не Phase 3.x).
* [ ] Sensitive contacts section → показывается, но без backend
  enforcement'а данных нет → empty-state (acceptable).

### ✅ Per-field canonical migration backward-compat

* [ ] Старые `person.canonicalIdentityId` (Phase 1) → preserved.
  Phase 3.1 переписывает canonicalFields per-field, но
  identityId как ключ stable.
* [ ] Старые tree.memberIds (legacy split в DECISIONS.md) → не
  drop'ятся: branch.includeRules.personIds дефолтит на ровно
  тот же набор.

---

## 5. Rollback plan

### Сценарий A: migration глюк (data corruption)

**Симптом**: post-migration юзер видит pустое дерево / not
найденных родственников / 500 на /v1/trees.

**Action**:
1. **Stop deploy** на текущем cluster'е.
2. Restore JSONB snapshot из pre-migration backup (Phase 3.1
   migration не делает atomic write — `_read` + transform +
   `_write` шагами).
3. Откатить cluster на pre-Phase-3.1 build (commit `0d5acec`'s
   parent).
4. Diff prod snapshot до/после, разобрать root cause.
5. **Не push'ать** в main пока root cause не закрыт.

### Сценарий B: UI глюк (frontend crash / blank screen)

**Симптом**: Flutter app падает на launch / blank на главной /
crash на person card.

**Action**:
1. UI ровно над Phase 3.4 — backend остаётся forward-compat.
2. Revert конкретный chunk commit в feature branch:
   - chunk 1 broken → revert `a24d7e8`.
   - chunk 2 broken → revert `bb692a1`.
   - chunk 3 broken → revert `e1bf67d`.
   - chunk 4 broken → revert `7d5294b`.
   - chunk 5 broken → revert `228e9e9`.
3. Backend остаётся новый — каждый chunk independent. Capability
   mixin gracefully скрывает соответствующий UI.

### Сценарий C: enforcement false-positive (юзер не может edit
своё)

**Симптом**: owner получает 403 на свою же карточку.

**Action**:
1. Backend revert `a40a429 feat(phase-3.2): owner-model
   enforcement gates`.
2. Phase 3.1 schema остаётся (новые поля идут с дефолтом).
3. UI Phase 3.4 продолжает работать, sensitive sections видны
   owner'у через capability mixin's snapshot fetch.
4. Re-deploy после исправления.

### Не-сценарий: rollback Phase 3.4-prep

Phase 3.4-prep backend addendum (`4adfc14`) — endpoint
addendum'ы (POST tree includeRules, GET issued-grants). Revert
этого только сломает chunk 1 + chunk 3 UI, но не data. Не
требуется в большинстве scenarios.

---

## 6. Pre-merge actions

После прохождения всех ✅ пунктов:

1. [ ] **PR создан** против `main`, описание ссылается на этот
   checklist + Phase 3.4 proposal.
2. [ ] **Code review** от Артёма.
3. [ ] **Squash или fast-forward** — НЕ rebase'ить (чтобы
   commit-by-commit story оставалась читаемой; 15 commits на
   ветке тщательно построены).
4. [ ] **Migration dry-run на prod snapshot** verified (см. §3).
5. [ ] **Pre-prod deploy** + manual smoke (см. §2). Минимум 24
   часа в pre-prod.
6. [ ] **Production deploy** только после OK от Артёма.

---

## 7. Post-merge actions

После merge'а в main:

1. [ ] Branch `claude/infallible-pike-41360c` остаётся доступной
   ещё минимум 30 дней — для rollback reference'а.
2. [ ] Метрики первой недели:
   - migration-time conflicts count per user (median).
   - 403 NOT_OWNER rate (если spike — false-positive, разобрать).
   - Conflict badge tap'ы (engagement metric — заходят ли юзеры в
     resolution flow).
3. [ ] Follow-up TODOs из DECISIONS.md (chunk 3 grantor preview;
   chunk 5 cache invalidation / performance) — добавить в
   roadmap до Phase 4.
4. [ ] **Phase 4 proposal** — extended-family network через
   identity граф. Дизайн начнётся после стабилизации Phase 3 в
   prod.

---

**Принято к работе**: Артём (user) 2026-05-11.

**Status**: 🟡 в работе — checklist готов, manual smoke и
production dry-run ждут pre-prod deploy.
