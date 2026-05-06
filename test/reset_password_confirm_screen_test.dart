import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:rodnya/backend/interfaces/auth_service_interface.dart';
import 'package:rodnya/screens/reset_password_confirm_screen.dart';

class _ConfirmCall {
  const _ConfirmCall({required this.token, required this.newPassword});
  final String token;
  final String newPassword;
}

class _RecordingAuthService implements AuthServiceInterface {
  final List<_ConfirmCall> confirmCalls = <_ConfirmCall>[];
  Object? throwOnConfirm;

  @override
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) async {
    confirmCalls.add(_ConfirmCall(token: token, newPassword: newPassword));
    if (throwOnConfirm != null) {
      throw throwOnConfirm!;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final getIt = GetIt.instance;

  setUp(() async {
    await getIt.reset();
    getIt.registerSingleton<AuthServiceInterface>(_RecordingAuthService());
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets(
    'ResetPasswordConfirmScreen rejects too-short password without burning the token',
    (tester) async {
      final auth = getIt<AuthServiceInterface>() as _RecordingAuthService;

      await tester.pumpWidget(
        const MaterialApp(
          home: ResetPasswordConfirmScreen(token: 'good-token-here'),
        ),
      );
      await tester.pumpAndSettle();

      // Title + subtitle render.
      expect(find.text('Установите новый пароль'), findsOneWidget);

      // Type 6 chars (below minimum) → validation kicks in, no API call.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Новый пароль'),
        'short1',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Повторите пароль'),
        'short1',
      );
      await tester.tap(find.text('Сохранить пароль'));
      await tester.pumpAndSettle();

      expect(find.text('Минимум 8 символов'), findsOneWidget);
      expect(auth.confirmCalls, isEmpty,
          reason: 'short-password attempt must NOT burn the token');
    },
  );

  testWidgets(
    'ResetPasswordConfirmScreen rejects mismatched confirm field',
    (tester) async {
      final auth = getIt<AuthServiceInterface>() as _RecordingAuthService;

      await tester.pumpWidget(
        const MaterialApp(
          home: ResetPasswordConfirmScreen(token: 'good-token-here'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Новый пароль'),
        'a-strong-password-1',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Повторите пароль'),
        'totally-different-pw',
      );
      await tester.tap(find.text('Сохранить пароль'));
      await tester.pumpAndSettle();

      expect(find.text('Пароли не совпадают'), findsOneWidget);
      expect(auth.confirmCalls, isEmpty);
    },
  );

  testWidgets(
    'ResetPasswordConfirmScreen forwards token + password to confirmPasswordReset on valid submit',
    (tester) async {
      final auth = getIt<AuthServiceInterface>() as _RecordingAuthService;

      await tester.pumpWidget(
        const MaterialApp(
          home: ResetPasswordConfirmScreen(token: 'goodtoken'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Новый пароль'),
        'a-strong-password-1',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Повторите пароль'),
        'a-strong-password-1',
      );
      await tester.tap(find.text('Сохранить пароль'));
      await tester.pump(); // Trigger the async submit
      await tester.pump();

      expect(auth.confirmCalls.length, 1);
      expect(auth.confirmCalls.first.token, 'goodtoken');
      expect(auth.confirmCalls.first.newPassword, 'a-strong-password-1');
    },
  );

  testWidgets(
    'ResetPasswordConfirmScreen surfaces a generic error on backend failure (no leak of which failure mode)',
    (tester) async {
      final auth = getIt<AuthServiceInterface>() as _RecordingAuthService;
      auth.throwOnConfirm = Exception('CustomApiException(token expired)');

      await tester.pumpWidget(
        const MaterialApp(
          home: ResetPasswordConfirmScreen(token: 'expired-token'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Новый пароль'),
        'a-strong-password-1',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Повторите пароль'),
        'a-strong-password-1',
      );
      await tester.tap(find.text('Сохранить пароль'));
      await tester.pumpAndSettle();

      // Generic "ссылка недействительна или истекла" — same UX for
      // bogus / replayed / expired token. Don't leak which.
      expect(
        find.textContaining('Ссылка недействительна или истекла'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'ResetPasswordConfirmScreen with empty token shows actionable error before submit',
    (tester) async {
      final auth = getIt<AuthServiceInterface>() as _RecordingAuthService;

      await tester.pumpWidget(
        const MaterialApp(
          home: ResetPasswordConfirmScreen(token: ''),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Новый пароль'),
        'a-strong-password-1',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Повторите пароль'),
        'a-strong-password-1',
      );
      await tester.tap(find.text('Сохранить пароль'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('В ссылке не оказалось токена'),
        findsOneWidget,
      );
      expect(auth.confirmCalls, isEmpty);
    },
  );
}
