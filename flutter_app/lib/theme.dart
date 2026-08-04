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

  /// Чуть светлее поверхности — для вложенных блоков внутри карточек.
  static const surfaceHigh = Color(0xFF181822);

  /// Мягкая подсветка золотом: подложка активных элементов.
  static Color goldWash(double alpha) => gold.withValues(alpha: alpha);
}

/// Скругления. Держим их в одном месте, иначе по экранам расползаются
/// восьмёрки, десятки и четырнадцатые радиусы.
class AppRadius {
  static const small = 9.0;
  static const medium = 12.0;
  static const large = 16.0;
  static const pill = 999.0;
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.gold,
    onPrimary: AppColors.bg,
    secondary: AppColors.goldDim,
    onSecondary: AppColors.bg,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    error: AppColors.red,
    onError: Colors.white,
    outline: AppColors.border,
  );

  // Единая шкала кегля: заголовки крупные и плотные, текст — воздушный.
  const textTheme = TextTheme(
    displaySmall: TextStyle(
      color: AppColors.text,
      fontSize: 30,
      fontWeight: FontWeight.w800,
      height: 1.12,
    ),
    headlineMedium: TextStyle(
      color: AppColors.text,
      fontSize: 24,
      fontWeight: FontWeight.w800,
      height: 1.15,
    ),
    titleLarge: TextStyle(
      color: AppColors.text,
      fontSize: 20,
      fontWeight: FontWeight.w700,
    ),
    titleMedium: TextStyle(
      color: AppColors.text,
      fontSize: 16,
      fontWeight: FontWeight.w700,
    ),
    titleSmall: TextStyle(
      color: AppColors.text,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: TextStyle(color: AppColors.text, fontSize: 15, height: 1.5),
    bodyMedium: TextStyle(color: AppColors.text, fontSize: 14, height: 1.5),
    bodySmall: TextStyle(color: AppColors.textDim, fontSize: 12, height: 1.45),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    labelSmall: TextStyle(
      color: AppColors.textDim,
      fontSize: 10,
      letterSpacing: 0.9,
      fontWeight: FontWeight.w700,
    ),
  );

  OutlineInputBorder inputBorder(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.small),
        borderSide: BorderSide(color: color),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    canvasColor: AppColors.bg,
    dividerColor: AppColors.border,
    textTheme: textTheme,
    splashFactory: InkSparkle.splashFactory,

    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),

    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        side: const BorderSide(color: AppColors.border),
      ),
    ),

    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.bg,
      hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: inputBorder(AppColors.border),
      enabledBorder: inputBorder(AppColors.border),
      focusedBorder: inputBorder(AppColors.goldDim),
      errorBorder: inputBorder(AppColors.red),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.bg,
        disabledBackgroundColor: AppColors.surfaceHigh,
        disabledForegroundColor: AppColors.textDim,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.small)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.gold,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),

    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: AppColors.textDim),
    ),

    // Всплывающие поверхности не должны светлеть от tint Material 3 —
    // иначе тёмная палитра «выцветает».
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.large)),
      titleTextStyle: const TextStyle(
        color: AppColors.text,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: const TextStyle(color: AppColors.textDim, fontSize: 14, height: 1.5),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        side: const BorderSide(color: AppColors.border),
      ),
      textStyle: const TextStyle(color: AppColors.text, fontSize: 14),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
      ),
    ),

    dropdownMenuTheme: const DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(AppColors.surface),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
      ),
    ),

    listTileTheme: const ListTileThemeData(
      textColor: AppColors.text,
      iconColor: AppColors.textDim,
      titleTextStyle: TextStyle(color: AppColors.text, fontSize: 15),
      subtitleTextStyle: TextStyle(color: AppColors.textDim, fontSize: 12),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceHigh,
      contentTextStyle: const TextStyle(color: AppColors.text, fontSize: 14),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.small)),
    ),

    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.goldWash(0.16),
      selectedLabelTextStyle: const TextStyle(
        color: AppColors.gold,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
    ),

    drawerTheme: const DrawerThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.gold,
      linearTrackColor: AppColors.bg,
      circularTrackColor: Colors.transparent,
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.small),
        border: Border.all(color: AppColors.border),
      ),
      textStyle: const TextStyle(color: AppColors.text, fontSize: 12),
    ),
  );
}

/// Рамка карточки — одинаковая по всему приложению.
BoxDecoration cardDecoration({bool highlighted = false}) => BoxDecoration(
      color: AppColors.surface,
      border: Border.all(
        color: highlighted ? AppColors.goldDim : AppColors.border,
        width: highlighted ? 1.5 : 1,
      ),
      borderRadius: BorderRadius.circular(AppRadius.medium),
    );
