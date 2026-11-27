import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/circle_service_interface.dart';
import 'package:rodnya/backend/interfaces/family_tree_service_interface.dart';
import 'package:rodnya/models/audience_preset.dart';
import 'package:rodnya/models/circle.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/widgets/manage_circles_sheet.dart';

class _FakeCircleService implements CircleServiceInterface {
  _FakeCircleService(List<FamilyCircle> initialCircles)
      : circles = List<FamilyCircle>.from(initialCircles);

  final List<FamilyCircle> circles;
  final Map<String, List<String>> memberIdentityIdsByCircle = {};

  @override
  Future<List<FamilyCircle>> getCircles(String treeId) async =>
      List<FamilyCircle>.from(circles);

  @override
  Future<AudiencePresetsResponse> getAudiencePresets(String treeId) async =>
      AudiencePresetsResponse.empty;

  @override
  Future<FamilyCircle> createCircle({
    required String treeId,
    required String name,
    String? description,
  }) async {
    final created = FamilyCircle(
      id: 'circle-new-${circles.length + 1}',
      treeId: treeId,
      kind: FamilyCircleKind.custom,
      name: name,
      description: description,
      createdBy: 'viewer-1',
      isSystem: false,
      memberCount: 0,
      createdAt: DateTime(2026, 6, 1),
    );
    circles.add(created);
    return created;
  }

  @override
  Future<FamilyCircle> updateCircle({
    required String treeId,
    required String circleId,
    required String name,
    String? description,
  }) async {
    final idx = circles.indexWhere((c) => c.id == circleId);
    final old = circles[idx];
    final updated = FamilyCircle(
      id: old.id,
      treeId: old.treeId,
      kind: old.kind,
      name: name,
      description: description,
      createdBy: old.createdBy,
      isSystem: old.isSystem,
      memberCount: old.memberCount,
      createdAt: old.createdAt,
    );
    circles[idx] = updated;
    return updated;
  }

  @override
  Future<List<String>> getCircleMemberIdentityIds({
    required String treeId,
    required String circleId,
  }) async =>
      memberIdentityIdsByCircle[circleId] ?? const <String>[];

  @override
  Future<FamilyCircle> replaceCircleMembers({
    required String treeId,
    required String circleId,
    List<String> identityIds = const <String>[],
    List<String> personIds = const <String>[],
  }) async {
    memberIdentityIdsByCircle[circleId] = List<String>.from(identityIds);
    return circles.firstWhere((c) => c.id == circleId);
  }

  @override
  Future<void> deleteCircle({
    required String treeId,
    required String circleId,
  }) async {
    circles.removeWhere((c) => c.id == circleId);
  }
}

class _FakeTreeService implements FamilyTreeServiceInterface {
  @override
  Future<List<FamilyPerson>> getRelatives(String treeId) async => [
        FamilyPerson(
          id: 'person-1',
          treeId: treeId,
          identityId: 'identity-1',
          name: 'Мария Петрова',
          gender: Gender.female,
          isAlive: true,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<FamilyCircle> _seedCircles() => [
      FamilyCircle(
        id: 'all-1',
        treeId: 'tree-1',
        kind: FamilyCircleKind.allTree,
        name: 'Всё дерево',
        isSystem: true,
        memberCount: 3,
        createdAt: DateTime(2026, 1, 1),
      ),
      FamilyCircle(
        id: 'own-1',
        treeId: 'tree-1',
        kind: FamilyCircleKind.custom,
        name: 'Мой круг',
        createdBy: 'viewer-1',
        isSystem: false,
        memberCount: 1,
        createdAt: DateTime(2026, 1, 2),
      ),
      FamilyCircle(
        id: 'other-1',
        treeId: 'tree-1',
        kind: FamilyCircleKind.custom,
        name: 'Чужой круг',
        createdBy: 'other-user',
        isSystem: false,
        memberCount: 1,
        createdAt: DateTime(2026, 1, 3),
      ),
    ];

void main() {
  testWidgets(
      'ManageCirclesSheet gates edit/delete for non-owner creator and creates circles',
      (tester) async {
    final circleService = _FakeCircleService(_seedCircles());
    final treeService = _FakeTreeService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showManageCirclesSheet(
                context,
                treeId: 'tree-1',
                viewerUserId: 'viewer-1',
                canCreate: true,
                isOwner: false,
                circleService: circleService,
                treeService: treeService,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('circle-edit-own-1')), findsOneWidget);
    expect(find.byKey(const Key('circle-delete-own-1')), findsOneWidget);
    expect(find.byKey(const Key('circle-edit-other-1')), findsNothing);
    expect(find.byKey(const Key('circle-delete-other-1')), findsNothing);

    await tester.tap(find.byKey(const Key('circles-create-btn')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('circle-form-name')),
      'Бабушки',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('circle-form-save')));
    await tester.pumpAndSettle();

    // _openCreateDialog opens PersonMultiPickerSheet when relatives exist.
    expect(find.text('Участники «Бабушки»'), findsOneWidget);
    Navigator.of(tester.element(find.text('Участники «Бабушки»'))).pop();
    await tester.pumpAndSettle();

    expect(find.text('Бабушки'), findsOneWidget);
  });

  testWidgets('ManageCirclesSheet allows Semya owner to edit/delete any circle',
      (tester) async {
    final circleService = _FakeCircleService(_seedCircles());
    final treeService = _FakeTreeService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showManageCirclesSheet(
                context,
                treeId: 'tree-1',
                viewerUserId: 'owner-user',
                canCreate: true,
                isOwner: true,
                circleService: circleService,
                treeService: treeService,
              ),
              child: const Text('open-owner'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-owner'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('circle-edit-other-1')), findsOneWidget);
    expect(find.byKey(const Key('circle-delete-other-1')), findsOneWidget);
  });
}
