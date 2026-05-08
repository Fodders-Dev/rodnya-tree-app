import 'package:flutter/material.dart';

@immutable
class RodnyaDesignTokens extends ThemeExtension<RodnyaDesignTokens> {
  const RodnyaDesignTokens({
    required this.bgBase,
    required this.bgTintWarm,
    required this.bgTintSage,
    required this.bgTintHoney,
    required this.ink,
    required this.inkSecondary,
    required this.inkMuted,
    required this.inkLine,
    required this.accent,
    required this.accentStrong,
    required this.accentSoft,
    required this.accentInk,
    required this.warm,
    required this.warmSoft,
    required this.surface,
    required this.surfaceStrong,
    required this.surfaceLine,
    required this.radiusXs,
    required this.radiusSm,
    required this.radiusMd,
    required this.radiusLg,
  });

  // Profile Redesign tokens (teal accent + honey warm).
  // Source: docs/design_handoff/Profile Redesign.html design tokens, which
  // describe the canonical Rodnya palette. Earlier the app used a sage-green
  // accent; the redesign moves us to the teal-and-honey identity that the
  // hero gradient + brand work all build on.
  static const light = RodnyaDesignTokens(
    bgBase: Color(0xFFF3F5F1),
    bgTintWarm: Color(0xFFF9FBF8),
    bgTintSage: Color(0xFFEBF0EB),
    bgTintHoney: Color(0xFFF8E6B5),
    ink: Color(0xFF18201E),
    inkSecondary: Color(0xFF3D4845),
    inkMuted: Color(0xFF5B6863),
    inkLine: Color(0xFFD7DED9),
    accent: Color(0xFF129A8D),
    accentStrong: Color(0xFF0E857A),
    accentSoft: Color(0x1A129A8D),
    accentInk: Color(0xFFFFFFFF),
    warm: Color(0xFFC9A84C),
    warmSoft: Color(0x21C9A84C),
    surface: Color(0xFFFFFFFF),
    surfaceStrong: Color(0xFFFFFFFF),
    surfaceLine: Color(0xFFD7DED9),
    radiusXs: 8,
    radiusSm: 14,
    radiusMd: 18,
    radiusLg: 28,
  );

  static const dark = RodnyaDesignTokens(
    bgBase: Color(0xFF101513),
    bgTintWarm: Color(0xFF1B2320),
    bgTintSage: Color(0xFF26312D),
    bgTintHoney: Color(0xFF2A2418),
    ink: Color(0xFFF1F5F3),
    inkSecondary: Color(0xFFC8D4CF),
    inkMuted: Color(0xFFB2BDB8),
    inkLine: Color(0xFF33403B),
    accent: Color(0xFF65D4C6),
    accentStrong: Color(0xFF4CBDB0),
    accentSoft: Color(0x1F65D4C6),
    accentInk: Color(0xFF0A1816),
    warm: Color(0xFFD4A84C),
    warmSoft: Color(0x24D4A84C),
    surface: Color(0xFF161D1B),
    surfaceStrong: Color(0xFF1B2320),
    surfaceLine: Color(0xFF33403B),
    radiusXs: 8,
    radiusSm: 14,
    radiusMd: 18,
    radiusLg: 28,
  );

  final Color bgBase;
  final Color bgTintWarm;
  final Color bgTintSage;
  final Color bgTintHoney;
  final Color ink;
  final Color inkSecondary;
  final Color inkMuted;
  final Color inkLine;
  final Color accent;
  final Color accentStrong;
  final Color accentSoft;
  final Color accentInk;
  final Color warm;
  final Color warmSoft;
  final Color surface;
  final Color surfaceStrong;
  final Color surfaceLine;
  final double radiusXs;
  final double radiusSm;
  final double radiusMd;
  final double radiusLg;

  BorderRadius get cardRadius => BorderRadius.circular(radiusLg);
  BorderRadius get controlRadius => BorderRadius.circular(radiusMd);
  BorderRadius get chipRadius => BorderRadius.circular(999);

