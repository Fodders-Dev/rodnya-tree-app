# План доведения create/edit flows до минималистичного UI

## Цель
- привести `posts`, `stories`, `profile edit`, `settings` к тому же плотному и тихому стилю, что уже есть на `Home`, `Tree`, `Profile`, `Chats`
- убрать длинные подсказки и повторяющийся текст
- оставить только действия, статус и короткие labels

## Волна 1. Post composer
- заменить тяжёлый desktop split на более спокойную glass-композицию
- сократить helper copy
- сделать scope, branch selection и media actions компактными
- убрать отдельную карточку с длинными publishing hints

## Волна 2. Story composer
- сделать историю как быстрый composer, а не длинную форму
- сократить текст про `24 часа / v1 / highlights`
- уплотнить media picker, preview и type switch

## Волна 3. Profile edit
- убрать старую длинную форму без визуальной иерархии
- собрать экран в компактные glass sections:
  - avatar
  - имя и базовые поля
  - пол и дата рождения
  - локация и телефон
- сократить labels и helper text

## Волна 4. Settings
- уйти от длинного списка `ListTile + Divider + text`
- собрать настройки в компактные тематические sections
- сделать destructive actions отдельным блоком
- сократить описания до коротких статусов

## Проверка
- `dart format` на изменённых Dart-файлах
- `flutter analyze`
- профильные `flutter test`
- локальный browser smoke на web static bundle
