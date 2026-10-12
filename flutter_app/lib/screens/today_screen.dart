import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/session.dart';
import '../data/budget_repository.dart';
import '../data/discover_repository.dart';
import '../data/goal_repository.dart';
import '../data/movie_repository.dart';
import '../data/task_repository.dart';
import '../data/trip_repository.dart';
import '../models/json.dart';
import '../models/movie.dart';
import '../models/task.dart';
import '../models/trip.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/poster_card.dart';
import '../widgets/series_today.dart';
import '../data/series_repository.dart';
import '../widgets/task_bits.dart';
import 'hub_screens.dart';
import 'movie_detail_screen.dart';
import 'tasks_screen.dart';
import 'tonight_screen.dart';
import 'trip_detail_screen.dart';
import 'wrapped_screen.dart';
import '../widgets/net_image.dart';

/// Главный экран: всё, что важно сегодня, — по одной карточке на раздел.
///
/// Здесь ничего не грузится отдельно: данные уже лежат в репозиториях
/// (их загружает старт приложения), экран только собирает их вместе.
class TodayScreen extends StatelessWidget {
  /// Переход в раздел «Деньги» нижней панели — карточка бюджета ведёт туда.
  final VoidCallback? onOpenMoney;

  const TodayScreen({super.key, this.onOpenMoney});

  @override
  Widget build(BuildContext context) {
    // На широком экране у каждой темы своя раскладка: это её «лицо».
    if (MediaQuery.sizeOf(context).width >= 900) {
      final data = _TodayData.of(context);
      final Widget layout = switch (AppTheme.spec.id) {
        AppThemeId.bento => _BentoToday(data: data, onOpenMoney: onOpenMoney),
        AppThemeId.glass => _GlassToday(data: data, onOpenMoney: onOpenMoney),
        AppThemeId.paper => _PaperToday(data: data, onOpenMoney: onOpenMoney),
        AppThemeId.classic => _ClassicWideToday(onOpenMoney: onOpenMoney),
      };
      return _refreshable(context, layout);
    }

    return _refreshable(
      context,
      ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: [
          const _Greeting(),
          const SizedBox(height: 18),
          const _TonightCard(),
          const SizedBox(height: 14),
          const SeriesToday(),
          const _TasksCard(),
          const SizedBox(height: 14),
          _BudgetCard(onOpen: onOpenMoney),
          const _TripCard(),
          const _WatchlistRail(),
          const _GoalsCard(),
          const SizedBox(height: 14),
          const _WrappedCard(),
        ],
      ),
    );
  }
}

Widget _refreshable(BuildContext context, Widget child) => RefreshIndicator(
      color: AppColors.gold,
      backgroundColor: AppColors.sheet,
      onRefresh: () => Future.wait([
        context.read<TaskRepository>().refresh(),
        context.read<WeekGoalRepository>().refresh(),
        context.read<BudgetRepository>().refresh(),
        context.read<TripRepository>().refresh(),
        context.read<MovieRepository>().refresh(),
        context.read<SeriesRepository>().refresh(),
      ]),
      child: child,
    );

const _weekdays = ['понедельник', 'вторник', 'среда', 'четверг', 'пятница', 'суббота', 'воскресенье'];
const _monthsGen = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

bool _isToday(DateTime d) {
  final now = DateTime.now();
  return d.year == now.year && d.month == now.month && d.day == now.day;
}

/// Заголовок карточки: значок, название и необязательная ссылка справа.
class _CardTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? action;
  final VoidCallback? onAction;

  const _CardTitle({required this.icon, required this.title, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.gold),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: Text(action!),
          ),
      ],
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final name = context.watch<Session>().displayName;
    final hello = now.hour < 5
        ? 'Доброй ночи'
        : now.hour < 12
            ? 'Доброе утро'
            : now.hour < 18
                ? 'Добрый день'
                : 'Добрый вечер';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_weekdays[now.weekday - 1]}, ${now.day} ${_monthsGen[now.month - 1]}'.toUpperCase(),
          style: kEyebrowStyle,
        ),
        const SizedBox(height: 6),
        Text(
          name == null || name.isEmpty ? hello : '$hello, $name',
          style: AppText.display(26),
        ),
      ],
    );
  }
}

/// Главная кнопка экрана — подборка на вечер.
class _TonightCard extends StatelessWidget {
  const _TonightCard();

  @override
  Widget build(BuildContext context) {
    final evening = DateTime.now().hour >= 17;
    final tones = featureColors(FeatureTone.tonight);
    final fg = featureForeground(tones);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const TonightScreen()),
      ),
      child: Ink(
        padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: tones,
          ),
          borderRadius: BorderRadius.circular(AppRadius.medium),
          border: AppTheme.spec.isDark ? Border.all(color: AppColors.goldWash(0.35)) : null,
        ),
        child: Row(
          children: [
            const Text('🍿', style: TextStyle(fontSize: 34)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    evening ? 'Что посмотреть сегодня?' : 'Что посмотреть вечером?',
                    style: AppText.display(17, color: fg, height: 1.2),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Настроение, время и компания — и подборка готова',
                    style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 12.5),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: fg),
          ],
        ),
      ),
    );
  }
}

class _TasksCard extends StatelessWidget {
  const _TasksCard();

