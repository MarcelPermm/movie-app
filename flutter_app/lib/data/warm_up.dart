import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'book_repository.dart';
import 'budget_repository.dart';
import 'discover_repository.dart';
import 'goal_repository.dart';
import 'movie_repository.dart';
import 'notebook_repository.dart';
import 'profile_repository.dart';
import 'task_repository.dart';
import 'trip_repository.dart';
import 'wishlist_repository.dart';

/// Освежить разделы при запуске и при возврате в приложение.
///
/// В два захода: сперва то, что видно на «Сегодня», потом остальное.
/// Сервер на бесплатном тарифе слабый, и десяток запросов разом делят его
/// поровну — а первым нужен главный экран, а не вишлист.
///
/// Каждый раздел сам решает, идти ли в сеть: свежий кэш запроса не даст.
Future<void> warmUp(BuildContext context) async {
  // Всё читаем до первого await: дальше контекст может уже не жить.
  final today = <Future<void> Function()>[
    context.read<TaskRepository>().load,
    context.read<WeekGoalRepository>().load,
    context.read<BudgetRepository>().load,
    context.read<TripRepository>().load,
    context.read<MovieRepository>().load,
    context.read<DiscoverRepository>().load,
  ];
  final rest = <Future<void> Function()>[
    context.read<GoalRepository>().load,
    context.read<NotebookRepository>().load,
    context.read<BookRepository>().load,
    context.read<WishlistRepository>().load,
    context.read<ProfileRepository>().load,
  ];

  Future<void> safe(Future<void> Function() load) => load().catchError((Object _) {});

  // Второй заход не ждёт дольше пары секунд: если сервер просыпается,
  // всё равно встанем в одну очередь.
  await Future.any([
    Future.wait(today.map(safe)),
    Future<void>.delayed(const Duration(seconds: 2)),
  ]);
  for (final load in rest) {
    unawaited(safe(load));
  }
}
