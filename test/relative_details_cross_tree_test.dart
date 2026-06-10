// P0 (мамин баг): карточка родственника должна открываться из ЛЮБОГО
// дерева, а не только из выбранного. Тесты фиксируют цепочку резолва
// (selected → обход деревьев), деградацию второстепенных данных и
// честную заглушку «не нашли».

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:rodnya/backend/interfaces/auth_service_interface.dart';
import 'package:rodnya/backend/interfaces/chat_service_interface.dart';
import 'package:rodnya/backend/interfaces/family_tree_service_interface.dart';
import 'package:rodnya/backend/interfaces/invitation_link_service_interface.dart';
import 'package:rodnya/backend/interfaces/profile_service_interface.dart';
import 'package:rodnya/backend/interfaces/storage_service_interface.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/models/family_relation.dart';
import 'package:rodnya/models/family_tree.dart';
import 'package:rodnya/models/person_dossier.dart';
import 'package:rodnya/models/tree_change_record.dart';
import 'package:rodnya/models/user_profile.dart';
import 'package:rodnya/providers/tree_provider.dart';
import 'package:rodnya/screens/relative_details_screen.dart';
import 'package:rodnya/services/custom_api_auth_service.dart'
    show CustomApiException;
import 'package:rodnya/services/local_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

FamilyTree _tree(String id, String name) => FamilyTree(
      id: id,
      name: name,
      description: '',
      creatorId: 'user-1',
      memberIds: const ['user-1'],
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
      isPrivate: true,
      members: const ['user-1'],
    );

class _FakeAuthService implements AuthServiceInterface {
  @override
  String? get currentUserId => 'user-1';

  @override
  String? get currentUserDisplayName => 'Артем';

  @override
  Stream<String?> get authStateChanges => const Stream.empty();