  void _openAll(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(appBar: AppBar(), body: const TasksScreen()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<TaskRepository>();
    final today = _isToday(repo.day);
    final pending = repo.pending;
    final all = repo.tasks.where((t) => !t.isCancelled).length;
    final done = repo.done.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 12),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            icon: Icons.check_circle_outline,
            title: today && all > 0 ? 'Задачи · $done из $all' : 'Задачи на сегодня',
            action: 'Все',
            onAction: () => _openAll(context),
          ),
          if (!today)
            // Задачи сейчас открыты на другой день — не показываем чужие.
            TextButton(
              onPressed: () => _backToToday(context),
              child: const Text('Показать задачи на сегодня'),
            )
          else if (pending.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 4, 8, 4),
              child: Text(
                all == 0 ? 'На сегодня ничего не запланировано' : 'Всё сделано — можно отдыхать 🎉',
                style: TextStyle(color: AppColors.textDim, fontSize: 13.5),
              ),
            )
          else ...[
            ...pending.take(5).map((t) => _TaskRow(task: t)),
            if (pending.length > 5)
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 2),
                child: Text(
                  'и ещё ${pending.length - 5}',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
                ),
              ),
          ],
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _WeekGoalsMini(onOpen: () => _openAll(context), divided: true),
          ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final TaskItem task;

  const _TaskRow({required this.task});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.small),
      onTap: () => context.read<TaskRepository>().toggleDone(task),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(
              task.isDone ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 20,
              color: task.isHighPriority ? AppColors.red : AppColors.textDim,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.text, fontSize: 14),
              ),
            ),
            if (task.isWork) ...[const SizedBox(width: 8), const WorkPill(dense: true)],
            if (task.timeStr != null && task.timeStr!.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(task.timeStr!, style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
            ],
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  final VoidCallback? onOpen;

  const _BudgetCard({this.onOpen});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<BudgetRepository>();
    final planned = repo.plannedTotal;
    if (planned == 0 && repo.total == 0) return const SizedBox.shrink();

    final left = planned - repo.total;
    final over = planned > 0 && left < 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        onTap: onOpen,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardTitle(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Бюджет · ${monthNames[repo.month.month - 1].toLowerCase()}',
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    planned > 0 ? formatMoney(left.abs()) : formatMoney(repo.total),
                    style: AppText.number(28, color: over ? AppColors.red : AppColors.text),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      planned > 0 ? (over ? 'перерасход за месяц' : 'осталось на месяц') : 'потрачено за месяц',
                      style: TextStyle(color: AppColors.textDim, fontSize: 13),
                    ),
                  ),
                ],
              ),
              if (planned > 0) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (repo.total / planned).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: AppColors.surfaceHigh,
                    valueColor: AlwaysStoppedAnimation(over ? AppColors.red : AppColors.gold),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'потрачено ${formatMoney(repo.total)} из ${formatMoney(planned)}',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Поездка, которая идёт сейчас, или ближайшая предстоящая.
class _TripCard extends StatelessWidget {
  const _TripCard();

  static (Trip, int?, int?)? _pick(TripRepository repo) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    Trip? current;
    int? dayOf;
    int? totalDays;
    for (final t in repo.rootTrips) {
      final a = parseDateOnly(t.startDate);
      final b = parseDateOnly(t.endDate) ?? a;
      if (a == null || b == null) continue;
      final lo = a.isBefore(b) ? a : b;
      final hi = a.isBefore(b) ? b : a;
      if (!today.isBefore(lo) && !today.isAfter(hi)) {
        current = t;
        dayOf = today.difference(lo).inDays + 1;
        totalDays = hi.difference(lo).inDays + 1;
        break;
      }
    }
    if (current != null) return (current, dayOf, totalDays);
    final upcoming = repo.upcoming;
    return upcoming.isEmpty ? null : (upcoming.first, null, null);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<TripRepository>();
    final picked = _pick(repo);
    if (picked == null) return const SizedBox.shrink();

