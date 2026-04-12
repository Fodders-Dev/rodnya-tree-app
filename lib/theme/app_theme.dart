import 'package:flutter/material.dart';

// Цветовая схема в стиле WhatsApp, но теплее
// final Color primaryColor = Color(0xFF0C6E4E);  // Теплый темно-зеленый
// final Color accentColor = Color(0xFF25A36F);   // Теплый зеленый
// final Color lightGreen = Color(0xFF3DD182);    // Яркий зеленый
// final Color lightBackground = Color(0xFFF5F2E3); // Теплый светлый фон (желтоватый)
// final Color chatBubbleColor = Color(0xFFE6F7D4); // Теплый цвет сообщений
// final Color darkerBackground = Color(0xFFEEEAD9); // Альтернативный теплый фон

// <<< УБИРАЕМ СТАРУЮ appTheme >>>
// final ThemeData appTheme = ThemeData(
// ... (весь старый код темы)
// );

class AppTheme {
  // Цвета WhatsApp (приблизительные)
  static const Color waGreen = Color(
    0xFF128C7E,
  ); // Основной зеленый для светлой темы
  static const Color waLightGreen = Color(0xFF25D366); // Акцентный зеленый
  static const Color waBlue = Color(0xFF34B7F1); // Цвет ссылок
  static const Color waLightBg = Color(0xFFFFFFFF); // Белый фон
  static const Color waLightSurface = Color(0xFFFFFFFF); // Белый для карточек

  static const Color waDarkGreen = Color(
    0xFF00A884,
  ); // Основной/Акцентный зеленый для темной темы
  static const Color waDarkBg = Color(0xFF111B21); // Темно-сине-серый фон
  static const Color waDarkSurface = Color(
    0xFF202C33,
  ); // Темно-серый для карточек

  static final TextTheme _lightTextTheme = ThemeData.light()
      .textTheme
      .apply(
        bodyColor: Colors.black,
        displayColor: Colors.black,
      )
      .copyWith(
        titleLarge: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 18,
          color: Colors.black,
        ),
        titleMedium: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          color: Colors.black,
        ),
        bodySmall: const TextStyle(
          fontSize: 12,
          color: Colors.black87,
        ),
      );

  static final TextTheme _darkTextTheme = ThemeData.dark()
      .textTheme
      .apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      )
      .copyWith(
        titleLarge: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 18,
          color: Colors.white,
        ),
        titleMedium: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          color: Colors.white,
        ),
        bodySmall: const TextStyle(
          fontSize: 12,
          color: Colors.white60,
        ),
      );

  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    primaryColor: waGreen,
    colorScheme: const ColorScheme.light(
      primary: waGreen, // Основной цвет элементов управления, AppBar
      secondary: waLightGreen, // Фон Scaffold
      surface: waLightSurface, // Фон карточек, диалогов
      onPrimary: Colors.white, // Текст/иконки на primary цвете
      onSecondary: Colors.white, // Основной цвет текста
      onSurface: Colors.black87, // Цвет текста на карточках/диалогах
      error: Colors.redAccent,
      onError: Colors.white,
    ),
    iconTheme: const IconThemeData(
      color: Colors.black87, // Гарантируем видимость иконок в светлой теме
      size: 24,
    ),
    primaryIconTheme: const IconThemeData(
      color: Colors.white, // Иконки на фоне primary ( AppBar и т.д.)
    ),
    scaffoldBackgroundColor: waLightBg,
    appBarTheme: AppBarTheme(
      backgroundColor: waGreen,
      foregroundColor: Colors.white, // Цвет текста и иконок в AppBar
      elevation: 1.0, // Небольшая тень как в WA
      titleTextStyle: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w500,
      ),
    ),
    textTheme: _lightTextTheme,
    cardTheme: CardThemeData(
      color: waLightSurface,
      elevation: 1,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ), // Менее скругленные углы
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: waLightGreen,
      foregroundColor: Colors.white,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.grey[200], // Сделали фон поля чуть темнее для контраста
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none, // Без рамки по умолчанию
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: waGreen, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: const TextStyle(
        color: Colors.black45, // Более видимый серый для подсказок
        fontWeight: FontWeight.w400,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: waGreen, // Основной цвет кнопки
        foregroundColor: Colors.white, // Цвет текста на кнопке
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: waGreen, // Цвет текста для TextButton
      ),
    ),
    dividerTheme: DividerThemeData(color: Colors.grey.shade300, thickness: 0.5),
    // Можно добавить другие настройки: bottomNavigationBarTheme, tabBarTheme и т.д.
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: waLightSurface,
      selectedItemColor: waGreen,
      unselectedItemColor: Colors.grey.shade600,
      type: BottomNavigationBarType.fixed,
      elevation: 4,
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: waDarkGreen,
    colorScheme: const ColorScheme.dark(
      primary: waDarkGreen, // Основной цвет элементов управления, AppBar
      secondary: waDarkGreen, // Фон Scaffold
      surface: waDarkSurface, // Фон карточек, диалогов
      onPrimary: Colors.white, // Текст/иконки на primary цвете
      onSecondary: Colors.white, // Основной цвет текста - сделали ярче
      onSurface: Colors.white, // Цвет текста на карточках/диалогах
      error: Colors.redAccent,
      onError: Colors.black,
    ),
    iconTheme: const IconThemeData(
      color: Colors.white, // Гарантируем видимость иконок в темной теме
      size: 24,
    ),
    primaryIconTheme: const IconThemeData(
      color: Colors.white,
    ),
    scaffoldBackgroundColor: waDarkBg,
    appBarTheme: AppBarTheme(
      backgroundColor: waDarkSurface, // В темной теме WA AppBar не зеленый
      foregroundColor:
          Colors.white, // Цвет текста и иконок в AppBar - сделали ярче
      elevation: 1.0,
      titleTextStyle: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w500,
        color: Colors.white,
      ),
    ),
    textTheme: _darkTextTheme,
    cardTheme: CardThemeData(
      color: waDarkSurface,
      elevation: 1,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: waDarkGreen,
      foregroundColor: Colors.white,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.grey[900], // Темно-серый фон поля ввода
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none, // Без рамки по умолчанию
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: waDarkGreen, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle:
          TextStyle(color: Colors.white38), // Видимый, но ненавязчивый хинт
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: waDarkGreen, // Основной цвет кнопки
        foregroundColor: Colors.white, // Цвет текста на кнопке
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: waDarkGreen, // Цвет текста для TextButton
      ),
    ),
    dividerTheme: DividerThemeData(color: Colors.grey.shade700, thickness: 0.5),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: waDarkSurface,
      selectedItemColor: waDarkGreen,
      unselectedItemColor: Colors.grey.shade500,
      type: BottomNavigationBarType.fixed,
      elevation: 4,
    ),
  );
}
