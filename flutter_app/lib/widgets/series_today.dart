import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/config.dart';
import '../data/series_repository.dart';
import '../models/series.dart';
import '../screens/movie_detail_screen.dart';
import '../screens/player_screen.dart';
import '../theme.dart';
import 'net_image.dart';

/// Сериалы на «Сегодня»: с какой серии продолжить и что выходит.
///
/// Обе части берут данные из [SeriesRepository] и прячутся, если показать
/// нечего, — поэтому блок можно ставить в любую раскладку экрана.
class SeriesToday extends StatelessWidget {
  const SeriesToday({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<SeriesRepository>();
    final progress = repo.progress.take(10).toList();
    final upcoming = repo.upcoming.take(5).toList();
    if (progress.isEmpty && upcoming.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (progress.isNotEmpty) _ContinueRail(items: progress),
          if (progress.isNotEmpty && upcoming.isNotEmpty) const SizedBox(height: 14),
          if (upcoming.isNotEmpty) _UpcomingCard(items: upcoming),
        ],
      ),
    );
  }
}

/// Открыть серию из «Продолжить»: сразу в плеере, без захода в карточку.
Future<void> _resume(BuildContext context, TvProgress p) async {
  final nav = Navigator.of(context);
  if (!PlayerScreen.isSupported) {
    // Без встроенного плеера всё равно нужна карточка — там выход в браузер.
    nav.push(MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: p.asMovie)));
    return;
  }
  final repo = context.read<SeriesRepository>();
  final source = p.source != null && Config.watchSources.containsKey(p.source)
      ? p.source!
      : Config.defaultWatchSource;
  repo.recordOpen(
    showId: p.showId,
    title: p.title,
    season: p.season,
    episode: p.episode,
    source: source,
  );
  await nav.push(MaterialPageRoute(
    builder: (_) => PlayerScreen(
      tmdbId: p.showId,
      mediaType: 'tv',
      title: p.title,
      season: p.season,
      episode: p.episode,
      source: source,
      onSourceChanged: (s) => repo.recordOpen(
        showId: p.showId,
        title: p.title,
        season: p.season,
        episode: p.episode,
        source: s,
      ),
    ),
  ));
}

class _ContinueRail extends StatelessWidget {
  final List<TvProgress> items;

  const _ContinueRail({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 4, 0, 10),
          child: Text('ПРОДОЛЖИТЬ ПРОСМОТР', style: kEyebrowStyle),
        ),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _ContinueTile(item: items[i]),
          ),
        ),
      ],
    );
  }
}

class _ContinueTile extends StatelessWidget {
  final TvProgress item;

  const _ContinueTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final still = item.stillUrl;
    return SizedBox(
      width: 224,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _resume(context, item),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (still != null)
                NetImage(
                  imageUrl: still,
                  aspect: 16 / 9,
                  placeholder: (_, _) => Container(color: AppColors.surfaceHigh),
                  errorWidget: (_, _, _) => Container(color: AppColors.surfaceHigh),
                )
              else
                Container(color: AppColors.surfaceHigh),
              // Затемнение снизу, чтобы подпись читалась на любом кадре.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xD9000000)],
                    stops: [0.35, 1],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 44,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Сезон ${item.season} · Серия ${item.episode}',
                      style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 10,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
                  child: Icon(Icons.play_arrow, size: 20, color: AppColors.bg),
                ),
              ),
              Positioned(
                right: 2,
                top: 2,
                child: _TileMenu(item: item),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Меню плитки: открыть карточку сериала или убрать его из «Продолжить».
class _TileMenu extends StatelessWidget {
  final TvProgress item;

  const _TileMenu({required this.item});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Ещё',
      color: AppColors.sheet,
      icon: const Icon(Icons.more_vert, size: 18, color: Colors.white),
      onSelected: (value) {
        if (value == 'open') {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: item.asMovie)),
          );
        } else if (value == 'hide') {
          context.read<SeriesRepository>().dismiss(item.showId);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'open', child: Text('Все серии')),
        PopupMenuItem(value: 'hide', child: Text('Убрать отсюда')),
      ],
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  final List<UpcomingEpisode> items;

  const _UpcomingCard({required this.items});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_active_outlined, size: 18, color: AppColors.gold),
              const SizedBox(width: 8),
              Text(
                'Новые серии',
                style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final e in items) _UpcomingRow(item: e, now: now),
        ],
      ),
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  final UpcomingEpisode item;
  final DateTime now;

  const _UpcomingRow({required this.item, required this.now});

  @override
  Widget build(BuildContext context) {
    final days = item.daysFrom(now);
    // Вышедшая или выходящая сегодня — главное, выделяем цветом.
    final hot = days <= 0;
    final poster = item.posterUrl;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: item.asMovie)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 34,
                height: 50,
                child: poster == null
                    ? Container(color: AppColors.surfaceHigh)
                    : NetImage(
                        imageUrl: poster,
                        aspect: 2 / 3,
                        placeholder: (_, _) => Container(color: AppColors.surfaceHigh),
                        errorWidget: (_, _, _) => Container(color: AppColors.surfaceHigh),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [item.code, if (item.realName.isNotEmpty) item.realName].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textDim, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              item.whenLabel(now),
              style: TextStyle(
                color: hot ? AppColors.gold : AppColors.textDim,
                fontSize: 12.5,
                fontWeight: hot ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
