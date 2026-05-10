import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:rodnya/backend/interfaces/cross_tree_person_search_capable_family_tree_service.dart';
import 'package:rodnya/backend/interfaces/family_tree_service_interface.dart';
import 'package:rodnya/backend/models/cross_tree_person_suggestion.dart';
import 'package:rodnya/backend/models/include_rules.dart';
import 'package:rodnya/models/family_tree.dart';
import 'package:rodnya/screens/family_tree/create_tree_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeFamilyTreeService
    implements
        FamilyTreeServiceInterface,
        CrossTreePersonSearchCapableFamilyTreeService {
  String? createdName;
  String? createdDescription;
  bool? createdIsPrivate;
  TreeKind? createdKind;
  IncludeRules? createdIncludeRules;
  List<CrossTreePersonSuggestion> searchResults = const [];

  @override
  Future<String> createTree({
    required String name,
    required String description,
    required bool isPrivate,
    TreeKind kind = TreeKind.family,
    IncludeRules? includeRules,
  }) async {
    createdName = name;
    createdDescription = description;
    createdIsPrivate = isPrivate;
    createdKind = kind;
    createdIncludeRules = includeRules;
    return 'tree-99';
  }

  @override
  Future<List<CrossTreePersonSuggestion>> searchPersonsAcrossOwnTrees({
    required String query,
    String? excludeTreeId,
    int limit = 20,
  }) async {
    return searchResults;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: '/trees/create',
    routes: [
      GoRoute(
        path: '/trees/create',
        builder: (context, state) => const CreateTreeScreen(),
      ),
      GoRoute(
        path: '/tree/view/:treeId',
        builder: (context, state) => Scaffold(
          body: Center(
            child: Text(
              'opened ${state.pathParameters['treeId']} ${state.uri.queryParameters['name']}',
            ),
          ),
        ),
      ),
    ],
  );
}

