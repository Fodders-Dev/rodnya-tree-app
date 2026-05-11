# Identity Matcher — анализ

**Файл**: [backend/src/identity-matcher.js](backend/src/identity-matcher.js) (288 LOC)
**Точки вызова**:
- [backend/src/store.js:findCrossTreeSuggestionsForPerson](backend/src/store.js) → cross-tree 💡 indicator
- [backend/src/routes/tree-routes.js:213](backend/src/routes/tree-routes.js:213) (`GET /v1/trees/:treeId/duplicates`) → within-tree merge UX
- [backend/src/routes/tree-routes.js:245](backend/src/routes/tree-routes.js:245) (`GET .../:personId/identity-suggestions`) → cross-tree 💡

**Тесты**: [backend/test/identity-matcher.test.js](backend/test/identity-matcher.test.js) (77 LOC, 2 теста — ниже подробнее).

---

## 1. Сигналы, которые использует matcher

Все нормализации идут через локальные helpers:
- `normalizeName(value)` — strip, lowercase, **ё → е**, оставляет только `[a-zа-я0-9\s-]`, схлопывает пробелы.
- `normalizeNameTokens(value)` — токенизация через пробел, dedupe + сортировка по локали.
- `normalizeIsoDate(value)` — парсит в `YYYY-MM-DD` (ISO date).
- `normalizedBirthYear(value)` — первые 4 символа от `normalizeIsoDate`.
- `sameKnownValue(a, b)` — оба не пусты + строго равны после `String/trim`.

Главная функция: [`scorePersonPair(left, right)`](backend/src/identity-matcher.js:58).
Возвращает `{score, reasons}` или `null`.

| # | Сигнал | Условие | Прибавка к score | Кумулятивный «потолок» |
|---|---|---|---|---|
| 1a | **ФИО полностью совпадают** (после нормализации) | `leftName === rightName` | **+0.62** | основа |
| 1b | **Очень похожее имя** (token similarity ≥ 0.85, оба ≥ 2 токена) | `tokenSimilarity ≥ 0.85` | **+0.42** | альтернатива 1a |
| 1c | **Похожее имя** (token similarity ≥ 0.7, оба ≥ 2 токена) | `tokenSimilarity ≥ 0.7` | **+0.28** | альтернатива 1a/1b |
| 2a | **Полная дата рождения совпадает** | `leftDate === rightDate` (ISO) | **+0.28** | |
| 2b | **Только год рождения совпадает** (если 2a не сработал) | `leftYear === rightYear` | **+0.16** | альтернатива 2a |
| 3 | **Пол совпадает и не "unknown"** | `left.gender === right.gender ∧ ≠ "unknown"` | **+0.05** | |
| 4 | **Место рождения совпадает** (строгое равенство) | `sameKnownValue(left.birthPlace, right.birthPlace)` | **+0.06** | |
| 5 | **Дата смерти совпадает** | `sameKnownValue(left.deathDate, right.deathDate)` (ISO) | **+0.04** | |

**Hard gate (return null если не выполнен)**:
- `hasStrongNameSignal`: `leftName === rightName` ИЛИ `tokenSimilarity ≥ 0.85`. Слабое имя не пройдёт.
- `hasBiographicalSignal`: хоть одна из сторон должна иметь `birthDate` ИЛИ `birthPlace`. **Если у обоих нет ни даты ни места — никогда не предложим.**

**Минимальный score**: `0.78`. Если меньше — `null`.

**Cap**: `Math.min(0.99, score)`.

**Confidence**:
- `high` если `score ≥ 0.9`
- `medium` если `0.78 ≤ score < 0.9`
- `null` если `< 0.78`

---

## 2. Чего matcher НЕ использует

* **Имена родителей.** Сейчас при сравнении не учитывается граф. Два человека с одинаковым ФИО+датой и разными родителями получат full score (0.62 + 0.28 + 0.05 = 0.95).
* **Имена супругов.**
* **Девичью фамилию.** В person есть `maidenName`, но `scorePersonPair` его не читает.
* **Отчество отдельно.** Отчество ловится только как один из токенов в полном имени. «Иванов Иван Петрович» vs «Иванов Иван Сергеевич» — `tokenSimilarity = 2/3 = 0.67`, ниже 0.7 порога → НЕ предложит. Это даже скорее false-negative.
* **Транслитерация.** `Ivanov` vs `Иванов` — разные имена, similarity = 0.
* **Опечатки.** Levenshtein/edit-distance не используется. «Иваноф» vs «Иванов» — разные токены, similarity = 0.
* **Близкие даты.** «1970-03-12» vs «1970-03-13» = разные, никаких +0.16. Только полное совпадение либо только год.
* **Возрастные диапазоны для unknown-year.** Если нет birthDate с обеих сторон — не учитывается.

---

## 3. Threshold guideline

