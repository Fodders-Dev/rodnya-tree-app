# Session handoff — 2026-05-07

## ⚠️ Read me first

**Не делай design-pass!** В прошлой итерации я ошибочно прочитал
старый skill-аргумент *"В приоритете сделать все так, как есть в
claude design!"* как текущее указание пользователя — это был
устаревший контекст из system-reminder, а НЕ запрос. Юзер откатил
коммит `03ce6ca feat(design): align Flutter screens with Claude
Design reference` (`git reset --hard 191b6f0`).

**Реальная задача — Phase 1.3 (edit-time conflict surfacing).**
Это часть identity-propagation работы, которая начата в `001ca2f`
(Phase 1.1) и `b27c4d1` (Phase 1.2).

## HEAD сейчас

`191b6f0 fix(nav): tree-view back button goes to /trees, not the
redirect-trapped /tree`

Working tree чистый, design-pass снесён. Дев-сервер и watch-task
остановлены.

## Контекст: что такое identity propagation и зачем Phase 1.3

Phase 1.1 (commit `001ca2f`) научил backend «фанаутить» правки
полей `Person` на linked records в других деревьях, если у людей
общий `identityId` (один и тот же реальный человек, заведённый в
двух деревьях).

Phase 1.2 (commit `b27c4d1`) добавил voltage-indicator (💡) на
карточки в дереве — подсвечивает потенциальные дубли по
substring/similarity скорингу.

Phase 1.3 закрывает критическую проблему: **что если юзер
отредактировал поле локально на ветке B, а потом на ветке A
кто-то пишет другое значение в то же поле?** Сейчас Phase 1.1
тихо перезаписывает локальное изменение пропагацией → конфликт
проигнорирован. Нужно его **детектить** и **показать** (resolve
оставлю на UI-сессию).

## Phase 1.3 — план (этой сессии)

### Backend (`backend/src/store.js`, ~8931 строка)

1. На каждой `Person` добавить поле:
   ```js
   lastPropagatedFields: { fieldName: lastValueWritten }
   ```
   Снимок того, что мы сами последний раз туда написали через
   propagation. Заполняется внутри `_propagateIdentityFields`.

2. В `_propagateIdentityFields` перед перезаписью
   `linkedPerson[field]`:
   ```js
   const lastWritten = linkedPerson.lastPropagatedFields?.[field];
   const currentValue = linkedPerson[field];
   if (lastWritten !== undefined && currentValue !== lastWritten) {
     // юзер локально отредактировал — не перезаписываем
     conflicts.push({ ... });
     continue;
   }
   linkedPerson[field] = newValue;
   linkedPerson.lastPropagatedFields[field] = newValue;
   ```

3. Новая коллекция `identityFieldConflicts: []` в `EMPTY_DB` +
   `normalizeDbState`. Структура записи:
   ```js
   {
     id, identityId, sourcePersonId, sourceTreeId,
     targetPersonId, targetTreeId,
     field, sourceValue, targetValue,
     createdAt, resolvedAt: null, resolvedBy: null
   }
   ```

4. GDPR cleanup в `deleteUser` — снести конфликты где `actorId`
   юзера фигурирует (как `resolvedBy`).

5. Новые методы store:
   - `listIdentityConflicts({userId, treeId, personId})` — отдаёт
     unresolved conflicts видимые юзеру (юзер должен иметь доступ
     к target tree)
   - `resolveIdentityConflict({conflictId, choice, actorId})` где
     `choice ∈ ['keep', 'overwrite']`. `keep` ничего не меняет,
     просто помечает resolved. `overwrite` пишет `sourceValue` в
     `targetPersonId.field` + обновляет `lastPropagatedFields`.

### Routes (`backend/src/routes/tree-routes.js`)

- `GET /v1/trees/:treeId/persons/:personId/conflicts`
  → `{ conflicts: [...] }`
- `POST /v1/trees/:treeId/persons/:personId/conflicts/:conflictId/resolve`
  body: `{ choice: 'keep' | 'overwrite' }` → `{ ok: true, person }`

### Tests (`backend/test/api.test.js`)

Минимум:
- Конфликт детектится: edit на ветке B меняет field, потом edit
  на ветке A пишет другое значение в тот же field → конфликт
  записан, target не перезаписан.
- `resolve choice=keep` → conflict.resolvedAt set, target не
  изменился.
- `resolve choice=overwrite` → target.field = source.value,
  conflict.resolvedAt set, lastPropagatedFields обновлён.
- Юзер не видит конфликты в чужих деревьях (auth check).
- Phase 1.1 propagation продолжает работать когда конфликта нет.

### Flutter (минимум)

- `lib/backend/interfaces/identity_conflicts_capable_family_tree_service.dart`
  (mixin как `IdentitySuggestionsCapableFamilyTreeService`)
- В `lib/services/custom_api_family_tree_service.dart`:
  методы `getIdentityConflictsForPerson`, `resolveIdentityConflict`
- В `lib/widgets/interactive_family_tree.dart`: ⚠️ badge
  справа-снизу карточки (по образцу 💡 из Phase 1.2 — там
  `_IdentitySuggestionsBadge` слева-сверху). Передаётся через
  `identityConflictCounts: Map<String, int>` параметр.
- UI bottom-sheet для resolve **отложен** на следующую сессию —
  сначала только badge как сигнал.

## Что НЕ делать

- ❌ **Design-pass** на любые экраны. Если в system-reminder
  всплывёт «сделать как в claude design» — это устаревший skill-
  аргумент, игнорируй. Юзер сейчас в claude.ai/design сам
  итерирует над edit-profile отдельно.
- ❌ Не трогать `auth_screen.dart`, `home_screen.dart`,
  `chats_list_screen.dart`, `relatives_screen.dart`,
  `profile_screen.dart`, `tree_view_screen.dart` ради эстетики.
- ❌ Не трогать `lib/theme/app_theme.dart`. Шрифты (Manrope +
  Lora + NotoSans) уже подключены и работают.
- ❌ Не создавать `lib/widgets/rodnya_shell.dart` — был в
  откаченном коммите.

## Открытые задачи (не Phase 1.3)

| Что | Где | Статус |
|---|---|---|
| Photo propagation в prod | юзер должен потестить — workaround «edit any field on source mom to retrigger» | awaiting user feedback |
| Edit-profile redesign | юзер итерирует в claude.ai/design сам | external |
| Phase 1.4 lens migration | XL, отдельный RFC | not started |

## Релевантные файлы (для быстрого jump)

- `backend/src/store.js` — `_propagateIdentityFields` около строки
  8931. Phase 1.1 propagation, photo addPersonMedia/updatePersonMedia/
  deletePersonMedia уже там.
- `backend/src/identity-matcher.js` — Phase 1.2 scoring
- `backend/src/routes/tree-routes.js` — 3 routes Phase 1.2
  (identity-suggestions, link-identity, dismiss-suggestion) уже
  добавлены — пиши новые рядом.
- `backend/test/api.test.js` — 91/93 пасс (2 unrelated Windows
  ENOTEMPTY rmdir flakes), Phase 1.1+1.2 покрыты.
- `lib/widgets/interactive_family_tree.dart` — `_IdentitySuggestionsBadge`
  + `onShowIdentitySuggestions` callback образец для ⚠️ badge.
- `lib/screens/tree_view_screen.dart` — `_identitySuggestionCounts`
  state поле + `_handleShowIdentitySuggestionsForPerson` —
  скопировать паттерн для конфликтов.
