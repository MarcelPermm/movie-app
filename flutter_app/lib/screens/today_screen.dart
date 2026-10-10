import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/session.dart';
import '../data/budget_repository.dart';
import '../data/goal_repository.dart';
import '../data/movie_repository.dart';
import '../data/task_repository.dart';
import '../data/trip_repository.dart';
import '../models/task.dart';
import '../models/trip.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/poster_card.dart';
import 'movie_detail_screen.dart';
import 'tasks_screen.dart';
import 'tonight_screen.dart';
import 'trip_detail_screen.dart';
import 'wrapped_screen.dart';

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
    return RefreshIndicator(
      color: AppColors.gold,
      backgroundColor: AppColors.surface,
      onRefresh: () => Future.wait([
        context.read<TaskRepository>().refresh(),
        context.read<BudgetRepository>().refresh(),
        context.read<TripRepository>().refresh(),
        context.read<MovieRepository>().refresh(),
      ]),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: [
          const _Greeting(),
          const SizedBox(height: 18),
          const _TonightCard(),
          const SizedBox(height: 14),
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
            style: const TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w700),
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
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
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
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const TonightScreen()),
      ),
      child: Ink(
        padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3A2A08), Color(0xFF171009)],
          ),
          borderRadius: BorderRadius.circular(AppRadius.medium),
          border: Border.all(color: AppColors.goldWash(0.35)),
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
                    style: const TextStyle(color: AppColors.text, fontSize: 16.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Настроение, время и компания — и подборка готова',
                    style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.gold),
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
              onPressed: () => context.read<TaskRepository>().setDay(DateTime.now()),
              child: const Text('Показать задачи на сегодня'),
            )
          else if (pending.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 4, 8, 4),
              child: Text(
                all == 0 ? 'На сегодня ничего не запланировано' : 'Всё сделано — можно отдыхать 🎉',
                style: const TextStyle(color: AppColors.textDim, fontSize: 13.5),
              ),
            )
          else ...[
            ...pending.take(5).map((t) => _TaskRow(task: t)),
            if (pending.length > 5)
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 2),
                child: Text(
                  'и ещё ${pending.length - 5}',
                  style: const TextStyle(color: AppColors.textDim, fontSize: 12.5),
                ),
              ),
          ],
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
                style: const TextStyle(color: AppColors.text, fontSize: 14),
              ),
            ),
            if (task.timeStr != null && task.timeStr!.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(task.timeStr!, style: const TextStyle(color: AppColors.textDim, fontSize: 12.5)),
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
    final now = DateTime.now();
    final thisMonth = repo.month.year == now.year && repo.month.month == now.month;

    // Сколько можно тратить в день до конца месяца, чтобы уложиться в план.
    final daysLeft = DateTime(now.year, now.month + 1, 0).day - now.day + 1;
    final perDay = thisMonth && left > 0 ? left ~/ daysLeft : null;

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
                    style: TextStyle(
                      color: over ? AppColors.red : AppColors.text,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      planned > 0 ? (over ? 'перерасход' : 'осталось') : 'потрачено',
                      style: const TextStyle(color: AppColors.textDim, fontSize: 13),
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
                    backgroundColor: AppColors.bg,
                    valueColor: AlwaysStoppedAnimation(over ? AppColors.red : AppColors.gold),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  [
                    '${formatMoney(repo.total)} из ${formatMoney(planned)}',
                    if (perDay != null) 'можно ${formatMoney(perDay)} в день',
                  ].join('  ·  '),
                  style: const TextStyle(color: AppColors.textDim, fontSize: 12.5),
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
                      style: const TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(status, style: const TextStyle(color: AppColors.gold, fontSize: 12.5)),
                    if (cities.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        cities.map((c) => c.name).join(' → '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textDim, fontSize: 12.5),
                      ),
                    ],
                    if (plan > 0) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (spent / plan).clamp(0.0, 1.0),
                          minHeight: 4,
                          backgroundColor: AppColors.bg,
                          valueColor: AlwaysStoppedAnimation(
                            spent > plan ? AppColors.red : AppColors.blue,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${formatMoney(spent)} из ${formatMoney(plan)}',
                        style: const TextStyle(color: AppColors.textDim, fontSize: 12),
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
          const Padding(
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
              backgroundColor: AppColors.bg,
              valueColor: const AlwaysStoppedAnimation(AppColors.green),
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

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => WrappedScreen(year: year)),
      ),
      child: Ink(
        padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A1240), Color(0xFF0E0A18)],
          ),
          borderRadius: BorderRadius.circular(AppRadius.medium),
          border: Border.all(color: const Color(0x55B39DFF)),
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
                    style: const TextStyle(color: AppColors.text, fontSize: 16.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Фильмы, книги, поездки и деньги за год',
                    style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFFB39DFF)),
          ],
        ),
      ),
    );
  }
}
