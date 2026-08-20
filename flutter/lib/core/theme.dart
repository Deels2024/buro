import 'package:flutter/material.dart';

abstract final class BureauColors {
  static const blue = Color(0xFF1769FF);
  static const blueDark = Color(0xFF0D55E8);
  static const blueSoft = Color(0xFFEAF2FF);
  static const navy = Color(0xFF0B1F3A);
  static const slate = Color(0xFF64748B);
  static const muted = Color(0xFF98A4B7);
  static const line = Color(0xFFDCE4EE);
  static const canvas = Color(0xFFF4F7FB);
  static const webCanvas = Color(0xFFE8EEF7);
  static const green = Color(0xFF09A875);
  static const greenSoft = Color(0xFFE6F8F1);
  static const amber = Color(0xFFD98500);
  static const amberSoft = Color(0xFFFFF4DF);
  static const red = Color(0xFFE14655);
  static const redSoft = Color(0xFFFFF0F2);
}

abstract final class BureauTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: BureauColors.blue,
      brightness: Brightness.light,
      primary: BureauColors.blue,
      surface: Colors.white,
      error: BureauColors.red,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: BureauColors.canvas,
      splashFactory: InkSparkle.splashFactory,
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          color: BureauColors.navy,
          fontSize: 36,
          height: 1.05,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.3,
        ),
        headlineSmall: TextStyle(
          color: BureauColors.navy,
          fontSize: 26,
          height: 1.12,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.7,
        ),
        titleLarge: TextStyle(
          color: BureauColors.navy,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
        titleMedium: TextStyle(
          color: BureauColors.navy,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
        bodyLarge: TextStyle(
          color: BureauColors.navy,
          fontSize: 15,
          height: 1.45,
        ),
        bodyMedium: TextStyle(
          color: BureauColors.slate,
          fontSize: 13,
          height: 1.45,
        ),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: BureauColors.line),
          borderRadius: BorderRadius.circular(22),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: const TextStyle(color: BureauColors.muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 17,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: BureauColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: BureauColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: BureauColors.blue, width: 1.7),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: BureauColors.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: Colors.white,
        indicatorColor: BureauColors.blueSoft,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? BureauColors.blue
                : BureauColors.muted,
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
