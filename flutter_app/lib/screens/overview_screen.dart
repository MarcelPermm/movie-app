import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/discover_repository.dart';
import '../data/movie_repository.dart';
import '../models/movie.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/poster_card.dart';
import 'movie_detail_screen.dart';
import 'search_screen.dart';

/// Главная: большая карусель сверху и ряды подборок под ней.
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
    });
    _heroTimer = Timer.periodic(const Duration(seconds: 8), (_) => _advanceHero());
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
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  void _open(Movie movie) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: movie)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<DiscoverRepository>();

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
                    padding: const EdgeInsets.only(bottom: 32),
                    children: [
                      if (repo.heroSlides.isNotEmpty) _buildHero(repo.heroSlides),
                      const SizedBox(height: 8),
                      if (repo.recommendations.isNotEmpty)
                        _Rail(
                          title: 'Для тебя',
                          movies: repo.recommendations,
                          onTap: _open,
                        ),
                      _Rail(
                        title: 'Популярные фильмы',
                        movies: repo.popularMovies,
                        onTap: _open,
                      ),
                      _Rail(
                        title: 'Популярные сериалы',
                        movies: repo.popularTv,
                        onTap: _open,
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
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
      height: 340,
      child: Stack(
        children: [
          PageView.builder(
            controller: _heroController,
            itemCount: slides.length,
            onPageChanged: (i) => setState(() => _heroIndex = i),
            itemBuilder: (context, i) => _HeroSlide(
              movie: slides[i],
              onOpen: () => _open(slides[i]),
            ),
          ),
          Positioned(
            bottom: 14,
            right: 22,
            child: Row(
              children: List.generate(slides.length, (i) {
                final active = i == _heroIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.only(left: 6),
                  height: 5,
                  width: active ? 20 : 6,
                  decoration: BoxDecoration(
                    color: active ? AppColors.gold : AppColors.textDim,
                    borderRadius: BorderRadius.circular(3),
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

  const _HeroSlide({required this.movie, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      child: Stack(
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
          // Двойной градиент: снизу — под текст, слева — чтобы буквы
          // не тонули в светлых кадрах.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                stops: [0.0, 0.55, 1.0],
                colors: [AppColors.bg, Color(0xBB0A0A0F), Color(0x330A0A0F)],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xCC0A0A0F), Colors.transparent],
              ),
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            bottom: 30,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (movie.genres.isNotEmpty)
                  Text(
                    movie.genres.take(3).join('  ·  ').toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 10,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Text(
                    movie.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                ),
                if (movie.shortMeta.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    movie.shortMeta,
                    style: const TextStyle(color: AppColors.textDim, fontSize: 13),
                  ),
                ],
                if (movie.overview.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Text(
                      movie.overview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.play_arrow, size: 20),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.bg,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                  ),
                  label: const Text('Открыть'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Горизонтальный ряд подборки.
class _Rail extends StatelessWidget {
  final String title;
  final List<Movie> movies;
  final void Function(Movie) onTap;

  const _Rail({required this.title, required this.movies, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (movies.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(
          height: 252,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: movies.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final movie = movies[i];
              return SizedBox(
                width: 132,
                child: Stack(
                  children: [
                    PosterCard(
                      title: movie.title,
                      subtitle: movie.shortMeta,
                      imageUrl: movie.posterUrl,
                      badge: movie.rating,
                      onTap: () => onTap(movie),
                    ),
                    // Уже просмотренное помечаем, чтобы не открывать зря.
                    if (movie.isWatched)
                      const Positioned(
                        left: 6,
                        top: 6,
                        child: CircleAvatar(
                          radius: 11,
                          backgroundColor: AppColors.green,
                          child: Icon(Icons.check, size: 13, color: AppColors.bg),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
