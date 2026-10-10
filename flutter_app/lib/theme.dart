import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/material.dart';

import 'core/local_store.dart';

// ─── Темы ─────────────────────────────────────────────────────────────
//
// Каждая тема — это набор токенов: цвета, шрифты, скругления, вид карточек
// и навигации. Экраны берут значения только отсюда (AppColors, AppRadius,
// AppText, cardDecoration), поэтому одна и та же раскладка выглядит
// по-разному в каждой теме, а логика у всех тем общая.

enum AppThemeId { glass, bento, paper, classic }

/// Как выглядит карточка: заливка, полупрозрачное стекло или газетная линейка.
enum CardStyle { filled, tile, glass, ruled }

/// Навигация на широком экране.
enum NavStyle { rail, pills, floating, masthead }

class ThemeSpec {
  final AppThemeId id;
  final String name;
  final String hint;
  final Brightness brightness;

  final Color bg;
  final Color surface;
  final Color surfaceHigh;
  final Color surfaceTop;
  final Color border;
  final Color text;
  final Color textDim;
  final Color accent;
  final Color accentDim;
  final Color onAccent;
  final Color red;
  final Color green;
  final Color blue;

  /// Непрозрачная поверхность для диалогов, шторок и меню. В «Стекле»
  /// обычная поверхность полупрозрачная, а под шторкой это нечитаемо.
  final Color sheet;

  /// Главная кнопка.
  final Color buttonBg;
  final Color buttonFg;

  final List<Color> accentGradient;

  /// Шрифт текста и шрифт заголовков/крупных цифр. null — системный.
  final String? bodyFont;
  final String? displayFont;
  final FontWeight displayWeight;

  /// Трекинг крупного кегля в долях размера (−0.04 = −4 %).
  final double displayTracking;

  final double radiusSmall;
  final double radiusMedium;
  final double radiusLarge;
  final double radiusPill;

  final CardStyle cardStyle;
  final NavStyle navStyle;

  /// Рубрики над блоками: цвет и разрядка.
  final Color eyebrowColor;
  final double eyebrowSpacing;

  /// Размытые пятна на фоне — только у «Стекла».
  final List<Color> backdrop;

  const ThemeSpec({
    required this.id,
    required this.name,
    required this.hint,
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    required this.surfaceTop,
    required this.border,
    required this.text,
    required this.textDim,
    required this.accent,
    required this.accentDim,
    required this.onAccent,
    required this.red,
    required this.green,
    required this.blue,
    required this.sheet,
    required this.buttonBg,
    required this.buttonFg,
    required this.accentGradient,
    required this.bodyFont,
    required this.displayFont,
    required this.displayWeight,
    required this.displayTracking,
    required this.radiusSmall,
    required this.radiusMedium,
    required this.radiusLarge,
    required this.radiusPill,
    required this.cardStyle,
    required this.navStyle,
    required this.eyebrowColor,
    required this.eyebrowSpacing,
    this.backdrop = const [],
  });

  bool get isDark => brightness == Brightness.dark;
}

const _glass = ThemeSpec(
  id: AppThemeId.glass,
  name: 'Стекло',
  hint: 'Тёмная, полупрозрачные панели поверх размытого фона',
  brightness: Brightness.dark,
  bg: Color(0xFF160C22),
  surface: Color(0x17FFFFFF),
  surfaceHigh: Color(0x24FFFFFF),
  surfaceTop: Color(0x33FFFFFF),
  border: Color(0x2BFFFFFF),
  text: Color(0xFFFFFFFF),
  textDim: Color(0xB3FFFFFF),
  accent: Color(0xFFF2C584),
  accentDim: Color(0xFFA57E45),
  onAccent: Color(0xFF1B1030),
  red: Color(0xFFFF8B7A),
  green: Color(0xFF7FE0A8),
  blue: Color(0xFF9CC3E6),
  sheet: Color(0xFF241634),
  buttonBg: Color(0xFFFFFFFF),
  buttonFg: Color(0xFF1B1030),
  accentGradient: [Color(0xFFFFFFFF), Color(0xFFF1E6FF)],
  bodyFont: 'Jost',
  displayFont: 'Jost',
  displayWeight: FontWeight.w500,
  displayTracking: -0.03,
  radiusSmall: 14,
  radiusMedium: 22,
  radiusLarge: 28,
  radiusPill: 999,
  cardStyle: CardStyle.glass,
  navStyle: NavStyle.floating,
  eyebrowColor: Color(0x99FFFFFF),
  eyebrowSpacing: 1.2,
  backdrop: [Color(0xFFE79A7A), Color(0xFF5B2A78), Color(0xFFF2C584), Color(0xFF2B1B5E)],
);

