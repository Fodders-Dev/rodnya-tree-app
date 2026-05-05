import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/screens/onboarding_screen.dart';
import 'package:rodnya/services/onboarding_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await OnboardingService.instance.reset();
  });

  Future<void> pumpOnboarding(
    WidgetTester tester, {
    VoidCallback? onFinish,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(onFinish: onFinish),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows welcome slide first with "Далее" CTA', (tester) async {
    await pumpOnboarding(tester);

    expect(find.text('Добро пожаловать в Родню'), findsOneWidget);
    expect(find.text('Далее'), findsOneWidget);
    expect(find.text('Пропустить'), findsOneWidget);
  });

  testWidgets('walking through all slides ends with "Начать" CTA',
      (tester) async {
    await pumpOnboarding(tester);

    // 5 slides total — first 4 use "Далее", last shows "Начать".
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Далее'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Начать'), findsOneWidget);
    expect(find.text('Пропустить'), findsNothing);
  });

  testWidgets('finishing the tour calls onFinish and marks seen',
      (tester) async {
    var finished = false;
    await pumpOnboarding(tester, onFinish: () => finished = true);

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Далее'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Начать'));
    await tester.pumpAndSettle();

    expect(finished, isTrue);
    expect(await OnboardingService.instance.hasSeen(), isTrue);
  });

  testWidgets('skipping the tour also marks seen', (tester) async {
    var finished = false;
    await pumpOnboarding(tester, onFinish: () => finished = true);

    await tester.tap(find.text('Пропустить'));
    await tester.pumpAndSettle();

    expect(finished, isTrue);
    expect(await OnboardingService.instance.hasSeen(), isTrue);
  });

  group('OnboardingService', () {
    test('starts as unseen', () async {
      expect(await OnboardingService.instance.hasSeen(), isFalse);
    });

    test('markSeen flips the flag, reset clears it', () async {
      await OnboardingService.instance.markSeen();
      expect(await OnboardingService.instance.hasSeen(), isTrue);
      await OnboardingService.instance.reset();
      expect(await OnboardingService.instance.hasSeen(), isFalse);
    });
  });
}
