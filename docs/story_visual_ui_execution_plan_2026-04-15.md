# Story Visual UI Wave

## Goal
- Увести stories от text-first формы.
- Сделать stories ближе к `Instagram / Telegram`: превью-карточки, poster-like canvas, immersive viewer.
- Сократить copy до минимума и оставить акцент на медиа и ритме.

## Scope
- `lib/widgets/story_rail.dart`
- `lib/screens/create_story_screen.dart`
- `lib/screens/story_viewer_screen.dart`
- related story widget tests and web smoke

## Execution Plan
1. `StoryRail`
- Перевести stories из круглых аватаров в визуальные preview cards.
- Добавить более сильную hierarchy для unseen/new states.
- Упростить empty rail и сократить текст.

2. `CreateStoryScreen`
- Построить экран вокруг 9:16 preview stage.
- Текст, фото и видео должны собираться как story-canvas, а не как обычная форма.
- Тип, медиа-действия и подпись вынести в компактный control layer.

3. `StoryViewerScreen`
- Сделать full-bleed visual viewer с overlay-градентами.
- Поднять caption/status в нижний visual tray.
- Сохранить текущее поведение seen/delete/progress без изменения backend-контракта.

4. Verification
- `dart format`
- `flutter analyze`
- `flutter test` для `story_viewer`, `create_edit_flows`, и новых story widget tests
- web smoke на static bundle с локальной auth-сессией
