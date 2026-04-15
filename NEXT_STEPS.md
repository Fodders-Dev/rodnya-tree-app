# Current Next Steps

## Active release target

Довести `Родню` до удобного релизного Android/web состояния без big-bang rewrite и без поломки совместимости RuStore-обновления.

## Основной execution order

1. Закрепить phased rebrand в docs и agent-context, не меняя Android `applicationId`.
2. Закрыть `like` как server-driven flow с production-parity валидацией и нормальным rollback/refresh.
3. Ужать Home, Tree, Profile и Relatives до action-first UX без постоянных крупных helper-блоков.
4. Расширить events/calendar до реально полезного семейного сценария.
5. Доделать relative gallery, tree history и wiki-style collaboration.
6. Поверх стабильного core добавить `24h stories`.

## Что считать ближайшим done

- Бренд `Родня` отражён в основных docs и публичных UI-строках, кроме совместимых legacy identifiers.
- Основные экраны не тратят место на статичный текст без действий.
- Семейные события показывают не только дни рождения.
- Совместное редактирование дерева не теряет прозрачность изменений.
- Медиа-path на Android/web стабилен для постов, чатов, профилей и родственников.

## Опорные документы

- [docs/rodnya_release_plan_2026-04-13.md](docs/rodnya_release_plan_2026-04-13.md)
- [docs/mvp_web_audit_2026-04-09.md](docs/mvp_web_audit_2026-04-09.md)
- [docs/rustore_release_remaining_plan_2026-04-12.md](docs/rustore_release_remaining_plan_2026-04-12.md)
