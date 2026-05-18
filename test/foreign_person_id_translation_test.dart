// Phase 4 chunk 4b: id translation regression test.
//
// Bug surfaced при chunk 4b design analysis: chunk 3b/3c
// `_foreignPersonIds` returned slice.ownerMap.keys.toSet()
// (identity ids), но painter и card получают tree-scoped person.id.
// Set.contains(person.id) checked against identity ids → never
// matched → tint feature не activated в production.
//
// Fix: `_foreignPersonIds` translates identityIds → tree-scoped
// person.id через `_treePeople` mapping. Test verifies translation
// happens correctly при typical production data shape.
//
// Тест exercise'ит `FamilyTreeNodeCard.isForeignNode` rendering
// (proxy для `_isPersonForeign(person.id)` → branches на card
// surfaceColor). After fix, isForeignNode=true triggers tint;
// before fix, it never did.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/models/extended_network_slice.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/models/family_relation.dart';
import 'package:rodnya/providers/extended_network_controller.dart';
import 'package:rodnya/theme/app_theme.dart';
import 'package:rodnya/widgets/family_tree_node_card.dart';
import 'package:rodnya/widgets/interactive_family_tree.dart';

/// Reads `isForeignNode` property from rendered FamilyTreeNodeCard
/// matching given key. Behavioral verification — production-shape
/// check that id translation in `_foreignPersonIds` works.
bool _readIsForeignNode(WidgetTester tester, String personId) {
  final cardFinder = find.byKey(ValueKey<String>('tree-node-$personId'));
  if (cardFinder.evaluate().isEmpty) {
    throw StateError(
      'FamilyTreeNodeCard for $personId not found in widget tree',
    );
  }
  final card = tester.widget<FamilyTreeNodeCard>(cardFinder);
  return card.isForeignNode;
}

FamilyPerson _person({
  required String id,
  required String identityId,
  String name = 'Person',
}) {
  return FamilyPerson(
    id: id,
    treeId: 'tree-1',
    name: name,
    identityId: identityId,
    gender: Gender.male,
    isAlive: true,
    createdAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 1, 1),
  );
}

ExtendedNetworkSlice _sliceWithForeignIdentityIds(
  Set<String> foreignIdentityIds,
) {
  return ExtendedNetworkSlice(
    graphPersons: foreignIdentityIds
        .map((iid) => ExtendedNetworkPerson(
              id: iid,
              name: 'Foreign',
              gender: 'male',
              birthDate: null,
              deathDate: null,
              photoUrl: null,
              isAlive: true,
              hopDistance: 2,
            ))
        .toList(),
    graphRelations: const <ExtendedNetworkRelation>[],
    branchMembership: const <String, List<String>>{},
    ownerMap: {
      for (final iid in foreignIdentityIds)
        iid: const ExtendedNetworkOwnerInfo(
          userId: 'u-other',
          displayName: 'Other',
          photoUrl: null,
        ),
    },
    viewerSelfGraphPersonId: 'me-identity',
    stats: ExtendedNetworkStats(
      totalCount: foreignIdentityIds.length,
      myCount: 0,
      extendedCount: foreignIdentityIds.length,
      anonymousCount: 0,
      maxHopsReached: false,
      capReached: false,
    ),
  );
}

void main() {
  testWidgets(
      'foreign tint activates когда person.identityId matches '
      'foreign identityId (bug fix: id translation)', (tester) async {
    // Production-shape data:
    //   tree person с legacy id 'p-1' и identityId 'identity-x'.
    //   slice foreignIdentityIds = {'identity-x'} (foreign owner).
    //   Card должна получить isForeignNode=true → cool tint.
    final ownPerson = _person(
      id: 'p-1',
      identityId: 'identity-x', // foreign per slice
      name: 'Иван Foreign',
    );
    final ownPersonMine = _person(
      id: 'p-2',
      identityId: 'identity-me',
      name: 'Степа Mine',
    );
    final slice = _sliceWithForeignIdentityIds({'identity-x'});

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const <ThemeExtension<dynamic>>[
            RodnyaDesignTokens.light,
          ],
        ),
        home: Scaffold(
          body: InteractiveFamilyTree(
            peopleData: [
              {'person': ownPerson, 'userProfile': null},
              {'person': ownPersonMine, 'userProfile': null},
            ],
            relations: <FamilyRelation>[
              FamilyRelation(
                id: 'r-1',
                treeId: 'tree-1',
                person1Id: ownPersonMine.id,
                person2Id: ownPerson.id,
                relation1to2: RelationType.parent,
                relation2to1: RelationType.child,
                isConfirmed: true,
                createdAt: DateTime(2024, 1, 1),
              ),
            ],
            onPersonTap: (_) {},
            onAddRelativeTapWithType: (_, __) {},
            currentUserIsInTree: true,
            onAddSelfTapWithType: (_, __) async {},
            currentUserId: 'me',
            viewMode: ExtendedNetworkMode.extended,
            networkSlice: slice,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Behavioral verification — read rendered card props.
    expect(
      _readIsForeignNode(tester, 'p-1'),
      isTrue,
      reason: 'p-1 (identity-x foreign) → tinted',
    );
    expect(
      _readIsForeignNode(tester, 'p-2'),
      isFalse,
      reason: 'p-2 (identity-me NOT foreign) → not tinted',
    );
  });

  testWidgets(
      'empty foreign set когда slice ownerMap empty (no foreign persons)',
      (tester) async {
    final slice = _sliceWithForeignIdentityIds(<String>{});
    final ownPerson = _person(
      id: 'p-1',
      identityId: 'identity-x',
      name: 'Person',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InteractiveFamilyTree(
            peopleData: [
              {'person': ownPerson, 'userProfile': null},
            ],
            relations: const <FamilyRelation>[],
            onPersonTap: (_) {},
            onAddRelativeTapWithType: (_, __) {},
            currentUserIsInTree: true,
            onAddSelfTapWithType: (_, __) async {},
            currentUserId: 'me',
            viewMode: ExtendedNetworkMode.extended,
            networkSlice: slice,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_readIsForeignNode(tester, 'p-1'), isFalse);
  });
}