    final (trip, dayOf, totalDays) = picked;
    final spent = repo.actualOf(trip);
    final plan = repo.plannedOf(trip);
    final cities = repo.citiesOf(trip.id);
    final status = dayOf != null
        ? 'идёт сейчас · день $dayOf из $totalDays'
        : 'через ${trip.daysUntil} ${_days(trip.daysUntil ?? 0)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TripDetailScreen(tripId: trip.id)),
        ),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: cardDecoration(highlighted: true),
          child: Row(
            children: [
              Text(trip.emoji, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.name,
                      style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(status, style: TextStyle(color: AppColors.gold, fontSize: 12.5)),
                    if (cities.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        cities.map((c) => c.name).join(' → '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
                      ),
                    ],
                    if (plan > 0) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (spent / plan).clamp(0.0, 1.0),
                          minHeight: 4,
                          backgroundColor: AppColors.surfaceHigh,
                          valueColor: AlwaysStoppedAnimation(
                            spent > plan ? AppColors.red : AppColors.blue,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${formatMoney(spent)} из ${formatMoney(plan)}',
                        style: TextStyle(color: AppColors.textDim, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _days(int n) {
    final mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 14) return 'дней';
    switch (n % 10) {
      case 1:
        return 'день';
      case 2:
      case 3:
      case 4:
        return 'дня';
      default:
        return 'дней';
    }
  }
}

/// Дата без времени — чтобы «сегодня» сравнивалось с днями поездки честно.
DateTime? parseDateOnly(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final d = DateTime.tryParse(raw);
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

class _WatchlistRail extends StatelessWidget {
  const _WatchlistRail();

  @override
  Widget build(BuildContext context) {
    final movies = context.watch<MovieRepository>().watchlist.take(12).toList();
    if (movies.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(2, 4, 0, 10),
            child: Text('В СПИСКЕ К ПРОСМОТРУ', style: kEyebrowStyle),
          ),
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: movies.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => SizedBox(
                width: 112,
                child: PosterCard(
                  title: movies[i].title,
                  subtitle: movies[i].shortMeta,
                  imageUrl: movies[i].posterUrl,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: movies[i])),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalsCard extends StatelessWidget {
  const _GoalsCard();

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<GoalRepository>();
    final total = repo.goals.length;
    if (total == 0) return const SizedBox.shrink();
    final done = repo.doneCount;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            icon: Icons.flag_outlined,
            title: repo.period == 'year' ? 'Цели года · $done из $total' : 'Цели месяца · $done из $total',
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: done / total,
              minHeight: 6,
              backgroundColor: AppColors.surfaceHigh,
              valueColor: AlwaysStoppedAnimation(AppColors.green),
            ),
          ),
        ],
      ),
    );
  }
}

class _WrappedCard extends StatelessWidget {
  const _WrappedCard();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // В январе интереснее прошлый год — он уже закончился.
    final year = now.month == 1 ? now.year - 1 : now.year;
    final tones = featureColors(FeatureTone.wrapped);
    final fg = featureForeground(tones);

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => WrappedScreen(year: year)),
      ),
      child: Ink(
        padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: tones,
          ),
          borderRadius: BorderRadius.circular(AppRadius.medium),
          border: AppTheme.spec.isDark ? Border.all(color: AppColors.border) : null,
        ),
        child: Row(
          children: [
            const Text('✨', style: TextStyle(fontSize: 30)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Итоги $year',
                    style: AppText.display(17, color: fg, height: 1.2),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Фильмы, книги, поездки и деньги за год',
                    style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 12.5),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: fg),
          ],
        ),
      ),
    );
  }
}

// ─── Широкий экран: раскладки тем ─────────────────────────────────────

String _hello(DateTime now) => now.hour < 5
    ? 'Доброй ночи'
    : now.hour < 12
        ? 'Доброе утро'
        : now.hour < 18
            ? 'Добрый день'
            : 'Добрый вечер';

String _daysWord(int n) {
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 14) return 'дней';
  switch (n % 10) {
    case 1:
      return 'день';
    case 2:
    case 3:
    case 4:
      return 'дня';
    default:
      return 'дней';
  }
}

/// Всё, что нужно главному экрану, — собрано из репозиториев один раз.
class _TodayData {
  final DateTime now;
  final String? name;
  final Movie? pick;
  final bool pickFromList;
  final List<Movie> watchlist;
  final BudgetRepository budget;
  final TaskRepository tasks;
  final TripRepository trips;
  final GoalRepository goals;
  final (Trip, int?, int?)? trip;

  const _TodayData({
    required this.now,
    required this.name,
    required this.pick,
    required this.pickFromList,
    required this.watchlist,
    required this.budget,
    required this.tasks,
    required this.trips,
    required this.goals,
    required this.trip,
  });

  factory _TodayData.of(BuildContext context) {
    final movies = context.watch<MovieRepository>();
    final discover = context.watch<DiscoverRepository>();
    final trips = context.watch<TripRepository>();
    final watchlist = movies.watchlist;

    // Фильм вечера: первый из списка «к просмотру», у которого есть кадр;
    // если список пуст — что-то из популярного.
    Movie? pick;
    var fromList = false;
    for (final m in watchlist) {
      if (m.backdropPath != null && m.backdropPath!.isNotEmpty) {
        pick = m;
        fromList = true;
        break;
      }
    }
    if (pick == null && discover.heroSlides.isNotEmpty) pick = discover.heroSlides.first;

    return _TodayData(
      now: DateTime.now(),
      name: context.watch<Session>().displayName,
      pick: pick,
      pickFromList: fromList,
      watchlist: watchlist,
      budget: context.watch<BudgetRepository>(),
      tasks: context.watch<TaskRepository>(),
      trips: trips,
      goals: context.watch<GoalRepository>(),
      trip: _TripCard._pick(trips),
    );
  }

  String get greeting => name == null || name!.isEmpty ? _hello(now) : '${_hello(now)}, $name';
  String get dateLine => '${_weekdays[now.weekday - 1]}, ${now.day} ${_monthsGen[now.month - 1]}';

  int get planned => budget.plannedTotal;
  int get spent => budget.total;
  int get left => planned - spent;
  bool get overspent => planned > 0 && left < 0;
  String get monthName => monthNames[budget.month.month - 1].toLowerCase();

  bool get tasksToday => _isToday(tasks.day);
  int get tasksAll => tasks.tasks.where((t) => !t.isCancelled).length;
  int get tasksDone => tasks.done.length;

