# Phase 3.4 — Flutter UI для visibility / grants / branch wizard

> **Статус**: design proposal, ожидает review Артёма.
> **Источник правды**: [tree_model_overhaul_rfc.md](../tree_model_overhaul_rfc.md) §3.4
> + [DECISIONS.md](DECISIONS.md) (ответы A–D + 3.2 follow-ups)
> + commit'ы `0d5acec` (Phase 3.1 schema), `a40a429` (Phase 3.2 enforcement).
> **Не лезть в код** до явного approve.

---

## 0. Контекст и DoD

### Что делаем в Phase 3.4

После Phase 3.1+3.2 backend:
* graphPerson schema готова (visibility, override, grants).
* Routes enforce'ят owner-model и privacy.
* Endpoints для CRUD grants + visibility toggle уже работают.

**Чего у юзера нет** — UI handle ко всему этому. Visibility default
"connected-via-blood-graph" работает невидимо; sensitive contacts
hide от non-owner — без UI badge юзер не знает что они скрыты;
grants нельзя выписать — нет screen'а; branch wizard не выбирает
new `includeRules.type`.

Phase 3.4 закрывает client-side: каждая Phase 3.1+3.2 механика
получает понятный человеческий surface.

### Что НЕ делаем в Phase 3.4

Per Артёмовому scope от 2026-05-10:

* Extended-family network view (RFC Phase 4 BFS UI) — отдельная фаза.
* «Найти родство» между двумя юзерами с consent (RFC Phase 4) — отдельно.
* Public layer (Pushkin etc, RFC Phase 5).
* Onboarding wizard (RFC 6.5).
* Hard-delete background job (Phase 3.6).
* Никакого «claude design pass» (RFC явно отверг).

### DoD Phase 3.4

* Branch creation wizard поддерживает `includeRules.type ∈
  {manual, blood-from-me, descendants-of, ancestors-of}` + `maxHops`
  (3..8 slider) + `anchorPersonId` picker для not-manual.
* Visibility toggle на person card отдаёт три варианта в человеко-
  читаемом языке + checkbox «Override default».
* Edit-grants screen с двумя табами — outgoing (revokable) +
  incoming (informational).
* Sensitive contacts section в profile-editor с явным «Видно
  только тебе» badge.
* Conflict ⚠ badge surface на карточках (read-list уже есть в
  tree_view; в Phase 3.4 расширяется на relative_details_screen).
* Migration story: «Дерево» → «Ветка» в strings (список ниже).
* `flutter analyze` zero issues.
* Все новые screens покрыты widget-tests (минимум — render +
  primary action smoke).

---

## 1. Existing UI baseline (что уже есть, для контекста)

Phase 6.1 уже сделана (commit pre-handoff):
* [`lib/widgets/branch_switcher_chip.dart`](lib/widgets/branch_switcher_chip.dart)
  — chip в top bar, переключение между ветками.
* [`lib/screens/family_tree/create_tree_screen.dart`](lib/screens/family_tree/create_tree_screen.dart)
  — text formо `name`/`description`/`isPrivate` + 4 шаблона
  («По маминой линии», «По папиной линии», «Семья жены», «Кровная
  родня»). `includeRules` НЕ поддерживается — все branches
  создаются с `type: "manual"`.
* [`lib/screens/tree_selector_screen.dart`](lib/screens/tree_selector_screen.dart)
  — список trees, leave/delete UI.
* [`lib/screens/relative_details_screen.dart`](lib/screens/relative_details_screen.dart)
  — person card. Использует `unlinkUserFromPerson` из Phase 1.x.
* [`lib/widgets/interactive_family_tree.dart`](lib/widgets/interactive_family_tree.dart)
  — canvas с `_IdentityConflictsBadge` (Phase 1.3 ⚠) и
  `_IdentitySuggestionsBadge` (Phase 1.2 💡).
* [`lib/screens/tree_view_screen.dart`](lib/screens/tree_view_screen.dart) →
  `_IdentityConflictsSheet` для resolve. **Уже работает на
  canvas**. Phase 3.4 — расширяем surface на не-canvas paths
  (e.g. relative_details_screen).

Phase 3.4 **дополняет**, не переделывает существующее.

---

## 2. Per-feature wireframes