const _bento = ThemeSpec(
  id: AppThemeId.bento,
  name: 'Бенто',
  hint: 'Светлая, плитки разного размера и яркие акценты',
  brightness: Brightness.light,
  bg: Color(0xFFE7E8ED),
  surface: Color(0xFFFFFFFF),
  surfaceHigh: Color(0xFFF2F3F6),
  surfaceTop: Color(0xFFFFFFFF),
  border: Color(0xFFE1E3E8),
  text: Color(0xFF111318),
  textDim: Color(0xFF6B7080),
  accent: Color(0xFF111318),
  accentDim: Color(0xFF3A3E48),
  onAccent: Color(0xFFFFFFFF),
  red: Color(0xFFE5484D),
  green: Color(0xFF16A34A),
  blue: Color(0xFF2D3BFF),
  sheet: Color(0xFFFFFFFF),
  buttonBg: Color(0xFF111318),
  buttonFg: Color(0xFFFFFFFF),
  accentGradient: [Color(0xFF111318), Color(0xFF111318)],
  bodyFont: 'Manrope',
  displayFont: 'Manrope',
  displayWeight: FontWeight.w800,
  displayTracking: -0.045,
  radiusSmall: 14,
  radiusMedium: 24,
  radiusLarge: 30,
  radiusPill: 999,
  cardStyle: CardStyle.tile,
  navStyle: NavStyle.pills,
  eyebrowColor: Color(0xFF6B7080),
  eyebrowSpacing: 0.6,
);

const _paper = ThemeSpec(
  id: AppThemeId.paper,
  name: 'Ночная газета',
  hint: 'Вечерний выпуск: антиква, колонки и линейки',
  brightness: Brightness.dark,
  bg: Color(0xFF0F1B2D),
  surface: Color(0xFF13213A),
  surfaceHigh: Color(0xFF1A2B44),
  surfaceTop: Color(0xFF22344F),
  border: Color(0x2EEFE7D8),
  text: Color(0xFFEFE7D8),
  textDim: Color(0x8CEFE7D8),
  accent: Color(0xFFC8A15A),
  accentDim: Color(0xFF8C7038),
  onAccent: Color(0xFF0F1B2D),
  red: Color(0xFFE07A5F),
  green: Color(0xFF8FBF8A),
  blue: Color(0xFF8FB3D9),
  sheet: Color(0xFF15243A),
  buttonBg: Color(0xFFC8A15A),
  buttonFg: Color(0xFF0F1B2D),
  accentGradient: [Color(0xFFC8A15A), Color(0xFFC8A15A)],
  bodyFont: 'Plex Sans',
  displayFont: 'Prata',
  displayWeight: FontWeight.w400,
  displayTracking: -0.01,
  radiusSmall: 2,
  radiusMedium: 2,
  radiusLarge: 4,
  radiusPill: 2,
  cardStyle: CardStyle.ruled,
  navStyle: NavStyle.masthead,
  eyebrowColor: Color(0xFFC8A15A),
  eyebrowSpacing: 1.8,
);

/// Прежнее оформление — для тех, кто к нему привык.
const _classic = ThemeSpec(
  id: AppThemeId.classic,
  name: 'Классика',
  hint: 'Прежняя чёрно-золотая',
  brightness: Brightness.dark,
  bg: Color(0xFF08080C),
  surface: Color(0xFF12121A),
  surfaceHigh: Color(0xFF1B1B26),
  surfaceTop: Color(0xFF232331),
  border: Color(0xFF24242F),
  text: Color(0xFFF2EFE8),
  textDim: Color(0xFF8E8880),
  accent: Color(0xFFD9B65C),
  accentDim: Color(0xFF8A6C2A),
  onAccent: Color(0xFF08080C),
  red: Color(0xFFD65C5C),
  green: Color(0xFF5CBC80),
  blue: Color(0xFF5C8AD9),
  sheet: Color(0xFF12121A),
  buttonBg: Color(0xFFD9B65C),
  buttonFg: Color(0xFF08080C),
  accentGradient: [Color(0xFFE8C973), Color(0xFFC0983C)],
  bodyFont: null,
  displayFont: null,
  displayWeight: FontWeight.w800,
  displayTracking: -0.025,
  radiusSmall: 12,
  radiusMedium: 18,
  radiusLarge: 24,
  radiusPill: 999,
  cardStyle: CardStyle.filled,
  navStyle: NavStyle.rail,
  eyebrowColor: Color(0xFF8E8880),
  eyebrowSpacing: 1.4,
);

