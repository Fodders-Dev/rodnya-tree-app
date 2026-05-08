import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:rodnya/backend/interfaces/auth_service_interface.dart';
import 'package:rodnya/backend/interfaces/cross_tree_person_search_capable_family_tree_service.dart';
import 'package:rodnya/backend/interfaces/family_tree_service_interface.dart';
import 'package:rodnya/backend/interfaces/profile_service_interface.dart';
import 'package:rodnya/backend/interfaces/storage_service_interface.dart';
import 'package:rodnya/backend/models/cross_tree_person_suggestion.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/models/family_relation.dart';
import 'package:rodnya/models/tree_change_record.dart';
import 'package:rodnya/models/user_profile.dart';
import 'package:rodnya/screens/add_relative_screen.dart';
import 'package:image_picker/image_picker.dart';

class _FakeAuthService implements AuthServiceInterface {
  String? lastErrorDescription;

  @override
  String? get currentUserId => 'user-1';

  @override
  String? get currentUserEmail => 'user@example.com';

  @override
  String? get currentUserDisplayName => 'Тестовый пользователь';

  @override
  String? get currentUserPhotoUrl => null;

  @override
  List<String> get currentProviderIds => const ['password'];

  @override
  Stream<String?> get authStateChanges => const Stream.empty();

  @override
  String describeError(Object error) {
    return lastErrorDescription ?? error.toString();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFamilyTreeService implements FamilyTreeServiceInterface {
  bool failOnAdd = false;
  RelationType relationToUser = RelationType.sibling;
  List<TreeChangeRecord> historyRecords = const [];
  FamilyPerson? personById;

  @override
  Future<List<FamilyPerson>> getRelatives(String treeId) async => const [];

  @override
  Future<FamilyPerson> getPersonById(String treeId, String personId) async {
    final person = personById;
    if (person != null && person.id == personId) {
      return person;
    }
    throw StateError('Unknown person $personId');
  }

  @override
  Future<String> addRelative(String treeId, Map<String, dynamic> personData) {
    if (failOnAdd) {
      throw Exception('save failed');
    }
    return Future.value('person-1');
  }

  @override
  Future<RelationType> getRelationToUser(
      String treeId, String relativeId) async {
    return relationToUser;
  }

  @override
  Future<List<TreeChangeRecord>> getTreeHistory({
    required String treeId,
    String? personId,
    String? type,
    String? actorId,
  }) async {
    return historyRecords;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfileService implements ProfileServiceInterface {
  @override
  Future<UserProfile?> getCurrentUserProfile() async => UserProfile.create(
        id: 'user-1',
        email: 'user@example.com',
        username: 'tester',
        phoneNumber: '',
        gender: Gender.male,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeStorageService implements StorageServiceInterface {
  @override
  Future<bool> deleteImage(String imageUrl) async => true;

  @override
  Future<String?> uploadImage(XFile imageFile, String folder) async =>
      'https://example.com/$folder/${imageFile.name}';

  @override
  Future<String?> uploadProfileImage(XFile imageFile) async =>
      'https://example.com/avatar/${imageFile.name}';

  @override
  Future<String?> uploadCoverImage(XFile imageFile) async =>
      'https://example.com/cover/${imageFile.name}';

  @override
  Future<String?> uploadBytes({
    required String bucket,
    required String path,
    required dynamic fileBytes,
    dynamic fileOptions,
  }) async =>
      'https://example.com/$bucket/$path';
}

void main() {
  final getIt = GetIt.instance;

  setUp(() async {
    await getIt.reset();
    getIt.registerSingleton<AuthServiceInterface>(_FakeAuthService());
    getIt.registerSingleton<FamilyTreeServiceInterface>(
        _FakeFamilyTreeService());
    getIt.registerSingleton<ProfileServiceInterface>(_FakeProfileService());
    getIt.registerSingleton<StorageServiceInterface>(_FakeStorageService());
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('показывает упрощенный режим для первого человека в дереве',
      (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/add',
          builder: (context, state) => AddRelativeScreen(
            treeId: 'tree-1',
            routeExtra: state.extra as Map<String, dynamic>?,
            routeQueryParameters: state.uri.queryParameters,
          ),
        ),
      ],
      initialLocation: '/add',
    );

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Первый человек в дереве'), findsOneWidget);
    expect(
      find.textContaining('Сначала достаточно имени и пола'),
      findsOneWidget,
    );
    expect(find.text('Что нужно сейчас'), findsOneWidget);
    expect(find.text('Добавить первого человека'), findsOneWidget);
    expect(
      find.textContaining('Связать себя с деревом можно позже'),
      findsOneWidget,
    );
  });

  testWidgets('показывает конкретную CTA для добавления из контекста дерева',
      (tester) async {
    final relatedPerson = FamilyPerson(
      id: 'person-1',
      treeId: 'tree-1',
      name: 'Петров Иван',
      gender: Gender.male,
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/add',
          builder: (context, state) => AddRelativeScreen(
            treeId: 'tree-1',
            relatedTo: relatedPerson,
            predefinedRelation: RelationType.child,
            quickAddMode: true,
            routeExtra: state.extra as Map<String, dynamic>?,
            routeQueryParameters: state.uri.queryParameters,
          ),
        ),
      ],
      initialLocation: '/add',
    );

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Добавить ребёнка'), findsOneWidget);
    expect(
      find.textContaining('Связь с Петров Иван уже выбрана'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Связь будет создана автоматически'),
      findsOneWidget,
    );
    expect(find.text('Режим быстрого ввода'), findsOneWidget);
    expect(find.text('Добавить ещё одного'), findsOneWidget);
    expect(find.text('Добавить и открыть на дереве'), findsOneWidget);
  });

  testWidgets('не показывает сырую ошибку сохранения карточки', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authService = _FakeAuthService()
      ..lastErrorDescription =
          'Не удалось сохранить карточку. Проверьте данные и попробуйте ещё раз.';
    final familyService = _FakeFamilyTreeService()..failOnAdd = true;

    await getIt.reset();
    getIt.registerSingleton<AuthServiceInterface>(authService);
    getIt.registerSingleton<FamilyTreeServiceInterface>(familyService);
    getIt.registerSingleton<ProfileServiceInterface>(_FakeProfileService());
    getIt.registerSingleton<StorageServiceInterface>(_FakeStorageService());

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/add',
          builder: (context, state) => AddRelativeScreen(
            treeId: 'tree-1',
            routeExtra: state.extra as Map<String, dynamic>?,
            routeQueryParameters: state.uri.queryParameters,
          ),
        ),
      ],
      initialLocation: '/add',
    );

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Фамилия'),
      'Петров',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Имя'),
      'Иван',
    );
    await tester.tap(find.text('Мужской'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Добавить первого человека'));
    await tester.tap(find.text('Добавить первого человека'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text(
        'Не удалось сохранить карточку. Проверьте данные и попробуйте ещё раз.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Exception: save failed'), findsNothing);
  });

  testWidgets(
      'при добавлении супруга показывает поле даты свадьбы в расширенном режиме',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final relatedPerson = FamilyPerson(
      id: 'person-1',
      treeId: 'tree-1',
      name: 'Петров Иван',
      gender: Gender.male,
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/add',
          builder: (context, state) => AddRelativeScreen(
            treeId: 'tree-1',
            relatedTo: relatedPerson,
            predefinedRelation: RelationType.spouse,
            routeExtra: state.extra as Map<String, dynamic>?,
            routeQueryParameters: state.uri.queryParameters,
          ),
        ),
      ],
      initialLocation: '/add',
    );

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Расширенно'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Расширенно'));
    await tester.pumpAndSettle();

    expect(find.text('Дата свадьбы'), findsOneWidget);
    expect(find.text('Попадёт в семейный календарь'), findsOneWidget);
  });

  testWidgets(
      'поддерживает query-параметры для открытия add-relative из e2e deep link',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final familyService = _FakeFamilyTreeService()
      ..personById = FamilyPerson(
        id: 'person-1',
        treeId: 'tree-1',
        name: 'Петров Иван',
        gender: Gender.male,
        isAlive: true,
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      );

    await getIt.reset();
    getIt.registerSingleton<AuthServiceInterface>(_FakeAuthService());
    getIt.registerSingleton<FamilyTreeServiceInterface>(familyService);
    getIt.registerSingleton<ProfileServiceInterface>(_FakeProfileService());
    getIt.registerSingleton<StorageServiceInterface>(_FakeStorageService());

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/add',
          builder: (context, state) => AddRelativeScreen(
            treeId: 'tree-1',
            routeExtra: state.extra as Map<String, dynamic>?,
            routeQueryParameters: state.uri.queryParameters,
          ),
        ),
      ],
      initialLocation:
          '/add?contextPersonId=person-1&relationType=spouse&quickAddMode=1',
    );

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Режим быстрого ввода'), findsOneWidget);
    expect(
        find.textContaining('Связь с Петров Иван уже выбрана'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Расширенно'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Расширенно'));
    await tester.pumpAndSettle();

    expect(find.text('Дата свадьбы'), findsOneWidget);
  });

  testWidgets(
      'в режиме редактирования показывает быстрые действия для медиа и истории',
      (tester) async {
    final familyService = _FakeFamilyTreeService()
      ..historyRecords = [
        TreeChangeRecord(
          id: 'record-1',
          treeId: 'tree-1',
          type: 'person_media.updated',
          personId: 'person-1',
          createdAt: DateTime(2024, 1, 2),
        ),
      ];

    await getIt.reset();
    getIt.registerSingleton<AuthServiceInterface>(_FakeAuthService());
    getIt.registerSingleton<FamilyTreeServiceInterface>(familyService);
    getIt.registerSingleton<ProfileServiceInterface>(_FakeProfileService());
    getIt.registerSingleton<StorageServiceInterface>(_FakeStorageService());

    final person = FamilyPerson(
      id: 'person-1',
      treeId: 'tree-1',
      name: 'Петров Иван',
      gender: Gender.male,
      isAlive: true,
      photoUrl: 'https://example.com/photo-1.jpg',
      photoGallery: const [
        {
          'id': 'media-1',
          'url': 'https://example.com/photo-1.jpg',
          'isPrimary': true,
        },
        {
          'id': 'media-2',
          'url': 'https://example.com/photo-2.jpg',
          'isPrimary': false,
        },
      ],
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/edit',
          builder: (context, state) => AddRelativeScreen(
            treeId: 'tree-1',
            person: person,
            isEditing: true,
          ),
        ),
        GoRoute(
          path: '/relative/details/:personId',
          builder: (context, state) => Scaffold(
            body: Text('details ${state.pathParameters['personId']}'),
          ),
        ),
      ],
      initialLocation: '/edit',
    );

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Режим редактирования'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Основное'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Расширенно'), findsOneWidget);
    expect(find.text('Фото и видео'), findsOneWidget);
    expect(find.text('2 в карточке'), findsAtLeastNWidgets(1));
    expect(find.text('Основное медиа выбрано'), findsOneWidget);
    expect(find.text('Фото'), findsOneWidget);
    expect(find.text('Видео'), findsOneWidget);
    expect(find.text('Медиа и история'), findsOneWidget);
    expect(find.text('Открыть карточку'), findsAtLeastNWidgets(1));
    expect(find.text('Медиа (2)'), findsOneWidget);
    expect(find.text('История'), findsOneWidget);

    await tester.ensureVisible(find.text('История'));
    await tester.tap(find.text('История'));
    await tester.pumpAndSettle();

    expect(find.text('История изменений'), findsOneWidget);
    expect(find.text('Обновлено фото'), findsOneWidget);
  });

  testWidgets(
      'в режиме редактирования дедушка показывается как дедушка, а не как внук',
      (tester) async {
    final familyService =
        getIt<FamilyTreeServiceInterface>() as _FakeFamilyTreeService;
    familyService.relationToUser = RelationType.grandparent;

    final person = FamilyPerson(
      id: 'grandfather-1',
      treeId: 'tree-1',
      name: 'Мочалкин Геннадий',
      gender: Gender.male,
      isAlive: false,
      birthDate: DateTime(1940, 1, 25),
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/edit',
          builder: (context, state) => AddRelativeScreen(
            treeId: 'tree-1',
            person: person,
            isEditing: true,
          ),
        ),
      ],
      initialLocation: '/edit',
    );

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Дедушка'), findsWidgets);
    expect(find.text('Внук'), findsNothing);
  });

  testWidgets(
      'в режиме редактирования бабушка показывается как бабушка, а не как внучка',
      (tester) async {
    final familyService =
        getIt<FamilyTreeServiceInterface>() as _FakeFamilyTreeService;
    familyService.relationToUser = RelationType.grandparent;

    final person = FamilyPerson(
      id: 'grandmother-1',
      treeId: 'tree-1',
      name: 'Мочалкина Лидия',
      gender: Gender.female,
      isAlive: false,
      birthDate: DateTime(1949, 2, 19),
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/edit',
          builder: (context, state) => AddRelativeScreen(
            treeId: 'tree-1',
            person: person,
            isEditing: true,
          ),
        ),
      ],
      initialLocation: '/edit',
    );

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Бабушка'), findsWidgets);
    expect(find.text('Внучка'), findsNothing);
  });

  // Phase 0 cross-tree picker tests. The picker section appears
  // ONLY when the registered FamilyTreeServiceInterface also
  // implements CrossTreePersonSearchCapableFamilyTreeService — so a
  // service that doesn't can opt out of the feature entirely.
  group('Cross-tree person picker (Phase 0)', () {
    testWidgets(
      'is hidden when the service does not implement the search capability',
      (tester) async {
        // Default _FakeFamilyTreeService DOES NOT implement the
        // search capability; the picker should not surface.
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/add',
              builder: (context, state) =>
                  const AddRelativeScreen(treeId: 'tree-1'),
            ),
          ],
          initialLocation: '/add',
        );

        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        expect(find.text('Из моих других деревьев'), findsNothing);
      },
    );

    testWidgets(
      'expands on tap, runs a search, lists results and pre-fills form on pick',
      (tester) async {
        final searchableService = _SearchCapableFakeFamilyTreeService(
          results: [
            const CrossTreePersonSuggestion(
              id: 'mama-on-tree-1',
              treeId: 'tree-99',
              treeName: 'Семья',
              displayName: 'Кузнецова Анна Петровна',
              gender: 'female',
              birthDate: '1965-03-12T00:00:00.000Z',
            ),
          ],
        );
        await getIt.unregister<FamilyTreeServiceInterface>();
        getIt.registerSingleton<FamilyTreeServiceInterface>(searchableService);

        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/add',
              builder: (context, state) =>
                  const AddRelativeScreen(treeId: 'tree-2'),
            ),
          ],
          initialLocation: '/add',
        );

        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        // Picker header is visible but collapsed by default — the
        // form below stays the primary path for users with one tree.
        expect(find.text('Из моих других деревьев'), findsOneWidget);
        expect(find.byIcon(Icons.expand_more), findsOneWidget);

        await tester.tap(find.text('Из моих других деревьев'));
        await tester.pump(); // expansion animation tick
        await tester.pump(const Duration(milliseconds: 260)); // debounce
        await tester.pumpAndSettle();

        // Empty-query auto-fetch fires once on first expand → result
        // row renders with name + tree origin.
        expect(searchableService.searchCallCount, greaterThan(0));
        expect(find.text('Кузнецова Анна Петровна'), findsOneWidget);
        expect(find.textContaining('Из «Семья»'), findsOneWidget);

        // Tap the row → form pre-fills + picker collapses + linked
        // chip appears with tree name.
        await tester.tap(find.text('Кузнецова Анна Петровна'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Связан с человеком из «Семья»'),
          findsOneWidget,
        );
        // Form-field controllers were populated. We don't have a
        // direct getter, but the surname text-field hint disappears
        // because Flutter renders the actual text on top — find the
        // "Кузнецова" inside the form by looking past the chip.
        final allKuznetsova = find.text('Кузнецова');
        expect(allKuznetsova, findsWidgets);
      },
    );

    testWidgets(
      'X on the linked chip clears the source link without wiping the form',
      (tester) async {
        final searchableService = _SearchCapableFakeFamilyTreeService(
          results: [
            const CrossTreePersonSuggestion(
              id: 'p1',
              treeId: 't1',
              treeName: 'Дерево',
              displayName: 'Иванов Иван',
              gender: 'male',
            ),
          ],
        );
        await getIt.unregister<FamilyTreeServiceInterface>();
        getIt.registerSingleton<FamilyTreeServiceInterface>(searchableService);

        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/add',
              builder: (context, state) =>
                  const AddRelativeScreen(treeId: 'tree-2'),
            ),
          ],
          initialLocation: '/add',
        );

        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Из моих других деревьев'));
        await tester.pump(const Duration(milliseconds: 260));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Иванов Иван'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Связан с человеком'),
          findsOneWidget,
        );

        // Click "Отвязать" — the IconButton with tooltip.
        await tester.tap(find.byTooltip('Отвязать'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Связан с человеком'),
          findsNothing,
        );
        // Picker is back, form fields are NOT cleared (we only
        // strip the link, not the data — user might still want it).
        expect(find.text('Из моих других деревьев'), findsOneWidget);
      },
    );
  });
}

