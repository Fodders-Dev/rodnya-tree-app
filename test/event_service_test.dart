import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/family_tree_service_interface.dart';
import 'package:rodnya/models/app_event.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/models/family_relation.dart';
import 'package:rodnya/services/event_service.dart';

void main() {
  test('EventService returns expanded family and calendar events', () async {
    final service = EventService(
      familyTreeService: _FakeFamilyTreeService(
        relatives: [
          FamilyPerson(
            id: 'person-birthday',
            treeId: 'tree-1',
            name: 'Иван Петров',
            gender: Gender.male,
            birthDate: DateTime(1990, 4, 3),
            isAlive: true,
            createdAt: DateTime(2024, 1, 1),
            updatedAt: DateTime(2024, 1, 1),
            details: FamilyPersonDetails(
              importantEvents: [
                Event(
                  title: 'Сбор семьи',
                  date: DateTime(2026, 4, 6),
                ),
              ],
            ),
          ),
          FamilyPerson(
            id: 'person-memory',
            treeId: 'tree-1',
            name: 'Мария Петрова',
            gender: Gender.female,
            deathDate: DateTime(2020, 4, 10),
            isAlive: false,
            createdAt: DateTime(2024, 1, 1),
            updatedAt: DateTime(2024, 1, 1),
          ),
          FamilyPerson(
            id: 'person-memorial',
            treeId: 'tree-1',
            name: 'Алексей Петров',
            gender: Gender.male,
            deathDate: DateTime(2026, 3, 24),
            isAlive: false,
            createdAt: DateTime(2024, 1, 1),
            updatedAt: DateTime(2024, 1, 1),
          ),
        ],
        relations: [
          FamilyRelation(
            id: 'relation-wedding',
            treeId: 'tree-1',
            person1Id: 'person-birthday',
            person2Id: 'person-memory',
            relation1to2: RelationType.spouse,
            relation2to1: RelationType.spouse,
            isConfirmed: true,
            createdAt: DateTime(2012, 4, 5),
            marriageDate: DateTime(2012, 4, 5),
          ),
          FamilyRelation(
            id: 'relation-divorced',
            treeId: 'tree-1',
            person1Id: 'person-memory',
            person2Id: 'person-memorial',
            relation1to2: RelationType.spouse,
            relation2to1: RelationType.spouse,
            isConfirmed: true,
            createdAt: DateTime(2015, 4, 2),
            marriageDate: DateTime(2015, 4, 2),
            divorceDate: DateTime(2025, 4, 2),
          ),
        ],
      ),
      nowProvider: () => DateTime(2026, 4, 1, 10),
    );

    final events = await service.getUpcomingEvents('tree-1', limit: 20);
    final eventTypes = events.map((event) => event.type).toSet();
    final titles = events.map((event) => event.title).toSet();

    expect(eventTypes, contains(AppEventType.birthday));
    expect(eventTypes, contains(AppEventType.weddingAnniversary));
    expect(eventTypes, contains(AppEventType.deathAnniversary));
    expect(eventTypes, contains(AppEventType.memorial9days));
    expect(eventTypes, contains(AppEventType.memorial40days));
    expect(eventTypes, contains(AppEventType.customFamilyEvent));
    expect(eventTypes, contains(AppEventType.russianHoliday));
    expect(eventTypes, contains(AppEventType.orthodoxHoliday));
    expect(titles, contains('Сбор семьи'));
    expect(titles, contains('Годовщина свадьбы'));
    expect(titles, contains('Пасха'));
    expect(titles, contains('Праздник Весны и Труда'));
    expect(
      events
          .where((event) => event.type == AppEventType.weddingAnniversary)
          .single
          .personName,
      'Иван Петров и Мария Петрова',
    );
  });

  test('EventService prioritizes family events on home feed limit', () async {
    final service = EventService(
      familyTreeService: _FakeFamilyTreeService(
        relatives: [
          FamilyPerson(
            id: 'person-birthday',
            treeId: 'tree-1',
            name: 'Иван Петров',
            gender: Gender.male,
            birthDate: DateTime(1990, 4, 3),
            isAlive: true,
            createdAt: DateTime(2024, 1, 1),
            updatedAt: DateTime(2024, 1, 1),
            details: FamilyPersonDetails(
              importantEvents: [
                Event(
                  title: 'Сбор семьи',
                  date: DateTime(2026, 4, 6),
                ),
              ],
            ),
          ),
          FamilyPerson(
            id: 'person-memory',
            treeId: 'tree-1',
            name: 'Мария Петрова',
            gender: Gender.female,
            deathDate: DateTime(2020, 4, 10),
            isAlive: false,
            createdAt: DateTime(2024, 1, 1),
            updatedAt: DateTime(2024, 1, 1),
          ),
        ],
        relations: [
          FamilyRelation(
            id: 'relation-wedding',
            treeId: 'tree-1',
            person1Id: 'person-birthday',
            person2Id: 'person-memory',
            relation1to2: RelationType.spouse,
            relation2to1: RelationType.spouse,
            isConfirmed: true,
            createdAt: DateTime(2012, 4, 5),
            marriageDate: DateTime(2012, 4, 5),
          ),
        ],
      ),
      nowProvider: () => DateTime(2026, 4, 1, 10),
    );

    final events = await service.getUpcomingEvents('tree-1', limit: 4);

    expect(events, hasLength(4));
    expect(
      events.every(
        (event) => event.type != AppEventType.russianHoliday,
      ),
      isTrue,
    );
    expect(
      events.every(
        (event) => event.type != AppEventType.orthodoxHoliday,
      ),
      isTrue,
    );
    expect(
      events.map((event) => event.categoryLabel).toSet(),
      containsAll(<String>['Родня', 'Семья', 'Память', 'Повод']),
    );
  });

  test(
    'EventService repeats custom family events when marked annual',
    () async {
      final service = EventService(
        familyTreeService: _FakeFamilyTreeService(
          relatives: [
            FamilyPerson(
              id: 'person-custom',
              treeId: 'tree-1',
              name: 'Ольга Петрова',
              gender: Gender.female,
              isAlive: true,
              createdAt: DateTime(2024, 1, 1),
              updatedAt: DateTime(2024, 1, 1),
              details: FamilyPersonDetails(
                importantEvents: [
                  Event(
                    title: 'День семьи',
                    date: DateTime(2020, 4, 10),
                    repeatsAnnually: true,
                  ),
                  Event(
                    title: 'Разовая встреча',
                    date: DateTime(2020, 4, 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        nowProvider: () => DateTime(2026, 4, 1, 10),
      );

      final events = await service.getUpcomingEvents('tree-1', limit: 10);

      expect(events.map((event) => event.title), contains('День семьи'));
      expect(
        events.map((event) => event.title),
        isNot(contains('Разовая встреча')),
      );
      expect(
        events.singleWhere((event) => event.title == 'День семьи').date,
        DateTime(2026, 4, 10),
      );
    },
  );

  // ── Calendar grid (A): getEventsForMonth ──

  test('getEventsForMonth returns past + future dates in the month, no cap',
      () async {
    final service = EventService(
      familyTreeService: _FakeFamilyTreeService(
        relatives: [
          FamilyPerson(
            id: 'p-early',
            treeId: 'tree-1',
            name: 'Ранний',
            gender: Gender.male,
            birthDate: DateTime(1990, 4, 3), // early April
            isAlive: true,
            createdAt: DateTime(2024, 1, 1),
            updatedAt: DateTime(2024, 1, 1),
          ),
          FamilyPerson(
            id: 'p-late',
            treeId: 'tree-1',
            name: 'Поздняя',
            gender: Gender.female,
            birthDate: DateTime(1985, 4, 25), // late April
            isAlive: true,
            createdAt: DateTime(2024, 1, 1),
            updatedAt: DateTime(2024, 1, 1),
          ),
        ],
      ),
      nowProvider: () => DateTime(2026, 4, 15, 10), // mid-April «now»
    );

    final april = await service.getEventsForMonth('tree-1', 2026, 4);

    // Year-anchored to 2026, no upcoming filter: the Apr-3 birthday
    // (already past on Apr 15) is present AT 2026-04-03 — getUpcomingEvents
    // would have pushed it to next year.
    expect(
      april.any((e) =>
          e.type == AppEventType.birthday && e.date == DateTime(2026, 4, 3)),
      isTrue,
    );
    expect(
      april.any((e) =>
          e.type == AppEventType.birthday && e.date == DateTime(2026, 4, 25)),
      isTrue,
    );
    // Every event lands in the requested month.
    expect(
      april.every((e) => e.date.year == 2026 && e.date.month == 4),
      isTrue,
    );
  });

  test('getEventsForMonth includes fixed holidays of the month', () async {
    final service = EventService(
      familyTreeService: _FakeFamilyTreeService(relatives: const []),
      nowProvider: () => DateTime(2026, 1, 1),
    );

    final may = await service.getEventsForMonth('tree-1', 2026, 5);
    final mayTitles = may.map((e) => e.title).toSet();
    expect(mayTitles, contains('Праздник Весны и Труда')); // 1 мая
    expect(mayTitles, contains('День Победы')); // 9 мая
    expect(may.every((e) => e.date.month == 5), isTrue);

    final feb = await service.getEventsForMonth('tree-1', 2026, 2);
    expect(
      feb.any((e) => e.title == 'День защитника Отечества'),
      isTrue,
    );
  });

  // ── More holidays (B) ──

  test('getEventsForMonth includes the added B holidays on their dates',
      () async {
    final service = EventService(
      familyTreeService: _FakeFamilyTreeService(relatives: const []),
      nowProvider: () => DateTime(2026, 1, 1),
    );

    Future<Set<String>> titlesOf(int month) async => (await service
            .getEventsForMonth('tree-1', 2026, month))
        .map((e) => e.title)
        .toSet();

    // Russian additions (fixed dates).
    expect(await titlesOf(1), contains('Старый Новый год')); // 14/1
    expect(await titlesOf(7), contains('День семьи, любви и верности')); // 8/7
    expect(await titlesOf(9), contains('День знаний')); // 1/9
    expect(await titlesOf(12), contains('День Конституции')); // 12/12

    // Orthodox additions — fixed.
    expect(await titlesOf(10), contains('Покров Пресвятой Богородицы')); // 14/10
    expect(await titlesOf(7), contains('День Петра и Павла')); // 12/7

    // Orthodox additions — movable (Orthodox Easter 2026 = 12 Apr →
    // Радоница 21 Apr, Масленица 22 Feb).
    expect(await titlesOf(4), contains('Радоница'));
    expect(await titlesOf(2), contains('Масленица'));
  });

  test('K3: народные праздники с плавающими датами попадают в свой месяц',
      () async {
    final service = EventService(
      familyTreeService: _FakeFamilyTreeService(relatives: const []),
    );

    // Проверки владельца: медработник 2026 = 21 июня (3-е вс),
    // шахтёр 2026 = 30 августа (последнее вс).
    final june = await service.getEventsForMonth('tree-1', 2026, 6);
    final medic = june.firstWhere(
      (event) => event.title == 'День медицинского работника',
    );
    expect(medic.date, DateTime(2026, 6, 21));
    expect(medic.type, AppEventType.folkHoliday);
    expect(medic.categoryLabel, 'Народный');
    expect(medic.description, isNotEmpty);

    final august = await service.getEventsForMonth('tree-1', 2026, 8);
    final miner = august.firstWhere(
      (event) => event.title == 'День шахтёра',
    );
    expect(miner.date, DateTime(2026, 8, 30));

    // Фиксированные народные: Татьянин день; «последнее вс» — День матери.
    final january = await service.getEventsForMonth('tree-1', 2026, 1);
    expect(
      january.any((event) =>
          event.title == 'Татьянин день' &&
          event.date == DateTime(2026, 1, 25)),
      isTrue,
    );
    final november = await service.getEventsForMonth('tree-1', 2026, 11);
    final mothersDay = november.firstWhere(
      (event) => event.title == 'День матери',
    );
    expect(mothersDay.date, DateTime(2026, 11, 29));
  });
}

class _FakeFamilyTreeService implements FamilyTreeServiceInterface {
  _FakeFamilyTreeService({
    required this.relatives,
    this.relations = const <FamilyRelation>[],
  });

  final List<FamilyPerson> relatives;
  final List<FamilyRelation> relations;

  @override
  Future<List<FamilyPerson>> getRelatives(String treeId) async => relatives;

  @override
  Future<List<FamilyRelation>> getRelations(String treeId) async => relations;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
