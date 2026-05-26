// Ship Bug B (2026-05-26): cross-provider email collision frontend
// surface. Tests cover:
//   • EmailProviderMismatch.fromJson parses 409 body
//   • Dialog renders provider buttons + cancel
//   • Dialog returns picked provider value к caller
//   • Dialog returns null on cancel

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/models/email_provider_mismatch.dart';
import 'package:rodnya/widgets/email_provider_mismatch_dialog.dart';

void main() {
  group('EmailProviderMismatch.fromJson', () {
    test('parses 409 body с full shape', () {
      final result = EmailProviderMismatch.fromJson({
        'error': 'EMAIL_PROVIDER_MISMATCH',
        'email': 'user@example.com',
        'existingProviders': ['password', 'google'],
        'message': 'Уже привязан',
      });
      expect(result, isNotNull);
      expect(result!.email, 'user@example.com');
      expect(result.existingProviders, ['password', 'google']);
      expect(result.message, 'Уже привязан');
    });

    test('returns null когда error code не matches', () {
      final result = EmailProviderMismatch.fromJson({
        'error': 'EMAIL_ALREADY_EXISTS',
        'email': 'user@example.com',
      });
      expect(result, isNull);
    });

    test('defensive empty list when existingProviders malformed', () {
      final result = EmailProviderMismatch.fromJson({
        'error': 'EMAIL_PROVIDER_MISMATCH',
        'email': 'user@example.com',
        'existingProviders': 'not-a-list',
      });
      expect(result, isNotNull);
      expect(result!.existingProviders, isEmpty);
    });

    test('skips empty string providers', () {
      final result = EmailProviderMismatch.fromJson({
        'error': 'EMAIL_PROVIDER_MISMATCH',
        'email': 'x@y.z',
        'existingProviders': ['google', '', 'vk'],
      });
      expect(result!.existingProviders, ['google', 'vk']);
    });
  });

  group('EmailProviderMismatchDialog widget', () {
    testWidgets('renders email + button per existing provider',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmailProviderMismatchDialog(
              payload: EmailProviderMismatch(
                email: 'user@example.com',
                existingProviders: ['password', 'google'],
                message: 'Уже привязан',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Этот email уже используется'), findsOneWidget);
      expect(find.text('user@example.com'), findsOneWidget);
      expect(find.text('Уже привязан'), findsOneWidget);
      expect(find.text('Войти через Email и пароль'), findsOneWidget);
      expect(find.text('Войти через Google'), findsOneWidget);
      expect(find.text('Отмена'), findsOneWidget);
    });

    testWidgets('renders VK ID + Telegram + MAX labels', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmailProviderMismatchDialog(
              payload: EmailProviderMismatch(
                email: 'a@b.c',
                existingProviders: ['vk', 'telegram', 'max'],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Войти через VK ID'), findsOneWidget);
      expect(find.text('Войти через Telegram'), findsOneWidget);
      expect(find.text('Войти через MAX'), findsOneWidget);
    });

    testWidgets('falls back на default text когда message empty',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmailProviderMismatchDialog(
              payload: EmailProviderMismatch(
                email: 'a@b.c',
                existingProviders: ['google'],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Войдите тем способом, который'),
        findsOneWidget,
      );
    });

    testWidgets('Cancel button pops dialog с null', (tester) async {
      String? picked = 'sentinel';
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    picked = await showEmailProviderMismatchDialog(
                      context,
                      const EmailProviderMismatch(
                        email: 'a@b.c',
                        existingProviders: ['google'],
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('email-provider-mismatch-cancel')));
      await tester.pumpAndSettle();
      expect(picked, isNull);
    });

    testWidgets('Provider button pops dialog с provider name',
        (tester) async {
      String? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    picked = await showEmailProviderMismatchDialog(
                      context,
                      const EmailProviderMismatch(
                        email: 'a@b.c',
                        existingProviders: ['password', 'google'],
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('email-provider-mismatch-pick-google')));
      await tester.pumpAndSettle();
      expect(picked, 'google');
    });
  });
}
