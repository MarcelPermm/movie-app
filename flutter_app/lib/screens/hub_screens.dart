import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/sub_tabs.dart';
import 'budget_screen.dart';
import 'goals_screen.dart';
import 'notebook_screen.dart';
import 'overview_screen.dart';
import 'tasks_screen.dart';
import 'tonight_screen.dart';
import 'trips_screen.dart';
import 'wishlist_screen.dart';
import 'wrapped_screen.dart';

/// «Деньги» на телефоне: бюджет месяца и поездки — две стороны одних денег.
class MoneyScreen extends StatelessWidget {
  const MoneyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SubTabView(
      tabs: [
        SubTab(label: 'Бюджет', builder: (_) => const BudgetScreen()),
        SubTab(label: 'Поездки', builder: (_) => const TripsScreen()),
      ],
    );
  }
}

/// Раздел, открытый из «Ещё» поверх нижней панели.
///
/// Сами экраны рисуют свой заголовок (SectionHeader), поэтому у шапки
/// только кнопка «назад» — без дублирования названия.
Route<void> sectionRoute(Widget screen) => MaterialPageRoute(
      builder: (_) => Scaffold(appBar: AppBar(), body: screen),
    );

class _MoreItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final Route<void> Function() route;

  const _MoreItem(this.icon, this.title, this.subtitle, this.route);
}

/// «Ещё»: всё, что не поместилось в нижнюю панель.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  static final _items = [
    _MoreItem(Icons.auto_awesome_outlined, 'Обзор кино', 'Популярное, подборки, «для тебя»',
        () => sectionRoute(const OverviewScreen())),
    _MoreItem(Icons.check_circle_outline, 'Задачи', 'День за днём, повторяющиеся',
        () => sectionRoute(const TasksScreen())),
    _MoreItem(Icons.menu_book_outlined, 'Тетрадь', 'Заметки и списки',
        () => sectionRoute(const NotebookScreen())),
    _MoreItem(Icons.flag_outlined, 'Цели', 'На месяц и на год',
        () => sectionRoute(const GoalsScreen())),
    _MoreItem(Icons.card_giftcard_outlined, 'Желания', 'Виш-лист, друзья, складчина',
        () => sectionRoute(const WishlistScreen())),
  ];

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().month == 1 ? DateTime.now().year - 1 : DateTime.now().year;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: _Feature(
                emoji: '🍿',
                title: 'На вечер',
                colors: featureColors(FeatureTone.tonight),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TonightScreen()),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Feature(
                emoji: '✨',
                title: 'Итоги $year',
                colors: featureColors(FeatureTone.wrapped),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => WrappedScreen(year: year)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          decoration: cardDecoration(),
          child: Column(
            children: [
              for (var i = 0; i < _items.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 56),
                ListTile(
                  leading: Icon(_items[i].icon, color: AppColors.gold),
                  title: Text(_items[i].title, style: TextStyle(color: AppColors.text)),
                  subtitle: Text(
                    _items[i].subtitle,
                    style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
                  ),
                  trailing: Icon(Icons.chevron_right, color: AppColors.textDim),
                  onTap: () => Navigator.of(context).push(_items[i].route()),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text('ТЕМА', style: kEyebrowStyle),
        const SizedBox(height: 10),
        const ThemePicker(),
      ],
    );
  }
}

/// Выбор темы: карточки с названием, описанием и образцом цветов.
class ThemePicker extends StatelessWidget {
  const ThemePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final current = AppTheme.notifier.value;
    return Column(
      children: [
        for (final spec in AppTheme.specs.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.medium),
              onTap: () => AppTheme.select(spec.id),
              child: Ink(
                padding: const EdgeInsets.all(12),
                decoration: cardDecoration(highlighted: spec.id == current),
                child: Row(
                  children: [
                    // Образец: фон, поверхность и акцент самой темы.
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: spec.bg,
                        borderRadius: BorderRadius.circular(spec.radiusSmall),
                        border: Border.all(color: AppColors.border),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Expanded(child: ColoredBox(color: spec.text)),
                          const SizedBox(width: 4),
                          Expanded(child: ColoredBox(color: spec.accent)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            spec.name,
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              fontFamily: spec.displayFont,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(spec.hint, style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    if (spec.id == current) Icon(Icons.check_circle, color: AppColors.gold, size: 22),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Цвета ярких карточек («На вечер», «Итоги года») в текущей теме.
enum FeatureTone { tonight, wrapped, money, trip }

List<Color> featureColors(FeatureTone tone) {
  switch (AppTheme.spec.id) {
    case AppThemeId.bento:
      return switch (tone) {
        FeatureTone.tonight => const [Color(0xFF131418), Color(0xFF131418)],
        FeatureTone.wrapped => const [Color(0xFFCDBBFF), Color(0xFFCDBBFF)],
        FeatureTone.money => const [Color(0xFF2D3BFF), Color(0xFF2D3BFF)],
        FeatureTone.trip => const [Color(0xFFFF6A2B), Color(0xFFFF6A2B)],
      };
    case AppThemeId.glass:
      return const [Color(0x33FFFFFF), Color(0x14FFFFFF)];
    case AppThemeId.paper:
      return const [Color(0xFF15243A), Color(0xFF15243A)];
    case AppThemeId.classic:
      return switch (tone) {
        FeatureTone.wrapped => const [Color(0xFF2A1240), Color(0xFF0E0A18)],
        _ => const [Color(0xFF3A2A08), Color(0xFF171009)],
      };
  }
}

/// Текст поверх такой карточки: тёмный или белый — какой контрастнее.
///
/// Полупрозрачную карточку («Стекло») сначала накладываем на фон темы,
/// иначе белая дымка посчитается белой и текст станет тёмным на тёмном.
Color featureForeground(List<Color> colors) {
  const ink = Color(0xFF111318);
  final base = Color.alphaBlend(colors.first, AppColors.bg);
  double contrast(Color a) {
    final la = a.computeLuminance();
    final lb = base.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  return contrast(ink) > contrast(Colors.white) ? ink : Colors.white;
}

class _Feature extends StatelessWidget {
  final String emoji;
  final String title;
  final List<Color> colors;
  final VoidCallback onTap;

  const _Feature({required this.emoji, required this.title, required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      onTap: onTap,
      child: Ink(
        height: 96,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
          borderRadius: BorderRadius.circular(AppRadius.medium),
          border: AppTheme.spec.isDark ? Border.all(color: AppColors.border) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            Text(
              title,
              style: AppText.display(16, color: featureForeground(colors)),
            ),
          ],
        ),
      ),
    );
  }
}
