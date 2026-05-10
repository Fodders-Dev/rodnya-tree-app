import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/family_tree_service_interface.dart';
import 'package:rodnya/backend/interfaces/graph_person_access_capable_family_tree_service.dart';
import 'package:rodnya/backend/models/edit_grant.dart';
import 'package:rodnya/backend/models/visibility_choice.dart';
import 'package:rodnya/widgets/visibility_toggle_section.dart';

class _CapableFakeService
    implements
        FamilyTreeServiceInterface,
        GraphPersonAccessCapableFamilyTreeService {
  _CapableFakeService({required this.snapshot});

  GraphPersonAccessSnapshot? snapshot;
  VisibilityChoice? lastSetChoice;
  bool clearOverrideCalled = false;

  @override
  Future<GraphPersonAccessSnapshot?> getGraphPersonAccessSnapshot({
    required String graphPersonId,
  }) async {
    return snapshot;
  }

  @override
  Future<GraphPersonVisibility> setGraphPersonVisibility({
    required String graphPersonId,
    required VisibilityChoice choice,
  }) async {
    lastSetChoice = choice;
    final next = GraphPersonVisibility(choice: choice, override: true);
    snapshot = GraphPersonAccessSnapshot(
      graphPersonId: snapshot!.graphPersonId,
      visibility: next,
      userId: snapshot!.userId,
      createdBy: snapshot!.createdBy,
    );
    return next;
  }

  @override
  Future<GraphPersonVisibility> clearGraphPersonVisibilityOverride({
    required String graphPersonId,
  }) async {
    clearOverrideCalled = true;
    final current = snapshot!.visibility;
    final next = current.copyWith(override: false);
    snapshot = GraphPersonAccessSnapshot(
      graphPersonId: snapshot!.graphPersonId,
      visibility: next,
      userId: snapshot!.userId,
      createdBy: snapshot!.createdBy,
    );
    return next;
  }

  // Не нужны для этих тестов; throw'ются если случайно вызвался.
  @override
  Future<EditGrant> addGraphPersonGrant({
    required String graphPersonId,
    required String granteeUserId,
    required EditGrantScope scope,
  }) async =>
      throw UnimplementedError();

  @override
  Future<EditGrant> revokeGraphPersonGrant({
    required String graphPersonId,
    required String grantId,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<EditGrant>> listGraphPersonGrants({
    required String graphPersonId,
  }) async =>
      const [];

  @override
  Future<List<EditGrant>> listMyEditGrants() async => const [];

  @override
  Future<List<EditGrant>> listMyIssuedGrants() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NonCapableFakeService implements FamilyTreeServiceInterface {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: child),
    ),
  );
}

void main() {
  testWidgets(
      'VisibilityToggleSection: owner видит section с radio (без отдельного checkbox)',
      (tester) async {
    final service = _CapableFakeService(
      snapshot: const GraphPersonAccessSnapshot(
        graphPersonId: 'gp-1',
        visibility: GraphPersonVisibility(
          choice: VisibilityChoice.connectedViaBloodGraph,
          override: false,
        ),
        userId: 'user-owner',
      ),
    );
    await tester.pumpWidget(
      _wrap(
        VisibilityToggleSection(
          graphPersonId: 'gp-1',
          viewerUserId: 'user-owner',
          familyTreeService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Кому видна эта карточка?'), findsOneWidget);
    expect(find.text('Моим родственникам'), findsOneWidget);
    expect(find.text('Только мне'), findsOneWidget);
    expect(find.text('Всем'), findsOneWidget);
    // Phase 3.4 chunk 2 (verify-1): отдельного override checkbox'а
    // нет. Default radio = «delegate to time», non-default = lock.
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets(
      'VisibilityToggleSection: non-owner НЕ видит section (privacy)',
      (tester) async {
    final service = _CapableFakeService(
      snapshot: const GraphPersonAccessSnapshot(
        graphPersonId: 'gp-1',
        visibility: GraphPersonVisibility(
          choice: VisibilityChoice.connectedViaBloodGraph,
          override: false,
        ),
        userId: 'user-owner',
      ),
    );
    await tester.pumpWidget(
      _wrap(
        VisibilityToggleSection(
          graphPersonId: 'gp-1',
          viewerUserId: 'user-stranger',
          familyTreeService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Section полностью скрыт.
    expect(find.text('Кому видна эта карточка?'), findsNothing);
    expect(find.text('Моим родственникам'), findsNothing);
  });

  testWidgets(
      'VisibilityToggleSection: backend без capability mixin → секция скрыта',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        VisibilityToggleSection(
          graphPersonId: 'gp-1',
          viewerUserId: 'user-owner',
          familyTreeService: _NonCapableFakeService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Кому видна эта карточка?'), findsNothing);
  });

  testWidgets(
      'VisibilityToggleSection: tap «Только мне» вызывает setGraphPersonVisibility (server auto-sets override=true)',
      (tester) async {
    final service = _CapableFakeService(
      snapshot: const GraphPersonAccessSnapshot(
        graphPersonId: 'gp-1',
        visibility: GraphPersonVisibility(
          choice: VisibilityChoice.connectedViaBloodGraph,
          override: false,
        ),
        userId: 'user-owner',
      ),
    );
    await tester.pumpWidget(
      _wrap(
        VisibilityToggleSection(
          graphPersonId: 'gp-1',
          viewerUserId: 'user-owner',
          familyTreeService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap на «Только мне» radio.
    await tester.tap(find.text('Только мне'));
    await tester.pumpAndSettle();

    expect(service.lastSetChoice, VisibilityChoice.ownerOnly);
    expect(service.clearOverrideCalled, isFalse);
  });

  testWidgets(
      'VisibilityToggleSection: tap default radio («Моим родственникам») вызывает clearOverride (delegate to time)',
      (tester) async {
    // Verify-1 (DECISIONS.md follow-up): default radio = clear
    // override, не setVisibility. Это сохраняет auto-resolve
    // semantics — приватность пересчитывается со временем.
    final service = _CapableFakeService(
      snapshot: const GraphPersonAccessSnapshot(
        graphPersonId: 'gp-1',
        visibility: GraphPersonVisibility(
          choice: VisibilityChoice.ownerOnly,
          override: true,
        ),
        userId: 'user-owner',
      ),
    );
    await tester.pumpWidget(
      _wrap(
        VisibilityToggleSection(
          graphPersonId: 'gp-1',
          viewerUserId: 'user-owner',
          familyTreeService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Моим родственникам'));
    await tester.pumpAndSettle();

    expect(service.clearOverrideCalled, isTrue);
    expect(service.lastSetChoice, isNull);
  });

  testWidgets(
      'VisibilityToggleSection: graphPerson without identityId — секция скрыта',
      (tester) async {
    // Пустой snapshot ↔ невозможно загрузить → service возвращает null.
    final service = _CapableFakeService(snapshot: null);
    await tester.pumpWidget(
      _wrap(
        VisibilityToggleSection(
          graphPersonId: '',
          viewerUserId: 'user-owner',
          familyTreeService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Кому видна эта карточка?'), findsNothing);
  });
}