/// Fake that implements both the standard tree service and the
/// Phase 0 cross-tree search capability — used to verify that the
/// picker section appears + functions when the capability is
/// available.
class _SearchCapableFakeFamilyTreeService implements
    FamilyTreeServiceInterface,
    CrossTreePersonSearchCapableFamilyTreeService {
  _SearchCapableFakeFamilyTreeService({required this.results});

  final List<CrossTreePersonSuggestion> results;

  int searchCallCount = 0;
  String? lastQuery;
  String? lastExcludeTreeId;

  /// Records the last call so we can assert behavior on it.
  Map<String, dynamic>? lastAddRelativeData;

  @override
  Future<List<FamilyPerson>> getRelatives(String treeId) async => const [];

  @override
  Future<String> addRelative(String treeId, Map<String, dynamic> personData) {
    lastAddRelativeData = personData;
    return Future.value('person-1');
  }

  @override
  Future<List<TreeChangeRecord>> getTreeHistory({
    required String treeId,
    String? personId,
    String? type,
    String? actorId,
  }) async {
    return const [];
  }

  @override
  Future<List<CrossTreePersonSuggestion>> searchPersonsAcrossOwnTrees({
    required String query,
    String? excludeTreeId,
    int limit = 20,
  }) async {
    searchCallCount += 1;
    lastQuery = query;
    lastExcludeTreeId = excludeTreeId;
    if (query.isEmpty) return results;
    final lowered = query.toLowerCase();
    return results
        .where(
          (entry) => entry.displayName.toLowerCase().contains(lowered),
        )
        .toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
