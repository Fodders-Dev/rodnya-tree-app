import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:rodnya/backend/interfaces/family_tree_service_interface.dart';
import 'package:rodnya/backend/interfaces/kinship_check_capable_family_tree_service.dart';
import 'package:rodnya/backend/interfaces/profile_service_interface.dart';
import 'package:rodnya/backend/models/kinship_check.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/models/family_relation.dart';
import 'package:rodnya/models/user_profile.dart';
import 'package:rodnya/screens/discover_relatives/discover_relatives_screen.dart';

class _FakeKinshipService
    implements
        FamilyTreeServiceInterface,
        KinshipCheckCapableFamilyTreeService {
  final List<Map<String, dynamic>> sentRequests = <Map<String, dynamic>>[];

  @override
  Future<List<FamilyPerson>> getRelatives(String treeId) async =>
      const <FamilyPerson>[];

  @override
  Future<void> sendRelationRequest({
    required String treeId,
    required String recipientId,
    required RelationType relationType,
    String? message,
  }) async {
    sentRequests.add({
      'treeId': treeId,
      'recipientId': recipientId,
      'relationType': relationType,
    });
  }

  @override
  Future<List<KinshipCheck>> listIssuedKinshipChecks({
    KinshipCheckStatus? status,
  }) async =>
      const [];

  @override
  Future<List<KinshipCheck>> listReceivedKinshipChecks({
    KinshipCheckStatus? status,
  }) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfileService implements ProfileServiceInterface {
  _FakeProfileService({this.results = const <UserProfile>[]});

  final List<UserProfile> results;
  String? lastQuery;

  @override
  Future<List<UserProfile>> searchUsers(String query, {int limit = 10}) async {
    lastQuery = query;
    return results;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

UserProfile _profile(String id, {required String name, String? username}) {
  return UserProfile(
    id: id,
    email: '$id@example.com',
    displayName: name,
    username: username ?? '',
    phoneNumber: '',
    createdAt: DateTime(2026, 4, 16),
  );
}

GoRouter _router() => GoRouter(
      initialLocation: '/discover',
      routes: [
        GoRoute(
          path: '/discover',
          builder: (context, state) => const DiscoverRelativesScreen(),
        ),
        GoRoute(
          // «Родные» — своя вкладка без ?view=: режимов внутри больше нет.
          path: '/family',
          builder: (context, state) => const Scaffold(
            body: Text('family-tab'),
          ),
        ),
      ],
    );

void main() {
  final getIt = GetIt.instance;

  setUp(() async {
    await getIt.reset();
    getIt.registerSingleton<FamilyTreeServiceInterface>(
      _FakeKinshipService(),
    );
    getIt.registerSingleton<ProfileServiceInterface>(
      _FakeProfileService(),
    );
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('объясняет поиск и ведёт к списку семьи', (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
    await tester.pumpAndSettle();

    expect(find.text('Как это работает'), findsOneWidget);
    expect(find.text('Открыть семью'), findsOneWidget);

    await tester.tap(find.text('Открыть семью'));
    await tester.pumpAndSettle();

    expect(find.text('family-tab'), findsOneWidget);
  });

  testWidgets('пустой поиск предлагает добавить человека в дерево',
      (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Несуществующий человек');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('Добавить человека в дерево'), findsOneWidget);
  });

  testWidgets(
    'density chunk 25: search result row is ~56dp, no card-in-card wrapper',
    (tester) async {
      // Regression guard for chunk 25. Before: each result was a
      // Card(elevation:0)+ListTile — a rounded card sitting on the plain
      // page background (~72dp incl. Card's own margin). After: a flat
      // 56dp row with a hairline divider, matching the rest of this
      // chunk's list rows (invitations, семья members).
      await getIt.unregister<ProfileServiceInterface>();
      getIt.registerSingleton<ProfileServiceInterface>(
        _FakeProfileService(
          results: [
            _profile('user-2', name: 'Ирина Кузнецова', username: 'irina'),
          ],
        ),
      );

      tester.view.physicalSize = const Size(412 * 3, 915 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Ирина');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('Ирина Кузнецова'), findsOneWidget);
      expect(find.byType(Card), findsNothing);

      final rowRect =
          tester.getRect(find.byKey(const ValueKey('discover-result-user-2')));
      expect(
        rowRect.height,
        inInclusiveRange(52, 60),
        reason: 'Строка результата поиска должна быть ~56dp (до чанка 25 — '
            'Card+ListTile, ~72dp).',
      );

      final avatarRect = tester.getRect(find.byType(CircleAvatar).first);
      expect(
        avatarRect.height,
        40,
        reason: 'Аватар результата поиска — 40dp.',
      );
    },
  );

  testWidgets(
      'P2.5a: initialProfileCode strips leading @, auto-searches & allows add to tree',
      (tester) async {
    final kinship = _FakeKinshipService();
    final profileSvc = _FakeProfileService(
      results: [
        _profile('user-2', name: 'Ирина Кузнецова', username: 'irina'),
      ],
    );
    await getIt.unregister<FamilyTreeServiceInterface>();
    await getIt.unregister<ProfileServiceInterface>();
    getIt.registerSingleton<FamilyTreeServiceInterface>(kinship);
    getIt.registerSingleton<ProfileServiceInterface>(profileSvc);

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/discover',
          routes: [
            GoRoute(
              path: '/discover',
              builder: (_, __) => const DiscoverRelativesScreen(
                treeId: 'tree-1',
                initialProfileCode: '@irina',
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(profileSvc.lastQuery, 'irina');
    expect(find.text('Ирина Кузнецова'), findsOneWidget);

    await tester.tap(find.byKey(const Key('discover-add-relative-user-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Кем приходится?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Брат/сестра').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('discover-confirm-add-relative')));
    await tester.pumpAndSettle();

    expect(kinship.sentRequests, hasLength(1));
    expect(kinship.sentRequests.first['treeId'], 'tree-1');
    expect(kinship.sentRequests.first['recipientId'], 'user-2');
    expect(kinship.sentRequests.first['relationType'], RelationType.sibling);
  });
}
