import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/models/family_relation.dart';
import 'package:rodnya/widgets/interactive_family_tree.dart';

// L (lost-user recovery): the «Вернуться к дереву» pill appears only when the
// tree has drifted fully off the viewport, and tapping it refits the tree.
// Lives in its own file — test/interactive_family_tree_test.dart is not touched.
void main() {
  FamilyPerson person(String id, String name, Gender gender) => FamilyPerson(
        id: id,
        treeId: 'tree-1',
        name: name,
        gender: gender,
        isAlive: true,
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      );

  testWidgets(
    'off-screen recovery pill appears when the tree is panned away and refits '
    'the tree on tap',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.reset());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InteractiveFamilyTree(
              peopleData: [
                {'person': person('person-a', 'Анна', Gender.female),
                    'userProfile': null},
                {'person': person('person-b', 'Борис', Gender.male),
                    'userProfile': null},
              ],
              relations: const <FamilyRelation>[],
              onPersonTap: (_) {},
              isEditMode: false,
              onAddRelativeTapWithType: (_, __) {},
              currentUserIsInTree: false,
              onAddSelfTapWithType: (_, __) async {},
              currentUserId: 'user-1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Auto-fit ran → tree is in view → no recovery pill.
      expect(find.text('Вернуться к дереву'), findsNothing);

      // Drive the tree fully off the viewport at minScale.
      final viewer =
          tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      viewer.transformationController!.value = Matrix4.identity()
        ..translateByDouble(-8000.0, -8000.0, 0.0, 1.0)
        ..scaleByDouble(0.08, 0.08, 1.0, 1.0);
      // Clear the ~220ms debounce.
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Вернуться к дереву'), findsOneWidget);

      // Tap it → the tree fits back into view and the pill dismisses.
      await tester.tap(find.text('Вернуться к дереву'));
      await tester.pumpAndSettle();

      final controller = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
      expect(
        controller.value.getMaxScaleOnAxis(),
        greaterThanOrEqualTo(0.55),
        reason: 'tapping the pill should fit the tree back to at least the '
            '0.55 fit floor',
      );
      expect(find.text('Вернуться к дереву'), findsNothing);
    },
  );
}
