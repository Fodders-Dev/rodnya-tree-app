import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:lineage/backend/interfaces/auth_service_interface.dart';
import 'package:lineage/backend/interfaces/family_tree_service_interface.dart';
import 'package:lineage/backend/interfaces/profile_service_interface.dart';
import 'package:lineage/backend/interfaces/storage_service_interface.dart';
import 'package:lineage/models/family_person.dart';
import 'package:lineage/models/family_relation.dart';
import 'package:lineage/models/tree_change_record.dart';
import 'package:lineage/models/user_profile.dart';
import 'package:lineage/screens/add_relative_screen.dart';
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
}