  @override
  String describeError(Object error) => error.toString();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocalStorageService implements LocalStorageService {
  @override
  Future<List<FamilyTree>> getAllTrees() async =>
      [_tree('tree-a', 'Семья А'), _tree('tree-b', 'Семья Б')];

  @override
  Future<FamilyTree?> getTree(String treeId) async => _tree(treeId, treeId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfileService implements ProfileServiceInterface {
  bool throwOnPersonProfile = false;
  int personProfileRequests = 0;

  @override
  Future<UserProfile?> getUserProfile(String userId) async {
    if (userId == 'user-x') {
      personProfileRequests += 1;
      if (throwOnPersonProfile) {
        throw CustomApiException('профиль недоступен', statusCode: 500);
      }
    }
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeChatService implements ChatServiceInterface {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInvitationLinkService implements InvitationLinkServiceInterface {
  @override
  Uri buildInvitationLink({required String treeId, required String personId}) =>
      Uri.parse('https://example.com/invite/$treeId/$personId');
}

class _FakeStorageService implements StorageServiceInterface {
  @override
  Future<String?> uploadImage(XFile imageFile, String folder) async => null;

  @override
  Future<bool> deleteImage(String imageUrl) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Тётя живёт в дереве Б; выбранное дерево — А. Сервис НЕ реализует
/// PersonTreeResolutionCapable — экран обязан дойти до ручного обхода
/// деревьев пользователя.
class _CrossTreeFamilyService implements FamilyTreeServiceInterface {
  _CrossTreeFamilyService({required this.aunt});

  final FamilyPerson aunt;
  final List<String> personRequests = <String>[];

  @override
  Future<List<FamilyTree>> getUserTrees() async =>
      [_tree('tree-a', 'Семья А'), _tree('tree-b', 'Семья Б')];

  @override
  Future<FamilyPerson> getPersonById(String treeId, String personId) async {
    personRequests.add('$treeId/$personId');
    if (treeId == 'tree-b' && personId == aunt.id) {
      return aunt;
    }
    throw CustomApiException('не найден', statusCode: 404);
  }

  @override
  Future<List<FamilyPerson>> getRelatives(String treeId) async =>
      treeId == 'tree-b' ? [aunt] : const <FamilyPerson>[];

  @override
  Future<List<FamilyRelation>> getRelations(String treeId) async =>
      const <FamilyRelation>[];

  @override
  Future<PersonDossier> getPersonDossier(String treeId, String personId) {
    // Деградация: досье не доехало — карточка обязана жить без него.
    throw CustomApiException('временно недоступно', statusCode: 500);
  }

  @override
  Future<List<TreeChangeRecord>> getTreeHistory({
    required String treeId,
    String? personId,
    String? type,
    String? actorId,
  }) async =>
      const <TreeChangeRecord>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final getIt = GetIt.instance;
  late _CrossTreeFamilyService familyService;
  late _FakeProfileService profileService;

  final aunt = FamilyPerson(
    id: 'aunt-1',
    treeId: 'tree-b',
    userId: 'user-x',
    name: 'Смирнова Ольга Петровна',
    gender: Gender.female,
    isAlive: true,
    createdAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 1, 1),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    getIt.registerSingleton<AuthServiceInterface>(_FakeAuthService());
    getIt.registerSingleton<LocalStorageService>(_FakeLocalStorageService());
    profileService = _FakeProfileService();
    getIt.registerSingleton<ProfileServiceInterface>(profileService);
    getIt.registerSingleton<ChatServiceInterface>(_FakeChatService());
    getIt.registerSingleton<InvitationLinkServiceInterface>(
      _FakeInvitationLinkService(),
    );
    getIt.registerSingleton<StorageServiceInterface>(_FakeStorageService());
    familyService = _CrossTreeFamilyService(aunt: aunt);
    getIt.registerSingleton<FamilyTreeServiceInterface>(familyService);
  });

  tearDown(() async {
    await getIt.reset();
  });

  Future<TreeProvider> pumpCard(
    WidgetTester tester, {
    required String personId,
    String? routeTreeId,
  }) async {
    final treeProvider = TreeProvider();
    await treeProvider.selectTree('tree-a', 'Семья А');
    await tester.pumpWidget(
      ChangeNotifierProvider<TreeProvider>.value(
        value: treeProvider,
        child: MaterialApp(
          home: RelativeDetailsScreen(
            personId: personId,
            treeId: routeTreeId,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return treeProvider;
  }

  testWidgets(
      'P0: человек из дерева Б открывается при выбранном дереве А (обход)',
      (tester) async {
    await pumpCard(tester, personId: 'aunt-1');

    // Карточка открылась — имя на экране, заглушек нет.
    expect(find.textContaining('Ольга'), findsWidgets);
    expect(find.text('Карточка не нашлась'), findsNothing);
    expect(find.text('Не получилось загрузить'), findsNothing);
    // Резолв честно сходил в выбранное дерево (404) и нашёл в другом.
    expect(familyService.personRequests, contains('tree-a/aunt-1'));
    expect(familyService.personRequests, contains('tree-b/aunt-1'));
  });

  testWidgets('P0: явный ?treeId= открывает карточку без обхода',
      (tester) async {
    await pumpCard(tester, personId: 'aunt-1', routeTreeId: 'tree-b');

    expect(find.textContaining('Ольга'), findsWidgets);
    // С явным контекстом первый же GET — в правильное дерево.
    expect(familyService.personRequests.first, 'tree-b/aunt-1');
    expect(familyService.personRequests, isNot(contains('tree-a/aunt-1')));
  });

  testWidgets(
      'P0b: отказ getUserProfile персоны деградирует секцией — карточка живая',
      (tester) async {
    profileService.throwOnPersonProfile = true;

    await pumpCard(tester, personId: 'aunt-1', routeTreeId: 'tree-b');

    // Профиль запрашивался и упал, но карточка отрисована.
    expect(profileService.personProfileRequests, greaterThan(0));
    expect(find.textContaining('Ольга'), findsWidgets);
    expect(find.text('Карточка не нашлась'), findsNothing);
    expect(find.text('Не получилось загрузить'), findsNothing);
  });

  testWidgets(
      'P0b: человек, которого нет ни в одном дереве → честная заглушка',
      (tester) async {
    await pumpCard(tester, personId: 'ghost-1');

    expect(find.text('Карточка не нашлась'), findsOneWidget);
    expect(find.text('Назад'), findsOneWidget);
    // Без кнопки «Повторить» — повтор не вернёт удалённого человека.
    expect(find.text('Повторить'), findsNothing);
  });
}
