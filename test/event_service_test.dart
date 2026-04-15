import 'package:flutter_test/flutter_test.dart';
import 'package:lineage/backend/interfaces/family_tree_service_interface.dart';
import 'package:lineage/models/app_event.dart';
import 'package:lineage/models/family_person.dart';
import 'package:lineage/models/family_relation.dart';
import 'package:lineage/services/event_service.dart';

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
