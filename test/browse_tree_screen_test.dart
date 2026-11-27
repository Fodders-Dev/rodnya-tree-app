import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:rodnya/backend/backend_runtime_config.dart';
import 'package:rodnya/backend/interfaces/auth_service_interface.dart';
import 'package:rodnya/backend/interfaces/family_tree_service_interface.dart';
import 'package:rodnya/backend/interfaces/semya_capable_family_tree_service.dart';
import 'package:rodnya/backend/models/semya_browse_token.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/screens/browse_tree_screen.dart';
import 'package:rodnya/widgets/interactive_family_tree.dart';

class _FakeBrowseService
    implements FamilyTreeServiceInterface, SemyaCapableFamilyTreeService {
  _FakeBrowseService(this.snapshot);

  final BrowsedSemyaTree snapshot;

  @override
  Future<BrowsedSemyaTree> fetchBrowseTree(String token) async => snapshot;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements AuthServiceInterface {
  _FakeAuth(this.userId);

  final String? userId;

  @override
  String? get currentUserId => userId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final getIt = GetIt.instance;

  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  test('SemyaBrowseToken.shareUrl honors BackendRuntimeConfig.publicAppUrl',
      () {
    const token = SemyaBrowseToken(
      id: 'bt-1',
      semyaId: 'semya-1',
      token: 'abc-token',
      createdByUserId: 'u-1',
      createdAt: '2026-11-27T00:00:00Z',
      expiresAt: '2026-12-27T00:00:00Z',
    );
    final base = BackendRuntimeConfig.current.publicAppUrl
        .trim()
        .replaceAll(RegExp(r'/+$'), '');
    expect(token.shareUrl, '$base/browse/abc-token');
  });

  testWidgets(
      'BrowseTreeScreen shows person details + login CTA for anonymous visitor',
      (tester) async {
    getIt.registerSingleton<FamilyTreeServiceInterface>(
      _FakeBrowseService(
        const BrowsedSemyaTree(
          semyaId: 'semya-1',
          semyaName: 'Семья Ивановых',
          treeId: 'tree-1',
          treeName: 'Семья Ивановых',
          treeKind: 'family',
          sessionExpiresAt: '2026-12-27T00:00:00Z',
          persons: [
            BrowsedPerson(
              id: 'p-1',
              treeId: 'tree-1',
              name: 'Дед Николай',
              gender: 'male',
              birthDate: '1938-01-01',
              birthDatePrecision: 'year',
            ),
          ],
          relations: [],
        ),
      ),
    );

    final router = GoRouter(
      initialLocation: '/browse/tok',
      routes: [
        GoRoute(
          path: '/browse/:token',
          builder: (_, state) => BrowseTreeScreen(
            browseToken: state.pathParameters['token']!,
          ),
        ),
        GoRoute(
          path: '/login',
          builder: (_, state) => Scaffold(
            body: Text('login:${state.uri.queryParameters['from']}'),
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final tree = tester.widget<InteractiveFamilyTree>(
      find.byType(InteractiveFamilyTree),
    );
    expect(tree.peopleData, hasLength(1));
    tree.onPersonTap(tree.peopleData.first['person'] as FamilyPerson);
    await tester.pumpAndSettle();

    expect(find.text('Дед Николай'), findsOneWidget);

    expect(find.byKey(const Key('browse-person-focus-branch')), findsOneWidget);
    expect(find.byKey(const Key('browse-person-login')), findsOneWidget);
    expect(find.byKey(const Key('browse-person-pull')), findsNothing);

    await tester.tap(find.byKey(const Key('browse-person-login')));
    await tester.pumpAndSettle();
    expect(find.text('login:/browse/tok'), findsOneWidget);
  });

  testWidgets(
      'BrowseTreeScreen shows pull-to-family CTA for authenticated visitor',
      (tester) async {
    getIt.registerSingleton<AuthServiceInterface>(_FakeAuth('user-2'));
    getIt.registerSingleton<FamilyTreeServiceInterface>(
      _FakeBrowseService(
        const BrowsedSemyaTree(
          semyaId: 'semya-1',
          semyaName: 'Семья Ивановых',
          treeId: 'tree-1',
          treeName: 'Семья Ивановых',
          treeKind: 'family',
          sessionExpiresAt: '2026-12-27T00:00:00Z',
          persons: [
            BrowsedPerson(
              id: 'p-1',
              treeId: 'tree-1',
              name: 'Бабушка Ольга',
              gender: 'female',
            ),
          ],
          relations: [],
        ),
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: BrowseTreeScreen(browseToken: 'tok')),
    );
    await tester.pumpAndSettle();

    final tree = tester.widget<InteractiveFamilyTree>(
      find.byType(InteractiveFamilyTree),
    );
    tree.onPersonTap(tree.peopleData.first['person'] as FamilyPerson);
    await tester.pumpAndSettle();

    expect(find.text('Бабушка Ольга'), findsOneWidget);

    expect(find.byKey(const Key('browse-person-pull')), findsOneWidget);
    expect(find.byKey(const Key('browse-person-login')), findsNothing);
  });
}
