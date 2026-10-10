import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/session.dart';
import '../data/book_repository.dart';
import '../data/budget_repository.dart';
import '../data/discover_repository.dart';
import '../data/goal_repository.dart';
import '../data/local_first_repository.dart';
import '../data/movie_repository.dart';
import '../data/notebook_repository.dart';
import '../data/task_repository.dart';
import '../data/trip_repository.dart';
import '../data/wishlist_repository.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'books_screen.dart';
import 'budget_screen.dart';
import 'goals_screen.dart';
import 'movies_screen.dart';
import 'notebook_screen.dart';
import 'overview_screen.dart';
import 'tasks_screen.dart';
import 'trips_screen.dart';
import 'wishlist_screen.dart';

/// Один раздел приложения.
class _Section {
  final String label;
  final IconData icon;
  final Widget screen;

  /// Репозиторий раздела — из него берётся состояние синхронизации в шапке.
  final LocalFirstRepository Function(BuildContext) repo;

  const _Section({
    required this.label,
    required this.icon,
    required this.screen,
    required this.repo,
  });
}

/// Каркас приложения: на узком экране — выдвижное меню, на широком —
/// боковая панель. Разделов семь, для нижней панели их слишком много.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static final _sections = <_Section>[
    _Section(
      label: 'Обзор',
      icon: Icons.auto_awesome_outlined,
      screen: const OverviewScreen(),
      repo: (c) => c.watch<DiscoverRepository>(),
    ),
    _Section(
      label: 'Кино',
      icon: Icons.movie_outlined,
      screen: const MoviesScreen(),
      repo: (c) => c.watch<MovieRepository>(),
    ),
    _Section(
      label: 'Книги',
      icon: Icons.menu_book_outlined,
      screen: const BooksScreen(),
      repo: (c) => c.watch<BookRepository>(),
    ),
    _Section(
      label: 'Задачи',
      icon: Icons.check_circle_outline,
      screen: const TasksScreen(),
      repo: (c) => c.watch<TaskRepository>(),
    ),
    _Section(
      label: 'Тетрадь',
      icon: Icons.sticky_note_2_outlined,
      screen: const NotebookScreen(),
      repo: (c) => c.watch<NotebookRepository>(),
    ),
    _Section(
      label: 'Цели',
      icon: Icons.flag_outlined,
      screen: const GoalsScreen(),
      repo: (c) => c.watch<GoalRepository>(),
    ),
    _Section(
      label: 'Бюджет',
      icon: Icons.account_balance_wallet_outlined,
      screen: const BudgetScreen(),
      repo: (c) => c.watch<BudgetRepository>(),
    ),
    _Section(
      label: 'Поездки',
      icon: Icons.luggage_outlined,
      screen: const TripsScreen(),
      repo: (c) => c.watch<TripRepository>(),
    ),
    _Section(
      label: 'Желания',
      icon: Icons.card_giftcard_outlined,
      screen: const WishlistScreen(),
      repo: (c) => c.watch<WishlistRepository>(),
    ),
  ];

  void _select(int index) {
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final extended = MediaQuery.sizeOf(context).width >= 1180;

    // IndexedStack сохраняет состояние разделов: вернувшись, ты видишь
    // ту же прокрутку и тот же выбранный день.
    final content = IndexedStack(
      index: _index,
      children: _sections.map((s) => s.screen).toList(),
    );

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 58,
        titleSpacing: wide ? 24 : 4,
        title: Row(
          children: [
            if (!wide) ...[
              const Text('🐒', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
            ],
            Text(
              _sections[_index].label,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(width: 12),
            SyncBadge(_sections[_index].repo(context)),
          ],
        ),
        // Тонкая линия вместо тени: тень на тёмном фоне читается как грязь.
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
        actions: [
          _ProfileMenu(),
          const SizedBox(width: 10),
        ],
      ),
      drawer: wide ? null : _buildDrawer(),
      body: wide
          ? Row(
              children: [
                _buildRail(extended),
                const VerticalDivider(width: 1, color: AppColors.border),
                Expanded(child: content),
              ],
            )
          : content,
    );
  }

  /// Собственная боковая панель вместо NavigationRail: там жёстко заданы
  /// отступы и форма подсветки, а нам нужна «таблетка» с золотой засечкой
  /// и плавным переходом. Своя реализация проще, чем бороться с чужой.
  Widget _buildRail(bool extended) {
    return Container(
      width: extended ? 214 : 76,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF14141D), Color(0xFF0C0C13)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(extended ? 20 : 0, 24, 0, 22),
            child: Row(
              mainAxisAlignment:
                  extended ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                const Text('🐒', style: TextStyle(fontSize: 24)),
                if (extended) ...[
                  const SizedBox(width: 10),
                  const Text(
                    'Monkey',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: _sections.length,
              itemBuilder: (context, i) => _RailItem(
                section: _sections[i],
                active: i == _index,
                extended: extended,
                onTap: () => _select(i),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 22, 20, 18),
              child: Row(
                children: [
                  Text('🐒', style: TextStyle(fontSize: 24)),
                  SizedBox(width: 10),
                  Text(
                    'Monkey App',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: List.generate(_sections.length, (i) {
                  final section = _sections[i];
                  final active = i == _index;
                  return ListTile(
                    leading: Icon(
                      section.icon,
                      color: active ? AppColors.gold : AppColors.textDim,
                    ),
                    title: Text(
                      section.label,
                      style: TextStyle(
                        color: active ? AppColors.gold : AppColors.text,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    selected: active,
                    selectedTileColor: AppColors.gold.withValues(alpha: 0.08),
                    onTap: () {
                      _select(i);
                      Navigator.pop(context);
                    },
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Пункт боковой панели: подсветка-таблетка и золотая засечка слева.
class _RailItem extends StatefulWidget {
  final _Section section;
  final bool active;
  final bool extended;
  final VoidCallback onTap;

  const _RailItem({
    required this.section,
    required this.active,
    required this.extended,
    required this.onTap,
  });

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final color = active
        ? AppColors.gold
        : _hover
            ? AppColors.text
            : AppColors.textDim;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          height: 46,
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: active
                ? AppColors.goldWash(0.13)
                : _hover
                    ? AppColors.surfaceHigh
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.small),
          ),
          child: Row(
            children: [
              // Засечка занимает место всегда, иначе при выборе пункта
              // текст дёргался бы вбок.
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 3,
                height: active ? 22 : 0,
                margin: const EdgeInsets.only(right: 9),
                decoration: BoxDecoration(
                  gradient: AppColors.goldGradient,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(
                width: widget.extended ? 34 : 60,
                child: Icon(widget.section.icon, color: color, size: 21),
              ),
              if (widget.extended)
                Expanded(
                  child: Text(
                    widget.section.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 13.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Имя пользователя и выход.
class _ProfileMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final name = session.displayName ?? session.username ?? 'Профиль';

    return PopupMenuButton<String>(
      color: AppColors.surface,
      tooltip: name,
      offset: const Offset(0, 44),
      onSelected: (value) {
        if (value == 'logout') _confirmLogout(context);
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Text(name, style: const TextStyle(color: AppColors.textDim, fontSize: 13)),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'logout',
          child: Text('Выйти', style: TextStyle(color: AppColors.red)),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: CircleAvatar(
          radius: 15,
          backgroundColor: AppColors.goldDim.withValues(alpha: 0.25),
          child: Text(
            name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
            style: const TextStyle(
              color: AppColors.gold,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final session = context.read<Session>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Выйти?', style: TextStyle(color: AppColors.text, fontSize: 17)),
        content: const Text(
          'Локальные копии данных сотрутся. После входа они загрузятся заново.',
          style: TextStyle(color: AppColors.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена', style: TextStyle(color: AppColors.textDim)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    if (ok == true) await session.signOut();
  }
}
