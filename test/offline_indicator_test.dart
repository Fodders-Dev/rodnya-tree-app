import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:rodnya/services/app_status_service.dart';
import 'package:rodnya/widgets/offline_indicator.dart';

void main() {
  final getIt = GetIt.I;

  setUp(() async {
    await getIt.reset();
    getIt.registerSingleton<AppStatusService>(AppStatusService());
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets(
    'OfflineIndicator stays hidden when there is no visible app status',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OfflineIndicator(),
          ),
        ),
      );

      expect(find.byType(OfflineIndicator), findsOneWidget);
      expect(find.text('Повторить'), findsNothing);
      expect(find.byType(SizedBox), findsWidgets);
    },
  );

  testWidgets(
    'OfflineIndicator shows retry banner for retryable service issues',
    (tester) async {
      final appStatusService = getIt<AppStatusService>();
      appStatusService.reportServiceIssue('Не удалось обновить чат.');

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OfflineIndicator(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Не удалось обновить чат.'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Повторить'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Повторить'));
      await tester.pump();

      expect(appStatusService.retryToken, 1);
      expect(find.text('Не удалось обновить чат.'), findsNothing);
    },
  );
}
