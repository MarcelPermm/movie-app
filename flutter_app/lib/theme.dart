import 'package:flutter/material.dart';

/// Палитра один в один с frontend/style.css, чтобы приложение и сайт
/// выглядели одним продуктом.
class AppColors {
  static const bg = Color(0xFF0A0A0F);
  static const surface = Color(0xFF12121A);
  static const border = Color(0xFF222230);
  static const gold = Color(0xFFC9A84C);
  static const goldDim = Color(0xFF8A6C2A);
  static const text = Color(0xFFE8E4DC);
  static const textDim = Color(0xFF7A7570);
  static const red = Color(0xFFC94C4C);
  static const green = Color(0xFF4CAC70);
  static const blue = Color(0xFF4C7AC9);
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.gold,
    onPrimary: AppColors.bg,
    secondary: AppColors.goldDim,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    error: AppColors.red,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    canvasColor: AppColors.bg,
    dividerColor: AppColors.border,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.text,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      hintStyle: const TextStyle(color: AppColors.textDim),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.goldDim),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.bg,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.gold),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surface,
      contentTextStyle: TextStyle(color: AppColors.text),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.gold),
  );
}
