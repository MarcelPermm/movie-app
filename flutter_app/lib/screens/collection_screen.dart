import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/movie_repository.dart';
import '../models/movie.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/poster_card.dart';
import '../widgets/rating_sheet.dart';
import 'movie_detail_screen.dart';

/// Как отсортирована плитка.
enum CollectionSort { none, rating, year, title }

/// Вся подборка плиткой — то, что открывается ссылкой «Все →» у блока.
///
/// Лента на главной показывает первые несколько фильмов и хороша для
/// разглядывания. Когда нужно найти конкретное или окинуть взглядом весь
/// список, удобнее плитка: она показывает три десятка обложек разом.
class CollectionScreen extends StatefulWidget {
  final String title;
  final String? subtitle;
  final List<Movie> movies;

  const CollectionScreen({
    super.key,
    required this.title,
    required this.movies,
    this.subtitle,
  });

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  CollectionSort _sort = CollectionSort.none;
  String _query = '';

  /// Жанр-фильтр. Пустая строка — показывать все.
  String _genre = '';

  /// Жанры, которые реально встречаются в этой подборке. Показывать список
  /// всех жанров TMDB тут незачем — половина не дала бы ни одной карточки.
  List<String> get _genres {
    final counts = <String, int>{};
    for (final movie in widget.movies) {
      for (final g in movie.genres) {
        if (g.isNotEmpty) counts[g] = (counts[g] ?? 0) + 1;
      }
    }
    final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.map((e) => e.key).toList();
  }

  List<Movie> get _visible {
    final query = _query.trim().toLowerCase();

    final pool = widget.movies.where((m) {
      if (_genre.isNotEmpty && !m.genres.contains(_genre)) return false;
      if (query.isNotEmpty && !m.title.toLowerCase().contains(query)) return false;
      return true;
    }).toList();

    switch (_sort) {
      case CollectionSort.rating:
        pool.sort((a, b) => b.voteAverage.compareTo(a.voteAverage));
      case CollectionSort.year:
        pool.sort((a, b) => (b.releaseYear ?? 0).compareTo(a.releaseYear ?? 0));
      case CollectionSort.title:
        pool.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case CollectionSort.none:
        break; // порядок подборки — он же осмысленный
    }
    return pool;
  }

  @override
  Widget build(BuildContext context) {
    final movies = _visible;
    final genres = _genres;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              '${movies.length} из ${widget.movies.length}',
              style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildToolbar(),
          if (genres.isNotEmpty) _buildGenreStrip(genres),
          const Divider(height: 1),
          Expanded(
            child: movies.isEmpty
                ? const EmptyHint(emoji: '◌', text: 'Ничего не нашлось с такими условиями')
                : PosterGrid(
                    itemCount: movies.length,
                    itemBuilder: (context, i) {
                      final movie = movies[i];
                      return PosterCard(
                        title: movie.title,
                        subtitle: movie.shortMeta,
                        imageUrl: movie.posterUrl,
                        badge: movie.rating,
                        seen: movie.isWatched,
                        hoverAction: Icons.play_arrow_rounded,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MovieDetailScreen(movie: movie),
                          ),
                        ),
                        onLongPress: () => _showActions(movie),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Найти в подборке',
                prefixIcon: Icon(Icons.search, color: AppColors.textDim, size: 20),
                isDense: true,
              ),
              style: TextStyle(color: AppColors.text, fontSize: 14),
            ),
          ),
          const SizedBox(width: 14),
          SegmentedToggle<CollectionSort>(
            value: _sort,
            options: const {
              CollectionSort.none: 'По подборке',
              CollectionSort.rating: 'Рейтинг',
              CollectionSort.year: 'Год',
              CollectionSort.title: 'А—Я',
            },
            onChanged: (v) => setState(() => _sort = v),
          ),
        ],
      ),
    );
  }

  Widget _buildGenreStrip(List<String> genres) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
        itemCount: genres.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final value = i == 0 ? '' : genres[i - 1];
          final label = i == 0 ? 'Все жанры' : value;
          final active = _genre == value;

          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => setState(() => _genre = value),
              behavior: HitTestBehavior.opaque,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  gradient: active ? AppColors.goldGradient : null,
                  color: active ? null : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: active ? Colors.transparent : AppColors.border),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: active ? AppColors.bg : AppColors.textDim,
                    fontSize: 12.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showActions(Movie movie) {
    final repo = context.read<MovieRepository>();

    showActionSheet(
      context,
      title: movie.title,
      actions: (sheetContext) => [
        ListTile(
          leading: Icon(Icons.bookmark_add_outlined, color: AppColors.gold),
          title: const Text('В список «к просмотру»'),
          onTap: () {
            Navigator.pop(sheetContext);
            repo.addToWatchlist(movie);
          },
        ),
        ListTile(
          leading: Icon(Icons.check_circle_outline, color: AppColors.green),
          title: const Text('Уже смотрел'),
          onTap: () {
            Navigator.pop(sheetContext);
            repo.markWatched(movie);
          },
        ),
        ListTile(
          leading: Icon(Icons.visibility_off_outlined, color: AppColors.textDim),
          title: const Text('Больше не предлагать'),
          onTap: () {
            Navigator.pop(sheetContext);
            repo.dismiss(movie);
          },
        ),
      ],
    );
  }
}
