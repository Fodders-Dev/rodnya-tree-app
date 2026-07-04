// UX-аудит 2026-07-04 P1: double-tap на канвасе = зум к точке
// (карты/Figma), а не «вписать всё». Fit остаётся на кнопке дока и
// клавише 0; на большом приближении double-tap возвращает обзор.
//
// Отдельный файл (не interactive_family_tree_test.dart), чтобы не
// смешиваться с независимым WIP в том файле.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/models/family_relation.dart';
import 'package:rodnya/widgets/interactive_family_tree.dart';

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

  // Stable references — didUpdateWidget не должен пересчитывать layout
  // между pump'ами (см. recenterOnPersonId-тест в основном файле).
  final stablePeopleData = [
    {'person': person('person-a', 'Анна', Gender.female), 'userProfile': null},
    {'person': person('person-b', 'Борис', Gender.male), 'userProfile': null},
  ];
  const stableRelations = <FamilyRelation>[];

  Widget buildTree() => MaterialApp(
        home: Scaffold(
          body: InteractiveFamilyTree(
            peopleData: stablePeopleData,
            relations: stableRelations,
            onPersonTap: (_) {},
            isEditMode: false,
            onAddRelativeTapWithType: (_, __) {},
            currentUserIsInTree: false,
            onAddSelfTapWithType: (_, __) async {},
            currentUserId: 'user-1',
          ),
        ),
      );

  Future<void> doubleTapAt(WidgetTester tester, Offset point) async {
    await tester.tapAt(point);
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(point);
    await tester.pumpAndSettle();
  }

  TransformationController controllerOf(WidgetTester tester) => tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer))
      .transformationController!;

  testWidgets('double-tap по пустому канвасу приближает ×1.5 к точке тапа',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    await tester.pumpWidget(buildTree());
    await tester.pumpAndSettle();

    final controller = controllerOf(tester);
    final scaleBefore = controller.value.getMaxScaleOnAxis();
    // Точка у края вьюпорта — гарантированно мимо карточек (2 человека
    // по центру) и с асимметрией для проверки «точка под пальцем».
    final viewerTopLeft =
        tester.getTopLeft(find.byType(InteractiveViewer).first);
    final tapPoint = viewerTopLeft + const Offset(40, 120);
    final sceneBefore = controller.toScene(tapPoint - viewerTopLeft);

    await doubleTapAt(tester, tapPoint);

    final scaleAfter = controller.value.getMaxScaleOnAxis();
    expect(
      scaleAfter,
      moreOrLessEquals(
        (scaleBefore * 1.5).clamp(0.08, 3.5),
        epsilon: 0.01,
      ),
      reason: 'double-tap должен приближать ×1.5 (с клампом 3.5)',
    );
    // Точка тапа осталась под пальцем: scene-координата той же
    // viewport-точки не изменилась.
    final sceneAfter = controller.toScene(tapPoint - viewerTopLeft);
    expect(sceneAfter.dx, moreOrLessEquals(sceneBefore.dx, epsilon: 0.5));
    expect(sceneAfter.dy, moreOrLessEquals(sceneBefore.dy, epsilon: 0.5));
  });

  testWidgets('на большом приближении (>2.2) double-tap возвращает обзор',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    await tester.pumpWidget(buildTree());
    await tester.pumpAndSettle();

    final controller = controllerOf(tester);
    final fitMatrix = controller.value.clone();

    // Ставим сильное приближение напрямую через контроллер.
    controller.value = Matrix4.identity()..scaleByDouble(3.0, 3.0, 1, 1);
    await tester.pump();

    final viewerTopLeft =
        tester.getTopLeft(find.byType(InteractiveViewer).first);
    await doubleTapAt(tester, viewerTopLeft + const Offset(40, 120));

    final scaleAfter = controller.value.getMaxScaleOnAxis();
    expect(
      scaleAfter,
      moreOrLessEquals(fitMatrix.getMaxScaleOnAxis(), epsilon: 0.01),
      reason: 'второй double-tap на приближении = fit-обзор',
    );
  });
}
