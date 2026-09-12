import 'package:flutter/material.dart';

abstract final class BureauColors {
  static const blue = Color(0xFF245EE8);
  static const blueDark = Color(0xFF174BC3);
  static const blueSoft = Color(0xFFECF2FF);
  static const navy = Color(0xFF152B40);
  static const slate = Color(0xFF526477);
  static const muted = Color(0xFF68788B);
  static const line = Color(0xFFDFE7EE);
  static const canvas = Color(0xFFF7F9FC);
  static const webCanvas = Color(0xFFEDF1F6);
  static const green = Color(0xFF087F64);
  static const greenSoft = Color(0xFFEAF6F0);
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
      fontFamily: 'BureauSans',
      splashFactory: InkSparkle.splashFactory,
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          color: BureauColors.navy,
          fontSize: 32,
          height: 1.16,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
        ),
        headlineSmall: TextStyle(
          color: BureauColors.navy,
          fontSize: 26,
          height: 1.22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          color: BureauColors.navy,
          fontSize: 20,
          height: 1.3,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleMedium: TextStyle(
          color: BureauColors.navy,
          fontSize: 16,
          height: 1.35,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
          color: BureauColors.navy,
          fontSize: 16,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          color: BureauColors.slate,
          fontSize: 14,
          height: 1.5,
        ),
        bodySmall: TextStyle(color: BureauColors.slate, fontSize: 12, height: 1.5),
        labelLarge: TextStyle(fontSize: 15, height: 1.3, fontWeight: FontWeight.w600),
        labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
        hintStyle: const TextStyle(color: BureauColors.muted, fontSize: 16, fontWeight: FontWeight.w400),
        labelStyle: const TextStyle(color: BureauColors.slate, fontSize: 14),
        helperStyle: const TextStyle(color: BureauColors.slate, fontSize: 12, height: 1.45),
        errorStyle: const TextStyle(fontSize: 12, height: 1.45),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
          textStyle: const TextStyle(fontFamily: 'BureauSans', fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: const BorderSide(color: BureauColors.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
          textStyle: const TextStyle(fontFamily: 'BureauSans', fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        elevation: 0,
        backgroundColor: Colors.white,
        indicatorColor: BureauColors.blueSoft,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? BureauColors.blue
                : BureauColors.muted,
            fontFamily: 'BureauSans',
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        textStyle: const TextStyle(fontFamily: 'BureauSans', fontSize: 14, fontWeight: FontWeight.w600),
      )),
      appBarTheme: const AppBarTheme(
        backgroundColor: BureauColors.canvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: BureauColors.navy,
        centerTitle: false,
        toolbarHeight: 68,
      ),
    );
  }
}
