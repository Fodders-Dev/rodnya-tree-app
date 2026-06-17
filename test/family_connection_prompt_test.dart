import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/models/family_connection_prompt.dart';
import 'package:rodnya/models/family_person.dart';

void main() {
  FamilyPerson person({
    required String id,
    required String name,
    DateTime? birthDate,
    String? userId,
    String? relation,
    bool isAlive = true,
  }) {
    return FamilyPerson(
      id: id,
      treeId: 'tree-1',
      userId: userId,
      name: name,
      relation: relation,
      gender: Gender.unknown,
      birthDate: birthDate,
      isAlive: isAlive,
      deathDate: isAlive ? null : DateTime(2020),
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );
  }

  test('select prefers living older relatives and skips current user', () {
    final prompt = FamilyConnectionPromptSelector.select(
      currentUserId: 'me',
      now: DateTime(2026, 6, 18),
      relatives: [
        person(id: 'me-card', name: 'Кузнецов Артём', userId: 'me'),
        person(
          id: 'cousin',
          name: 'Кузнецов Иван',
          birthDate: DateTime(1998, 1, 1),
        ),
        person(
          id: 'grandmother',
          name: 'Петрова Анна',
          relation: 'бабушка',
          birthDate: DateTime(1945, 5, 3),
          userId: 'anna-user',
        ),
      ],
    );

    expect(prompt, isNotNull);
    expect(prompt!.person.id, 'grandmother');
    expect(prompt.title, 'Спросить, пока можно услышать');
    expect(prompt.ctaLabel, 'Спросить историю');
  });

  test('select returns null when there is no living relative to ask', () {
    final prompt = FamilyConnectionPromptSelector.select(
      currentUserId: 'me',
      relatives: [
        person(id: 'me-card', name: 'Кузнецов Артём', userId: 'me'),
        person(id: 'late', name: 'Петров Иван', isAlive: false),
      ],
    );

    expect(prompt, isNull);
  });
}
