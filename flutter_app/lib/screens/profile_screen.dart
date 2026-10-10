import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/book_repository.dart';
import '../data/profile_repository.dart';
import '../models/profile_stats.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/poster_card.dart';
import '../widgets/stats.dart';

/// Вкладка «Профиль» в разделе Кино: сколько, что и как ты смотришь,
/// плюс разбор вкуса от AI по кнопке.
class MovieProfileTab extends StatefulWidget {
  const MovieProfileTab({super.key});

  @override
  State<MovieProfileTab> createState() => _MovieProfileTabState();
}

class _MovieProfileTabState extends State<MovieProfileTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProfileRepository>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ProfileRepository>();
    final stats = repo.stats;

    if (stats == null) {
      return Center(
        child: repo.syncing
            ? const CircularProgressIndicator(color: AppColors.gold)
            : const EmptyHint(emoji: '📊', text: 'Статистика появится после первой синхронизации'),
      );
    }

    if (stats.isEmpty) {
      return const EmptyHint(
        emoji: '📊',
        text: 'Отметь что-нибудь просмотренным —\nи здесь появится разбор твоего вкуса',
      );
    }

    return RefreshIndicator(
      color: AppColors.gold,
      backgroundColor: AppColors.surface,
      onRefresh: () => context.read<ProfileRepository>().refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          _buildSummary(stats),
          const SizedBox(height: 14),
          _AiAnalysisCard(repo: repo),
          if (stats.ratingDistribution.any((b) => b.total > 0))
            StatBlock(
              title: 'Как ты оцениваешь',
              hint: stats.avgRating == null ? null : 'средняя ${stats.avgRating}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ColumnChart(
                    bars: stats.ratingDistribution
                        .map((b) => ColumnBar(label: '${b.score}', total: b.total))
                        .toList(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Оценено ${stats.ratedCount} из ${stats.total}',
                    style: const TextStyle(color: AppColors.textDim, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          if (stats.topGenres.isNotEmpty)
            StatBlock(
              title: 'Любимые жанры',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...stats.topGenres.map((g) => SplitBarRow(
                        label: g.name,
                        primary: g.movieCount,
                        secondary: g.tvCount,
                        max: stats.topGenres.first.total,
                      )),
                  const SizedBox(height: 10),
                  const ChartLegend({
                    'фильмы': AppColors.gold,
                    'сериалы': AppColors.blue,
                  }),
                ],
              ),
            ),
          if (stats.topDirectors.isNotEmpty)
            StatBlock(
              title: 'Режиссёры',
              child: Column(
                children: stats.topDirectors
                    .map((d) => SplitBarRow(
                          label: d.name,
                          primary: d.count,
                          max: stats.topDirectors.first.count,
                        ))
                    .toList(),
              ),
            ),
          if (stats.monthly.isNotEmpty)
            StatBlock(
              title: 'По месяцам',
              hint: 'последние ${stats.monthly.length > 12 ? 12 : stats.monthly.length}',
              child: ColumnChart(
                // Больше года на узком экране превращается в частокол —
                // показываем последние двенадцать точек.
                bars: stats.monthly
                    .sublist(stats.monthly.length > 12 ? stats.monthly.length - 12 : 0)
                    .map((m) => ColumnBar(label: m.shortLabel, total: m.total))
                    .toList(),
              ),
            ),
          if (stats.topRated.isNotEmpty)
            StatBlock(
              title: 'Лучшее по твоей оценке',
              child: SizedBox(
                height: 200,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: stats.topRated.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final item = stats.topRated[i];
                    return SizedBox(
                      width: 100,
                      child: PosterCard(
                        title: item.title,
                        imageUrl: item.posterUrl,
                        badge: item.rating,
                      ),
                    );
                  },
                ),
              ),
            ),
          if (stats.platforms.isNotEmpty)
            StatBlock(
              title: 'Где смотришь',
              child: Column(
                children: stats.platforms
                    .map((p) => SplitBarRow(
                          label: p.name,
                          primary: p.count,
                          max: stats.platforms.first.count,
                          primaryColor: AppColors.green,
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummary(ProfileStats stats) {
    return Row(
      children: [
        Expanded(child: StatTile(value: '${stats.total}', label: 'всего')),
        const SizedBox(width: 10),
        Expanded(child: StatTile(value: '${stats.movies}', label: 'фильмов')),
        const SizedBox(width: 10),
        Expanded(
          child: StatTile(value: '${stats.tv}', label: 'сериалов', color: AppColors.blue),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatTile(
            value: stats.avgRating?.toString() ?? '—',
            label: 'средняя',
            color: AppColors.green,
          ),
        ),
      ],
    );
  }
}

/// Разбор вкуса от AI. Запускается только по кнопке — это платный вызов,
/// и дёргать его при каждом заходе в профиль незачем.
class _AiAnalysisCard extends StatelessWidget {
  final ProfileRepository repo;

  const _AiAnalysisCard({required this.repo});

  @override
  Widget build(BuildContext context) {
    return StatBlock(
      title: '✦ Что скажет обезьянка',
      hint: repo.analysis == null ? null : 'сохранено',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (repo.analysis != null)
            Text(
              repo.analysis!,
              style: const TextStyle(color: AppColors.text, fontSize: 13.5, height: 1.6),
            )
          else if (!repo.analyzing)
            const Text(
              'Обезьянка посмотрит, что ты смотрел, и расскажет про твой вкус.',
              style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.5),
            ),
          if (repo.analysisError != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                repo.analysisError!,
                style: const TextStyle(color: AppColors.red, fontSize: 12.5),
              ),
            ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: repo.analyzing ? null : () => repo.analyze(),
              child: Text(
                repo.analyzing
                    ? 'Думает…'
                    : repo.analysis == null
                        ? 'Разобрать мой вкус'
                        : 'Обновить разбор',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Вкладка «Профиль» в разделе Книги. Сводка считается на клиенте —
/// отдельного эндпоинта под неё у бэкенда нет.
class BookProfileTab extends StatelessWidget {
  const BookProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<BookRepository>();
    final stats = repo.stats;

    if (stats.isEmpty) {
      return const EmptyHint(
        emoji: '📚',
        text: 'Отметь пару прочитанных книг —\nи здесь появится сводка',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        Row(
          children: [
            Expanded(child: StatTile(value: '${stats.readCount}', label: 'прочитано')),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                value: '${stats.wishlistCount}',
                label: 'в списке',
                color: AppColors.blue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                value: stats.avgRating == null ? '—' : stats.avgRating!.toStringAsFixed(1),
                label: 'средняя',
                color: AppColors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (stats.totalPages > 0)
          StatBlock(
            title: 'Страниц прочитано',
            child: Text(
              '${stats.totalPages}',
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        if (stats.topAuthors.isNotEmpty)
          StatBlock(
            title: 'Авторы',
            child: Column(
              children: stats.topAuthors
                  .map((a) => SplitBarRow(
                        label: a.name,
                        primary: a.count,
                        max: stats.topAuthors.first.count,
                      ))
                  .toList(),
            ),
          ),
        if (stats.topGenres.isNotEmpty)
          StatBlock(
            title: 'Жанры',
            child: Column(
              children: stats.topGenres
                  .map((g) => SplitBarRow(
                        label: g.name,
                        primary: g.count,
                        max: stats.topGenres.first.count,
                        primaryColor: AppColors.blue,
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }
}