| Score range | Confidence | UX behaviour | False-positive risk |
|---|---|---|---|
| `≥ 0.95` | high | Безопасно показать как «определённо тот же человек, связать?» | Low |
| `0.90 – 0.95` | high | Inline suggestion с одной кнопкой confirm | Low-Medium |
| `0.78 – 0.90` | medium | Suggestion с явным «Похоже на … — проверьте» | Medium |
| `< 0.78` | (silent) | Не показывается совсем | — |

Полный score 0.99 (cap) достигается при: ФИО + дата + пол + место + дата смерти = 0.62+0.28+0.05+0.06+0.04 = 1.05 → cap 0.99.

«Минимальный для surface» — 0.78 — достигается, например, при:
- ФИО полностью + только год рождения + пол → 0.62 + 0.16 + 0.05 = 0.83 ✅
- ФИО полностью + место рождения → 0.62 + 0.06 = 0.68 ❌ (не пройдёт)
- Очень похожее имя + полная дата рождения → 0.42 + 0.28 = 0.70 ❌

Это значит: **полная дата рождения почти всегда требуется**, иначе короткое совпадение по имени отсекается.

---

## 4. False-positive risk score (моя оценка)

| Сценарий | Что matcher выдаст | False-positive risk |
|---|---|---|
| **Двое внуков названы в честь общего предка** (тёзки) с одинаковыми датами рождения, но разные люди | High confidence, score ≈ 0.95 | 🔴 **Высокий**. Без графовых сигналов (родители, супруги) их не отличить. |
| **Однофамильцы с одинаковым именем и близкой датой рождения** (распространённые ФИО типа «Иванов Иван Иванович», даты совпадают) | High confidence | 🔴 **Высокий**. В крупном дереве с 200+ людьми вероятен. |
| **Двое со сходным именем-отчеством, разные даты** | Не предложит (нет даты или год не совпадает → 0.62 → fail biography gate) | 🟢 **Низкий**. Hard gate спасает. |
| **Опечатки в именах**: «Кузнецов» vs «Кузнецова» (склонение), «Иванoв» (латинская O) | Не сработает strong-name gate (similarity ≠ 1.0, обе руки сторонние) | 🟢 **Низкий** (но есть false-negative — не предложит реального дубля). |
| **Маидeнская vs текущая фамилия одной и той же женщины** | Не предложит — `name` не совпадает, maidenName не используется | 🟢 **Низкий FP, но 🔴 false-negative**. |
| **Близкий родственник с тем же именем** (отец и сын, бабушка и внучка тёзки) | Если совпали даты — high confidence | 🔴 **Высокий**. Особенно для русских семей с традицией называть в честь. |
| **Группы людей с распространёнными именами** (Иванов Иван, Кузнецов Алексей, etc.) | High confidence при дате | 🟡 **Средний**. Хорошие даты обычно различают. |
| **Близнецы** | High confidence (имена и даты часто совпадают). Гендер только -0.05, спасает только если разные пол. | 🔴 **Высокий**. Особенно однополые. |

### Совокупная оценка для текущей реализации

* **Внутри одного дерева** (`/v1/trees/:treeId/duplicates`): **умеренный риск**. Данные вводит один человек, скорее всего не вводит одного и того же дважды без причины. Тесты покрывают main happy path и one negative.
* **Cross-tree** (`/v1/trees/.../:personId/identity-suggestions`): **высокий риск**. Два разных юзера могут описывать соседа/тёзку одинаково. Сейчас матчер scope'ится только в `accessibleTrees` юзера (его собственные деревья) — это ограничивает blast radius. **Но в Phase 4 расширенный cross-tree scope взорвёт false-positives**, если matcher не получит дополнительные сигналы.

Моя оценка: **6/10 на FP-риск** (где 0 — никаких false-positives, 10 — каждое второе предложение wrong). Текущий threshold 0.78 + biography gate спасают от тривиального шума, но «однополый тёзка с тем же годом» проходит на ура.

---

## 5. Что нужно расширить в Phase 2

PLAN.md Phase 2 говорит «усилить identity-matcher» — конкретный план:

### 5.1 Графовые сигналы (главный фикс FP)

Добавить:
- **Имя матери / имя отца** (если знаны) — `+0.10`/`+0.10`. Совпадение обоих — `+0.25` экстра-bonus.
- **Имя супруга** — `+0.08` (но осторожно: разводы/повторные браки).
- **Хотя бы один общий ребёнок** (через relations) — мощный сигнал, `+0.20`. Это исключает «отец и сын тёзки».

Без этого Phase 2 cross-tree расширение даст лавину FP.

### 5.2 Devichea (maiden name) на той стороне где он есть

```js
// если у одной стороны есть maidenName а другая называется этой
// maidenName'ом (или фамилия меняется через брак) — score +0.20
if (sameKnownValue(left.maidenName, right.lastName) ||
    sameKnownValue(right.maidenName, left.lastName)) {
  score += 0.20;
  reasons.push("Совпадает девичья фамилия");
}
```

Это покроет основной false-negative для женщин.

