import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/movie_repository.dart';
import '../models/movie.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/poster_card.dart';
import '../widgets/rating_sheet.dart';
import 'search_screen.dart';

class MoviesScreen extends StatefulWidget {
  const MoviesScreen({super.key});

  @override
  State<MoviesScreen> createState() => _MoviesScreenState();
}

class _MoviesScreenState extends State<MoviesScreen> {
  bool _showWatched = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MovieRepository>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<MovieRepository>();
    final movies = _showWatched ? repo.watched : repo.watchlist;

    return Column(
      children: [
        SectionHeader(
          title: 'Кино',
          actions: [
            SegmentedToggle<String>(
              value: repo.mediaType,
              options: const {'movie': 'Фильмы', 'tv': 'Сериалы'},
              onChanged: (v) => context.read<MovieRepository>().setMediaType(v),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Поиск',
              icon: const Icon(Icons.search, color: AppColors.textDim),
              onPressed: _openSearch,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedToggle<bool>(
              value: _showWatched,
              options: {
                true: 'Просмотрено · ${repo.watched.length}',
                false: 'К просмотру · ${repo.watchlist.length}',
              },
              onChanged: (v) => setState(() => _showWatched = v),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.gold,
            backgroundColor: AppColors.surface,
            onRefresh: () => context.read<MovieRepository>().refresh(),
            child: movies.isEmpty
                ? EmptyHint(
                    emoji: '🍿',
                    text: _showWatched
                        ? 'Пока ничего не отмечено просмотренным'
                        : 'Список «к просмотру» пуст',
                  )
                : PosterGrid(
                    itemCount: movies.length,
                    itemBuilder: (context, i) => PosterCard(
                      title: movies[i].title,
                      subtitle: movies[i].releaseYear?.toString(),
                      imageUrl: movies[i].posterUrl,
                      badge: movies[i].rating,
                      onTap: () => _showActions(movies[i]),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  void _openSearch() {
    final repo = context.read<MovieRepository>();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SearchScreen(
        hint: 'Название фильма или сериала',
        onSearch: (query) async {
          final found = await repo.search(query);
          return found
              .map((m) => SearchResult(
                    title: m.title,
                    subtitle: m.releaseYear?.toString(),
                    imageUrl: m.posterUrl,
                    payload: m,
                  ))
              .toList();
        },
        onPick: (result) {
          final movie = result.payload as Movie;
          repo.addToWatchlist(movie);
          return '«${movie.title}» добавлен к просмотру';
        },
      ),
    ));
  }

  void _showActions(Movie movie) {
    final watched = _showWatched;
    showActionSheet(
      context,
      title: movie.title,
      actions: (sheetContext) => [
        if (!watched)
          ListTile(
            leading: const Icon(Icons.check_circle_outline, color: AppColors.green),
            title: const Text('Отметить просмотренным'),
            onTap: () {
              Navigator.pop(sheetContext);
              context.read<MovieRepository>().markWatched(movie);
            },
          ),
        ListTile(
          leading: const Icon(Icons.star_outline, color: AppColors.gold),
          title: Text(movie.rating == null ? 'Поставить оценку' : 'Изменить оценку'),
          onTap: () async {
            Navigator.pop(sheetContext);
            final rating = await pickRating(context, title: movie.title, current: movie.rating);
            if (rating != null && mounted) {
              await context.read<MovieRepository>().rate(movie, rating);
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline, color: AppColors.red),
          title: const Text('Удалить'),
          onTap: () {
            Navigator.pop(sheetContext);
            final repo = context.read<MovieRepository>();
            watched ? repo.removeFromWatched(movie.id) : repo.removeFromWatchlist(movie.id);
          },
        ),
      ],
    );
  }
}
