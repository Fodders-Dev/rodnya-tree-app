import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:rodnya/backend/interfaces/auth_service_interface.dart';
import 'package:rodnya/backend/interfaces/family_tree_service_interface.dart';
import 'package:rodnya/backend/interfaces/profile_service_interface.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/models/user_profile.dart';
import 'package:rodnya/screens/find_relative_screen.dart';
import 'package:rodnya/services/app_status_service.dart';

class _FakeAuthService implements AuthServiceInterface {
  @override
  String? get currentUserId => 'user-1';

  @override
  String? get currentUserEmail => null;

  @override
  String? get currentUserDisplayName => null;

  @override
  String? get currentUserPhotoUrl => null;

  @override
  List<String> get currentProviderIds => const ['password'];

  @override
  Stream<String?> get authStateChanges => const Stream.empty();

  @override
  String describeError(Object error) => error.toString();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFamilyTreeService implements FamilyTreeServiceInterface {
  @override
  Future<List<FamilyPerson>> getRelatives(String treeId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfileService implements ProfileServiceInterface {
  @override
  Future<List<UserProfile>> searchUsersByField({
    required String field,
    required String value,
    int limit = 10,
  }) async {
    if ((field == 'username' && value == 'irina') ||
        (field == 'email' && value == 'relative@rodnya.app')) {
      return [
        UserProfile(
          id: 'user-2',
          email: 'relative@rodnya.app',
          displayName: 'Ирина Кузнецова',
          username: 'irina',
          phoneNumber: '',
          createdAt: DateTime(2026, 4, 16),
        ),
      ];
    }
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final getIt = GetIt.instance;

  setUp(() async {
    await getIt.reset();
    getIt.registerSingleton<AuthServiceInterface>(_FakeAuthService());
    getIt.registerSingleton<FamilyTreeServiceInterface>(
      _FakeFamilyTreeService(),
    );
    getIt.registerSingleton<ProfileServiceInterface>(_FakeProfileService());
    getIt.registerSingleton<AppStatusService>(AppStatusService());
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('FindRelativeScreen searches by username without phone flow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: FindRelativeScreen(treeId: 'tree-1'),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Никнейм'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.bySemanticsLabel('Никнейм пользователя'), 'irina');
    await tester.tap(find.byIcon(Icons.search).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Ирина Кузнецова'), findsOneWidget);
    expect(find.text('@irina'), findsWidgets);
    expect(find.text('Телефон'), findsNothing);
    expect(find.text('Контакты'), findsNothing);
  });

  testWidgets('FindRelativeScreen supports profile code entry point',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: FindRelativeScreen(
          treeId: 'tree-1',
          initialProfileCode: 'irina',
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Профильный код'), findsOneWidget);
    await tester.tap(find.text('Код'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.search).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Ирина Кузнецова'), findsOneWidget);
    expect(find.text('@irina'), findsWidgets);
  });

  testWidgets('FindRelativeScreen shows invite flow instead of contact scan',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: FindRelativeScreen(treeId: 'tree-1'),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Приглашение'));
    await tester.pumpAndSettle();

    expect(find.text('Без поиска по телефону'), findsOneWidget);
    expect(find.text('Открыть invite или claim ссылку'), findsOneWidget);
    expect(
      find.text('Добавить карточку родственника', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('Проверить контакты'), findsNothing);
  });
}