### 2.1 Branch creation wizard (расширение существующего CreateTreeScreen)

**Где**: `/trees/new` route, `CreateTreeScreen`. После approval —
текущий screen разбивается на 2 секции либо на 3-step wizard
(см. §6 UX-considerations).

**Mobile-first wireframe (single screen, vertical scroll)**:

```
┌─────────────────────────────────────────────┐
│ ← Новая ветка                               │
├─────────────────────────────────────────────┤
│                                             │
│ 1. Какую ветку строим?                      │
│                                             │
│ ┌─────────────────────────────────────────┐ │
│ │ ⦿ 🩸 Кровная семья от меня (по умолчанию) │ │
│ │   Все родственники до 5 колен.            │ │
│ │   Простой выбор.                          │ │
│ └─────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────┐ │
│ │ ○ ✋ Свободная — я добавляю кого хочу     │ │
│ │   Полный контроль над списком людей.      │ │
│ └─────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────┐ │
│ │ ○ 🌳 От конкретного человека              │ │
│ │   Все потомки или предки выбранного       │ │
│ │   родственника.                           │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│ ─── (для blood/descendants/ancestors): ─── │
│                                             │
│ 2. Глубина обхода: 3 ─ ●━━━━ 8   (5 колен) │
│                                             │
│ 3. Якорь  (только для descendants/         │
│   ancestors):                               │
│ [👤 Выбрать человека]                       │
│                                             │
│ ─── общие поля: ─── │
│                                             │
│ Название ветки:                             │
│ [_______________________________________]  │
│                                             │
│ Описание (необязательно):                   │
│ [_______________________________________]  │
│ [_______________________________________]  │
│                                             │
│ ☑ Приватная ветка                           │
│   (только участники видят посты)            │
│                                             │
│           [   Создать ветку   ]             │
└─────────────────────────────────────────────┘
```

**Element semantics**:

* **Radio rule selector** — 3 варианта. Default — «Кровная семья от
  меня» (`type: "blood-from-me"`, `maxHops: 5`).
* **Slider 3..8** — visible только когда `type` ≠ `"manual"`.
  Лейбл интерполируется: «3 колен» / «4 колен» / «5 колен» / ...
  / «8 колен». («колен», не «hops» — RFC §A).
* **Анкор-picker** — visible только для `descendants-of` / `ancestors-of`.
  Кнопка → bottom sheet с list-of-persons из любой ветки юзера
  (через existing cross-tree picker `/v1/persons/search`).
* **Manual-mode** показывает «Список людей добавишь позже» вместо
  slider'а (no upfront selection — это даёт пустую ветку, юзер
  ручкой добавляет).
* **Шаблоны** (existing `_BranchTemplate`) — не убираю; превращаю
  в quick-pick chips НАД radio'ом, которые pre-fill name+description
  (как сейчас) **плюс** rule-tipy:
  - «По маминой линии» → manual + name «По маминой линии».
  - «Кровная родня» → blood-from-me + name «Кровная родня».
  - «Семья жены» → manual (нужно явно выбрать кого).

**API contract** (без изменений в endpoint shape, только payload):

```dart
POST /v1/trees
{
  "name": "Кровная родня",
  "description": "...",
  "isPrivate": true,
  "kind": "family",
  "includeRules": {
    "type": "blood-from-me",
    "anchorPersonId": null,
    "maxHops": 5,
  }
}
```

**Backend gap**: `POST /v1/trees` сейчас принимает только
`name/description/isPrivate/kind`. Для Phase 3.4 необходимо
расширить shape: store-side `createTree` → принимать `includeRules`
(если не передан — default `{type: "manual", manualPersonIds: [], maxHops: 5}`).
Это **минимальный backend addendum** в рамках 3.4 (или может
быть отдельным small commit сразу после 3.2 cutover) — без него
UI wizard не сможет fact'и stick rule.

**Tests**: widget-test → render + radio toggle + slider visibility
+ submit с правильным payload (mock service).

---

### 2.2 Visibility toggle на person card

**Где**: [`relative_details_screen.dart`](lib/screens/relative_details_screen.dart) —
существующий screen карточки. Добавляется секция «Кому видно эту
карточку» в profile-editor mode.

**Wireframe (часть relative_details_screen)**:

```
┌─────────────────────────────────────────────┐
│ Карточка: Бабушка Лида                      │
├─────────────────────────────────────────────┤
│ ...                                         │
│ Имя:        Лидия Александровна             │
│ Дата:       14 марта 1949                   │
│ ...                                         │
│                                             │
│ ─── Приватность ─────────────────────────  │
│                                             │
│ Кому видна эта карточка?                    │
│                                             │
│ ⦿ Моим родственникам (по умолчанию)          │
│   Видят те, кто связан со мной через        │
│   семейные связи до 4 колен.                │
│                                             │
│ ○ Только мне                                 │
│   Никто кроме меня не видит эту карточку.   │
│                                             │
│ ○ Всем                                       │
│   Открыта в общем поиске (например, для     │
│   старых родственников).                    │
│                                             │
│ ☐ Запомнить мой выбор и не пересчитывать    │
│   автоматически                             │
│   (По умолчанию приватность пересчитывается │
│   через 100 лет после смерти.)              │
│                                             │
│             [  Сохранить  ]                 │
└─────────────────────────────────────────────┘
```

**Element semantics**:

* **3 radio**:
  - «Моим родственникам» = `connected-via-blood-graph`.
  - «Только мне» = `owner-only`.
  - «Всем» = `public`.
* **Override checkbox**: «Запомнить мой выбор и не пересчитывать
  автоматически». Когда checked → API ставит `visibilityOverride:
  true`. Когда unchecked → текущее значение сохраняется как
  stored, **но** `visibilityOverride: false` ⇒ auto-public для
  deceased+>100лет всё равно сработает поверх.
  - Для `owner-only` — checkbox по умолчанию true (если юзер
    выбирает «Только мне», он явно хочет тверды).
  - Для остальных — false по умолчанию.
* **Sensitive поля гейтятся отдельно**: даже если visibility =
  «Всем», phone/email/address не показываются (см. §2.4).
* **Кнопка «Сохранить»** → `PATCH /v1/graph-persons/:id/visibility`.
  - Если override unchecked AND stored value matches default —
    можно дополнительно вызвать `DELETE /v1/graph-persons/:id/visibility-override`
    чтобы reset был чистым. Mostly nice-to-have, low priority.

**Visible только**: на graphPerson'е, чьим owner'ом viewer является.
Если viewer не owner — секция скрыта (или показана read-only с
текущим эффективным visibility lavbom).

**Tests**: widget render + 3 radio toggle + override checkbox state
+ save call (mock).

---

### 2.3 Edit-grants management screen

**Где**: новый screen `/settings/access` или
`/profile/access`. Per Артёмовой UX-Q C — оптимально в
**profile editor → «Доступы»** (там же где будущая Phase 4
«Связи родства» сядет).

**Routing**: `/profile/access` (новый), доступен из profile-screen
строкой «Доступы» в settings-section. Также из long-press menu
на person card в /tree-view (Phase 3.4 расширение).

**Wireframe (full screen, two tabs)**:

```
┌─────────────────────────────────────────────┐
│ ← Доступы                                   │
├─────────────────────────────────────────────┤
│ [ Кому я разрешил ]   Что мне разрешено     │
├─────────────────────────────────────────────┤
│                                             │
│ Карточка «Я» (Артём Кузнецов)               │
│   👤 Дарья Иванова — может редактировать    │
│      Выдано 5 марта 2026                    │
│                            [ ⋯ ]            │
│      ───                                    │
│      ⊗ Отозвано 12 марта 2026               │
│                                             │
│ Карточка «Прабабушка Лида»                  │
│   👤 Виктор Кузнецов — может объединять     │
│      Выдано 8 апреля 2026                   │
│                            [ ⋯ ]            │
│                                             │
│ ─── без активных доступов ─────────────────│
│                                             │
│ + Карточки без доступов: 12                 │
│   (никому не выдавал)                       │
│                                             │
└─────────────────────────────────────────────┘
```

**Tab-2: «Что мне разрешено»** (informational):

