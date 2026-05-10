import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/auth_service_interface.dart';
import 'package:rodnya/backend/interfaces/family_tree_service_interface.dart';
import 'package:rodnya/backend/interfaces/graph_person_access_capable_family_tree_service.dart';
import 'package:rodnya/backend/models/edit_grant.dart';
import 'package:rodnya/backend/models/visibility_choice.dart';
import 'package:rodnya/screens/access_grants_screen.dart';

class _FakeAuth implements AuthServiceInterface {
  _FakeAuth({this.userId});

  final String? userId;

  @override
  String? get currentUserId => userId;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _CapableFakeService
    implements
        FamilyTreeServiceInterface,
        GraphPersonAccessCapableFamilyTreeService {
  _CapableFakeService();

  @override
  Future<List<EditGrant>> listMyIssuedGrants() async => const <EditGrant>[];

  @override
  Future<List<EditGrant>> listMyEditGrants() async => const <EditGrant>[];

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

class _NonCapableService implements FamilyTreeServiceInterface {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
      'AccessGrantsScreen: backend без capability — показывает unsupported state',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AccessGrantsScreen(
          familyTreeService: _NonCapableService(),
          authService: _FakeAuth(userId: 'me'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Управление доступами недоступно'), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
  });

  testWidgets('AccessGrantsScreen: viewer null — sign-in required state',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AccessGrantsScreen(
          familyTreeService: _CapableFakeService(),
          authService: _FakeAuth(userId: null),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Войдите, чтобы посмотреть доступы'), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
  });

  testWidgets(
      'AccessGrantsScreen: capable + auth — показывает оба таба',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AccessGrantsScreen(
          familyTreeService: _CapableFakeService(),
          authService: _FakeAuth(userId: 'me'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Кому я разрешил'), findsOneWidget);
    expect(find.text('Что мне разрешено'), findsOneWidget);
    expect(find.byType(TabBar), findsOneWidget);
  });

  testWidgets(
      'AccessGrantsScreen: переключение на incoming таб показывает empty state',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AccessGrantsScreen(
          familyTreeService: _CapableFakeService(),
          authService: _FakeAuth(userId: 'me'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Default tab = outgoing.
    expect(find.text('Никому не выдано прав'), findsOneWidget);

    // Tap incoming.
    await tester.tap(find.text('Что мне разрешено'));
    await tester.pumpAndSettle();

    expect(find.text('Вам не выдано прав на чужие карточки'), findsOneWidget);
  });
}
