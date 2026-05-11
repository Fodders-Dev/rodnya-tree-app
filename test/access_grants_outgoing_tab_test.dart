import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/family_tree_service_interface.dart';
import 'package:rodnya/backend/interfaces/graph_person_access_capable_family_tree_service.dart';
import 'package:rodnya/backend/models/edit_grant.dart';
import 'package:rodnya/backend/models/visibility_choice.dart';
import 'package:rodnya/widgets/access_grants_outgoing_tab.dart';

class _FakeAccessService
    implements
        FamilyTreeServiceInterface,
        GraphPersonAccessCapableFamilyTreeService {
  _FakeAccessService({this.issuedGrants = const <EditGrant>[]});

  List<EditGrant> issuedGrants;
  bool throwOnList = false;
  String? lastRevokedGrantId;
  bool throwOnRevoke = false;

  @override
  Future<List<EditGrant>> listMyIssuedGrants() async {
    if (throwOnList) throw StateError('boom');
    return List<EditGrant>.from(issuedGrants);
  }

  @override
  Future<EditGrant> revokeGraphPersonGrant({
    required String graphPersonId,
    required String grantId,
  }) async {
    if (throwOnRevoke) throw StateError('revoke-failed');
    lastRevokedGrantId = grantId;
    final updated = <EditGrant>[];
    for (final grant in issuedGrants) {
      if (grant.id == grantId) {
        updated.add(EditGrant(
          id: grant.id,
          graphPersonId: grant.graphPersonId,
          grantorUserId: grant.grantorUserId,
          granteeUserId: grant.granteeUserId,
          scope: grant.scope,
          grantedAt: grant.grantedAt,
          revokedAt: DateTime.now().toIso8601String(),
          graphPerson: grant.graphPerson,
          grantee: grant.grantee,
        ));
      } else {
        updated.add(grant);
      }
    }
    issuedGrants = updated;
    return updated.firstWhere((g) => g.id == grantId);
  }

  @override
  Future<List<EditGrant>> listMyEditGrants() async => const [];

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
  String? granteeName,
  String revokedAt = '',
}) {
  return EditGrant(
    id: id,
    graphPersonId: graphPersonId,
    grantorUserId: 'me',
    granteeUserId: 'grantee-$id',
    scope: scope,
    grantedAt: '2026-04-01T00:00:00Z',
    revokedAt: revokedAt.isEmpty ? null : revokedAt,
    graphPerson: graphPersonName == null
        ? null
        : GrantPreviewSubject(
            id: graphPersonId,
            displayName: graphPersonName,
          ),
    grantee: granteeName == null
        ? null
        : GrantPreviewSubject(
            id: 'grantee-$id',
            displayName: granteeName,
          ),
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  testWidgets('outgoing: empty state когда grants пуст', (tester) async {
    final service = _FakeAccessService();
    await tester.pumpWidget(
      _wrap(
        AccessGrantsOutgoingTab(
          accessService: service,
          viewerUserId: 'me',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Никому не выдано прав'), findsOneWidget);
    expect(find.byIcon(Icons.key_off_rounded), findsOneWidget);
  });

  testWidgets('outgoing: группирует grants по graphPersonId',
      (tester) async {
    final service = _FakeAccessService(issuedGrants: [
      _grant(
        id: 'g-1',
        graphPersonId: 'gp-1',
        scope: EditGrantScope.edit,
        graphPersonName: 'Иван Петров',
        granteeName: 'Алиса',
      ),
      _grant(
        id: 'g-2',
        graphPersonId: 'gp-1',
        scope: EditGrantScope.softDelete,
        graphPersonName: 'Иван Петров',
        granteeName: 'Боб',
      ),
      _grant(
        id: 'g-3',
        graphPersonId: 'gp-2',
        scope: EditGrantScope.mergeConsent,
        graphPersonName: 'Мария',
        granteeName: 'Карл',
      ),
    ]);
    await tester.pumpWidget(
      _wrap(
        AccessGrantsOutgoingTab(
          accessService: service,
          viewerUserId: 'me',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Двa header'а — по одному на graphPerson.
    expect(find.text('Иван Петров'), findsOneWidget);
    expect(find.text('Мария'), findsOneWidget);
    // Три grantee row'а.
    expect(find.text('Алиса'), findsOneWidget);
    expect(find.text('Боб'), findsOneWidget);
    expect(find.text('Карл'), findsOneWidget);
    // Соответствующие labels scope'ов.
    expect(find.text('Может редактировать'), findsOneWidget);
    expect(find.text('Может удалить'), findsOneWidget);
    expect(find.text('Может объединять с другой карточкой'), findsOneWidget);
  });

  testWidgets(
      'outgoing: tap close → confirm → revokeGraphPersonGrant вызывается',
      (tester) async {
    final service = _FakeAccessService(issuedGrants: [
      _grant(
        id: 'g-1',
        graphPersonId: 'gp-1',
        scope: EditGrantScope.edit,
        graphPersonName: 'Иван',
        granteeName: 'Алиса',
      ),
    ]);
    await tester.pumpWidget(
      _wrap(
        AccessGrantsOutgoingTab(
          accessService: service,
          viewerUserId: 'me',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Кликаем на close icon.
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    // Confirm dialog появился.
    expect(find.text('Отозвать доступ?'), findsOneWidget);
    expect(find.text('Отозвать'), findsOneWidget);

    // Подтверждаем.
    await tester.tap(find.text('Отозвать'));
    await tester.pumpAndSettle();

    expect(service.lastRevokedGrantId, 'g-1');
  });

  testWidgets('outgoing: cancel в confirm dialog НЕ вызывает revoke',
      (tester) async {
    final service = _FakeAccessService(issuedGrants: [
      _grant(
        id: 'g-1',
        graphPersonId: 'gp-1',
        scope: EditGrantScope.edit,
        graphPersonName: 'Иван',
        granteeName: 'Алиса',
      ),
    ]);
    await tester.pumpWidget(
      _wrap(
        AccessGrantsOutgoingTab(
          accessService: service,
          viewerUserId: 'me',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(service.lastRevokedGrantId, isNull);
  });

  testWidgets('outgoing: revoked grant показывается серым, без кнопки',
      (tester) async {
    final service = _FakeAccessService(issuedGrants: [
      _grant(
        id: 'g-revoked',
        graphPersonId: 'gp-1',
        scope: EditGrantScope.edit,
        graphPersonName: 'Иван',
        granteeName: 'Бывший',
        revokedAt: '2026-05-09T12:00:00Z',
      ),
    ]);
    await tester.pumpWidget(
      _wrap(
        AccessGrantsOutgoingTab(
          accessService: service,
          viewerUserId: 'me',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Нет кнопки revoke для уже отозванного grant'а.
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    // Есть «отозвано ... назад» подпись.
    expect(
      find.textContaining('Отозвано'),
      findsOneWidget,
    );
  });

  testWidgets('outgoing: error state с retry кнопкой', (tester) async {
    final service = _FakeAccessService()..throwOnList = true;
    await tester.pumpWidget(
      _wrap(
        AccessGrantsOutgoingTab(
          accessService: service,
          viewerUserId: 'me',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Не удалось загрузить доступы'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);

    // Retry — снимаем флаг и тапаем.
    service.throwOnList = false;
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();

    expect(find.text('Никому не выдано прав'), findsOneWidget);
  });
}