```
│ Дарья Иванова                               │
│ • Прадедушка Никита — могу редактировать    │
│   с 1 марта 2026                            │
│                                             │
│ Степан Сергеев                              │
│ • Бабушка Лариса — могу объединять          │
│   с 8 апреля 2026                           │
│                                             │
│ ─── ⊗ Недавно отозваны ─── │
│                                             │
│ • Дедушка Иван — отозвано 7 апреля 2026     │
│   (можешь спросить владельца, почему)       │
```

**Element semantics**:

* **Outgoing tab** (active): list grants выписанных текущим viewer'ом.
  Group by graphPerson (визуально читать «на каждой моей карточке —
  кто имеет доступ»). Revoked rows показаны в свёрнутом виде
  (чёрно-серым), за последние 30 дней (бек уже отдаёт revoked в
  этом окне).
* **[⋯] menu** — single action «Отозвать доступ».
* **Incoming tab**: read-only список grants для viewer'а. Group by
  grantor. **No revoke** action (grantee не может revoke свой grant).
* **Empty state**: «У вас никому ничего не разрешено. Когда вы
  выпишете доступ — он появится здесь».
* **Add grant** path: НЕТ button «выписать grant» в edit-grants
  screen напрямую. Grant выписывается из карточки человека: «Дать
  родственнику возможность редактировать эту карточку» в long-press
  menu / overflow на относительной карточке (см. §3 architecture).

