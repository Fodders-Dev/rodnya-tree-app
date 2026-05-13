// Phase 4 chunk 3 prep — synthetic perf fixture generator для
// InteractiveFamilyTree baseline. Не используется в production
// code; только test/perf/* benchmarks.
//
// Pattern: дерево в форме «vertical chain» (linear ancestor line)
// — каждый person — родитель следующего. Даёт N persons + N-1
// parent-child relations. Простая shape; render cost скейлится
// преимущественно с node count'ом, не с edge complexity.

import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/models/family_relation.dart';

/// Output shape для perf fixtures. Records требуют SDK 3.0+, у нас
/// pubspec ">=2.17.0" — поэтому plain class.
class PerfFixture {
  PerfFixture({required this.peopleData, required this.relations});

  final List<Map<String, dynamic>> peopleData;
  final List<FamilyRelation> relations;

  int get nodeCount => peopleData.length;
  int get edgeCount => relations.length;
}

/// Generates a linear chain of [count] FamilyPerson'ов с parent-
/// child relations между соседями. Возвращает peopleData (`List<Map>`
/// shape ожидаемый InteractiveFamilyTree.peopleData) + relations.
PerfFixture generateLinearChain({
  required int count,
  String treeId = 'perf-tree',
  DateTime? base,
}) {
  final baseDate = base ?? DateTime(2024, 1, 1);
  final people = <FamilyPerson>[];
  for (var i = 0; i < count; i++) {
    people.add(FamilyPerson(
      id: 'perf-p-$i',
      treeId: treeId,
      userId: i == 0 ? 'perf-user' : null,
      name: 'Person$i Familyname',
      gender: i.isEven ? Gender.male : Gender.female,
      isAlive: true,
      createdAt: baseDate,
      updatedAt: baseDate,
    ));
  }
  final relations = <FamilyRelation>[];
  for (var i = 0; i < count - 1; i++) {
    relations.add(FamilyRelation(
      id: 'perf-r-$i',
      treeId: treeId,
      person1Id: 'perf-p-${i + 1}', // parent
      person2Id: 'perf-p-$i', // child
      relation1to2: RelationType.parent,
      relation2to1: RelationType.child,
      isConfirmed: true,
      createdAt: baseDate,
    ));
  }
  return PerfFixture(
    peopleData: people
        .map((p) => <String, dynamic>{
              'person': p,
              'userProfile': null,
            })
        .toList(growable: false),
    relations: relations,
  );
}
