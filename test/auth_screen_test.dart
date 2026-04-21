import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:rodnya/backend/interfaces/auth_service_interface.dart';
import 'package:rodnya/screens/auth_screen.dart';
import 'package:rodnya/services/app_status_service.dart';

class _FakeAuthService implements AuthServiceInterface {
  String? _currentUserId;

  @override
  String? get currentUserId => _currentUserId;

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
  Future<Object?> loginWithEmail(String email, String password) async {
    _currentUserId = 'user-1';
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final getIt = GetIt.instance;

  setUp(() async {
    await getIt.reset();
    getIt.registerSingleton<AuthServiceInterface>(_FakeAuthService());
    getIt.registerSingleton<AppStatusService>(AppStatusService());
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('AuthScreen shows public product entry on wide layouts',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: AuthScreen(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Семья. Чат. Дерево.'), findsOneWidget);
    expect(find.text('Войти'), findsWidgets);
    expect(find.text('Создать аккаунт'), findsWidgets);
    expect(find.text('Stories'), findsWidgets);
    expect(find.text('Вход'), findsWidgets);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Telegram'), findsOneWidget);
    expect(find.text('VK ID'), findsOneWidget);
    expect(find.text('MAX'), findsOneWidget);
  });

  testWidgets('wide CTA switches auth screen into registration mode',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: AuthScreen(),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Создать аккаунт').first);
    await tester.pumpAndSettle();

    expect(find.text('Новый аккаунт'), findsOneWidget);
    expect(find.text('Имя'), findsOneWidget);
    expect(find.text('Создать аккаунт'), findsWidgets);
  });

  testWidgets('AuthScreen keeps login form first on mobile layouts',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: AuthScreen(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Семья. Чат. Дерево.'), findsOneWidget);
    expect(find.text('Вход'), findsWidgets);
    expect(find.text('Регистрация'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Один вход для своих.'), findsOneWidget);
    expect(find.text('Дерево, родные и чат в одном аккаунте.'), findsNothing);
    expect(find.text('Дерево'), findsWidgets);
    expect(find.text('Родные'), findsOneWidget);
    expect(find.text('Чат'), findsOneWidget);
    expect(find.text('Stories'), findsWidgets);
    expect(find.text('Google'), findsOneWidget);
    expect(find.text('Telegram'), findsOneWidget);
  });

  testWidgets('AuthScreen respects deferred route after successful login',
      (tester) async {
    final authService = getIt<AuthServiceInterface>() as _FakeAuthService;

    final router = GoRouter(
      initialLocation: '/login?from=%2Fchats',
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => AuthScreen(
            redirectAfterLogin: state.uri.queryParameters['from'],
          ),
        ),
        GoRoute(
          path: '/chats',
          builder: (context, state) => const Text('chats-screen'),
        ),
        GoRoute(
          path: '/',
          builder: (context, state) => const Text('home-screen'),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(routerConfig: router),
    );

    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'user@test.dev');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    final submitButton = find.descendant(
      of: find.byType(Form),
      matching: find.widgetWithText(FilledButton, 'Войти'),
    );
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(authService.currentUserId, 'user-1');
    expect(find.text('chats-screen'), findsOneWidget);
    expect(find.text('home-screen'), findsNothing);
  });

  testWidgets('AuthScreen clears stale session banner on reauth input',
      (tester) async {
    final appStatusService = getIt<AppStatusService>();
    appStatusService.reportSessionExpired();

    await tester.pumpWidget(
      const MaterialApp(
        home: AuthScreen(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Сессия истекла. Войдите снова.'), findsOneWidget);
    expect(appStatusService.hasSessionIssue, isTrue);

    await tester.enterText(find.byType(TextFormField).at(0), 'user@test.dev');
    await tester.pump();

    expect(appStatusService.hasSessionIssue, isFalse);
    expect(find.text('Сессия истекла. Войдите снова.'), findsNothing);
  });
}
