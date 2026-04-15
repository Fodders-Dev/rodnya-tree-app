import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lineage/backend/interfaces/auth_service_interface.dart';
import 'package:lineage/backend/interfaces/family_tree_service_interface.dart';
import 'package:lineage/backend/interfaces/post_service_interface.dart';
import 'package:lineage/backend/interfaces/profile_service_interface.dart';
import 'package:lineage/backend/interfaces/story_service_interface.dart';
import 'package:lineage/backend/models/profile_form_data.dart';
import 'package:lineage/models/family_person.dart';
import 'package:lineage/models/family_tree.dart';
import 'package:lineage/models/post.dart';
import 'package:lineage/models/story.dart';
import 'package:lineage/providers/theme_provider.dart';
import 'package:lineage/providers/tree_provider.dart';
import 'package:lineage/screens/create_post_screen.dart';
import 'package:lineage/screens/create_story_screen.dart';
import 'package:lineage/screens/profile_edit_screen.dart';
import 'package:lineage/screens/settings_screen.dart';
import 'package:lineage/services/local_storage_service.dart';
import 'package:lineage/services/rustore_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

class _FakeFamilyTreeService implements FamilyTreeServiceInterface {
  @override
  Future<List<FamilyPerson>> getRelatives(String treeId) async => [
        FamilyPerson(
          id: 'person-1',
          treeId: treeId,
          userId: 'user-2',
          name: 'Ирина Кузнецова',
          gender: Gender.female,
          isAlive: true,
          createdAt: DateTime(2026, 4, 15),
          updatedAt: DateTime(2026, 4, 15),
        ),
      ];

