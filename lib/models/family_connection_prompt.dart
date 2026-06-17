import 'family_person.dart';

class FamilyConnectionPrompt {
  const FamilyConnectionPrompt({
    required this.person,
    required this.title,
    required this.message,
    required this.ctaLabel,
  });

  final FamilyPerson person;
  final String title;
  final String message;
  final String ctaLabel;
}

class FamilyConnectionPromptSelector {
  static FamilyConnectionPrompt? select({
    required List<FamilyPerson> relatives,
    required String? currentUserId,
    DateTime? now,
  }) {
    final candidates = relatives
        .where((person) {
          if (person.id.isEmpty || person.id == FamilyPerson.empty.id) {
            return false;
          }
          if (person.name.trim().isEmpty) {
            return false;
          }
          if (currentUserId != null &&
              currentUserId.isNotEmpty &&
              person.userId == currentUserId) {
            return false;
          }
          return person.isAlive && person.deathDate == null;
        })
        .map(_FamilyConnectionCandidate.fromPerson)
        .toList();

    if (candidates.isEmpty) {
      return null;
    }

    candidates.sort(_compareCandidates);

    final strongestPriority = candidates.first.priority;
    final top = candidates
        .where((candidate) => candidate.priority == strongestPriority)
        .take(6)
        .toList(growable: false);
    final day = _dayIndex(now ?? DateTime.now());
    final selected = top[day % top.length].person;
    final shortName = _shortName(selected.name);

    return FamilyConnectionPrompt(
      person: selected,
      title: 'Спросить, пока можно услышать',
      message: 'Задайте $shortName один живой вопрос. Такие разговоры '
          'часто откладывают, а потом их уже не вернуть.',
      ctaLabel: 'Спросить историю',
    );
  }

  static int _compareCandidates(
    _FamilyConnectionCandidate a,
    _FamilyConnectionCandidate b,
  ) {
    final priority = b.priority.compareTo(a.priority);
    if (priority != 0) return priority;

    final age = b.age.compareTo(a.age);
    if (age != 0) return age;

    final connected = (b.person.userId != null ? 1 : 0)
        .compareTo(a.person.userId != null ? 1 : 0);
    if (connected != 0) return connected;

    return a.person.name.compareTo(b.person.name);
  }

  static int _dayIndex(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day)
          .difference(DateTime.utc(1970))
          .inDays
          .abs();

  static String _shortName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return parts[1];
    }
    return parts.first;
  }
}

class _FamilyConnectionCandidate {
  const _FamilyConnectionCandidate({
    required this.person,
    required this.age,
    required this.priority,
  });

  final FamilyPerson person;
  final int age;
  final int priority;

  factory _FamilyConnectionCandidate.fromPerson(FamilyPerson person) {
    final age = person.getAge() ?? -1;
    final relation = person.relation?.toLowerCase() ?? '';
    final name = person.name.toLowerCase();
    final priorityText = '$relation $name';
    final elder = age >= 60 ? 50 : 0;
    final parent = _containsAny(priorityText, const [
      'мама',
      'мать',
      'папа',
      'отец',
      'родител',
    ])
        ? 40
        : 0;
    final grandparent = _containsAny(priorityText, const [
      'бабуш',
      'дедуш',
      'дед ',
      'дед',
      'grand',
    ])
        ? 60
        : 0;
    final connected =
        person.userId != null && person.userId!.isNotEmpty ? 10 : 0;

    return _FamilyConnectionCandidate(
      person: person,
      age: age,
      priority: elder + parent + grandparent + connected,
    );
  }

  static bool _containsAny(String value, List<String> needles) {
    for (final needle in needles) {
      if (value.contains(needle)) return true;
    }
    return false;
  }
}