  String? get tripStatus {
    final t = trip;
    if (t == null) return null;
    final (item, dayOf, total) = t;
    if (dayOf != null) return 'идёт сейчас · день $dayOf из $total';
    final d = item.daysUntil ?? 0;
    return 'через $d ${_daysWord(d)}';
  }

  String get pickReason {
    final m = pick;
    if (m == null) return '';
    if (m.aiReason != null && m.aiReason!.isNotEmpty) return m.aiReason!;
    return pickFromList ? 'Давно лежит в вашем списке к просмотру' : 'Сейчас смотрят чаще всего';
  }

  String get pickMeta {
    final m = pick;
    if (m == null) return '';
    return [
      'На вечер',
      if (m.releaseYear != null) '${m.releaseYear}',
      if (m.genres.isNotEmpty) m.genres.first.toLowerCase(),
    ].join(' · ');
  }

  void openPick(BuildContext context) {
    final m = pick;
    if (m == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: m)));
  }

  void openTonight(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TonightScreen()));

  void openTrip(BuildContext context) {
    final t = trip;
    if (t == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TripDetailScreen(tripId: t.$1.id)));
  }

  void openWrapped(BuildContext context) {
    final year = now.month == 1 ? now.year - 1 : now.year;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => WrappedScreen(year: year)));
  }

  void openTasks(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(), body: const TasksScreen())),
      );
}

/// Кадр фильма во всю площадь блока; без кадра — мягкая заливка.
class _Still extends StatelessWidget {
  final Movie? movie;
  final double blur;

  const _Still({required this.movie, this.blur = 0});

  @override
  Widget build(BuildContext context) {
    final url = movie?.backdropUrl;
    Widget image = url == null
        ? ColoredBox(color: AppColors.surfaceHigh)
        : NetImage(
            imageUrl: url,
            aspect: 16 / 9,
            // Под размытием детали не видны — хватает картинки поменьше.
            maxDecodeWidth: blur > 0 ? 640 : null,
            fadeInDuration: const Duration(milliseconds: 250),
            errorWidget: (_, _, _) => ColoredBox(color: AppColors.surfaceHigh),
          );
    if (blur > 0) {
      image = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.decal),
        child: image,
      );
    }
    return image;
  }
}

/// Две кнопки фильма вечера.
class _PickButtons extends StatelessWidget {
  final _TodayData data;
  final Color? fg;
  final Color? bg;
  final bool square;

  const _PickButtons({required this.data, this.fg, this.bg, this.square = false});

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(square ? 2 : 999));
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        if (data.pick != null)
          FilledButton.icon(
            onPressed: () => data.openPick(context),
            style: FilledButton.styleFrom(
              backgroundColor: bg,
              foregroundColor: fg,
              shape: shape,
            ),
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: const Text('Смотреть'),
          ),
        OutlinedButton(
          onPressed: () => data.openTonight(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: bg ?? AppColors.text,
            side: BorderSide(color: (bg ?? AppColors.text).withValues(alpha: 0.4)),
            shape: shape,
          ),
          child: const Text('Подобрать другое'),
        ),
      ],
    );
  }
}

// ─── Бенто ────────────────────────────────────────────────────────────