/// Текущая тема и её переключение.
class AppTheme {
  static const specs = {
    AppThemeId.glass: _glass,
    AppThemeId.bento: _bento,
    AppThemeId.paper: _paper,
    AppThemeId.classic: _classic,
  };

  static const _storeKey = 'app::theme';

  /// Меняется — перерисовывается всё приложение (см. MonkeyApp).
  static final notifier = ValueNotifier<AppThemeId>(AppThemeId.glass);

  static ThemeSpec get spec => specs[notifier.value]!;

  /// Выбор из прошлого запуска. Вызывается после LocalStore.init().
  static void restore() {
    final saved = LocalStore.readMap(_storeKey)?['id'];
    for (final id in AppThemeId.values) {
      if (id.name == saved) notifier.value = id;
    }
  }

  static Future<void> select(AppThemeId id) async {
    if (notifier.value == id) return;
    notifier.value = id;
    await LocalStore.writeMap(_storeKey, {'id': id.name});
  }
}

ThemeSpec get _t => AppTheme.spec;

// ─── Токены ───────────────────────────────────────────────────────────
//
// Имена остались прежними (gold — это теперь «акцент темы»), чтобы сотни
// мест в экранах не переписывать. Значения — геттеры: читаются при каждой
// отрисовке и меняются вместе с темой.

class AppColors {
  static Color get bg => _t.bg;
  static Color get surface => _t.surface;
  static Color get border => _t.border;
  static Color get gold => _t.accent;
  static Color get goldDim => _t.accentDim;
  static Color get text => _t.text;
  static Color get textDim => _t.textDim;
  static Color get red => _t.red;
  static Color get green => _t.green;
  static Color get blue => _t.blue;

  /// Чуть светлее поверхности — для вложенных блоков внутри карточек.
  static Color get surfaceHigh => _t.surfaceHigh;

  /// Верхний слой: всплывающие панели, карточки при наведении.
  static Color get surfaceTop => _t.surfaceTop;

  /// Непрозрачный фон шторок, диалогов и меню.
  static Color get sheet => _t.sheet;

  /// Текст и значки поверх акцентной заливки.
  static Color get onGold => _t.onAccent;

  /// Мягкая подсветка акцентом: подложка активных элементов.
  static Color goldWash(double alpha) => gold.withValues(alpha: alpha);

  static LinearGradient get goldGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: _t.accentGradient,
      );

  /// Затемнение (в светлой теме — высветление) поверх кадра, чтобы текст
  /// читался на любой обложке.
  static LinearGradient get scrim => LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        stops: const [0.0, 0.5, 1.0],
        colors: [
          _t.bg.withValues(alpha: 0.95),
          _t.bg.withValues(alpha: 0.6),
          _t.bg.withValues(alpha: 0.1),
        ],
      );
}

/// Скругления — свои у каждой темы: от газетных прямых углов до мягких плиток.
class AppRadius {
  static double get small => _t.radiusSmall;
  static double get medium => _t.radiusMedium;
  static double get large => _t.radiusLarge;
  static double get pill => _t.radiusPill;
}

class AppShadow {
  static List<BoxShadow> get card => _t.isDark
      ? const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 8))]
      : const [BoxShadow(color: Color(0x14111318), blurRadius: 14, offset: Offset(0, 4))];

  static List<BoxShadow> get raised => _t.isDark
      ? const [BoxShadow(color: Color(0x99000000), blurRadius: 28, offset: Offset(0, 14))]
      : const [BoxShadow(color: Color(0x1F111318), blurRadius: 24, offset: Offset(0, 10))];

  /// Свечение под активной карточкой.
  static List<BoxShadow> glow(Color color) => [
        BoxShadow(color: color.withValues(alpha: 0.28), blurRadius: 26, offset: const Offset(0, 10)),
      ];
}

/// Стили заголовков и крупных цифр — шрифт и насечка темы.
class AppText {
  static TextStyle display(double size, {Color? color, double height = 1.05}) => TextStyle(
        fontFamily: _t.displayFont,
        fontWeight: _t.displayWeight,
        fontSize: size,
        height: height,
        letterSpacing: size * _t.displayTracking,
        color: color ?? AppColors.text,
      );

