# Architectural Decisions Log

Каждое архитектурное решение принятое в ходе рефакторинга
заносится сюда с датой и обоснованием. Формат:

```
## YYYY-MM-DD: краткое название
**Контекст**: какая ситуация
**Решение**: что выбрали
**Альтернативы**: что отклонили и почему
**Влияет на**: список файлов / API
**Принято**: имя decision-maker'а
```

---

## 2026-05-09: фундаментальное направление

**Контекст**: текущая модель «multi-tree per user + invite to
slot» не масштабируется когда у юзеров общие родственники, и
не позволяет приглашённому юзеру быть активным редактором.

**Решение**: переходим на **connected per-user trees** —
каждый юзер имеет одно дерево с собой как корнем, cross-tree
связи через `personIdentities`.

**Альтернативы**:
* Single shared global tree (FamilySearch model) — отвергнут:
  невозможен без community moderation, не подходит для
  закрытой семейной соцсети.
* Status quo с расширенными permissions (приглашённые могут
  редактировать BLOOD-RELATED slot'ы) — отвергнут как полумера,
  не решает дубликаты cross-tree.

**Влияет на**: всё. См. PLAN.md полностью.

**Принято**: Артём (user) + Claude.

---

## 2026-05-09: PLAN.md superseded by RFC

**Контекст**: Phase 0 audit (этой сессии) обнаружил, что в коде уже
существует параллельный unified-graph слой (`graphPersons` /
`graphRelations` / `branches` / `branchPersonViews`), реализующий
бо́льшую часть «целевой модели». Это исполнение отдельного RFC —
[`docs/tree_model_overhaul_rfc.md`](../tree_model_overhaul_rfc.md)
от 2026-05-07. Сделанные фазы по RFC: Phase 0 (person-picker),
Phase 1.1 (identity propagation), Phase 1.2 (silent 💡 matcher),
Phase 3.1 (schema graph), Phase 3.4 (post.branchIds[]), Phase 6.1
(BranchSwitcherChip).

PLAN.md (написан в этой же сессии до audit'а) описывает альтернативную
модель «single tree per user», которая НЕ совместима с RFC: PLAN.md
требует удалить multi-branch концепцию и BranchSwitcher, RFC — её
центральный UX-элемент.

**Решение**: PLAN.md superseded by RFC. RFC — единственный source
of truth. graphPersons + branches слой остаётся. Phase 0 / 1.1 /
1.2 / 3.1 / 3.4 / 6.1 правильны и не выпиливаются. Никаких
гибридов — чисто B (RFC выигрывает).

**Альтернативы**:
* **A: PLAN.md правильный, RFC выпиливаем** — отвергнут: пара
  месяцев работы по 1.1/1.2/1.3/3.1/3.4/6.1 не должна выкидываться
  из-за того что новый план был написан в неведении. И сама
  multi-branch модель отвечает на пользовательскую боль про
  ветки лучше, чем single-tree.
* **C: гибрид (граф под капотом, single-tree сверху)** — отвергнут:
  половинчато, BranchSwitcher уже в проде, одна модель должна
  победить, а не сосуществовать.

**Влияет на**: всё дальнейшее. PLAN.md помечен SUPERSEDED, фазы
ниже (Phase 1, 2, 3, ...) больше НЕ актуальны в его трактовке.
Источник правды — RFC.

**Принято**: Артём (user).

---

## 2026-05-09: memberIds — split into two distinct mechanisms

**Контекст**: в legacy модели `tree.memberIds[]` несёт два смешанных
смысла — (a) право редактировать дерево и (b) право видеть/писать
в ленту дерева. В RFC модели эти смыслы разъезжаются по разным
сущностям, поэтому простой drop невозможен.

**Решение**:
* (a) **Право редактировать** → owner-model на уровне `graphPerson`,
  не на уровне ветки. Реализуется в RFC Phase 3.2: автоматически
  на ≤2 hops по кровным рёбрам, модерация на 3+, hard-delete
  запрещён. Per-узел, не per-ветка.
* (b) **Право видеть ленту ветки** → отдельный механизм branch
  sharing. Дизайн — при подходе к Phase 3 (TREE → BRANCH миграция),
  отдельным design-pass'ом.

`memberIds` как поле в `branches` пока зеркалится из legacy
`tree.memberIds` (через `_syncTreeToBranch`), но не используется
для авторизации в новых endpoints. Будет полностью удалено когда
оба механизма (a)+(b) задеплоены и legacy переход завершён.

**Альтернативы**:
* «Просто drop memberIds» — отвергнут: теряем два разных смысла,
  ломаем существующие use case'ы.
* «Конвертировать в общий treeVisibility» — отвергнут как
  половинчатое решение: владелец-модель и share-модель — разные
  концепции, должны быть разные API.

**Влияет на**: backend Phase 3.2 (owner-model), новый branch-share
API в Phase 3.

**Принято**: Артём (user).

---

## 2026-05-09: Three legacy invite flows → two API + three user-facing actions

**Контекст**: сейчас три разных flow «привлечь юзера в моё дерево»:
1. `linkPersonToUser` через invite-link (`/v1/invitations/pending/process`)
2. `createTreeInvitation` (`/v1/trees/:treeId/invitations`)
3. `linkPersonsByIdentity` (`/v1/trees/:treeId/persons/:personId/link-identity`)

В RFC модели семантика «привязать userId к слоту» становится
частным случаем identity-claim (self-graphPerson юзера ←→ identity
link с targetPerson).

**Решение**:
* **Invite-link** → identity-claim: `linkPersonsByIdentity` API
  поверх self-graphPerson юзера и слота в чужой ветке.
* **Manual merge двух узлов** → тот же `linkPersonsByIdentity` API.
* **Share branch access** (read/post в чужой ленте без identity
  claim'а) → отдельный API. Либо новый, либо repurposed
  `createTreeInvitation` — решим на дизайне Phase 3.
* **`linkPersonToUser` → DEPRECATED.** Старые ссылки продолжают
  работать через legacy-redirect ([web/index.html](web/index.html)
  уже это делает) ~3 месяца после Phase 3, потом депрекейтятся.

**Альтернативы**:
* «Все три legacy flow жизнеспособны, оставляем» — отвергнут:
  семантика slot-link противоречит graph-модели и порождает
  дубли в graphPersons.
* «Резко выпиливаем всё legacy после Phase 3» — отвергнут:
  у юзеров на руках старые invite-ссылки, нужен переходный
  период.

**Влияет на**: Phase 3 (TREE → BRANCH миграция), endpoint
`/v1/invitations/pending/process` будет переписан на тонкий
shim над `linkPersonsByIdentity`.

**Принято**: Артём (user).

---

## 2026-05-09: Phase 3 заблокирован 4 нерешёнными вопросами

**Контекст**: Phase 3 (TREE → BRANCH миграция) — XL-фаза, требует
отдельного design-pass перед началом кода. RFC оставил 4 вопроса
открытыми; без ответов лезть в Phase 3 нельзя.

**Решение**: до старта Phase 3 нужно зафиксировать ответы на:
1. **Privacy escape hatch на graphPerson** — три уровня:
   `owner` / `connected` / `public`. Дефолт? Кто видит контактные
   данные живых людей? Как переключать без UI-катастрофы?
2. **Migration conflict strategy** — что wins при initial merge
   противоречивых данных? Самый недавний `updatedAt`? Самый
   полный record? Manual merge через mergeProposals?
3. **Owner-model thresholds** — реально ли «≤2 hops auto» работает
   в большой семье (200+ родственников)? Где граница между
   автоматическим propagation и moderation queue?
4. **BFS depth для blood-branch визуализации** — 4-5 hops, не 10?
   Где обрезаем visualization чтобы canvas не падал?

Phase 1.3 (edit-time conflict surfacing) **НЕ заблокирован** этими
вопросами. Закрываем 1.3 как описано в RFC, потом design-pass
по Q1-Q4, потом Phase 3.

**Принято**: Артём (user).

---
