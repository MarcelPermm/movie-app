import 'package:flutter/material.dart';

/// Палитра. Отталкивается от frontend/style.css, но фон и поверхности
/// разведены сильнее: плоский тёмный экран без слоёв читается как интерфейс
/// десятилетней давности. Три ступени глубины дают ощущение объёма даже
/// без единой картинки.
class AppColors {
  static const bg = Color(0xFF08080C);
  static const surface = Color(0xFF12121A);
  static const border = Color(0xFF24242F);
  static const gold = Color(0xFFD9B65C);
  static const goldDim = Color(0xFF8A6C2A);
  static const text = Color(0xFFF2EFE8);
  static const textDim = Color(0xFF8E8880);
  static const red = Color(0xFFD65C5C);
  static const green = Color(0xFF5CBC80);
  static const blue = Color(0xFF5C8AD9);

  /// Чуть светлее поверхности — для вложенных блоков внутри карточек.
  static const surfaceHigh = Color(0xFF1B1B26);

  /// Верхний слой: всплывающие панели, карточки при наведении.
  static const surfaceTop = Color(0xFF232331);

  /// Мягкая подсветка золотом: подложка активных элементов.
  static Color goldWash(double alpha) => gold.withValues(alpha: alpha);

  /// Акцентный градиент — на кнопках и активных вкладках. Одна плоская
  /// заливка выглядит дёшево, лёгкий перелив стоит ноль и меняет всё.
  static const goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE8C973), Color(0xFFC0983C)],
  );

  /// Затемнение поверх кадра, чтобы текст читался на любой обложке.
  static const scrim = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    stops: [0.0, 0.5, 1.0],
    colors: [Color(0xF208080C), Color(0x9908080C), Color(0x1A08080C)],
  );
}

/// Скругления. Держим их в одном месте, иначе по экранам расползаются
/// восьмёрки, десятки и четырнадцатые радиусы.
///
/// Значения заметно крупнее прежних: мелкий радиус — самая заметная примета
/// старого интерфейса.
class AppRadius {
  static const small = 12.0;
  static const medium = 18.0;
  static const large = 24.0;
  static const pill = 999.0;
}

/// Тени. Чёрная тень на тёмном фоне не видна — поэтому она не столько
/// затемняет, сколько отделяет слой от фона за счёт размытия.
class AppShadow {
  static const card = [
    BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 8)),
  ];

  static const raised = [
    BoxShadow(color: Color(0x99000000), blurRadius: 28, offset: Offset(0, 14)),
  ];

  /// Золотое свечение под активной карточкой.
  static List<BoxShadow> glow(Color color) => [
        BoxShadow(color: color.withValues(alpha: 0.28), blurRadius: 26, offset: const Offset(0, 10)),
      ];
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
  // Отрицательный трекинг на крупном кегле — то, что отличает современную
  // типографику от набора по умолчанию.
  const textTheme = TextTheme(
    displaySmall: TextStyle(
      color: AppColors.text,
      fontSize: 34,
      fontWeight: FontWeight.w800,
      height: 1.08,
      letterSpacing: -0.8,
    ),
    headlineMedium: TextStyle(
      color: AppColors.text,
      fontSize: 26,
      fontWeight: FontWeight.w800,
      height: 1.12,
      letterSpacing: -0.5,
    ),
    titleLarge: TextStyle(
      color: AppColors.text,
      fontSize: 20,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
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
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: -0.1),
        elevation: 0,
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
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
BoxDecoration cardDecoration({bool highlighted = false, bool raised = false}) => BoxDecoration(
      color: raised ? AppColors.surfaceHigh : AppColors.surface,
      border: Border.all(
        color: highlighted ? AppColors.goldDim : AppColors.border,
        width: highlighted ? 1.5 : 1,
      ),
      borderRadius: BorderRadius.circular(AppRadius.medium),
      boxShadow: raised ? AppShadow.card : null,
    );

/// Надпись-рубрика над блоком: мелкая, разрежённая, приглушённая.
/// Одна из тех мелочей, которые отличают собранный интерфейс от набора.
const kEyebrowStyle = TextStyle(
  color: AppColors.textDim,
  fontSize: 10.5,
  letterSpacing: 1.4,
  fontWeight: FontWeight.w700,
);
