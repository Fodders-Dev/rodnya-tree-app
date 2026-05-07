# Session handoff — 2026-05-07

## ⚠️ Read me first

**См. `docs/tree_model_overhaul_rfc.md`** — там полный план + промпт
для нового чата. Этот файл — короткий контекст-сводка, RFC — источник
истины.

## Что произошло в этой сессии

1. **Откат design-pass**. Я ошибочно прочитал старый skill-аргумент
   *"В приоритете сделать все так, как есть в claude design!"* как
   текущее указание пользователя — это был устаревший контекст из
   system-reminder, а НЕ запрос. Юзер откатил коммит `03ce6ca feat(design):
   align Flutter screens with Claude Design reference` (`git reset
   --hard 191b6f0`).

2. **Зафиксирован архитектурный план** на длинную перспективу —
   переход от «много частных деревьев» к «единый граф + ветки +
   per-branch лента». Это переворот модели данных. План записан в
   `docs/tree_model_overhaul_rfc.md` (полный, не сокращённый).

3. **Текущий HEAD:** `7ea0ca8 docs: session handoff` (на момент
   написания этого файла будет следующий коммит с RFC).

## Куда смотреть в новом чате

1. Прочитать `docs/tree_model_overhaul_rfc.md` целиком
2. Использовать промпт из секции «Промпт для нового чата» в RFC
3. Стартовать с Phase 1.3 — edit-time conflict surfacing (готовит почву для большой Phase 3)
4. После Phase 1.3 — обсудить open questions Phase 3 перед кодом

## Что НЕ делать (повторяю на случай если RFC не прочитан)

- ❌ **Design-pass** на любые экраны. Skill-аргумент в system-reminder про "claude design" устарел.
- ❌ Слово **«линза»** — отвергнуто, используем «ветка».
- ❌ **Live presence** на канвасе.
- ❌ **Push-уведомления** при матчинге.
- ❌ **Hard delete** узлов — только soft с 30-day undo.

## Открытые задачи (не Phase 1.3)

| Что | Статус |
|---|---|
| Photo propagation в prod (workaround «edit any field on source mom to retrigger») | awaiting user feedback |
| Edit-profile redesign | юзер сам в claude.ai/design |
| Phase 3 — Tree → Branch migration | XL, ждёт RFC-обсуждения |
| Phase 4 — Найти родство BFS | M, после Phase 3 |
| Phase 5 — Public layer of historical figures | S, opt-in |
