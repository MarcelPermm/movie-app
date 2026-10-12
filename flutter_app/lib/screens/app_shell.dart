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
import '../data/profile_repository.dart';
import '../data/task_repository.dart';
import '../data/trip_repository.dart';
import '../data/wishlist_repository.dart';
import '../data/warm_up.dart';
import '../games/games_screen.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'books_screen.dart';
import 'budget_screen.dart';
import 'goals_screen.dart';
import 'hub_screens.dart';
import 'movies_screen.dart';
import 'notebook_screen.dart';
import 'overview_screen.dart';
import 'tasks_screen.dart';
import 'today_screen.dart';
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

/// Каркас приложения.
///
/// На телефоне — нижняя панель из пяти пунктов: Сегодня, Кино, Книги,
/// Деньги (бюджет и поездки) и Ещё. Всё остальное открывается из «Ещё».
/// На широком экране места хватает — там боковая панель со всеми разделами.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  @override
  void initState() {
    super.initState();
    // Первый кадр рисуется из кэша, а свежие данные подтягиваются следом.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) warmUp(context);
    });
  }

  /// Выбранный раздел боковой панели (широкий экран).
  int _index = 0;

  /// Выбранный пункт нижней панели (телефон).
  int _tab = 0;

  /// Нижняя панель телефона. Индексы нужны «Сегодня», чтобы карточка
  /// бюджета переключала на «Деньги».
  static const _moneyTab = 3;

  late final _tabs = <_Section>[
    _Section(
      label: 'Сегодня',
      icon: Icons.wb_sunny_outlined,
      screen: TodayScreen(onOpenMoney: () => _selectTab(_moneyTab)),
      repo: (c) => c.watch<TaskRepository>(),
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
      label: 'Деньги',
      icon: Icons.account_balance_wallet_outlined,
      screen: const MoneyScreen(),
      repo: (c) => c.watch<BudgetRepository>(),
    ),
    _Section(
      label: 'Ещё',
      icon: Icons.grid_view_outlined,
      screen: const MoreScreen(),
      repo: (c) => c.watch<NotebookRepository>(),
    ),
  ];

  /// Пункты нижней панели строятся лениво — как вкладки внутри разделов.
  final Set<int> _visitedTabs = {0};

  late final _sections = <_Section>[
    _Section(
      label: 'Сегодня',
      icon: Icons.wb_sunny_outlined,
      screen: TodayScreen(onOpenMoney: () => setState(() => _index = _budgetIndex)),
      repo: (c) => c.watch<TaskRepository>(),
    ),
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
    _Section(
      label: 'Игры',
      icon: Icons.sports_esports_outlined,
      screen: const GamesScreen(),
      // Игры локальные: синхронизировать нечего, индикатор берём у профиля.
      repo: (c) => c.watch<ProfileRepository>(),
    ),
  ];

  int get _budgetIndex => _sections.indexWhere((s) => s.label == 'Бюджет');

  void _select(int index) {
    setState(() => _index = index);
  }

  void _selectTab(int index) {
    setState(() {
      _tab = index;
      _visitedTabs.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final extended = MediaQuery.sizeOf(context).width >= 1180;
    final current = wide ? _sections[_index] : _tabs[_tab];

    // IndexedStack сохраняет состояние разделов: вернувшись, ты видишь
    // ту же прокрутку и тот же выбранный день.
    final content = wide
        ? IndexedStack(
            index: _index,
            children: _sections.map((s) => s.screen).toList(),
          )
        : IndexedStack(
            index: _tab,
            children: [
              for (var i = 0; i < _tabs.length; i++)
                _visitedTabs.contains(i) ? _tabs[i].screen : const SizedBox.shrink(),
            ],
          );

    if (!wide) {
      return Scaffold(
        appBar: _buildAppBar(current, wide: false),
        bottomNavigationBar: _buildBottomBar(),
        body: content,
      );
    }

    // На широком экране навигация — главная примета темы.
    switch (AppTheme.spec.navStyle) {
      case NavStyle.rail:
        return Scaffold(
          appBar: _buildAppBar(current, wide: true),
          body: Row(
            children: [
              _buildRail(extended),
              VerticalDivider(width: 1, color: AppColors.border),
              Expanded(child: content),
            ],
          ),
        );
      case NavStyle.floating:
        return Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              Padding(padding: const EdgeInsets.only(left: 104), child: content),
              Positioned(
                left: 22,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _FloatingNav(
                    sections: _sections,
                    index: _index,
                    onSelect: _select,
                    sync: SyncBadge(current.repo(context)),
                  ),
                ),
              ),
            ],
          ),
        );
      case NavStyle.pills:
        return Scaffold(
          body: Column(
            children: [
              _PillsBar(
                sections: _sections,
                index: _index,
                onSelect: _select,
                sync: SyncBadge(current.repo(context)),
              ),
              Expanded(child: content),
            ],
          ),
        );
      case NavStyle.masthead:
        return Scaffold(
          body: Column(
            children: [
              _Masthead(
                sections: _sections,
                index: _index,
                onSelect: _select,
                sync: SyncBadge(current.repo(context)),
              ),
              Expanded(child: content),
            ],
          ),
        );
    }
  }

  PreferredSizeWidget _buildAppBar(_Section current, {required bool wide}) {
    return AppBar(
      toolbarHeight: 58,
      titleSpacing: wide ? 24 : 16,
      title: Row(
        children: [
          Text(current.label, style: AppText.display(19, height: 1.2)),
          const SizedBox(width: 12),
          SyncBadge(current.repo(context)),
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
    );
  }

  /// Классическая боковая панель: «таблетка» с засечкой у активного пункта.
  Widget _buildRail(bool extended) {
    return Container(
      width: extended ? 214 : 76,
      color: AppColors.surface,
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
                  Text('Monkey', style: AppText.display(18)),
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

  /// Нижняя панель телефона. Своя отрисовка подсветки — золотая «таблетка»
  /// под значком, как засечка в боковой панели на широком экране.
  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        // В «Стекле» поверхность полупрозрачная — панели нужна плотность.
        color: AppTheme.spec.cardStyle == CardStyle.glass
            ? AppColors.sheet.withValues(alpha: 0.92)
            : AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: _BottomItem(
                    section: _tabs[i],
                    active: i == _tab,
                    onTap: () => _selectTab(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  final _Section section;
  final bool active;
  final VoidCallback onTap;

  const _BottomItem({required this.section, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.gold : AppColors.textDim;
    return InkResponse(
      onTap: onTap,
      radius: 36,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: active ? 54 : 34,
            height: 30,
            decoration: BoxDecoration(
              color: active ? AppColors.goldWash(0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Icon(section.icon, size: 21, color: color),
          ),
          const SizedBox(height: 3),
          Text(
            section.label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
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

/// Имя пользователя, выбор темы и выход.
class _ProfileMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final name = session.displayName ?? session.username ?? 'Профиль';
    final current = AppTheme.notifier.value;

    return PopupMenuButton<String>(
      color: AppColors.sheet,
      tooltip: name,
      offset: const Offset(0, 44),
      onSelected: (value) {
        if (value == 'logout') _confirmLogout(context);
        if (value.startsWith('theme:')) {
          final id = AppThemeId.values.byName(value.substring(6));
          AppTheme.select(id);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Text(name, style: TextStyle(color: AppColors.textDim, fontSize: 13)),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          enabled: false,
          height: 30,
          child: Text('ТЕМА', style: kEyebrowStyle),
        ),
        for (final spec in AppTheme.specs.values)
          PopupMenuItem(
            value: 'theme:${spec.id.name}',
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: spec.id == current
                      ? Icon(Icons.check, size: 18, color: AppColors.gold)
                      : null,
                ),
                const SizedBox(width: 8),
                Text(spec.name, style: TextStyle(color: AppColors.text)),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'logout',
          child: Text('Выйти', style: TextStyle(color: AppColors.red)),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: _Avatar(name: name),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final session = context.read<Session>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.sheet,
        title: Text('Выйти?', style: TextStyle(color: AppColors.text, fontSize: 17)),
        content: Text(
          'Локальные копии данных сотрутся. После входа они загрузятся заново.',
          style: TextStyle(color: AppColors.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Отмена', style: TextStyle(color: AppColors.textDim)),
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

/// Кружок с первой буквой имени.
class _Avatar extends StatelessWidget {
  final String name;

  const _Avatar({required this.name});

  static const double radius = 15;

  @override
  Widget build(BuildContext context) {
    final bento = AppTheme.spec.id == AppThemeId.bento;
    return CircleAvatar(
      radius: radius,
      backgroundColor: bento ? AppColors.text : AppColors.goldDim.withValues(alpha: 0.25),
      child: Text(
        name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
        style: TextStyle(
          color: bento ? AppColors.surface : AppColors.gold,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.85,
        ),
      ),
    );
  }
}

// ─── Навигация широкого экрана по темам ─────────────────────────────

/// «Стекло»: плавающая капсула из одних значков слева.
class _FloatingNav extends StatelessWidget {
  final List<_Section> sections;
  final int index;
  final ValueChanged<int> onSelect;
  final Widget sync;

  const _FloatingNav({
    required this.sections,
    required this.index,
    required this.onSelect,
    required this.sync,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.large),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < sections.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Tooltip(
                  message: sections[i].label,
                  preferBelow: false,
                  waitDuration: const Duration(milliseconds: 300),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => onSelect(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: i == index ? AppColors.surfaceTop : Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        sections[i].icon,
                        size: 22,
                        color: i == index ? AppColors.text : AppColors.textDim,
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            sync,
            const SizedBox(height: 8),
            _ProfileMenu(),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

/// «Бенто»: логотип и ряд «пилюль» сверху.
class _PillsBar extends StatelessWidget {
  final List<_Section> sections;
  final int index;
  final ValueChanged<int> onSelect;
  final Widget sync;

  const _PillsBar({
    required this.sections,
    required this.index,
    required this.onSelect,
    required this.sync,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 16, 22, 8),
        child: Row(
          children: [
            Text('monkey', style: AppText.display(22)),
            const SizedBox(width: 28),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      boxShadow: const [BoxShadow(color: Color(0x0F111318), blurRadius: 3, offset: Offset(0, 1))],
                    ),
                    child: Row(
                      children: [
                        for (var i = 0; i < sections.length; i++)
                          InkWell(
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            onTap: () => onSelect(i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                              decoration: BoxDecoration(
                                color: i == index ? AppColors.text : Colors.transparent,
                                borderRadius: BorderRadius.circular(AppRadius.pill),
                              ),
                              child: Text(
                                sections[i].label,
                                style: TextStyle(
                                  color: i == index ? AppColors.surface : AppColors.textDim,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            sync,
            const SizedBox(width: 8),
            _ProfileMenu(),
          ],
        ),
      ),
    );
  }
}

/// «Ночная газета»: шапка издания, двойная линейка и рубрики.
class _Masthead extends StatelessWidget {
  final List<_Section> sections;
  final int index;
  final ValueChanged<int> onSelect;
  final Widget sync;

  const _Masthead({
    required this.sections,
    required this.index,
    required this.onSelect,
    required this.sync,
  });

  static const _weekdays = ['понедельник', 'вторник', 'среда', 'четверг', 'пятница', 'суббота', 'воскресенье'];
  static const _months = [
    'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final issue = now.difference(DateTime(now.year)).inDays + 1;
    final session = context.watch<Session>();
    final name = session.displayName ?? session.username ?? '';

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 14, 32, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Monkey', style: AppText.display(44, height: 1)),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      now.hour >= 17 ? 'Вечерний выпуск № $issue' : 'Выпуск № $issue',
                      style: TextStyle(color: AppColors.text, fontSize: 13),
                    ),
                    Text(
                      '${_weekdays[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]} ${now.year}'
                      '${name.isEmpty ? '' : ' · для $name'}',
                      style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                sync,
                _ProfileMenu(),
              ],
            ),
            const SizedBox(height: 10),
            // Двойная линейка под названием — как у настоящей газеты.
            Container(height: 1, color: AppColors.border),
            const SizedBox(height: 2),
            Container(height: 1, color: AppColors.border),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < sections.length; i++)
                    InkWell(
                      onTap: () => onSelect(i),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 11, 26, 9),
                        child: Container(
                          padding: const EdgeInsets.only(bottom: 3),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: i == index ? AppColors.gold : Colors.transparent,
                              ),
                            ),
                          ),
                          child: Text(
                            sections[i].label,
                            style: TextStyle(
                              color: i == index ? AppColors.gold : AppColors.textDim,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(height: 1, color: AppColors.border),
          ],
        ),
      ),
    );
  }
}