  /// Цифры: та же гарнитура, цифры одной ширины — суммы не «пляшут».
  static TextStyle number(double size, {Color? color}) => display(size, color: color).copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

/// Надпись-рубрика над блоком: мелкая, разрежённая, приглушённая.
TextStyle get kEyebrowStyle => TextStyle(
      color: _t.eyebrowColor,
      fontSize: _t.id == AppThemeId.classic ? 10.5 : 11.5,
      letterSpacing: _t.eyebrowSpacing,
      fontWeight: _t.id == AppThemeId.bento ? FontWeight.w700 : FontWeight.w600,
    );

/// Рамка карточки — по-своему в каждой теме.
BoxDecoration cardDecoration({bool highlighted = false, bool raised = false}) {
  final t = _t;
  switch (t.cardStyle) {
    case CardStyle.ruled:
      // Газета: без заливки, линейка сверху. Неравномерная рамка не
      // сочетается со скруглением, поэтому радиуса нет вовсе.
      return BoxDecoration(
        color: raised ? t.surface : Colors.transparent,
        border: Border(
          top: BorderSide(
            color: highlighted ? t.accent : t.border,
            width: highlighted ? 2 : 1,
          ),
        ),
      );
    case CardStyle.tile:
      return BoxDecoration(
        color: raised ? t.surfaceHigh : t.surface,
        border: highlighted ? Border.all(color: t.accent, width: 1.5) : null,
        borderRadius: BorderRadius.circular(t.radiusMedium),
        boxShadow: raised ? AppShadow.card : const [BoxShadow(color: Color(0x0A111318), blurRadius: 2, offset: Offset(0, 1))],
      );
    case CardStyle.glass:
      return BoxDecoration(
        color: raised ? t.surfaceHigh : t.surface,
        border: Border.all(
          color: highlighted ? t.accent.withValues(alpha: 0.7) : t.border,
          width: highlighted ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(t.radiusMedium),
      );
    case CardStyle.filled:
      return BoxDecoration(
        color: raised ? t.surfaceHigh : t.surface,
        border: Border.all(
          color: highlighted ? t.accentDim : t.border,
          width: highlighted ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(t.radiusMedium),
        boxShadow: raised ? AppShadow.card : null,
      );
  }
}

/// Фон за всем приложением. У «Стекла» — размытые цветные пятна,
/// у остальных — ровная заливка.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final t = _t;
    if (t.backdrop.isEmpty) return ColoredBox(color: t.bg);
    final c = t.backdrop;
    return RepaintBoundary(
      child: ColoredBox(
        color: t.bg,
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            final h = box.maxHeight;
            Widget blob(double left, double top, double size, Color color, double alpha) => Positioned(
                  left: left,
                  top: top,
                  width: size,
                  height: size,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: alpha),
                    ),
                  ),
                );
            return Stack(
              fit: StackFit.expand,
              children: [
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90, tileMode: TileMode.decal),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      blob(w * 0.35, -h * 0.35, w * 0.6, c[0], 0.55),
                      blob(-w * 0.12, h * 0.35, w * 0.5, c[1], 0.9),
                      if (c.length > 2) blob(w * 0.72, h * 0.6, w * 0.38, c[2], 0.45),
                      if (c.length > 3) blob(w * 0.38, h * 0.75, w * 0.3, c[3], 0.8),
                    ],
                  ),
                ),
                const ColoredBox(color: Color(0x5C0C0614)),
              ],
            );
          },
        ),
      ),
    );
  }
}

