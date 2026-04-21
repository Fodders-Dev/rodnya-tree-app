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

  test('ThemeProvider defaults to dark when device brightness is dark',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final provider = ThemeProvider(
      preferences: preferences,
      initialPlatformBrightness: Brightness.dark,
    );

    await provider.ready;

    expect(provider.themeMode, ThemeMode.dark);
    expect(provider.isDarkMode, isTrue);
  });

  test('ThemeProvider migrates legacy system mode to effective dark mode',
      () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'system'});
    final preferences = await SharedPreferences.getInstance();
    final provider = ThemeProvider(
      preferences: preferences,
      initialPlatformBrightness: Brightness.dark,
    );

    await provider.ready;

    expect(provider.themeMode, ThemeMode.dark);
    expect(provider.isDarkMode, isTrue);
    expect(preferences.getString('theme_mode'), 'dark');
  });

  test('ThemeProvider toggle switches dark mode off in one tap', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
    final preferences = await SharedPreferences.getInstance();
    final provider = ThemeProvider(
      preferences: preferences,
      initialPlatformBrightness: Brightness.dark,
    );

    await provider.ready;
    await provider.toggleTheme();

    expect(provider.themeMode, ThemeMode.light);
    expect(provider.isDarkMode, isFalse);
    expect(preferences.getString('theme_mode'), 'light');
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
