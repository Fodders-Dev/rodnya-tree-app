// MVP-1.1 «Спросить историю»: unit-тесты для чистого мёржа/дедупа кандидатов
// шага «Кого спросить» (STORY-REQUEST-MVP1-BRIEF.md §3.3 + семья extension,
// см. docs/connected-trees-refactor/CURRENT-PHASE.md). Сама функция —
// top-level `buildStoryAskTargets` в relative_details_screen_sections.dart
// (part of relative_details_screen.dart), тестируется без виджет-дерева и
// без сети. Существующий test/family_story_questions_sheet_test.dart
// проверяет лист с уже готовым списком askTargets — эта функция как раз
// строит тот список.
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/models/semya.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/screens/relative_details_screen.dart';

FamilyPerson _person({
  required String id,
  required String name,
  String? userId,
  Gender gender = Gender.unknown,
}) {
  final now = DateTime.fromMillisecondsSinceEpoch(0);
  return FamilyPerson(
    id: id,
    treeId: 't1',
    name: name,
    userId: userId,
    gender: gender,
    isAlive: true,
    createdAt: now,
    updatedAt: now,
  );
}

SemyaMembership _membership({
  required String userId,
  String? displayName,
  String? avatarUrl,
  SemyaRole role = SemyaRole.viewer,
}) {
  return SemyaMembership(
    id: 'm-$userId',
    semyaId: 'semya-1',
    userId: userId,
    role: role,
    joinedAt: '2026-01-01T00:00:00Z',
    displayName: displayName,
    avatarUrl: avatarUrl,
  );
}

void main() {
  group('buildStoryAskTargets', () {
    test('семья-участник без своей персоны в дереве попадает в список', () {
      final hero = _person(id: 'p-hero', name: 'Бабушка Лида', userId: 'u-hero');
      final targets = buildStoryAskTargets(
        heroPerson: hero,
        heroDisplayName: 'Лида',
        treePeople: const <FamilyPerson>[],
        semyaMembers: <SemyaMembership>[
          _membership(userId: 'u-aunt', displayName: 'Тётя Оля'),
        ],
        currentUserId: 'u-me',
      );

      expect(targets, hasLength(2)); // герой + тётя без персоны
      expect(targets.map((t) => t.userId), containsAll(<String>['u-hero', 'u-aunt']));
      final aunt = targets.firstWhere((t) => t.userId == 'u-aunt');
      expect(aunt.displayName, 'Тётя Оля');
      expect(aunt.isHero, isFalse);
    });

    test('дубли по userId не появляются (персона дерева = член семьи)', () {
      final hero = _person(id: 'p-hero', name: 'Бабушка Лида', userId: 'u-hero');
      final dualPerson = _person(id: 'p-dual', name: 'Дядя Женя', userId: 'u-dual');
      final targets = buildStoryAskTargets(
        heroPerson: hero,
        heroDisplayName: 'Лида',
        treePeople: <FamilyPerson>[dualPerson],
        semyaMembers: <SemyaMembership>[
          // тот же userId, что и dualPerson — не должен задвоиться
          _membership(userId: 'u-dual', displayName: 'Евгений'),
        ],
        currentUserId: 'u-me',
      );

      final dualMatches = targets.where((t) => t.userId == 'u-dual');
      expect(dualMatches, hasLength(1));
      // Побеждает запись из _treePeople (обрабатывается раньше семьи) —
      // имя персоны дерева, не имя из семьи.
      expect(dualMatches.single.displayName, 'Дядя Женя');
    });

    test('текущий пользователь исключён из списка (герой, персона, семья)', () {
      final hero = _person(id: 'p-hero', name: 'Я', userId: 'u-me');
      final selfPerson = _person(id: 'p-self', name: 'Я', userId: 'u-me');
      final targets = buildStoryAskTargets(
        heroPerson: hero,
        heroDisplayName: 'Я',
        treePeople: <FamilyPerson>[selfPerson],
        semyaMembers: <SemyaMembership>[
          _membership(userId: 'u-me', displayName: 'Я'),
        ],
        currentUserId: 'u-me',
      );

      expect(targets, isEmpty);
    });

    test('порядок: герой → персоны дерева → остальные члены семьи', () {
      final hero = _person(id: 'p-hero', name: 'Бабушка Лида', userId: 'u-hero');
      final treePerson = _person(id: 'p-2', name: 'Мама', userId: 'u-mama');
      final targets = buildStoryAskTargets(
        heroPerson: hero,
        heroDisplayName: 'Лида',
        treePeople: <FamilyPerson>[treePerson],
        semyaMembers: <SemyaMembership>[
          _membership(userId: 'u-aunt', displayName: 'Тётя Оля'),
        ],
        currentUserId: 'u-me',
      );

      expect(targets.map((t) => t.userId).toList(), <String>[
        'u-hero',
        'u-mama',
        'u-aunt',
      ]);
      expect(targets.first.isHero, isTrue);
    });

    test('семья-участник без displayName получает нейтральный фолбэк', () {
      final hero = _person(id: 'p-hero', name: 'Бабушка Лида', userId: 'u-hero');
      final targets = buildStoryAskTargets(
        heroPerson: hero,
        heroDisplayName: 'Лида',
        treePeople: const <FamilyPerson>[],
        semyaMembers: <SemyaMembership>[
          _membership(userId: 'u-nameless', displayName: null),
        ],
        currentUserId: 'u-me',
      );

      final nameless = targets.firstWhere((t) => t.userId == 'u-nameless');
      expect(nameless.displayName, isNotEmpty);
      expect(nameless.displayName, isNot('u-nameless')); // не «сырой» userId
    });

    test('пустые treePeople и semyaMembers — только герой (либо пусто)', () {
      final hero = _person(id: 'p-hero', name: 'Бабушка Лида', userId: null);
      final targets = buildStoryAskTargets(
        heroPerson: hero,
        heroDisplayName: 'Лида',
        treePeople: const <FamilyPerson>[],
        semyaMembers: const <SemyaMembership>[],
        currentUserId: 'u-me',
      );
      expect(targets, isEmpty);
    });
  });
}