void main() {
  final getIt = GetIt.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets(
      'CreateTreeScreen держит форму короткой и открывает новое дерево',
      (tester) async {
    final familyTreeService = _FakeFamilyTreeService();
    getIt.registerSingleton<FamilyTreeServiceInterface>(familyTreeService);

    await tester.pumpWidget(MaterialApp.router(routerConfig: _buildRouter()));
    await tester.pumpAndSettle();

    // After the «дерево»→«ветка» rebrand (commit 0a9929d) the AppBar
    // title is «Новая ветка». Old test expectation predates the rename.
    expect(find.text('Новая ветка'), findsOneWidget);
    expect(find.text('С чего начнём?'), findsOneWidget);
    expect(find.text('Создать и открыть'), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField).first,
      'Семья Смирновых',
    );
    await tester.ensureVisible(find.text('Создать и открыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Создать и открыть'));
    await tester.pumpAndSettle();

    expect(familyTreeService.createdName, 'Семья Смирновых');
    expect(familyTreeService.createdDescription, '');
    expect(familyTreeService.createdIsPrivate, isTrue);
    expect(familyTreeService.createdKind, TreeKind.family);
    // Phase 3.4: family kind default — blood-from-me с maxHops=5.
    expect(familyTreeService.createdIncludeRules, isNotNull);
    expect(
      familyTreeService.createdIncludeRules!.type,
      BranchRuleType.bloodFromMe,
    );
    expect(familyTreeService.createdIncludeRules!.maxHops, 5);
    expect(familyTreeService.createdIncludeRules!.anchorPersonId, isNull);
    expect(
      find.text('opened tree-99 Семья Смирновых'),
      findsOneWidget,
    );
  });

  testWidgets(
      'CreateTreeScreen: friends kind не передаёт includeRules в payload',
      (tester) async {
    final familyTreeService = _FakeFamilyTreeService();
    getIt.registerSingleton<FamilyTreeServiceInterface>(familyTreeService);

    await tester.pumpWidget(MaterialApp.router(routerConfig: _buildRouter()));
    await tester.pumpAndSettle();

    // Switch to friends kind через SegmentedButton segment label.
    // `'Друзья'` появляется только как label сегмента — unique
    // в дереве до switch'а, tap by text работает.
    final friendsSegment = find.text('Друзья');
    await tester.ensureVisible(friendsSegment);
    await tester.tap(friendsSegment);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).first,
      'Универ',
    );
    await tester.ensureVisible(find.text('Создать и открыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Создать и открыть'));
    await tester.pumpAndSettle();

    expect(familyTreeService.createdKind, TreeKind.friends);
    // Friends — backend применит default manual; UI не передаёт
    // includeRules в payload.
    expect(familyTreeService.createdIncludeRules, isNull);
  });

  testWidgets(
      'CreateTreeScreen: переключение rule type на manual — slider + anchor скрыты',
      (tester) async {
    final familyTreeService = _FakeFamilyTreeService();
    getIt.registerSingleton<FamilyTreeServiceInterface>(familyTreeService);

    await tester.pumpWidget(MaterialApp.router(routerConfig: _buildRouter()));
    await tester.pumpAndSettle();

    // Default = blood-from-me для family. Slider visible.
    expect(find.byType(Slider), findsOneWidget);

    // Tap manual radio.
    await tester.tap(find.text('Свободная — я выбираю кого добавить'));
    await tester.pumpAndSettle();

    // Slider hidden, anchor picker hidden (manual не requires).
    expect(find.byType(Slider), findsNothing);
    expect(find.text('Якорный человек'), findsNothing);

    await tester.enterText(
      find.byType(TextFormField).first,
      'Свободная',
    );
    await tester.ensureVisible(find.text('Создать и открыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Создать и открыть'));
    await tester.pumpAndSettle();

    expect(
      familyTreeService.createdIncludeRules!.type,
      BranchRuleType.manual,
    );
  });

  testWidgets(
      'CreateTreeScreen: descendants-of требует выбор anchor — submit без anchor показывает snackbar',
      (tester) async {
    final familyTreeService = _FakeFamilyTreeService();
    getIt.registerSingleton<FamilyTreeServiceInterface>(familyTreeService);

    await tester.pumpWidget(MaterialApp.router(routerConfig: _buildRouter()));
    await tester.pumpAndSettle();

    // Tap "Потомки выбранного человека".
    await tester.tap(find.text('Потомки выбранного человека'));
    await tester.pumpAndSettle();

    // Anchor picker visible.
    expect(find.text('Якорный человек'), findsOneWidget);
    expect(find.text('Выбрать человека'), findsOneWidget);

    // Try submit without anchor → snackbar.
    await tester.enterText(
      find.byType(TextFormField).first,
      'Без якоря',
    );
    await tester.ensureVisible(find.text('Создать и открыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Создать и открыть'));
    await tester.pump();

    // Service не был вызван — snackbar показывается.
    expect(familyTreeService.createdName, isNull);
    expect(
      find.text('Для этого правила выберите конкретного человека'),
      findsOneWidget,
    );
  });

  testWidgets(
      'CreateTreeScreen: «Кровная родня» template применяет blood-from-me rule',
      (tester) async {
    final familyTreeService = _FakeFamilyTreeService();
    getIt.registerSingleton<FamilyTreeServiceInterface>(familyTreeService);

    await tester.pumpWidget(MaterialApp.router(routerConfig: _buildRouter()));
    await tester.pumpAndSettle();

    // Default — blood-from-me. Tap «По маминой линии» (manual
    // template) — переключает rule на manual, убирает slider.
    // Перед tap'ом каждого chip'а: ensureVisible + проверяем что
    // chip найден до того, как template скопировал name в
    // TextField (после чего find.text стал бы ambiguous).
    final maternalChip = find.widgetWithText(ChoiceChip, 'По маминой линии');
    expect(maternalChip, findsOneWidget);
    await tester.ensureVisible(maternalChip);
    await tester.tap(maternalChip);
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing); // manual = no slider

    // Tap «Кровная родня» (blood-from-me template) — slider возвращается.
    final closeBloodChip = find.widgetWithText(ChoiceChip, 'Кровная родня');
    expect(closeBloodChip, findsOneWidget);
    await tester.ensureVisible(closeBloodChip);
    await tester.tap(closeBloodChip);
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsOneWidget);

    await tester.ensureVisible(find.text('Создать и открыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Создать и открыть'));
    await tester.pumpAndSettle();

    expect(
      familyTreeService.createdIncludeRules!.type,
      BranchRuleType.bloodFromMe,
    );
  });
}