### 5.3 Возрастная толерантность для нечётких дат

Если у обоих есть `birthDate` но они разные:
- Разница в днях ≤ 7 → `+0.20` (опечатка: «3 марта» vs «13 марта»)
- Разница в днях ≤ 31 (один месяц) → `+0.10`
- Разница в годах = 0 (т.е. месяц/день не совпадают, но год тот же) → текущий `+0.16` сценарий уже покрыт.

### 5.4 Транслитерация имён

Для cross-tree — потенциально пользователь A пишет «Иванов», B пишет «Ivanov»:
- `transliterateRuToEn(name)` → дополнительный canonical форм для сравнения.
- Сейчас `normalizeName` дропает не-кириллицу `[^a-zа-я0-9\s-]`, потому скорее эти латинские варианты не сматчатся вообще.

Это L размер фичи. Можно отложить до Phase 4 (когда identity-граф расширяется до global поиска).

### 5.5 Privacy-aware accessibleTrees scope

Сейчас [findCrossTreeIdentitySuggestions](backend/src/identity-matcher.js:213) принимает `accessibleTrees: [...]` и сравнивает только в этом scope. PLAN.md Phase 2 говорит «расширить до identity-graph соседей с двусторонним consent».

Конкретная реализация:
```js
// 1) Стартовый scope — accessible trees caller'а (как сейчас).
// 2) Расширение: пройти identity-граф на 1 hop —
//    взять ВСЕ trees, в которых есть person с identityId
//    каждого из своего self-tree's persons.
// 3) Privacy-аут: каждый tree-owner на 1 hop должен
//    иметь `tree.allowDiscoveryFromConnected: true` или
//    `personIdentities.isPublicDiscoverable === true`.
```

### 5.6 Расширение тестов

Текущие 2 теста — слишком мало. Минимум для Phase 2:

1. **FP regression tests** (positive — НЕ должен предлагать):
   - Отец и сын-тёзка с разными датами рождения.
   - Близнецы, разный пол.
   - Однофамильцы с разными родителями (когда graph signal внедрён).
2. **TP confirmation tests**:
   - Та же ФИО+дата+место+пол → high confidence.
   - Совпадает только год + ФИО + место → medium.
   - Maiden name + текущая lastName → должен предложить.
3. **Threshold edge cases**:
   - Score = 0.7800001 → есть suggestion.
   - Score = 0.7799999 → нет.
4. **Biographical gate**:
   - Оба без birthDate и без birthPlace → null.
   - Один с birthDate, другой без → проходит.
5. **Cross-tree behavior**:
   - Source person в tree A, target в tree B — обе accessible — есть suggestion.
   - Target в tree C — caller не имеет access — silently skip.
   - Уже dismissed pair — silently skip.
   - Уже linked (одинаковый identityId) — silently skip.

### 5.7 Метрики и observability

* Добавить `scorePersonPair` логирование (sample rate 1%): score + reasons + результат (`linked`/`dismissed`/`silent_pass`/`silent_fail`).
* Дашборд: % suggestions, которые юзер `confirmed` vs `dismissed`. Если confirmation rate < 70% — threshold/scoring нужно tune.

---

## 6. Конкретные правки кода для Phase 2 (тезисы)

В файле [backend/src/identity-matcher.js](backend/src/identity-matcher.js):

1. **`scorePersonPair`** — добавить optional параметры `{leftRelatives, rightRelatives}` со списком `{role: 'mother'|'father'|'spouse'|'child', name, birthDate}` для графовых сигналов. Caller (store-side) передаст их через relations + persons.
2. **`findCrossTreeIdentitySuggestions`** — расширить signature: принимать `relationsByTreeId` для использования в графовых сигналах.
3. **Новый export `findIdentityCandidatesAcrossGraph`** для Phase 4-стиля поиска (consent-aware).

В store.js (около [`findCrossTreeSuggestionsForPerson`](backend/src/store.js)):
- Подкачивать relations + relative-persons для source person и target candidates перед scoring.
- Добавить `dismissedTargetPersonIds` уже есть — не трогать.

Тесты в [backend/test/identity-matcher.test.js](backend/test/identity-matcher.test.js) — обновить под новую сигнатуру + добавить кейсы из 5.6.

---

## 7. Резюме

* Текущий matcher — **простой, прозрачный и предсказуемый**. Работает на ФИО + датах + микро-сигналах.
* Threshold 0.78 + biographical gate отсекают **большинство** случайного шума.
* **Основной FP риск** — однополые тёзки с тем же годом рождения (распространено в семьях с династическими именами). Без графовых сигналов их не отличить.
* **Основной false-negative** — женщины через смену фамилии (нет работы с maidenName).
* В Phase 2 — добавить графовые сигналы и maidenName, иначе расширение cross-tree scope даст лавину FP.
* Тестов почти нет (2 кейса). Перед Phase 2 — расширить хотя бы до 10-12, иначе изменения в scoring пройдут незаметно.
