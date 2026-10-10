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
                colors: const [Color(0xFF3A2A08), Color(0xFF171009)],
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
                colors: const [Color(0xFF2A1240), Color(0xFF0E0A18)],
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
                  title: Text(_items[i].title, style: const TextStyle(color: AppColors.text)),
                  subtitle: Text(
                    _items[i].subtitle,
                    style: const TextStyle(color: AppColors.textDim, fontSize: 12.5),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: AppColors.textDim),
                  onTap: () => Navigator.of(context).push(_items[i].route()),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
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
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            Text(
              title,
              style: const TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