**Backend API**:
* `GET /v1/me/edit-grants` — для incoming tab (existing).
* `GET /v1/graph-persons/:id/grants` per-graphPerson — для outgoing
  tab. Грантеер должен знать список своих graphPersons и пройти
  по ним. Альтернатива (NEW endpoint): `GET /v1/me/issued-grants` —
  список grants выписанных viewer'ом. Это **минимальный backend
  addendum** для outgoing tab (иначе client делает N round-trip'ов
  по своему graphPerson'у).
  - Открытый вопрос: добавить endpoint в 3.4 или работать через
    bulk per-graphPerson? Я рекомендую endpoint — exactly как
    `/v1/me/edit-grants`, симметрично.

**Tests**: widget render обоих табов + revoke action + empty states.

---

### 2.4 Sensitive contacts visibility section

**Где**: расширение [`relative_details_screen.dart`](lib/screens/relative_details_screen.dart)
+ profile editor `user_profile_entry_screen.dart`. Это секция
рядом с person'овыми attributes (phone/email/address).

**Wireframe**:

```
┌─────────────────────────────────────────────┐
│ ─── Контакты ─────────────────────────────│
│                                             │
│ Телефон:    +7 999 1234567   🔒 Видно тебе │
│ E-mail:     anna@example.com  🔒 Видно тебе │
│ Адрес:      Москва, ул. Невская  🔒 ...     │
│                                             │
│  [ ⓘ ] Эти поля видны только владельцу     │
│        карточки. Другие родственники их     │
│        не увидят, даже если карточка        │
│        открыта «Всем».                      │
│                                             │
│ [✏️ Изменить]                                │
└─────────────────────────────────────────────┘
```

**Element semantics**:

* **🔒 Badge «Видно тебе»** на каждом sensitive поле. Tooltip /
  info-text расшифровывает почему.
* Когда viewer **не owner** — секция полностью скрыта (sensitive
  attributes отфильтрованы на бекенде в Phase 3.2).
* **«Изменить»** кнопка → открывает profile editor с pre-filled
  значениями. Save → PUT attributes (gating'уется backend'ом per
  scope=edit плюс owner-only-всегда для contacts category).

**No new endpoint** — sensitive attributes уже работают через
existing `GET/PUT /v1/trees/:treeId/persons/:personId/attributes`.
Phase 3.2 уже filter'ит на READ + reject'ит на WRITE.

**Tests**: render с/без owner; "Видно тебе" badge присутствует;
edit click → form opens; non-owner вообще не видит section.

---

### 2.5 Conflict ⚠ badge surface (read + список)

**Где**:
* Уже работает в [tree_view_screen.dart](lib/screens/tree_view_screen.dart)
  через `_IdentityConflictsBadge` + `_IdentityConflictsSheet`
  (Phase 1.3 closed).
* Phase 3.4 расширение — surface badge **на не-canvas screens**:
  - `relative_details_screen.dart` — header / status row.
  - `relatives_screen.dart` — list-item с ⚠ значком если у
    person есть unresolved конфликты.

**Wireframe (relative_details header)**:

```
┌─────────────────────────────────────────────┐
│ ← Бабушка Лида                ⚠ 3          │
├─────────────────────────────────────────────┤
│ ...                                         │
│ ⚠ Найдено 3 расхождения с другими ветками  │
│   [ Посмотреть и решить ]                   │
└─────────────────────────────────────────────┘
```

**Wireframe (relatives_screen list-item)**:

```
│ 👤 Бабушка Лида               ⚠              │
│   1949 — Тула                                 │
```

**Behavior**:
* Badge клик → existing `_IdentityConflictsSheet` (canvas-side
  helper) расширяется в reusable component (move to
  `lib/widgets/identity_conflicts_sheet.dart`) и используется в
  обоих новых surface'ах.
* **Resolve action в sheet** уже есть (keep / overwrite). Артём
  сказал «resolve sheet можно отложить отдельной фазой» — но он
  УЖЕ закрыт в Phase 1.3 (3 теста зелёные). Phase 3.4 — это
  минор: surface расширяется, sheet используется **as-is**.

**Tests**: relative_details рендерит badge при наличии конфликтов;
relatives_screen показывает ⚠ в list-item; click → sheet
opens.

---

## 3. Architecture: новые screens / changes в existing

### 3.1 Новые widgets / screens

```
lib/screens/access/
  ├── access_screen.dart                — main screen с two tabs
  ├── access_outgoing_tab.dart          — group by graphPerson
  └── access_incoming_tab.dart          — group by grantor

lib/widgets/
  ├── visibility_toggle_section.dart    — для relative_details
  ├── grant_action_sheet.dart           — long-press menu для
  │                                       relative card → "Дать доступ"
  └── identity_conflicts_sheet.dart     — moved из tree_view_screen.dart
                                          (reusable)

lib/backend/interfaces/
  └── graph_person_grants_capable_family_tree_service.dart
                                        — capability mixin

lib/backend/models/
  ├── edit_grant.dart                   — DTO grant + scope enum
  └── visibility_choice.dart            — enum (auto/owner/public)
                                          + override flag

lib/services/
  └── custom_api_graph_person_service.dart
                                        — реализация POST/DELETE/
                                          GET grants + PATCH visibility +
                                          GET /v1/me/edit-grants +
                                          new GET /v1/me/issued-grants
                                          (см. backend addendum в §2.3)
```

### 3.2 Существующие changes

| Файл | Что меняется |
|---|---|
| `lib/screens/family_tree/create_tree_screen.dart` | + radio rule selector + slider + anchor picker; submit передаёт `includeRules` payload. |
| `lib/screens/relative_details_screen.dart` | + visibility toggle section (для viewer=owner); + ⚠ conflict badge в header; + sensitive «Видно тебе» badge на contacts attributes; + long-press / overflow menu «Дать доступ родственнику». |
| `lib/screens/relatives_screen.dart` | + ⚠ значок в list-item для persons с unresolved conflicts. |
| `lib/screens/tree_view_screen.dart` | move `_IdentityConflictsSheet` → reusable widget (no behavior change). |
| `lib/screens/profile_screen.dart` | + строка «Доступы» в settings-section ведёт на `/profile/access`. |
| `lib/screens/tree_selector_screen.dart` | strings: «Деревья» → «Ветки», «Дерево "X"» → «Ветка "X"», etc. |
| `lib/screens/tree_view_screen.dart` (strings) | «Дерево» → «Ветка» в title, empty-state, error. |
| `lib/screens/tree_view_screen_sections.dart` | то же. |
| `lib/screens/relatives_screen.dart` (chip + headers) | «Дерево» → «Ветка» там, где не «Круг». |
| `lib/screens/profile_screen.dart` (helper-text) | «активное дерево» → «активная ветка». |
| `lib/screens/home_screen_sections.dart` | nav-tab label не меняется (это product-level identity), но pop-up texts да. |
| `lib/screens/auth_screen.dart` | onboarding tab «Дерево» → «Ветка»; «своё семейное дерево.» → «своё семейное древо.» |
| `lib/screens/chats_list_screen*.dart` | «Круг»/«Дерево» toggle сохраняется (это уже про friends vs family kind). |

### 3.3 Routing changes

Новые routes:
* `/profile/access` (Phase 3.4 access screen).
* `/branches/new` — alias на existing `/trees/new` (или migrate route целиком, см. §5.3).

В `app_router_guards.dart` / `app_shell_route_module.dart` — добавить.

### 3.4 State management

* Новый `GraphPersonAccessProvider` (или extension `TreeProvider`) —
  cache'ирует list-of-grants для current user'а, отдаёт reactive
  updates после revoke/grant.
* `IdentityConflictsCounts` уже в `tree_view_screen` state — extend
  на `relatives_screen` через provider.

---

## 4. Privacy language matrix (human-readable strings)

Per Артёмовой UX-Q A («connected-via-blood-graph» — техническое
слово, в UI должно быть человеческое):

| Backend value | UI label (RU) | UI explanation |
|---|---|---|
| `connected-via-blood-graph` | «Моим родственникам» | «Видят те, кто связан со мной через семейные связи до 4 колен» |
| `owner-only` | «Только мне» | «Никто кроме меня не видит эту карточку» |
| `public` | «Всем» | «Открыта в общем поиске» |
| `visibilityOverride: true` | «Запомнить мой выбор» | «По умолчанию приватность пересчитывается через 100 лет после смерти. С галочкой — твой выбор окончательный» |
| `auto-public` (deceased + >100 years, no override) | «Открыта как историческая запись» | «Прошло больше 100 лет с рождения — карточка автоматически стала публичной» |
| Sensitive (`field === "contacts"`) | «Видно только тебе» | «Контакты родственники не видят, даже если карточка открыта всем» |

| Backend grant scope | UI label (RU) |
|---|---|
| `edit` | «Может редактировать» |
| `merge-consent` | «Может объединять с другой карточкой» |
| `soft-delete` | «Может удалить» |

**Justification** для каждого: юзер не должен думать про hops. «4
колена» — concrete понятие («бабушки, прадеды, прапрадеды»).
«Запомнить мой выбор» — одна фраза вместо `visibilityOverride`.
«Историческая запись» — explanatory для auto-public.

**Не использовать** в UI: `visibility`, `override`, `hops`, `claim`,
`identity`, `graphPerson`. Эти слова остаются в backend +
internal docs.

---

## 5. Migration story: «Дерево» → «Ветка» в strings

Per RFC §3.4 «'Дерево' в UI меняется на 'Ветка' везде (строки,
иконки, навигация остаются на том же месте — менять только тексты)».

### 5.1 Места где «Дерево» → «Ветка»

| Файл | Текущий текст | Новый текст |
|---|---|---|
| [tree_selector_screen.dart:150](lib/screens/tree_selector_screen.dart:150) | «Деревья» (title) | «Ветки» |
| [tree_selector_screen.dart:770](lib/screens/tree_selector_screen.dart:770) | «Дерево "${tree.name}" исчезнет...» | «Ветка "${tree.name}" исчезнет...» |
| [tree_selector_screen.dart:825](lib/screens/tree_selector_screen.dart:825) | «Дерево удалено.» / «Вы покинули дерево.» | «Ветка удалена.» / «Вы вышли из ветки.» |
| [tree_view_screen.dart:828](lib/screens/tree_view_screen.dart:828) | toggle: «Дерево» / «Круг» | оставить (Дерево = семейная ветка с canvas-видом) — это product-identity, не migrate'им |
| [tree_view_screen_sections.dart:25,47](lib/screens/tree_view_screen_sections.dart:25) | «Дерево пока пустое», «Дерево сейчас недоступно» | «Ветка пока пустая», «Ветка сейчас недоступна» |
| [tree_view_screen_sections.dart:1010](lib/screens/tree_view_screen_sections.dart:1010) | «Дерево можно просматривать...» | «Ветку можно просматривать...» |
| [profile_screen.dart:177](lib/screens/profile_screen.dart:177) | «активное дерево» | «активная ветка» |
| [auth_screen.dart:1260](lib/screens/auth_screen.dart:1260) | «...семейное дерево.» | «...семейное древо.» (пасторально, продукт-identity) ИЛИ «...свою ветку семьи.» — обсудить (§7) |
| [home_screen_sections.dart:334](lib/screens/home_screen_sections.dart:334) | nav-label «Дерево» | оставить (nav-tab) — это identity главной фичи, юзер привык |

### 5.2 Где НЕ меняем

* **Nav-tab «Дерево»** на главной — это product identity. Артём
  сам RFC писал «иконки, навигация остаются». Tab остаётся
  «Дерево».
* **«Круг» / «Дерево» toggle** в chats-list / canvas — это уже
  family vs friends kind, не tree vs branch. Не trogа.
* **«Семейное древо» в onboarding splash** — поэтическое, оставить.

### 5.3 «branches» вместо «trees» в URL?

URL routes сейчас `/tree/view/:id`, `/trees/new`, etc. Migrate в
`/branch/view/:id` etc?

**Я рекомендую**: не трогать URL'ы в Phase 3.4. Backend `branches`
collection уже имеет `legacyTreeId === id`, routes `/v1/trees/:treeId/*`
работают. Меняем только UI strings; URL pattern остаётся для
backward-compat с deeplink'ами в already-shared invite-link'ах.

**Открытый вопрос**: одобрить как conservative или migrate
полностью? Re-evaluate в Phase 6 cleanup.

---

## 6. UX-considerations (Артёмовы Q A/B/C)

### 6.A: Privacy semantics в человеко-читаемом языке

**Решено** в §4 (Privacy language matrix). Юзер видит «Моим
родственникам», не «connected-via-blood-graph». Tooltip
explainer не появляется по умолчанию — это hover-info,
доступно через `[ ⓘ ]` иконку рядом с label'ом.

### 6.B: Branch wizard на мобильном — 3 шага или single-screen?

**Я рекомендую**: **single-screen с conditional sections**
(как в wireframe §2.1). Reasoning:

* На мобильном 3-step modal раздражает — каждый шаг полный
  экран, между transition'ами фрустрация.
* Defaults sensible: «Кровная семья от меня» selected,
  maxHops=5 prefilled, anchor-picker hidden до выбора rule
  type.
* One-tap «Создать с моей кровной семьёй» возможен — юзер
  заходит в wizard, печатает только название, жмёт Создать.
* На широких экранах (web / tablet) тот же layout масштабируется.

**Альтернатива**: 3-step wizard. **Отвергаю** для Phase 3.4 — UX
penalty не оправдан. Если post-deploy юзер report'ит «трудно
понять» — вернёмся.

### 6.C: Edit-grants management — где?

**Я рекомендую**: **profile editor → «Доступы»** (`/profile/access`).
Reasoning:

* Phase 4 «Связи родства» (Найти родство between users) тоже
  попадёт в profile, и юзер ищет privacy/connection settings
  естественно там.
* Settings-screen перегружен (devices, notifications, audio,
  account-deletion) — не место для feature-specific privacy
  controls.
* Quick-access из карточки человека через long-press / overflow
  menu — отдельный entry point.

---

## 7. Open questions

### Q1. URL migration `/tree/view` → `/branch/view`?

Conservative: keep. Migrate в Phase 6. **Рекомендую keep.**

### Q2. `auth_screen.dart` onboarding — «семейное дерево» оставить или migrate?

Это поэтический контекст, юзер видит первый раз. «семейное дерево»
звучит human, «семейная ветка» — техничнее. **Рекомендую keep**
и migrate только rendrant UI strings (где видно повседневно).

### Q3. Backend addendum для `GET /v1/me/issued-grants`?

Нужно для outgoing tab edit-grants screen. Альтернатива — N
round-trip'ов по `/v1/graph-persons/:id/grants` per graphPerson.
**Рекомендую**: добавить endpoint как тонкий список аналогично
`/v1/me/edit-grants` — это 20 строк store + route, естественная
симметрия. Делать в **same commit** Phase 3.4 backend portion
(до Flutter UI коммитов), либо в minor pre-3.4 backend commit.

### Q4. Branch wizard rule defaults для existing tree edit?

Создание — default «Кровная семья от меня». А что если юзер
edit'ит existing «manual» tree → branch? **Рекомендую**: edit-mode
показывает текущий type, **позволяет менять**, но warn'ит
«при смене типа автоматическая выборка перепишет manual list».
Это PATCH /v1/trees/:treeId с новым `includeRules` (эндпойнт уже
есть, расширить shape).

### Q5. Conflict badge в `relatives_screen` list-item — нужен per-row visual или summary?

Per-row (⚠ значок в list-item) добавляет visual noise если
конфликтов много (e.g. только-что после migration). **Рекомендую**:
per-row на конфликтных rows только; **plus** заголовочный «3
карточки требуют внимания» в screen header. Если уйдёт по
review — опускаем до header-only.

---

## 8. Out of scope Phase 3.4

* Extended-family network view (RFC Phase 4 «Найти родство» UI).
* Hard-delete background job (Phase 3.6 — server-side, отдельно).
* Public layer (Pushkin etc, RFC Phase 5).
* Onboarding wizard (RFC 6.5).
* «Найти родство» между двумя юзерами с consent (RFC Phase 4 cross-
  user feature).
* Owner-transfer-on-account-delete UI (RFC mention'd, deferred).

---

## 9. Tests strategy

### 9.1 Widget tests (новые)

* `branch_creation_wizard_test.dart` — render rule radio + slider
  visibility + submit payload.
* `visibility_toggle_section_test.dart` — render для owner / non-owner;
  3 radio toggle; override checkbox; save call.
* `access_screen_test.dart` — outgoing/incoming tabs render +
  empty states + revoke action.
* `relative_details_screen_test.dart` — расширить existing test'ом
  на conflict badge и sensitive section.
* `relatives_screen_test.dart` — расширить per-row ⚠ значок.

### 9.2 Service tests

* `custom_api_graph_person_service_test.dart` — mock все 6
  endpoints + verify request shape.

### 9.3 Integration

* End-to-end smoke в `tree_view_screen_test.dart` — full create
  branch wizard → tree-view loads с new rule type.

### 9.4 Migration smoke

* Все existing widget tests где «Дерево» в strings — adjust expectations
  с migration list (§5.1).

---

## 10. Risk summary

| Risk | Mitigation |
|---|---|
| `flutter analyze` не зелёный после migration strings | Coverage в каждом widget-test; pre-commit hook; manual smoke test runs. |
| Branch wizard на мобильном — single-screen перегружен | Sensible defaults + conditional sections. Если post-deploy juzer feedback'ит — back to 3-step. |
| Edit-grants screen empty for new users | Friendly empty state с explainer'ом «когда появится grant — увидишь его здесь». |
| Visibility toggle confusing for non-tech users | Clear language matrix (§4) + `[ⓘ]` info hover. |
| Sensitive contacts edit form breaks для non-owner viewers | Server already gates (Phase 3.2 PUT 403); UI скрывает «Изменить» button если viewer не owner. Defense in depth. |
| Conflict badge surface too noisy in list-item | Per-row + header-summary; if noisy after deploy, fall back to header-only (§Q5). |
| Hive box migration для `FamilyTree` если меняется shape | Phase 3.4 НЕ меняет `FamilyTree.dart` (`includeRules` живёт server-side, не парсится в Hive). Если local cache потребуется — отдельный Hive type bump в Phase 5/6. |

---

## 11. Что от Артёма

1. **Approve**, особенно UX-Q A/B/C decisions (§6) и open questions (§7).
2. **Approve backend addendum**:
   * `POST /v1/trees` принимает `includeRules` в payload.
   * `GET /v1/me/issued-grants` (новый endpoint).
   - Это minor backend extension. Сделать в одном commit ДО Flutter
     UI коммитов или в same Phase 3.4 commit?
3. **Migration strings story** (§5) — conservative («только rendant
   strings, URL'ы и onboarding не trogа») или aggressive
   (URL'ы тоже)?

После approve — implementation в порядке:
1. Backend addendum (если требуется): `includeRules` в `POST /trees`,
   `GET /v1/me/issued-grants`. Update tests.
2. Flutter services / models (capability mixin, DTO).
3. Migration strings (single commit «UI: «Дерево» → «Ветка»»).
4. Visibility toggle section.
5. Sensitive contacts section.
6. Branch creation wizard (расширение CreateTreeScreen).
7. Edit-grants screen + routing.
8. Conflict badge surface на не-canvas screens.
9. flutter analyze + flutter test (extended).
10. Diff на показ перед commit.

Никакого кода до approve.
