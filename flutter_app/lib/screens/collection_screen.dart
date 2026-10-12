import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/movie_repository.dart';
import '../models/movie.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/media_filters.dart';
import '../widgets/poster_card.dart';
import '../widgets/rating_sheet.dart';
import 'movie_detail_screen.dart';

/// Вся подборка плиткой — то, что открывается ссылкой «Все →» у блока.
///
/// Лента на главной показывает первые несколько фильмов и хороша для
/// разглядывания. Когда нужно найти конкретное или окинуть взглядом весь
/// список, удобнее плитка с фильтрами (см. [MediaFilterBar]).
class CollectionScreen extends StatefulWidget {
  final String title;
  final String? subtitle;
  final List<Movie> movies;

  /// Подпись первого порядка: «По вкусу» для рекомендаций, иначе «По подборке».
  final String relevanceLabel;

  const CollectionScreen({
    super.key,
    required this.title,
    required this.movies,
    this.subtitle,
    this.relevanceLabel = 'По подборке',
  });

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  MediaFilter _filter = const MediaFilter();
  String _query = '';

  List<Movie> get _visible {
    final query = _query.trim().toLowerCase();
    final pool = query.isEmpty
        ? widget.movies
        : widget.movies.where((m) => m.title.toLowerCase().contains(query)).toList();
    return _filter.apply(pool);
  }

  @override
  Widget build(BuildContext context) {
    final movies = _visible;

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
          _buildSearch(),
          MediaFilterBar(
            pool: widget.movies,
            filter: _filter,
            relevanceLabel: widget.relevanceLabel,
            onChanged: (f) => setState(() => _filter = f),
          ),
          const Divider(height: 1),
          Expanded(
            child: movies.isEmpty
                ? EmptyHint(
                    emoji: '◌',
                    text: _filter.activeCount > 0
                        ? 'С такими фильтрами пусто — нажми «Сбросить»'
                        : 'Ничего не нашлось',
                  )
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

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: TextField(
        onChanged: (v) => setState(() => _query = v),
        decoration: InputDecoration(
          hintText: 'Найти в подборке',
          prefixIcon: Icon(Icons.search, color: AppColors.textDim, size: 20),
          isDense: true,
        ),
        style: TextStyle(color: AppColors.text, fontSize: 14),
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
