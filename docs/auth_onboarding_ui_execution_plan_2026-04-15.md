# Auth / Onboarding UI Wave

## Visual Thesis
- Спокойный входной слой без маркетинговой простыни: стекло, крупные формы, короткие статусы, минимум слов.
- Первый экран должен ощущаться как мессенджер/соцсеть: быстрый вход, узнаваемые иконки, чистая иерархия.
- Stories в следующем проходе довести до визуального сценария `Instagram/Telegram`, а не текстового composer-first surface.

## Scope
- `lib/screens/auth_screen.dart`
- `lib/screens/complete_profile_screen.dart`
- `lib/screens/password_reset_screen.dart`
- `lib/screens/tree_selector_screen.dart`
- `lib/screens/settings_screen.dart`
- `lib/screens/profile_edit_screen.dart`
- reusable dialogs / pickers for flow surfaces

## Execution Plan
1. Пересобрать `AuthScreen`
- Укоротить hero и убрать описательные карточки.
- Сделать poster-like левую сцену на desktop и компактный стеклянный form panel.
- Оставить только ключевые states: `Вход`, `Регистрация`, `Google`, `Пароль`, `Правила`.

2. Пересобрать `CompleteProfileScreen`
- Разбить на короткие секции `Основное`, `Контакты`, `Личное`.
- Свернуть длинные labels и hint text.
- Сделать выбор страны и даты частью того же visual language.

3. Привести `PasswordResetScreen` к тому же паттерну
- Один стеклянный блок.
- Короткая инструкция.
- Чистое success/error state без красных системных панелей.

4. Упростить `TreeSelectorScreen`
- Убрать explanatory blocks и card-like перегруз.
- Оставить список деревьев, текущий выбор и быстрые действия.
- Сделать empty/error states короче и легче.

5. Добить reusable overlays
- Общий confirm dialog для destructive actions.
- Общий themed date picker для profile/edit flows.
- Протянуть reusable overlay style туда, где он уже нужен сейчас.

## Verification
- `dart format` на изменённых файлах
- `flutter analyze`
- widget tests: `auth`, `complete_profile`, `tree_selector`, новый flow-overlays/create-edit coverage при необходимости
- web smoke: `login`, `password reset`, `tree selector` в static E2E bundle