/// Плитка «Бенто»: свой цвет, крупное скругление, без рамки.
class _Tile extends StatelessWidget {
  final Color? color;
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const _Tile({required this.child, this.color, this.onTap, this.padding = const EdgeInsets.all(22)});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.large);
    return Material(
      color: color ?? AppColors.surface,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _BentoToday extends StatelessWidget {
  final _TodayData data;
  final VoidCallback? onOpenMoney;

  const _BentoToday({required this.data, this.onOpenMoney});

  static const _blue = Color(0xFF2D3BFF);
  static const _lilac = Color(0xFFCDBBFF);
  static const _ink = Color(0xFF131418);

  @override
  Widget build(BuildContext context) {
    final d = data;
    final white = Colors.white;
    // На оранжевой плитке белый текст почти не читается — пишем чернилами.
    final tripColor = featureColors(FeatureTone.trip).first;
    final tripInk = featureForeground([tripColor]);
    final cats = d.budget.plannedCategories.take(4).toList();
    final spentBy = d.budget.spentByCategory;

    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 10, 28, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(d.greeting, style: AppText.display(34)),
            const SizedBox(width: 16),
            Text(d.dateLine, style: TextStyle(color: AppColors.textDim, fontSize: 16, fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 470,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Фильм вечера на две строки плиток.
              Expanded(
                flex: 5,
                child: _Tile(
                  color: _ink,
                  padding: EdgeInsets.zero,
                  onTap: d.pick == null ? () => d.openTonight(context) : () => d.openPick(context),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _Still(movie: d.pick),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x00000000), Color(0x22000000), Color(0xE00A060C)],
                            stops: [0.0, 0.45, 1.0],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 26,
                        right: 26,
                        bottom: 26,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.pick == null ? 'На вечер' : d.pickMeta,
                              style: TextStyle(color: white.withValues(alpha: 0.8), fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              d.pick?.title ?? 'Что посмотреть сегодня?',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.display(38, color: white),
                            ),
                            const SizedBox(height: 16),
                            _PickButtons(data: d, bg: white, fg: _ink),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Задачи на всю высоту.
              Expanded(
                flex: 4,
                child: _Tile(
                  onTap: () => d.openTasks(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('Задачи', style: AppText.display(20))),
                          if (d.tasksToday && d.tasksAll > 0)
                            Text('${d.tasksDone} из ${d.tasksAll}',
                                style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Задачи дня и цели недели; если не влезают — плитка прокручивается.
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _TaskList(data: d, limit: 5),
                              _WeekGoalsMini(onOpen: () => d.openTasks(context), limit: 3),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 8,
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _Tile(
                              color: _blue,
                              onTap: onOpenMoney,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    d.overspent ? 'Перерасход за ${d.monthName}' : 'Осталось на ${d.monthName}',
                                    style: TextStyle(color: white.withValues(alpha: 0.8), fontWeight: FontWeight.w600),
                                  ),
                                  const Spacer(),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      formatMoney(d.planned > 0 ? d.left.abs() : d.spent),
                                      style: AppText.number(56, color: white),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    'потрачено ${formatMoney(d.spent)} из ${formatMoney(d.planned)}',
                                    style: TextStyle(color: white.withValues(alpha: 0.8), fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _Tile(
                              color: d.trip == null ? AppColors.surface : tripColor,
                              onTap: d.trip == null ? null : () => d.openTrip(context),
                              child: d.trip == null
                                  ? Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Поездки', style: AppText.display(20)),
                                        const Spacer(),
                                        Text('Ближайших поездок нет', style: TextStyle(color: AppColors.textDim)),
                                      ],
                                    )
                                  : Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          d.trip!.$2 != null ? 'Сейчас в поездке' : 'Следующая поездка',
                                          style: TextStyle(color: tripInk.withValues(alpha: 0.8), fontWeight: FontWeight.w600),
                                        ),
                                        const Spacer(),
                                        Text(
                                          d.trip!.$1.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppText.display(36, color: tripInk),
                                        ),
                                        const Spacer(),
                                        Text(d.tripStatus ?? '',
                                            style: TextStyle(color: tripInk, fontSize: 13.5, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _Tile(
                              onTap: onOpenMoney,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${monthNames[d.budget.month.month - 1]} · по категориям',
                                    style: AppText.display(17),
                                  ),
                                  const SizedBox(height: 14),
                                  Expanded(
                                    child: cats.isEmpty
                                        ? Text('Задай план категориям — здесь появятся столбики',
                                            style: TextStyle(color: AppColors.textDim, fontSize: 13))
                                        : Row(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              for (final c in cats)
                                                Expanded(
                                                  child: _CategoryColumn(
                                                    name: c.name,
                                                    share: c.planMonthly == 0
                                                        ? 0
                                                        : (spentBy[c.id] ?? 0) / c.planMonthly,
                                                  ),
                                                ),
                                            ],
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _Tile(
                              color: _lilac,
                              onTap: () => d.openWrapped(context),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Итоги ${d.now.month == 1 ? d.now.year - 1 : d.now.year}',
                                      style: const TextStyle(color: Color(0xFF24124F), fontWeight: FontWeight.w600)),
                                  const Spacer(),
                                  Text('Твой год', style: AppText.display(40, color: const Color(0xFF24124F))),
                                  const SizedBox(height: 4),
                                  const Text('кино, книги, поездки и деньги — историей',
                                      style: TextStyle(color: Color(0xFF24124F), fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 250,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 9,
                child: _Tile(
                  color: _ink,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('В списке к просмотру', style: AppText.display(19, color: white))),
                          Text('${d.watchlist.length}', style: TextStyle(color: white.withValues(alpha: 0.6))),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Expanded(child: _PosterStrip(movies: d.watchlist)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 4,
                child: _Tile(
                  onTap: () => d.openTonight(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Вечер свободен?', style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text('Подобрать фильм за три вопроса', style: AppText.display(26)),
                      const Spacer(),
                      FilledButton(onPressed: () => d.openTonight(context), child: const Text('Начать')),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const SeriesToday(),
      ],
    );
  }
}

/// Столбик категории: доля плана снизу вверх, перерасход — красным.
class _CategoryColumn extends StatelessWidget {
  final String name;
  final double share;

  const _CategoryColumn({required this.name, required this.share});

  @override
  Widget build(BuildContext context) {
    final over = share > 1;
    final near = share >= 0.8;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => Container(
                width: double.infinity,
                alignment: Alignment.bottomCenter,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: Container(
                  height: box.maxHeight * share.clamp(0.04, 1.0),
                  decoration: BoxDecoration(
                    color: over ? AppColors.red : (near ? AppColors.blue : AppColors.text),
                    borderRadius: BorderRadius.circular(AppRadius.small),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            name.split(' ').first.toLowerCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textDim, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Вернуть «Задачи» и цели недели к сегодняшнему дню.
void _backToToday(BuildContext context) {
  final now = DateTime.now();
  context.read<TaskRepository>().setDay(now);
  context.read<WeekGoalRepository>().showPeriodOf(now);
}

/// Цели недели под задачами дня: прогресс и то, что ещё не сделано.
///
/// Показываем только текущую неделю — если в «Задачах» листали вперёд,
/// здесь не должно появиться чужое.
class _WeekGoalsMini extends StatelessWidget {
  final VoidCallback onOpen;
  final int limit;

  /// Отбить от задач тонкой линией (в карточке телефона).
  final bool divided;

  const _WeekGoalsMini({required this.onOpen, this.limit = 3, this.divided = false});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<WeekGoalRepository>();
    if (repo.periodKey != ymd(weekStart(DateTime.now()))) return const SizedBox.shrink();

    final goals = repo.goals;
    final done = repo.doneCount;
    final open = goals.where((g) => !g.done).toList();
    final paper = AppTheme.spec.id == AppThemeId.paper;

    final header = Row(
      children: [
        Expanded(
          child: Text(
            paper ? 'ЦЕЛИ НЕДЕЛИ' : 'Цели недели',
            style: paper
                ? kEyebrowStyle
                : TextStyle(color: AppColors.textDim, fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.3),
          ),
        ),
        if (goals.isNotEmpty)
          Text(
            '$done из ${goals.length}',
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
      ],
    );

    return Padding(
      padding: EdgeInsets.only(top: paper ? 22 : 14),
      child: Container(
        padding: divided ? const EdgeInsets.only(top: 12) : EdgeInsets.zero,
        decoration: divided ? BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            if (goals.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                  onPressed: onOpen,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Поставить цели на неделю'),
                ),
              )
            else ...[
              const SizedBox(height: 8),
              ThinProgress(value: done / goals.length),
              const SizedBox(height: 4),
              if (open.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Все цели недели выполнены 🎉',
                      style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                ),
              for (final g in open.take(limit))
                InkWell(
                  onTap: () => repo.toggle(g),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        TaskCheck(done: false, size: 16),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            g.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppColors.text, fontSize: 13.5),
                          ),
                        ),
                        if (g.isWork) ...[const SizedBox(width: 8), const WorkPill(dense: true)],
                      ],
                    ),
                  ),
                ),
              if (open.length > limit)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('и ещё ${open.length - limit}',
                      style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Задачи дня списком с отметкой — для плиток и колонок.
class _TaskList extends StatelessWidget {
  final _TodayData data;
  final int limit;

  const _TaskList({required this.data, this.limit = 6});

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (!d.tasksToday) {
      return Align(
        alignment: Alignment.topLeft,
        child: TextButton(
          onPressed: () => _backToToday(context),
          child: const Text('Показать задачи на сегодня'),
        ),
      );
    }
    final all = [...d.tasks.pending, ...d.tasks.done].take(limit).toList();
    if (all.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text('На сегодня ничего не запланировано', style: TextStyle(color: AppColors.textDim)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in all)
          InkWell(
            onTap: () => d.tasks.toggleDone(t),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
              child: Row(
                children: [
                  TaskCheck(done: t.isDone, important: t.isHighPriority),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.isDone ? AppColors.textDim : AppColors.text,
                        fontSize: 14.5,
                        decoration: t.isDone ? TextDecoration.lineThrough : null,
                        decorationColor: AppColors.textDim,
                      ),
                    ),
                  ),
                  if (t.isWork) ...[const SizedBox(width: 8), const WorkPill(dense: true)],
                  if (t.timeStr != null && t.timeStr!.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(t.timeStr!, style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Ряд обложек «к просмотру».
class _PosterStrip extends StatelessWidget {
  final List<Movie> movies;
  final double? radius;

  const _PosterStrip({required this.movies, this.radius});

  @override
  Widget build(BuildContext context) {
    if (movies.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text('Список пуст — добавляй фильмы из «Кино»', style: TextStyle(color: AppColors.textDim)),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final h = box.maxHeight;
        final w = h * 2 / 3;
        return ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: movies.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, i) {
            final m = movies[i];
            return InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: m)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius ?? AppRadius.small),
                child: SizedBox(
                  width: w,
                  height: h,
                  child: m.posterUrl == null
                      ? ColoredBox(
                          color: AppColors.surfaceHigh,
                          child: Center(child: Icon(Icons.movie_outlined, color: AppColors.textDim)),
                        )
                      : NetImage(imageUrl: m.posterUrl!),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─── Стекло ───────────────────────────────────────────────────────────

class _GlassPanel extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const _GlassPanel({required this.child, this.onTap, this.padding = const EdgeInsets.all(22)});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.large);
    return Material(
      color: Colors.white.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

class _GlassToday extends StatelessWidget {
  final _TodayData data;
  final VoidCallback? onOpenMoney;

  const _GlassToday({required this.data, this.onOpenMoney});

  @override
  Widget build(BuildContext context) {
    final d = data;
    const white = Colors.white;
    final dim = white.withValues(alpha: 0.72);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Цвет экрана берётся из кадра фильма вечера: размытый кадр за всем.
        Opacity(opacity: 0.85, child: _Still(movie: d.pick, blur: 60)),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0x99100818), Color(0x33100818), Color(0x66100818)],
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 30, 36, 30),
            child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${d.greeting} · ${d.dateLine}', style: TextStyle(color: dim, fontSize: 17)),
                          // Название опускаем к низу первого экрана, как на афише.
                          SizedBox(height: (box.maxHeight * 0.16).clamp(30.0, 200.0)),
                          Text(d.pick == null ? 'На вечер' : d.pickMeta, style: TextStyle(color: dim, fontSize: 15)),
                          const SizedBox(height: 10),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 780),
                            child: Text(
                              d.pick?.title ?? 'Что посмотреть сегодня?',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.display(76, color: white, height: 1),
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (d.pickReason.isNotEmpty)
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 560),
                              child: Text(d.pickReason, style: TextStyle(color: dim, fontSize: 18, height: 1.45)),
                            ),
                          const SizedBox(height: 24),
                          _PickButtons(data: d, bg: white, fg: const Color(0xFF1B1030)),
                          const SizedBox(height: 40),
                          Text('В списке к просмотру', style: TextStyle(color: dim, fontSize: 15)),
                          const SizedBox(height: 12),
                          SizedBox(height: 190, child: _PosterStrip(movies: d.watchlist, radius: 14)),
                          const SizedBox(height: 28),
                          const SeriesToday(),
                        ],
                      ),
                    ),
                    const SizedBox(width: 28),
                    SizedBox(
                      width: 380,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _GlassPanel(
                            onTap: onOpenMoney,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d.overspent ? 'Перерасход за ${d.monthName}' : 'Осталось на ${d.monthName}',
                                  style: TextStyle(color: dim, fontSize: 15),
                                ),
                                const SizedBox(height: 8),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    formatMoney(d.planned > 0 ? d.left.abs() : d.spent),
                                    style: AppText.number(58, color: d.overspent ? AppColors.red : white),
                                  ),
                                ),
                                if (d.planned > 0) ...[
                                  const SizedBox(height: 14),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: LinearProgressIndicator(
                                      value: (d.spent / d.planned).clamp(0.0, 1.0),
                                      minHeight: 6,
                                      backgroundColor: white.withValues(alpha: 0.18),
                                      valueColor: AlwaysStoppedAnimation(d.overspent ? AppColors.red : white),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text('потрачено ${formatMoney(d.spent)} из ${formatMoney(d.planned)}',
                                      style: TextStyle(color: dim, fontSize: 14)),
                                ],
                              ],
                            ),
                          ),
                          if (d.trip != null) ...[
                            const SizedBox(height: 14),
                            _GlassPanel(
                              onTap: () => d.openTrip(context),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      color: white.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Icon(Icons.flight_takeoff, color: white, size: 22),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(d.trip!.$1.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppText.display(20, color: white)),
                                        Text(d.tripStatus ?? '', style: TextStyle(color: dim, fontSize: 14)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          _GlassPanel(
                              onTap: () => d.openTasks(context),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(child: Text('Задачи', style: AppText.display(20, color: white))),
                                      if (d.tasksToday && d.tasksAll > 0)
                                        Text('${d.tasksDone} из ${d.tasksAll}', style: TextStyle(color: dim)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  _TaskList(data: d, limit: 5),
                                  _WeekGoalsMini(onOpen: () => d.openTasks(context)),
                                ],
                              ),
                            ),
                          const SizedBox(height: 14),
                          _GlassPanel(
                            onTap: () => d.openWrapped(context),
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text('Итоги ${d.now.month == 1 ? d.now.year - 1 : d.now.year}',
                                      style: const TextStyle(color: white, fontSize: 17)),
                                ),
                                Icon(Icons.arrow_forward, color: dim, size: 20),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
          ),
        ),
      ],
    );
  }
}

// ─── Ночная газета ────────────────────────────────────────────────────

class _Kicker extends StatelessWidget {
  final String text;

  const _Kicker(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text.toUpperCase(), style: kEyebrowStyle),
      );
}

/// Строка с точками-отточиями: «Продукты ........ 6 400 ₽».
class _Leader extends StatelessWidget {
  final Widget left;
  final Widget right;

  const _Leader({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              left,
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                  child: SizedBox(
                    height: 2,
                    child: CustomPaint(painter: _DotsPainter(AppColors.textDim.withValues(alpha: 0.5))),
                  ),
                ),
              ),
              right,
            ],
          ),
        ],
      ),
    );
  }
}

class _PaperToday extends StatelessWidget {
  final _TodayData data;
  final VoidCallback? onOpenMoney;

  const _PaperToday({required this.data, this.onOpenMoney});

  @override
  Widget build(BuildContext context) {
    final d = data;
    final m = d.pick;
    // Колонки разделены линейками, как полосы газеты.
    BoxDecoration ruled() => BoxDecoration(border: Border(left: BorderSide(color: AppColors.border)));
    final cats = d.budget.plannedCategories.take(6).toList();
    final spentBy = d.budget.spentByCategory;
    final body = TextStyle(color: AppColors.text, fontSize: 15.5, height: 1.6);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(40, 24, 40, 40),
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Колонка 1: фильм вечера и программа.
            Expanded(
              flex: 21,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Kicker(m == null ? 'Фильм вечера' : (d.pickFromList ? 'Фильм вечера · из вашего списка' : 'Фильм вечера')),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 200,
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: m?.posterLargeUrl == null
                              ? ColoredBox(color: AppColors.surface)
                              : NetImage(imageUrl: m!.posterLargeUrl!),
                        ),
                      ),
                      const SizedBox(width: 26),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m?.title ?? 'Что посмотреть сегодня?', style: AppText.display(46, height: 1.04)),
                            const SizedBox(height: 10),
                            if (m != null)
                              Text(
                                [
                                  if (m.director != null) m.director!,
                                  if (m.releaseYear != null) '${m.releaseYear}',
                                  if (m.genres.isNotEmpty) m.genres.take(2).join(', ').toLowerCase(),
                                ].join(' · '),
                                style: TextStyle(color: AppColors.textDim, fontSize: 14),
                              ),
                            const SizedBox(height: 14),
                            if (m != null && m.overview.isNotEmpty)
                              Text(m.overview, maxLines: 7, overflow: TextOverflow.ellipsis, style: body),
                            const SizedBox(height: 18),
                            _PickButtons(data: d, square: true),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  _Kicker('Программа · к просмотру'),
                  for (final w in d.watchlist.take(6))
                    InkWell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: w)),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(w.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.display(17, height: 1.3)),
                            ),
                            if (w.releaseYear != null)
                              Text('${w.releaseYear}', style: TextStyle(color: AppColors.textDim, fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
                  if (d.watchlist.isEmpty)
                    Text('Список пуст — добавляйте фильмы в разделе «Кино».',
                        style: TextStyle(color: AppColors.textDim)),
                  const SizedBox(height: 22),
                  const SeriesToday(),
                ],
              ),
            ),
            const SizedBox(width: 26),
            // Колонка 2: деньги и поездки.
            Expanded(
              flex: 10,
              child: Container(
                decoration: ruled(),
                padding: const EdgeInsets.only(left: 26),
                child: InkWell(
                onTap: onOpenMoney,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Kicker(d.overspent ? 'Перерасход за ${d.monthName}' : 'Осталось на ${d.monthName}'),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        formatMoney(d.planned > 0 ? d.left.abs() : d.spent),
                        style: AppText.number(60, color: d.overspent ? AppColors.red : AppColors.text),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Потрачено ${formatMoney(d.spent)} из ${formatMoney(d.planned)} по плану.',
                      style: TextStyle(color: AppColors.textDim, fontSize: 14.5, height: 1.5),
                    ),
                    const SizedBox(height: 18),
                    for (final c in cats)
                      _Leader(
                        left: Text(c.name, style: TextStyle(color: AppColors.text, fontSize: 14.5)),
                        right: Text(
                          '${formatMoney(spentBy[c.id] ?? 0)} / ${formatMoney(c.planMonthly)}',
                          style: TextStyle(
                            color: (spentBy[c.id] ?? 0) > c.planMonthly ? AppColors.red : AppColors.text,
                            fontSize: 14,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    if (d.trip != null) ...[
                      const SizedBox(height: 26),
                      _Kicker('Поездки'),
                      InkWell(
                        onTap: () => d.openTrip(context),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.trip!.$1.name, style: AppText.display(30)),
                            const SizedBox(height: 4),
                            Text(
                              [
                                d.tripStatus ?? '',
                                if (d.trips.plannedOf(d.trip!.$1) > 0) 'план ${formatMoney(d.trips.plannedOf(d.trip!.$1))}',
                              ].join(' · '),
                              style: TextStyle(color: AppColors.textDim, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ),
            ),
            const SizedBox(width: 26),
            // Колонка 3: повестка дня и год.
            Expanded(
              flex: 10,
              child: Container(
                decoration: ruled(),
                padding: const EdgeInsets.only(left: 26),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Kicker('Повестка дня'),
                  _TaskList(data: d, limit: 7),
                  _WeekGoalsMini(onOpen: () => d.openTasks(context), limit: 4),
                  const SizedBox(height: 28),
                  _Kicker('В этом году'),
                  InkWell(
                    onTap: () => d.openWrapped(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${d.watchlist.length} фильмов ждут вечера,\nа год пора подытожить',
                            style: AppText.display(26, height: 1.2)),
                        const SizedBox(height: 14),
                        OutlinedButton(
                          onPressed: () => d.openWrapped(context),
                          child: Text('ИТОГИ ${d.now.month == 1 ? d.now.year - 1 : d.now.year}'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              ),
            ),
          ],
        ),
    );
  }
}

// ─── Классика ─────────────────────────────────────────────────────────

/// Прежние карточки, разложенные в две колонки.
class _ClassicWideToday extends StatelessWidget {
  final VoidCallback? onOpenMoney;

  const _ClassicWideToday({this.onOpenMoney});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 32),
      children: [
        const _Greeting(),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                children: [
                  const _TonightCard(),
                  const SizedBox(height: 14),
                  const SeriesToday(),
                  _BudgetCard(onOpen: onOpenMoney),
                  const _TripCard(),
                  const _WatchlistRail(),
                ],
              ),
            ),
            const SizedBox(width: 18),
            const Expanded(
              flex: 2,
              child: Column(
                children: [
                  _TasksCard(),
                  SizedBox(height: 14),
                  _GoalsCard(),
                  SizedBox(height: 14),
                  _WrappedCard(),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Точки-отточия между названием и суммой.
class _DotsPainter extends CustomPainter {
  final Color color;

  const _DotsPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var x = 0.0; x < size.width; x += 4) {
      canvas.drawCircle(Offset(x + 0.75, size.height / 2), 0.75, paint);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.color != color;
}
