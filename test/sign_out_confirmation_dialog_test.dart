// Ship Q3 (2026-05-26): confirmation dialog для sign-out. Tests
// verify dialog renders identity, surfaces Отмена/Выйти, и returns
// correct decision к caller.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/auth_service_interface.dart';
import 'package:rodnya/widgets/sign_out_confirmation_dialog.dart';

class _FakeAuthService implements AuthServiceInterface {
  _FakeAuthService({
    String? displayName,
    String? email,
    String? photoUrl,
  })  : currentUserDisplayName = displayName,
        currentUserEmail = email,
        currentUserPhotoUrl = photoUrl;

  @override
  final String? currentUserDisplayName;

  @override
  final String? currentUserEmail;

  @override
  final String? currentUserPhotoUrl;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  testWidgets('renders displayName + email + Отмена/Выйти buttons',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SignOutConfirmationDialog(
            displayName: 'Артём Кузнецов',
            email: 'artem@example.com',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Выйти из аккаунта?'), findsOneWidget);
    expect(find.text('Артём Кузнецов'), findsOneWidget);
    expect(find.text('artem@example.com'), findsOneWidget);
    expect(find.text('Отмена'), findsOneWidget);
    expect(find.text('Выйти'), findsOneWidget);
  });

  testWidgets('falls back to «Текущий аккаунт» when displayName empty',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SignOutConfirmationDialog(
            displayName: null,
            email: 'artem@example.com',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Текущий аккаунт'), findsOneWidget);
    expect(find.text('artem@example.com'), findsOneWidget);
  });

  testWidgets('Cancel button pops dialog with false', (tester) async {
    bool? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  popped = await showSignOutConfirmationDialog(
                    context,
                    _FakeAuthService(
                      displayName: 'Артём',
                      email: 'a@b.com',
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
    expect(find.text('Выйти из аккаунта?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sign-out-cancel')));
    await tester.pumpAndSettle();
    expect(popped, isFalse);
  });

  testWidgets('Confirm button pops dialog with true', (tester) async {
    bool? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  popped = await showSignOutConfirmationDialog(
                    context,
                    _FakeAuthService(
                      displayName: 'Артём',
                      email: 'a@b.com',
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
    await tester.tap(find.byKey(const Key('sign-out-confirm')));
    await tester.pumpAndSettle();
    expect(popped, isTrue);
  });

  testWidgets('barrierDismissible=false — outside tap не закрывает',
      (tester) async {
    bool? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  popped = await showSignOutConfirmationDialog(
                    context,
                    _FakeAuthService(),
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
    // Tap outside the dialog (on barrier).
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    // Dialog still visible (barrier didn't dismiss).
    expect(find.text('Выйти из аккаунта?'), findsOneWidget);
    expect(popped, isNull);
  });
}
