import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/family_tree_service_interface.dart';
import 'package:rodnya/backend/interfaces/graph_person_access_capable_family_tree_service.dart';
import 'package:rodnya/backend/models/edit_grant.dart';
import 'package:rodnya/backend/models/visibility_choice.dart';
import 'package:rodnya/widgets/access_grants_incoming_tab.dart';

class _FakeAccessService
    implements
        FamilyTreeServiceInterface,
        GraphPersonAccessCapableFamilyTreeService {
  _FakeAccessService({this.editGrants = const <EditGrant>[]});

  List<EditGrant> editGrants;
  bool throwOnList = false;

  @override
  Future<List<EditGrant>> listMyEditGrants() async {
    if (throwOnList) throw StateError('boom');
    return List<EditGrant>.from(editGrants);
  }

  @override
  Future<List<EditGrant>> listMyIssuedGrants() async => const [];

  @override
  Future<GraphPersonAccessSnapshot?> getGraphPersonAccessSnapshot({
    required String graphPersonId,
  }) async =>
      null;

  @override
  Future<GraphPersonVisibility> setGraphPersonVisibility({
    required String graphPersonId,
    required VisibilityChoice choice,
  }) async =>
      throw UnimplementedError();

  @override
  Future<GraphPersonVisibility> clearGraphPersonVisibilityOverride({
    required String graphPersonId,
  }) async =>
      throw UnimplementedError();

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
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

EditGrant _grant({
  required String id,
  required String graphPersonId,
  required EditGrantScope scope,
  String? graphPersonName,
  String revokedAt = '',
}) {
  return EditGrant(
    id: id,
    graphPersonId: graphPersonId,
    grantorUserId: 'someone-else',
    granteeUserId: 'me',
    scope: scope,
    grantedAt: '2026-04-01T00:00:00Z',
    revokedAt: revokedAt.isEmpty ? null : revokedAt,
    graphPerson: graphPersonName == null
        ? null
        : GrantPreviewSubject(
            id: graphPersonId,
            displayName: graphPersonName,
          ),
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  testWidgets('incoming: empty state когда grants пуст', (tester) async {
    final service = _FakeAccessService();
    await tester.pumpWidget(
      _wrap(
        AccessGrantsIncomingTab(
          accessService: service,
          viewerUserId: 'me',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Вам не выдано прав на чужие карточки'), findsOneWidget);
  });

  testWidgets(
      'incoming: render cards с graphPerson preview + scope chips '
      '(БЕЗ revoke кнопки)', (tester) async {
    final service = _FakeAccessService(editGrants: [
      _grant(
        id: 'g-1',
        graphPersonId: 'gp-1',
        scope: EditGrantScope.edit,
        graphPersonName: 'Иван Петров',
      ),
      _grant(
        id: 'g-2',
        graphPersonId: 'gp-1',
        scope: EditGrantScope.mergeConsent,
        graphPersonName: 'Иван Петров',
      ),
    ]);
    await tester.pumpWidget(
      _wrap(
        AccessGrantsIncomingTab(
          accessService: service,
          viewerUserId: 'me',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Иван Петров'), findsOneWidget);
    // Чипы с scope labels (по одному на каждый grant).
    expect(find.widgetWithText(Chip, 'Может редактировать'), findsOneWidget);
    expect(
      find.widgetWithText(Chip, 'Может объединять с другой карточкой'),
      findsOneWidget,
    );
    // Phase 3.4 chunk 3: incoming — informational, без revoke.
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets('incoming: revoked grant показывается отдельной строкой',
      (tester) async {
    final service = _FakeAccessService(editGrants: [
      _grant(
        id: 'g-revoked',
        graphPersonId: 'gp-1',
        scope: EditGrantScope.edit,
        graphPersonName: 'Иван',
        revokedAt: '2026-05-09T12:00:00Z',
      ),
    ]);
    await tester.pumpWidget(
      _wrap(
        AccessGrantsIncomingTab(
          accessService: service,
          viewerUserId: 'me',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('отозван'), findsOneWidget);
  });

  testWidgets('incoming: группировка нескольких graphPerson\'ов',
      (tester) async {
    final service = _FakeAccessService(editGrants: [
      _grant(
        id: 'g-1',
        graphPersonId: 'gp-1',
        scope: EditGrantScope.edit,
        graphPersonName: 'Иван',
      ),
      _grant(
        id: 'g-2',
        graphPersonId: 'gp-2',
        scope: EditGrantScope.softDelete,
        graphPersonName: 'Мария',
      ),
    ]);
    await tester.pumpWidget(
      _wrap(
        AccessGrantsIncomingTab(
          accessService: service,
          viewerUserId: 'me',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Иван'), findsOneWidget);
    expect(find.text('Мария'), findsOneWidget);
    expect(find.byType(Card), findsNWidgets(2));
  });

  testWidgets('incoming: error state с retry', (tester) async {
    final service = _FakeAccessService()..throwOnList = true;
    await tester.pumpWidget(
      _wrap(
        AccessGrantsIncomingTab(
          accessService: service,
          viewerUserId: 'me',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Не удалось загрузить доступы'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
  });
}