  LinearGradient get accentGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [accent, accentStrong],
      );

  List<BoxShadow> panelShadow(Brightness brightness, {bool floating = false}) {
    final isDark = brightness == Brightness.dark;
    return <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(
          alpha: isDark ? 0.34 : (floating ? 0.14 : 0.08),
        ),
        blurRadius: floating ? 34 : 26,
        spreadRadius: floating ? -12 : -16,
        offset: Offset(0, floating ? 18 : 10),
      ),
    ];
  }

  @override
  RodnyaDesignTokens copyWith({
    Color? bgBase,
    Color? bgTintWarm,
    Color? bgTintSage,
    Color? bgTintHoney,
    Color? ink,
    Color? inkSecondary,
    Color? inkMuted,
    Color? inkLine,
    Color? accent,
    Color? accentStrong,
    Color? accentSoft,
    Color? accentInk,
    Color? warm,
    Color? warmSoft,
    Color? surface,
    Color? surfaceStrong,
    Color? surfaceLine,
    double? radiusXs,
    double? radiusSm,
    double? radiusMd,
    double? radiusLg,
  }) {
    return RodnyaDesignTokens(
      bgBase: bgBase ?? this.bgBase,
      bgTintWarm: bgTintWarm ?? this.bgTintWarm,
      bgTintSage: bgTintSage ?? this.bgTintSage,
      bgTintHoney: bgTintHoney ?? this.bgTintHoney,
      ink: ink ?? this.ink,
      inkSecondary: inkSecondary ?? this.inkSecondary,
      inkMuted: inkMuted ?? this.inkMuted,
      inkLine: inkLine ?? this.inkLine,
      accent: accent ?? this.accent,
      accentStrong: accentStrong ?? this.accentStrong,
      accentSoft: accentSoft ?? this.accentSoft,
      accentInk: accentInk ?? this.accentInk,
      warm: warm ?? this.warm,
      warmSoft: warmSoft ?? this.warmSoft,
      surface: surface ?? this.surface,
      surfaceStrong: surfaceStrong ?? this.surfaceStrong,
      surfaceLine: surfaceLine ?? this.surfaceLine,
      radiusXs: radiusXs ?? this.radiusXs,
      radiusSm: radiusSm ?? this.radiusSm,
      radiusMd: radiusMd ?? this.radiusMd,
      radiusLg: radiusLg ?? this.radiusLg,
    );
  }

  @override
  RodnyaDesignTokens lerp(
    ThemeExtension<RodnyaDesignTokens>? other,
    double t,
  ) {
    if (other is! RodnyaDesignTokens) {
      return this;
    }
    double lerpDoubleValue(double a, double b) => a + (b - a) * t;

    return RodnyaDesignTokens(
      bgBase: Color.lerp(bgBase, other.bgBase, t)!,
      bgTintWarm: Color.lerp(bgTintWarm, other.bgTintWarm, t)!,
      bgTintSage: Color.lerp(bgTintSage, other.bgTintSage, t)!,
      bgTintHoney: Color.lerp(bgTintHoney, other.bgTintHoney, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkSecondary: Color.lerp(inkSecondary, other.inkSecondary, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      inkLine: Color.lerp(inkLine, other.inkLine, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentStrong: Color.lerp(accentStrong, other.accentStrong, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentInk: Color.lerp(accentInk, other.accentInk, t)!,
      warm: Color.lerp(warm, other.warm, t)!,
      warmSoft: Color.lerp(warmSoft, other.warmSoft, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceStrong: Color.lerp(surfaceStrong, other.surfaceStrong, t)!,
      surfaceLine: Color.lerp(surfaceLine, other.surfaceLine, t)!,
      radiusXs: lerpDoubleValue(radiusXs, other.radiusXs),
      radiusSm: lerpDoubleValue(radiusSm, other.radiusSm),
      radiusMd: lerpDoubleValue(radiusMd, other.radiusMd),
      radiusLg: lerpDoubleValue(radiusLg, other.radiusLg),
    );
  }
}

class AppTheme {
  // Profile Redesign palette — teal accent + honey warm. The
  // RodnyaDesignTokens above already use these values; the
  // legacy AppTheme.* constants stay in lockstep so widgets
  // pulling from either source render the same brand.
  static const Color accent = Color(0xFF129A8D);
  static const Color accentStrong = Color(0xFF0E857A);
  static const Color accentSoft = Color(0xFFE0F4F1);
  static const Color warmCanvas = Color(0xFFF3F5F1);
  static const Color warmSurface = Color(0xFFFFFFFF);
  static const Color warmLine = Color(0xFFD7DED9);
  static const Color warmText = Color(0xFF18201E);
  static const Color warmMuted = Color(0xFF5B6863);
  static const Color warm = Color(0xFFC9A84C);
  // Fallback chains list ONLY fonts we either bundle (Manrope, Lora) or that
  // every target browser ships with. Listing Noto entries triggers Flutter
  // web to issue "Could not find a set of Noto fonts" warnings every time a
  // glyph misses the active font, even though the warning is benign — keep
  // the chain Noto-free so the console stays clean.
  // Manrope first (bundled), then NotoSans (bundled, full Cyrillic / Symbol
  // coverage) so Flutter web does not try to lazy-fetch Noto from the CDN
  // and does not emit the "Could not find a set of Noto fonts" warning.
  // OS-installed fallbacks come after as belt-and-suspenders.
  static const List<String> _sansFallback = <String>[
    'Manrope',
    'NotoSans',
    'Segoe UI Variable Text',
    'Segoe UI',
    'system-ui',
    'Roboto',
    'Helvetica Neue',
    'Arial',
    'Apple Color Emoji',
    'Segoe UI Emoji',
    'sans-serif',
  ];

  static const List<String> _serifFallback = <String>[
    'Lora',
    'Georgia',
    'Cambria',
    'Times New Roman',
    'NotoSans',
    'serif',
  ];

  static const List<String> _fontFallback = _sansFallback;

  static TextStyle serif({
    Color? color,
    double fontSize = 22,
    FontWeight fontWeight = FontWeight.w600,
    double letterSpacing = -0.22,
    double? height,
  }) {
    return TextStyle(
      fontFamily: 'Lora',
      fontFamilyFallback: _serifFallback,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static TextStyle sans({
    Color? color,
    double fontSize = 15,
    FontWeight fontWeight = FontWeight.w500,
    double letterSpacing = -0.07,
    double? height,
  }) {
    return TextStyle(
      fontFamily: 'Manrope',
      fontFamilyFallback: _sansFallback,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static ThemeData get lightTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
    ).copyWith(
      primary: accentStrong,
      secondary: const Color(0xFF7F9C72),
      tertiary: accentSoft,
      surface: warmSurface,
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFFBF6EA),
      surfaceContainer: const Color(0xFFF3ECDB),
      surfaceContainerHigh: const Color(0xFFECE2CD),
      surfaceContainerHighest: const Color(0xFFE0D4BE),
      outline: warmLine,
      outlineVariant: const Color(0xFFE7DCC7),
      shadow: const Color(0xFF231B12),
      onSurface: warmText,
      onSurfaceVariant: warmMuted,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onTertiary: accentStrong,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: warmCanvas,
      canvasColor: warmCanvas,
      extensions: const <ThemeExtension<dynamic>>[
        RodnyaDesignTokens.light,
      ],
    );

    final textTheme = _withFontFallback(
      base.textTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
    );

    return base.copyWith(
      primaryColor: scheme.primary,
      textTheme: textTheme.copyWith(
        headlineSmall: textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        bodyLarge: textTheme.bodyLarge?.copyWith(height: 1.35),
        bodyMedium: textTheme.bodyMedium?.copyWith(height: 1.32),
        labelLarge: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface.withValues(alpha: 0.66),
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 18,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: RodnyaDesignTokens.light.surfaceStrong,
        margin: EdgeInsets.zero,
        elevation: 0,
        shadowColor: scheme.shadow.withValues(alpha: 0.06),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(
            color: RodnyaDesignTokens.light.surfaceLine,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(0, 46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 6,
        focusElevation: 8,
        hoverElevation: 8,
        highlightElevation: 10,
        shape: const CircleBorder(),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: scheme.surface.withValues(alpha: 0.72),
        selectedColor: scheme.primary.withValues(alpha: 0.18),
        disabledColor: scheme.surfaceContainerHighest,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        labelStyle: textTheme.labelLarge?.copyWith(color: scheme.onSurface),
        secondaryLabelStyle:
            textTheme.labelLarge?.copyWith(color: scheme.primary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        iconTheme: IconThemeData(size: 18, color: scheme.onSurfaceVariant),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.55),
        thickness: 0.7,
        space: 1,
      ),
      iconTheme: IconThemeData(color: scheme.onSurface, size: 22),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: RodnyaDesignTokens.light.surfaceStrong,
        hintStyle:
            textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide:
              BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide:
              BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: scheme.error),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF293327),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurfaceVariant,
        elevation: 0,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle:
            textTheme.labelMedium?.copyWith(color: scheme.primary),
        unselectedLabelTextStyle:
            textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      splashFactory: InkSparkle.splashFactory,
    );
  }

  static ThemeData get darkTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFF72D49D),
      secondary: const Color(0xFF93B889),
      tertiary: const Color(0xFF1D3B2A),
      surface: const Color(0xFF1C1812),
      surfaceContainerLowest: const Color(0xFF14110D),
      surfaceContainerLow: const Color(0xFF1A1610),
      surfaceContainer: const Color(0xFF221D16),
      surfaceContainerHigh: const Color(0xFF2C251A),
      surfaceContainerHighest: const Color(0xFF382E20),
      outline: const Color(0xFF564B3B),
      outlineVariant: const Color(0xFF3E3529),
      onSurface: const Color(0xFFF7F1E6),
      onSurfaceVariant: const Color(0xFFD1C7B8),
      onPrimary: const Color(0xFF102618),
      onSecondary: const Color(0xFF172612),
      onTertiary: const Color(0xFFEAF8E7),
      shadow: Colors.black,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: RodnyaDesignTokens.dark.bgBase,
      canvasColor: RodnyaDesignTokens.dark.bgBase,
      extensions: const <ThemeExtension<dynamic>>[
        RodnyaDesignTokens.dark,
      ],
    );

    final textTheme = _withFontFallback(
      base.textTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
    );

    return base.copyWith(
      primaryColor: scheme.primary,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface.withValues(alpha: 0.88),
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 18,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
          letterSpacing: 0,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: RodnyaDesignTokens.dark.surfaceStrong,
        margin: EdgeInsets.zero,
        elevation: 0,
        shadowColor: scheme.shadow.withValues(alpha: 0.16),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(0, 46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 6,
        shape: const CircleBorder(),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: scheme.surfaceContainerHigh.withValues(alpha: 0.92),
        selectedColor: scheme.primary.withValues(alpha: 0.2),
        disabledColor: scheme.surfaceContainerHighest,
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: textTheme.labelLarge?.copyWith(color: scheme.onSurface),
        secondaryLabelStyle:
            textTheme.labelLarge?.copyWith(color: scheme.primary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        iconTheme: IconThemeData(size: 18, color: scheme.onSurfaceVariant),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.9),
        thickness: 0.8,
        space: 1,
      ),
      iconTheme: IconThemeData(color: scheme.onSurface, size: 22),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow.withValues(alpha: 0.94),
        hintStyle:
            textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        labelStyle:
            textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: scheme.primary, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: scheme.error, width: 1.2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        contentTextStyle:
            textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
        actionTextColor: scheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurfaceVariant,
        elevation: 0,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle:
            textTheme.labelMedium?.copyWith(color: scheme.primary),
        unselectedLabelTextStyle:
            textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      splashFactory: InkSparkle.splashFactory,
    );
  }

  static TextTheme _withFontFallback(TextTheme textTheme) {
    TextStyle? apply(TextStyle? style) => style?.copyWith(
          fontFamily: 'Manrope',
          fontFamilyFallback: _fontFallback,
        );
    return textTheme.copyWith(
      displayLarge: apply(textTheme.displayLarge),
      displayMedium: apply(textTheme.displayMedium),
      displaySmall: apply(textTheme.displaySmall),
      headlineLarge: apply(textTheme.headlineLarge),
      headlineMedium: apply(textTheme.headlineMedium),
      headlineSmall: apply(textTheme.headlineSmall),
      titleLarge: apply(textTheme.titleLarge),
      titleMedium: apply(textTheme.titleMedium),
      titleSmall: apply(textTheme.titleSmall),
      bodyLarge: apply(textTheme.bodyLarge),
      bodyMedium: apply(textTheme.bodyMedium),
      bodySmall: apply(textTheme.bodySmall),
      labelLarge: apply(textTheme.labelLarge),
      labelMedium: apply(textTheme.labelMedium),
      labelSmall: apply(textTheme.labelSmall),
    );
  }
}
