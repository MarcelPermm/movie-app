import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/discover_repository.dart';
import '../data/movie_repository.dart';
import '../models/movie.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/media_rail.dart';
import 'collection_screen.dart';
import 'movie_detail_screen.dart';
import 'search_screen.dart';

/// Главная: большая карусель сверху и блоки подборок под ней.
///
/// Все блоки, кроме «Для тебя», собираются из уже загруженных списков —
/// новых запросов к серверу главная не делает.
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  final _heroController = PageController();
  Timer? _heroTimer;
  int _heroIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DiscoverRepository>().load();
      context.read<MovieRepository>().load();
    });
    _heroTimer = Timer.periodic(const Duration(seconds: 9), (_) => _advanceHero());
  }

  @override
  void dispose() {
    _heroTimer?.cancel();
    _heroController.dispose();
    super.dispose();
  }

  void _advanceHero() {
    final slides = context.read<DiscoverRepository>().heroSlides;
    if (slides.length < 2 || !_heroController.hasClients) return;
    _heroController.animateToPage(
      (_heroIndex + 1) % slides.length,
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOutCubic,
    );
  }

  void _open(Movie movie) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: movie)),
    );
  }

  void _quickAdd(Movie movie) {
    context.read<MovieRepository>().addToWatchlist(movie);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('«${movie.title}» — в список к просмотру'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<DiscoverRepository>();
    final movies = context.watch<MovieRepository>();

    return Column(
      children: [
        SectionHeader(
          title: 'Обзор',
          actions: [
            IconButton(
              tooltip: 'Поиск',
              icon: const Icon(Icons.search, color: AppColors.textDim),
              onPressed: _openSearch,
            ),
          ],
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.gold,
            backgroundColor: AppColors.surface,
            onRefresh: () => context.read<DiscoverRepository>().refresh(),
            child: repo.isEmpty
                ? EmptyHint(
                    emoji: '🍿',
                    text: repo.syncing ? 'Собираем подборку…' : 'Подборка пока не загрузилась',
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 40),
                    children: _buildRails(repo, movies),
                  ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildRails(DiscoverRepository repo, MovieRepository movies) {
    final rails = <Widget>[
      if (repo.heroSlides.isNotEmpty) _buildHero(repo.heroSlides),
      const SizedBox(height: 30),
    ];

    void add(String title, String eyebrow, List<Movie> items) {
      if (items.isEmpty) return;
      rails.add(MediaRail(
        title: title,
        eyebrow: eyebrow,
        movies: items,
        onOpen: _open,
        onQuickAdd: _quickAdd,
        // «Все» открывает ту же подборку плиткой — с поиском, сортировкой
        // и фильтром по жанрам, как раздел на сайте.
        onShowAll: () => _openCollection(title, eyebrow, items),
      ));
    }

    add('Для тебя', 'подобрано по просмотренному', repo.recommendations);
    add('Продолжить с того же места', 'твой список', movies.watchlist);
    add('Популярные фильмы', 'на этой неделе', repo.popularMovies);
    add('Популярные сериалы', 'на этой неделе', repo.popularTv);

    // Жанровые блоки собираем из уже загруженного: три самых частых жанра
    // в популярном. Так главная растёт вширь, не добавляя запросов.
    final pool = [...repo.popularMovies, ...repo.popularTv, ...repo.recommendations];
    for (final genre in _topGenres(pool, 3)) {
      final byGenre = pool.where((m) => m.genres.contains(genre)).toList();
      if (byGenre.length < 4) continue;
      add(genre, 'подборка по жанру', _unique(byGenre));
    }

    // Высокие оценки — без баннера: блок замыкает страницу, и второй крупный
    // кадр подряд перегрузил бы её.
    final acclaimed = pool.where((m) => m.voteAverage >= 7.5).toList()
      ..sort((a, b) => b.voteAverage.compareTo(a.voteAverage));
    if (acclaimed.length >= 4) {
      rails.add(MediaRail(
        title: 'Высоко оценённое',
        eyebrow: 'рейтинг 7.5 и выше',
        movies: _unique(acclaimed),
        onOpen: _open,
        onQuickAdd: _quickAdd,
        onShowAll: () =>
            _openCollection('Высоко оценённое', 'рейтинг 7.5 и выше', _unique(acclaimed)),
        showBanner: false,
      ));
    }

    return rails;
  }

  void _openCollection(String title, String subtitle, List<Movie> items) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CollectionScreen(
        title: title,
        subtitle: subtitle,
        movies: items,
      ),
    ));
  }

  /// Самые частые жанры в наборе.
  List<String> _topGenres(List<Movie> pool, int limit) {
    final counts = <String, int>{};
    for (final movie in pool) {
      for (final genre in movie.genres) {
        if (genre.isEmpty) continue;
        counts[genre] = (counts[genre] ?? 0) + 1;
      }
    }
    final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).map((e) => e.key).toList();
  }

  /// Один и тот же фильм попадает и в популярное, и в рекомендации —
  /// в общем блоке он не должен появляться дважды.
  List<Movie> _unique(List<Movie> items) {
    final seen = <String>{};
    final result = <Movie>[];
    for (final movie in items) {
      if (seen.add('${movie.mediaType}:${movie.id}')) result.add(movie);
    }
    return result;
  }

  void _openSearch() {
    final movies = context.read<MovieRepository>();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SearchScreen(
        hint: 'Название фильма или сериала',
        onSearch: (query) async {
          final found = await movies.search(query);
          return found
              .map((m) => SearchResult(
                    title: m.title,
                    subtitle: m.shortMeta,
                    imageUrl: m.posterUrl,
                    payload: m,
                  ))
              .toList();
        },
        onPick: (searchContext, result) => Navigator.of(searchContext).push(
          MaterialPageRoute(
            builder: (_) => MovieDetailScreen(movie: result.payload as Movie),
          ),
        ),
      ),
    ));
  }

  // ─── Карусель ───────────────────────────────────────────────────────

  Widget _buildHero(List<Movie> slides) {
    return SizedBox(
      height: 440,
      child: Stack(
        children: [
          PageView.builder(
            controller: _heroController,
            itemCount: slides.length,
            onPageChanged: (i) => setState(() => _heroIndex = i),
            itemBuilder: (context, i) => _HeroSlide(
              movie: slides[i],
              onOpen: () => _open(slides[i]),
              onAdd: () => _quickAdd(slides[i]),
            ),
          ),
          Positioned(
            bottom: 26,
            right: 30,
            child: Row(
              children: List.generate(slides.length, (i) {
                final active = i == _heroIndex;
                return GestureDetector(
                  onTap: () => _heroController.animateToPage(
                    i,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    margin: const EdgeInsets.only(left: 7),
                    height: 4,
                    width: active ? 30 : 12,
                    decoration: BoxDecoration(
                      gradient: active ? AppColors.goldGradient : null,
                      color: active ? null : const Color(0x55FFFFFF),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroSlide extends StatelessWidget {
  final Movie movie;
  final VoidCallback onOpen;
  final VoidCallback onAdd;

  const _HeroSlide({required this.movie, required this.onOpen, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (movie.backdropUrl != null)
          CachedNetworkImage(
            imageUrl: movie.backdropUrl!,
            fit: BoxFit.cover,
            placeholder: (_, _) => Container(color: AppColors.surface),
            errorWidget: (_, _, _) => Container(color: AppColors.surface),
          )
        else
          Container(color: AppColors.surface),

        // Три слоя затемнения: снизу — под текст, слева — под колонку,
        // сверху — чтобы шапка не спорила с кадром.
        const DecoratedBox(decoration: BoxDecoration(gradient: AppColors.scrim)),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: [0.0, 0.55, 1.0],
              colors: [Color(0xEE08080C), Color(0x8808080C), Colors.transparent],
            ),
          ),
        ),

        Positioned(
          left: 30,
          right: 30,
          bottom: 40,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: AppColors.goldGradient,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        movie.isTv ? 'СЕРИАЛ' : 'ФИЛЬМ',
                        style: const TextStyle(
                          color: AppColors.bg,
                          fontSize: 9.5,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (movie.genres.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          movie.genres.take(3).join('  ·  ').toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: kEyebrowStyle.copyWith(color: AppColors.text),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  movie.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 46,
                    fontWeight: FontWeight.w800,
                    height: 1.03,
                    letterSpacing: -1.4,
                    shadows: [
                      Shadow(color: Color(0xCC000000), blurRadius: 22, offset: Offset(0, 4)),
                    ],
                  ),
                ),
                if (movie.shortMeta.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    movie.shortMeta,
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (movie.overview.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    movie.overview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 14,
                      height: 1.55,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: onOpen,
                      icon: const Icon(Icons.play_arrow_rounded, size: 24),
                      label: const Text('Смотреть'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: onAdd,
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('В список'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.text,
                        backgroundColor: const Color(0x66121218),
                        side: const BorderSide(color: Color(0x44FFFFFF)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
