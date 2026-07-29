import 'package:flutter/material.dart';

abstract final class StashColors {
  static const background = Color(0xFF101214);
  static const surface = Color(0xFF181B1E);
  static const surfaceHigh = Color(0xFF202428);
  static const outline = Color(0xFF30363A);
  static const text = Color(0xFFF5F7F5);
  static const muted = Color(0xFF9DA4A1);
  static const accent = Color(0xFF52B54B);
  static const accentBright = Color(0xFF63CE5B);
  static const danger = Color(0xFFED7564);
  static const warning = Color(0xFFEFC95D);
}

ThemeData buildStashTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: StashColors.accent,
    brightness: Brightness.dark,
    surface: StashColors.surface,
    error: StashColors.danger,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: StashColors.background,
    fontFamilyFallback: const ['Microsoft YaHei', 'sans-serif'],
    appBarTheme: const AppBarTheme(
      backgroundColor: StashColors.background,
      foregroundColor: StashColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 70,
      backgroundColor: StashColors.surface,
      indicatorColor: StashColors.surfaceHigh,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected)
              ? StashColors.accentBright
              : StashColors.muted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? StashColors.accentBright
              : StashColors.muted,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: StashColors.surfaceHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: const BorderSide(color: StashColors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: const BorderSide(color: StashColors.accent),
      ),
      labelStyle: const TextStyle(color: StashColors.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 46),
        backgroundColor: StashColors.accent,
        foregroundColor: const Color(0xFF10200E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    cardTheme: CardThemeData(
      color: StashColors.surface,
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
    ),
    dividerColor: StashColors.outline,
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: StashColors.accent,
      linearTrackColor: StashColors.outline,
    ),
  );
}