  @override
  Future<List<FamilyTree>> getUserTrees() async => [
        FamilyTree(
          id: 'tree-1',
          name: 'Локальная семья',
          description: '',
          creatorId: 'user-1',
          memberIds: const ['user-1'],
          createdAt: DateTime(2026, 4, 15),
          updatedAt: DateTime(2026, 4, 15),
          isPrivate: true,
          members: const ['user-1'],
        ),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocalStorageService implements LocalStorageService {
  @override
  Future<FamilyTree?> getTree(String treeId) async => FamilyTree(
        id: treeId,
        name: 'Локальная семья',
        description: '',
        creatorId: 'user-1',
        memberIds: const ['user-1'],
        createdAt: DateTime(2026, 4, 15),
        updatedAt: DateTime(2026, 4, 15),
        isPrivate: true,
        members: const ['user-1'],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePostService implements PostServiceInterface {
  @override
  Future<Post> createPost({
    required String treeId,
    required String content,
    List<XFile> images = const [],
    bool isPublic = false,
    TreeContentScopeType scopeType = TreeContentScopeType.wholeTree,
    List<String> anchorPersonIds = const [],
  }) async =>
      Post(
        id: 'post-1',
        treeId: treeId,
        authorId: 'user-1',
        authorName: 'Codex',
        content: content,
        createdAt: DateTime(2026, 4, 15),
        isPublic: isPublic,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeStoryService implements StoryServiceInterface {
  @override
  Future<Story> createStory({
    required String treeId,
    required StoryType type,
    String? text,
    XFile? media,
    String? thumbnailUrl,
    DateTime? expiresAt,
  }) async =>
      Story(
        id: 'story-1',
        treeId: treeId,
        authorId: 'user-1',
        authorName: 'Codex',
        type: type,
        text: text,
        mediaUrl: null,
        thumbnailUrl: thumbnailUrl,
        createdAt: DateTime(2026, 4, 15),
        expiresAt: DateTime(2026, 4, 16),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthService implements AuthServiceInterface {
  @override
  String? get currentUserId => 'user-1';

  @override
  String? get currentUserEmail => 'codex@rodnya.dev';

  @override
  String? get currentUserDisplayName => 'Codex';

  @override
  String? get currentUserPhotoUrl => null;

  @override
  List<String> get currentProviderIds => const ['password'];

  @override
  Stream<String?> get authStateChanges => const Stream<String?>.empty();

  @override
  String describeError(Object error) => error.toString();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfileService implements ProfileServiceInterface {
  @override
  Future<ProfileFormData> getCurrentUserProfileFormData() async =>
      ProfileFormData(
        userId: 'user-1',
        email: 'codex@rodnya.dev',
        firstName: 'Кодекс',
        lastName: 'Локальный',
        middleName: '',
        displayName: 'Кодекс Локальный',
        username: 'codex',
        phoneNumber: '9991234567',
        countryCode: '7',
        countryName: 'Russia',
        city: 'Москва',
        isPhoneVerified: true,
        gender: Gender.male,
        birthDate: DateTime(1990, 1, 1),
      );

  @override
  Future<void> saveCurrentUserProfileFormData(ProfileFormData data) async {}

  @override
  Future<String?> uploadProfilePhoto(XFile photo) async =>
      'https://example.com/a.jpg';

  @override
  Future<void> verifyCurrentUserPhone({
    required String phoneNumber,
    required String countryCode,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _withTree(Widget child) {
  final treeProvider = TreeProvider();
  treeProvider.selectTree('tree-1', 'Локальная семья');
  return ChangeNotifierProvider<TreeProvider>.value(
    value: treeProvider,
    child: MaterialApp(home: child),
  );
}

Widget _withTheme(Widget child) {
  return ChangeNotifierProvider(
    create: (_) => ThemeProvider(),
    child: MaterialApp(home: child),
  );
}

void main() {
  final getIt = GetIt.instance;

  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  setUp(() async {
    await getIt.reset();
    PackageInfo.setMockInitialValues(
      appName: 'Rodnya',
      packageName: 'dev.rodnya.test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    getIt.registerSingleton<FamilyTreeServiceInterface>(
        _FakeFamilyTreeService());
    getIt.registerSingleton<PostServiceInterface>(_FakePostService());
    getIt.registerSingleton<StoryServiceInterface>(_FakeStoryService());
    getIt.registerSingleton<LocalStorageService>(_FakeLocalStorageService());
    getIt.registerSingleton<AuthServiceInterface>(_FakeAuthService());
    getIt.registerSingleton<ProfileServiceInterface>(_FakeProfileService());
    getIt.registerSingleton<RustoreService>(RustoreService(
      reviewInitialize: () async {},
      reviewRequest: () async {},
      reviewShow: () async {},
    ));
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('CreatePostScreen shows compact composer UI', (tester) async {
    await tester.pumpWidget(_withTree(const CreatePostScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Публикация'), findsOneWidget);
    expect(find.text('Что нового'), findsOneWidget);
    expect(find.text('Видимость'), findsOneWidget);
    expect(find.text('Фото'), findsOneWidget);
  });

  testWidgets('CreateStoryScreen shows compact story composer UI',
      (tester) async {
    await tester.pumpWidget(_withTree(const CreateStoryScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('История'), findsOneWidget);
    expect(find.text('24 часа'), findsWidgets);
    expect(find.text('Текст'), findsWidgets);
    expect(find.text('Превью'), findsOneWidget);
    expect(find.text('Формат'), findsOneWidget);
    expect(find.text('Поделитесь моментом'), findsOneWidget);
  });

  testWidgets('ProfileEditScreen shows sectioned profile form', (tester) async {
    await tester.pumpWidget(_withTheme(const ProfileEditScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Профиль'), findsOneWidget);
    expect(find.text('Фото профиля'), findsOneWidget);
    expect(find.text('Основное'), findsOneWidget);
    expect(find.text('Контакты'), findsOneWidget);
    expect(find.text('Сохранить'), findsOneWidget);
  });

  testWidgets('SettingsScreen shows compact settings sections', (tester) async {
    await tester.pumpWidget(_withTheme(const SettingsScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Настройки'), findsOneWidget);
    expect(find.text('Внешний вид'), findsOneWidget);
    expect(find.text('Документы и поддержка'), findsOneWidget);
    expect(find.text('Аккаунт'), findsOneWidget);
    expect(find.text('Удалить аккаунт'), findsOneWidget);
  });
}
