import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/session.dart';
import '../data/book_repository.dart';
import '../data/budget_repository.dart';
import '../data/goal_repository.dart';
import '../data/local_first_repository.dart';
import '../data/movie_repository.dart';
import '../data/notebook_repository.dart';
import '../data/task_repository.dart';
import '../data/wishlist_repository.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'books_screen.dart';
import 'budget_screen.dart';
import 'goals_screen.dart';
import 'movies_screen.dart';
import 'notebook_screen.dart';
import 'tasks_screen.dart';
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
        titleSpacing: wide ? 20 : 4,
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
              ),
            ),
            const SizedBox(width: 10),
            SyncBadge(_sections[_index].repo(context)),
          ],
        ),
        actions: [
          _ProfileMenu(),
          const SizedBox(width: 6),
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

  Widget _buildRail(bool extended) {
    return NavigationRail(
      selectedIndex: _index,
      onDestinationSelected: _select,
      extended: extended,
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.gold.withValues(alpha: 0.16),
      leading: Padding(
        padding: EdgeInsets.symmetric(vertical: 16, horizontal: extended ? 16 : 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🐒', style: TextStyle(fontSize: 22)),
            if (extended) ...[
              const SizedBox(width: 8),
              const Text(
                'Monkey App',
                style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
      destinations: _sections
          .map((s) => NavigationRailDestination(
                icon: Icon(s.icon, color: AppColors.textDim),
                selectedIcon: Icon(s.icon, color: AppColors.gold),
                label: Text(s.label),
              ))
          .toList(),
      selectedLabelTextStyle: const TextStyle(color: AppColors.gold, fontSize: 12),
      unselectedLabelTextStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
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
