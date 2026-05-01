import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

  static const light = RodnyaDesignTokens(
    bgBase: Color(0xFFF3ECDB),
    bgTintWarm: Color(0xFFF8F2E4),
    bgTintSage: Color(0xFFDDE8D2),
    bgTintHoney: Color(0xFFF2DB9A),
    ink: Color(0xFF293327),
    inkSecondary: Color(0xFF53624F),
    inkMuted: Color(0xFF778071),
    inkLine: Color(0x1F293327),
    accent: Color(0xFF3F8E52),
    accentStrong: Color(0xFF2F7644),
    accentSoft: Color(0x223F8E52),
    accentInk: Color(0xFFFFFFFF),
    warm: Color(0xFFD7A33A),
    warmSoft: Color(0x33D7A33A),
    surface: Color(0xA3FFFCF5),
    surfaceStrong: Color(0xE0FFFCF5),
    surfaceLine: Color(0x1F46381F),
    radiusXs: 10,
    radiusSm: 14,
    radiusMd: 20,
    radiusLg: 28,
  );

  static const dark = RodnyaDesignTokens(
    bgBase: Color(0xFF14110D),
    bgTintWarm: Color(0xFF352719),
    bgTintSage: Color(0xFF17342B),
    bgTintHoney: Color(0xFF302415),
    ink: Color(0xFFF7F1E6),
    inkSecondary: Color(0xFFD1C7B8),
    inkMuted: Color(0xFFA69B8C),
    inkLine: Color(0x1FF7F1E6),
    accent: Color(0xFF72D49D),
    accentStrong: Color(0xFF56B980),
    accentSoft: Color(0x2972D49D),
    accentInk: Color(0xFF102618),
    warm: Color(0xFFE3B75E),
    warmSoft: Color(0x2EE3B75E),
    surface: Color(0x8C1C1812),
    surfaceStrong: Color(0xD11C1812),
    surfaceLine: Color(0x1FF7F1E6),
    radiusXs: 10,
    radiusSm: 14,
    radiusMd: 20,
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
  static const Color accent = Color(0xFF3F8E52);
  static const Color accentStrong = Color(0xFF2F7644);
  static const Color accentSoft = Color(0xFFE4F0DF);
  static const Color warmCanvas = Color(0xFFF3ECDB);
  static const Color warmSurface = Color(0xFFFFFCF5);
  static const Color warmLine = Color(0xFFDDD3BE);
  static const Color warmText = Color(0xFF293327);
  static const Color warmMuted = Color(0xFF66715F);
  static const Color warm = Color(0xFFD7A33A);
  static const List<String> _fontFallback = <String>[
    'Segoe UI Variable Text',
    'Segoe UI',
    'Noto Sans',
    'Noto Sans Symbols 2',
    'Noto Sans Symbols',
    'Roboto',
    'Arial',
    'Arial Unicode MS',
    'Noto Emoji',
    'Segoe UI Emoji',
    'Apple Color Emoji',
    'Noto Color Emoji',
  ];

  static TextStyle serif({
    Color? color,
    double fontSize = 22,
    FontWeight fontWeight = FontWeight.w600,
    double letterSpacing = -0.22,
    double? height,
  }) {
    return GoogleFonts.lora(
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
    return GoogleFonts.manrope(
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
    final base = GoogleFonts.manropeTextTheme(textTheme);
    TextStyle? withFallback(TextStyle? style) =>
        style?.copyWith(fontFamilyFallback: _fontFallback);
    return base.copyWith(
      displayLarge: withFallback(base.displayLarge),
      displayMedium: withFallback(base.displayMedium),
      displaySmall: withFallback(base.displaySmall),
      headlineLarge: withFallback(base.headlineLarge),
      headlineMedium: withFallback(base.headlineMedium),
      headlineSmall: withFallback(base.headlineSmall),
      titleLarge: withFallback(base.titleLarge),
      titleMedium: withFallback(base.titleMedium),
      titleSmall: withFallback(base.titleSmall),
      bodyLarge: withFallback(base.bodyLarge),
      bodyMedium: withFallback(base.bodyMedium),
      bodySmall: withFallback(base.bodySmall),
      labelLarge: withFallback(base.labelLarge),
      labelMedium: withFallback(base.labelMedium),
      labelSmall: withFallback(base.labelSmall),
    );
  }
}
