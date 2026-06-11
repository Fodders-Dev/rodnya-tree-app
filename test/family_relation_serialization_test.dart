// F2: сложные семьи — divorceDate и ex-типы переживают сериализацию
// туда-обратно (toMap → fromFirestore), как их гоняет API-слой.

import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/models/family_relation.dart';

class _FakeDoc {
  _FakeDoc(this.id, this._data);

  final String id;
  final Map<String, dynamic> _data;

  Map<String, dynamic> data() => _data;
}

void main() {
  test('relation с marriageDate и divorceDate сериализуется туда-обратно', () {
    final original = FamilyRelation(
      id: 'rel-1',
      treeId: 'tree-1',
      person1Id: 'p1',
      person2Id: 'p2',
      relation1to2: RelationType.ex_spouse,
      relation2to1: RelationType.ex_spouse,
      isConfirmed: true,
      createdAt: DateTime(2024, 1, 10),
      marriageDate: DateTime(1980, 6, 21),
      divorceDate: DateTime(1995, 3, 2),
    );

    final restored = FamilyRelation.fromFirestore(
      _FakeDoc('rel-1', original.toMap()),
    );

    expect(restored.relation1to2, RelationType.ex_spouse);
    expect(restored.relation2to1, RelationType.ex_spouse);
    expect(restored.marriageDate, DateTime(1980, 6, 21));
    expect(restored.divorceDate, DateTime(1995, 3, 2));
  });

  test('divorceDate отсутствует — остаётся null после round-trip', () {
    final original = FamilyRelation(
      id: 'rel-2',
      treeId: 'tree-1',
      person1Id: 'p1',
      person2Id: 'p2',
      relation1to2: RelationType.spouse,
      relation2to1: RelationType.spouse,
      isConfirmed: true,
      createdAt: DateTime(2024, 1, 10),
      marriageDate: DateTime(2001, 9, 8),
    );

    final restored = FamilyRelation.fromFirestore(
      _FakeDoc('rel-2', original.toMap()),
    );

    expect(restored.marriageDate, DateTime(2001, 9, 8));
    expect(restored.divorceDate, isNull);
  });

  test('stepchild/partner ex-типы парсятся из строк', () {
    expect(
      FamilyRelation.stringToRelationType('ex_spouse'),
      RelationType.ex_spouse,
    );
    expect(
      FamilyRelation.stringToRelationType('ex_partner'),
      RelationType.ex_partner,
    );
    expect(
      FamilyRelation.stringToRelationType('stepchild'),
      RelationType.stepchild,
    );
    expect(
      FamilyRelation.stringToRelationType('partner'),
      RelationType.partner,
    );
  });
}
