import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeProvider({
    SharedPreferences? preferences,
    Brightness? initialPlatformBrightness,
  })  : _preferencesFuture = preferences != null
            ? Future.value(preferences)
            : SharedPreferences.getInstance(),
        _fallbackThemeMode = _themeModeFromBrightness(
          initialPlatformBrightness ??
              PlatformDispatcher.instance.platformBrightness,
        ),
        _themeMode = _themeModeFromBrightness(
          initialPlatformBrightness ??
              PlatformDispatcher.instance.platformBrightness,
        ) {
    _loadTask = _loadTheme();
  }

  final Future<SharedPreferences> _preferencesFuture;
  final ThemeMode _fallbackThemeMode;
  late final Future<void> _loadTask;
  ThemeMode _themeMode;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  Future<void> get ready => _loadTask;

  // Загрузка сохраненной темы
  Future<void> _loadTheme() async {
    final prefs = await _preferencesFuture;
    final themeName = prefs.getString('theme_mode');
    if (themeName == null || themeName.isEmpty) {
      return;
    }

    final loadedThemeMode = _getThemeFromString(themeName);
    final normalizedThemeName = _themeNameFromMode(loadedThemeMode);

    if (_themeMode != loadedThemeMode) {
      _themeMode = loadedThemeMode;
      notifyListeners();
    }

    if (normalizedThemeName != themeName) {
      await prefs.setString('theme_mode', normalizedThemeName);
    }
  }

  // Преобразование строки в ThemeMode
  ThemeMode _getThemeFromString(String themeName) {
    switch (themeName) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return _fallbackThemeMode;
    }
  }

  static ThemeMode _themeModeFromBrightness(Brightness brightness) {
    return brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
  }

  String _themeNameFromMode(ThemeMode mode) {
    return mode == ThemeMode.dark ? 'dark' : 'light';
  }

  // Сохранение и установка темы
  Future<void> setThemeMode(ThemeMode mode) async {
    final normalizedMode =
        mode == ThemeMode.dark ? ThemeMode.dark : ThemeMode.light;
    if (_themeMode == normalizedMode) {
      return;
    }

    _themeMode = normalizedMode;
    notifyListeners();

    final prefs = await _preferencesFuture;
    final themeName = _themeNameFromMode(normalizedMode);
    await prefs.setString('theme_mode', themeName);
  }

  // Переключение между темной и светлой темой
  Future<void> toggleTheme() async {
    await setThemeMode(isDarkMode ? ThemeMode.light : ThemeMode.dark);
  }
}
