import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/widgets/startup_failure_view.dart';

void main() {
  testWidgets('StartupFailureView keeps technical details collapsed by default',
      (tester) async {
    var retried = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StartupFailureView(
            title: 'Не удалось открыть Родню',
            message: 'Попробуйте ещё раз позже.',
            technicalDetails: 'Stack trace line 1',
            onRetry: () async {
              retried = true;
            },
          ),
        ),
      ),
    );

    expect(find.text('Не удалось открыть Родню'), findsOneWidget);
    expect(find.text('Попробуйте ещё раз позже.'), findsOneWidget);
    expect(find.text('Stack trace line 1'), findsNothing);

    await tester.tap(find.text('Попробовать снова'));
    await tester.pumpAndSettle();

    expect(retried, isTrue);
  });

  testWidgets(
      'StartupFailureView shows session reset action and details when enabled',
      (tester) async {
    var resetCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StartupFailureView(
            title: 'Не удалось открыть Родню',
            message: 'Старая сессия больше не подходит.',
            technicalDetails: 'CustomApiException: unauthorized',
            showTechnicalDetails: true,
            onRetry: () async {},
            onResetSessionAndRetry: () async {
              resetCalled = true;
            },
          ),
        ),
      ),
    );

    expect(find.text('Сбросить сессию и войти заново'), findsOneWidget);
    expect(find.text('Технические детали'), findsOneWidget);

    await tester.tap(find.text('Технические детали'));
    await tester.pumpAndSettle();
    expect(find.text('CustomApiException: unauthorized'), findsOneWidget);

    await tester.tap(find.text('Сбросить сессию и войти заново'));
    await tester.pumpAndSettle();
    expect(resetCalled, isTrue);
  });
}
