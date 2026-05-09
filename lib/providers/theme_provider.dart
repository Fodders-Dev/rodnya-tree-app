import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-reported: «надо чтобы приложение не всегда брало тему с
/// телефона. Варианты — как в системе / светлая / тёмная».
///
/// Раньше провайдер при старте читал текущую platform brightness и
/// держал её как «дефолтное значение», а `setThemeMode` принудительно
/// нормализовал любой вход к light/dark. То есть `ThemeMode.system`
/// существовал только как enum-значение, но никогда не сохранялся.
/// Если телефон ночью переключался на dark — наша prefs-запись
/// «light» не работала; если днём — наоборот. Юзер был заперт в
/// чьём-то частном случае.
///
/// Теперь у нас три первоклассных режима:
///   * system — Material передаёт ThemeMode.system, Flutter сам
///     следит за `MediaQuery.platformBrightnessOf` и переключается
///     автоматически. Default для свежих установок.
///   * light  — всегда светлая.
///   * dark   — всегда тёмная.
///
/// Persist через SharedPreferences под ключом `theme_mode`. Старые
/// записи 'light' / 'dark' остаются совместимыми; отсутствие ключа
/// означает «system» (новый default).
class ThemeProvider extends ChangeNotifier {
  ThemeProvider({SharedPreferences? preferences})
      : _preferencesFuture = preferences != null
            ? Future.value(preferences)
            : SharedPreferences.getInstance() {
    _loadTask = _loadTheme();
  }

  final Future<SharedPreferences> _preferencesFuture;
  late final Future<void> _loadTask;
  // Default — `system`, чтобы свежий установщик сразу получал тему
  // как у системы. Если юзер уже настроил light/dark, _loadTheme
  // перетрёт это значение из prefs.
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;
  bool get isSystemMode => _themeMode == ThemeMode.system;
  bool get isExplicitDark => _themeMode == ThemeMode.dark;
  bool get isExplicitLight => _themeMode == ThemeMode.light;
  Future<void> get ready => _loadTask;

  static const String _prefsKey = 'theme_mode';

  /// Resolved brightness — что реально показывается на экране СЕЙЧАС.
  /// Для system-режима смотрим на текущий platform brightness через
  /// `MediaQuery.platformBrightnessOf(context)`. Полезно для UI
  /// селектора — показывать «как сейчас выглядит».
  Brightness resolvedBrightness(BuildContext context) {
    if (_themeMode == ThemeMode.dark) return Brightness.dark;
    if (_themeMode == ThemeMode.light) return Brightness.light;
    return MediaQuery.platformBrightnessOf(context);
  }

  Future<void> _loadTheme() async {
    final prefs = await _preferencesFuture;
    final stored = prefs.getString(_prefsKey);
    if (stored == null || stored.isEmpty) {
      return;
    }
    final loaded = _modeFromString(stored);
    if (loaded != _themeMode) {
      _themeMode = loaded;
      notifyListeners();
    }
  }

  ThemeMode _modeFromString(String value) {
    switch (value) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  String _stringFromMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'system';
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) {
      return;
    }
    _themeMode = mode;
    notifyListeners();

    final prefs = await _preferencesFuture;
    await prefs.setString(_prefsKey, _stringFromMode(mode));
  }

  /// Cycle through system → light → dark → system. Used by the
  /// quick-toggle button (legacy `toggleTheme` callers).
  Future<void> toggleTheme() async {
    ThemeMode next;
    switch (_themeMode) {
      case ThemeMode.system:
        next = ThemeMode.light;
        break;
      case ThemeMode.light:
        next = ThemeMode.dark;
        break;
      case ThemeMode.dark:
        next = ThemeMode.system;
        break;
    }
    await setThemeMode(next);
  }
}