ThemeData buildAppTheme() {
  final t = _t;
  final dark = t.isDark;

  final scheme = (dark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
    primary: t.accent,
    onPrimary: t.onAccent,
    secondary: t.accentDim,
    onSecondary: t.onAccent,
    surface: t.sheet,
    onSurface: t.text,
    error: t.red,
    onError: Colors.white,
    outline: t.border,
  );

  // Заголовки — шрифтом темы для крупного кегля, остальное — текстовым.
  final textTheme = TextTheme(
    displaySmall: AppText.display(34),
    headlineMedium: AppText.display(26, height: 1.12),
    titleLarge: AppText.display(20, height: 1.2),
    titleMedium: TextStyle(color: t.text, fontSize: 16, fontWeight: FontWeight.w700),
    titleSmall: TextStyle(color: t.text, fontSize: 14, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(color: t.text, fontSize: 15, height: 1.5),
    bodyMedium: TextStyle(color: t.text, fontSize: 14, height: 1.5),
    bodySmall: TextStyle(color: t.textDim, fontSize: 12, height: 1.45),
    labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    labelSmall: TextStyle(color: t.textDim, fontSize: 10, letterSpacing: 0.9, fontWeight: FontWeight.w700),
  );

  OutlineInputBorder inputBorder(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.radiusSmall),
        borderSide: BorderSide(color: color),
      );

  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusPill));

  return ThemeData(
    useMaterial3: true,
    brightness: t.brightness,
    colorScheme: scheme,
    fontFamily: t.bodyFont,
    // «Стекло» рисует фон само (AppBackdrop), экраны должны быть прозрачными.
    scaffoldBackgroundColor: t.backdrop.isEmpty ? t.bg : Colors.transparent,
    canvasColor: t.bg,
    dividerColor: t.border,
    textTheme: textTheme,
    splashFactory: InkSparkle.splashFactory,

    appBarTheme: AppBarTheme(
      backgroundColor: t.backdrop.isEmpty ? t.bg : Colors.transparent,
      foregroundColor: t.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: AppText.display(18, height: 1.2),
    ),

    cardTheme: CardThemeData(
      color: t.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radiusMedium),
        side: BorderSide(color: t.border),
      ),
    ),

    dividerTheme: DividerThemeData(color: t.border, thickness: 1, space: 1),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? t.bg.withValues(alpha: t.backdrop.isEmpty ? 1 : 0.55) : t.surfaceHigh,
      hintStyle: TextStyle(color: t.textDim, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: inputBorder(t.border),
      enabledBorder: inputBorder(t.border),
      focusedBorder: inputBorder(t.accentDim),
      errorBorder: inputBorder(t.red),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.buttonBg,
        foregroundColor: t.buttonFg,
        disabledBackgroundColor: t.surfaceHigh,
        disabledForegroundColor: t.textDim,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: shape,
        textStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: t.id == AppThemeId.paper ? 0.8 : -0.1,
        ),
        elevation: 0,
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.id == AppThemeId.paper ? t.accent : t.text,
        side: BorderSide(color: t.id == AppThemeId.paper ? t.accent : t.border),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: shape,
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: dark ? t.accent : t.blue,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),

    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: t.textDim),
    ),

    // Всплывающие поверхности не должны светлеть от tint Material 3.
    dialogTheme: DialogThemeData(
      backgroundColor: t.sheet,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusLarge)),
      titleTextStyle: AppText.display(18, height: 1.2),
      contentTextStyle: TextStyle(color: t.textDim, fontSize: 14, height: 1.5),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: t.sheet,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radiusMedium),
        side: BorderSide(color: t.border),
      ),
      textStyle: TextStyle(color: t.text, fontSize: 14),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.sheet,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(t.radiusLarge)),
      ),
    ),

    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(t.sheet),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),

    listTileTheme: ListTileThemeData(
      textColor: t.text,
      iconColor: t.textDim,
      titleTextStyle: TextStyle(color: t.text, fontSize: 15, fontFamily: t.bodyFont),
      subtitleTextStyle: TextStyle(color: t.textDim, fontSize: 12, fontFamily: t.bodyFont),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? t.surfaceTop : t.text,
      contentTextStyle: TextStyle(color: dark ? t.text : t.bg, fontSize: 14, fontFamily: t.bodyFont),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusSmall)),
    ),

    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: t.surface,
      indicatorColor: t.accent.withValues(alpha: 0.16),
      selectedLabelTextStyle: TextStyle(color: t.accent, fontSize: 12, fontWeight: FontWeight.w700),
      unselectedLabelTextStyle: TextStyle(color: t.textDim, fontSize: 12),
    ),

    drawerTheme: DrawerThemeData(
      backgroundColor: t.sheet,
      surfaceTintColor: Colors.transparent,
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.accent,
      linearTrackColor: t.surfaceHigh,
      circularTrackColor: Colors.transparent,
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: dark ? t.sheet : t.text,
        borderRadius: BorderRadius.circular(t.radiusSmall),
        border: Border.all(color: t.border),
      ),
      textStyle: TextStyle(color: dark ? t.text : t.bg, fontSize: 12),
    ),
  );
}
