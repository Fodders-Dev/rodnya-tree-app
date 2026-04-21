import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:rodnya/backend/interfaces/auth_service_interface.dart';
import 'package:rodnya/screens/password_reset_screen.dart';

class _FakeAuthService implements AuthServiceInterface {
  String? lastResetEmail;

  @override
  Future<void> resetPassword(String email) async {
    lastResetEmail = email;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final getIt = GetIt.instance;

  setUp(() async {
    await getIt.reset();
    getIt.registerSingleton<AuthServiceInterface>(_FakeAuthService());
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('PasswordResetScreen shows compact reset flow', (tester) async {
    final authService = getIt<AuthServiceInterface>() as _FakeAuthService;

    await tester.pumpWidget(
      const MaterialApp(
        home: PasswordResetScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Сброс пароля'), findsWidgets);
    expect(find.text('Письмо придёт на ваш email.'), findsOneWidget);
    expect(find.text('Отправить'), findsOneWidget);

    await tester.enterText(
      find.bySemanticsLabel('Email'),
      'user@test.dev',
    );
    await tester.tap(find.text('Отправить'));
    await tester.pumpAndSettle();

    expect(authService.lastResetEmail, 'user@test.dev');
    expect(find.text('Ссылка отправлена.'), findsOneWidget);
    expect(find.text('К входу'), findsOneWidget);
  });
}
