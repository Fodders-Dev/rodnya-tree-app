import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/providers/theme_provider.dart';
import 'package:rodnya/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('ThemeProvider defaults to ThemeMode.system when no prefs are stored',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final provider = ThemeProvider(preferences: preferences);

    await provider.ready;

    expect(provider.themeMode, ThemeMode.system);
    expect(provider.isSystemMode, isTrue);
    expect(provider.isExplicitDark, isFalse);
    expect(provider.isExplicitLight, isFalse);
  });

  test('ThemeProvider loads ThemeMode.dark from prefs', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
    final preferences = await SharedPreferences.getInstance();
    final provider = ThemeProvider(preferences: preferences);

    await provider.ready;

    expect(provider.themeMode, ThemeMode.dark);
    expect(provider.isExplicitDark, isTrue);
  });

  test('ThemeProvider loads ThemeMode.light from prefs', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'light'});
    final preferences = await SharedPreferences.getInstance();
    final provider = ThemeProvider(preferences: preferences);

    await provider.ready;

    expect(provider.themeMode, ThemeMode.light);
    expect(provider.isExplicitLight, isTrue);
  });

  test('ThemeProvider treats stored "system" as first-class ThemeMode.system',
      () async {
    // После 249184e (три первоклассных режима) 'system' — не legacy,
    // а полноценный mode. Раньше был «migrate to dark by platform
    // brightness» — выпилен.
    SharedPreferences.setMockInitialValues({'theme_mode': 'system'});
    final preferences = await SharedPreferences.getInstance();
    final provider = ThemeProvider(preferences: preferences);

    await provider.ready;

    expect(provider.themeMode, ThemeMode.system);
    expect(provider.isSystemMode, isTrue);
    expect(preferences.getString('theme_mode'), 'system');
  });

  test('setThemeMode persists value and notifies listeners', () async {
    final preferences = await SharedPreferences.getInstance();
    final provider = ThemeProvider(preferences: preferences);
    await provider.ready;

    var notifyCount = 0;
    provider.addListener(() => notifyCount += 1);

    await provider.setThemeMode(ThemeMode.dark);

    expect(provider.themeMode, ThemeMode.dark);
    expect(preferences.getString('theme_mode'), 'dark');
    expect(notifyCount, 1);

    // Idempotent — same mode again must NOT re-notify or rewrite.
    await provider.setThemeMode(ThemeMode.dark);
    expect(notifyCount, 1);
  });

  test('toggleTheme cycles system → light → dark → system', () async {
    final preferences = await SharedPreferences.getInstance();
    final provider = ThemeProvider(preferences: preferences);
    await provider.ready;

    expect(provider.themeMode, ThemeMode.system);

    await provider.toggleTheme();
    expect(provider.themeMode, ThemeMode.light);
    expect(preferences.getString('theme_mode'), 'light');

    await provider.toggleTheme();
    expect(provider.themeMode, ThemeMode.dark);
    expect(preferences.getString('theme_mode'), 'dark');

    await provider.toggleTheme();
    expect(provider.themeMode, ThemeMode.system);
    expect(preferences.getString('theme_mode'), 'system');
  });

  testWidgets(
      'resolvedBrightness returns explicit Brightness for dark/light modes regardless of platform',
      (tester) async {
    final preferences = await SharedPreferences.getInstance();
    final provider = ThemeProvider(preferences: preferences);
    await provider.ready;
    await provider.setThemeMode(ThemeMode.dark);

    Brightness? captured;
    await tester.pumpWidget(
      MediaQuery(
        // Platform = light, but explicit mode = dark must win.
        data: const MediaQueryData(platformBrightness: Brightness.light),
        child: Builder(
          builder: (context) {
            captured = provider.resolvedBrightness(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(captured, Brightness.dark);

    await provider.setThemeMode(ThemeMode.light);
    captured = null;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(platformBrightness: Brightness.dark),
        child: Builder(
          builder: (context) {
            captured = provider.resolvedBrightness(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(captured, Brightness.light);
  });

  testWidgets(
      'resolvedBrightness in system mode follows MediaQuery.platformBrightness',
      (tester) async {
    final preferences = await SharedPreferences.getInstance();
    final provider = ThemeProvider(preferences: preferences);
    await provider.ready;
    expect(provider.isSystemMode, isTrue);

    Brightness? captured;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(platformBrightness: Brightness.dark),
        child: Builder(
          builder: (context) {
            captured = provider.resolvedBrightness(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(captured, Brightness.dark);

    captured = null;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(platformBrightness: Brightness.light),
        child: Builder(
          builder: (context) {
            captured = provider.resolvedBrightness(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(captured, Brightness.light);
  });

  test('AppTheme keeps app bars readable in dark theme', () {
    final background = AppTheme.darkTheme.appBarTheme.backgroundColor;

    expect(background, isNotNull);
    expect(background!.a, greaterThan(0));
  });

  test('AppTheme keeps app bars readable in light theme', () {
    final background = AppTheme.lightTheme.appBarTheme.backgroundColor;

    expect(background, isNotNull);
    expect(background!.a, greaterThan(0));
  });
}
