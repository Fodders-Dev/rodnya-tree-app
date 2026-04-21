# RuStore Moderator Notes - 1.0.2

## Build Summary
- Приложение: `Родня`
- Package: `com.ahjkuio.rodnya_family_app`
- Store flavor: `rustore`
- Publish type: `MANUAL`
- Основной backend: `https://api.rodnya-tree.ru`

## What To Check
- вход и навигация по приложению;
- семейное дерево;
- карточки родственников;
- личный чат и открытие медиа;
- публичные legal/support страницы;
- встроенное удаление аккаунта.

## Demo Scenario
- Основной demo dataset уже развёрнут на production API.
- Secure credentials и готовый moderator comment лежат локально в:
  - `.tmp/rustore_moderation_credentials_2026-04-12.md`
  - `.tmp/rustore_moderator_comment_1.0.2.txt`
- Эти файлы не коммитятся в git и должны передаваться в консоль публикации отдельно.

## Expected Review Flow
1. Войти под primary demo account.
2. Открыть дерево `Семья для модерации RuStore`.
3. Проверить, что дерево уже содержит готовые карточки людей и связи.
4. Открыть direct chat demo account и проверить текст + медиа-вложение.
5. При необходимости проверить public legal pages без авторизации:
   - `https://rodnya-tree.ru/#/privacy`
   - `https://rodnya-tree.ru/#/terms`
   - `https://rodnya-tree.ru/#/support`
   - `https://rodnya-tree.ru/#/account-deletion`

## Store/SDK Notes
- RuStore Review SDK используется только для запроса отзыва внутри приложения.
- RuStore Update SDK используется только для проверки доступности обновления.
- RuStore Push SDK используется для Android push path.
- Billing path не является blocker'ом этого релиза и в текущем `rustore` релизном контуре не считается основной пользовательской функцией.

## Support Notes
- Support email: `ahjkuio@gmail.com`
- Privacy/security contact: `ahjkuio@gmail.com`

## Operational Notes
- Production backend уже переведён на `postgres + s3`.
- Delete-account cascade проверен на production и удаляет как state, так и media objects.
