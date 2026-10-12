import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/movie_repository.dart';
import '../data/profile_repository.dart';
import '../models/catalog.dart';
import '../models/movie.dart';
import '../theme.dart';
import '../widgets/ai_panel.dart';
import '../widgets/common.dart';
import '../widgets/poster_card.dart';
import '../widgets/rating_sheet.dart';
import '../widgets/sub_tabs.dart';
import 'actors_screen.dart';
import 'ai_suggest_screen.dart';
import 'movie_detail_screen.dart';
import 'profile_screen.dart';
import 'recommendations_screen.dart';
import 'search_screen.dart';

/// Раздел «Кино» целиком: те же семь вкладок, что в шапке сайта.
class MoviesScreen extends StatefulWidget {
  const MoviesScreen({super.key});

  @override
  State<MoviesScreen> createState() => _MoviesScreenState();
}

class _MoviesScreenState extends State<MoviesScreen> {
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

    return SubTabView(
      header: SectionHeader(
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
            icon: Icon(Icons.search, color: AppColors.textDim),
            onPressed: _openSearch,
          ),
        ],
      ),
      tabs: [
        SubTab(
          label: 'Дневник',
          count: repo.watched.length,
          builder: (_) => const MovieListTab(kind: MovieListKind.watched),
        ),
        SubTab(
          label: 'К просмотру',
          count: repo.watchlist.length,
          builder: (_) => const MovieListTab(kind: MovieListKind.watchlist),
        ),
        SubTab(
          label: 'Отклонённые',
          count: repo.dismissed.length,
          builder: (_) => const MovieListTab(kind: MovieListKind.dismissed),
        ),
        SubTab(label: 'Актёры', builder: (_) => const ActorsTab()),
        SubTab(label: 'Рекомендации', builder: (_) => const RecommendationsTab()),
        SubTab(
          label: '✦ Посоветуй',
          builder: (_) => AiSuggestTab<Movie>(
            examples: const [
              'что-нибудь медленное и осеннее',
              'умный триллер на вечер',
              'как «Прибытие», но другое',
              'комедия, но не тупая',
            ],
            fetch: (query) => context.read<ProfileRepository>().suggestMovies(query: query),
            cardBuilder: (context, movie) => _SuggestedMovieCard(movie: movie),
          ),
        ),
        SubTab(label: 'Профиль', builder: (_) => const MovieProfileTab()),
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
                    subtitle: m.isTv ? ['Сериал', if (m.shortMeta.isNotEmpty) m.shortMeta].join('  ·  ') : m.shortMeta,
                    imageUrl: m.posterUrl,
                    payload: m,
                  ))
              .toList();
        },
        // Из поиска открываем карточку — оттуда и добавляют, и оценивают.
        onPick: (searchContext, result) => Navigator.of(searchContext).push(
          MaterialPageRoute(
            builder: (_) => MovieDetailScreen(movie: result.payload as Movie),
          ),
        ),
      ),
    ));
  }
}

/// Какой из трёх списков показывает вкладка. От этого зависит и набор
/// действий в шторке, и текст пустого состояния.
enum MovieListKind { watched, watchlist, dismissed }

class MovieListTab extends StatelessWidget {
  final MovieListKind kind;

  const MovieListTab({super.key, required this.kind});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<MovieRepository>();
    final movies = switch (kind) {
      MovieListKind.watched => repo.watched,
      MovieListKind.watchlist => repo.watchlist,
      MovieListKind.dismissed => repo.dismissed,
    };

    return RefreshIndicator(
      color: AppColors.gold,
      backgroundColor: AppColors.sheet,
      onRefresh: () => context.read<MovieRepository>().refresh(),
      child: movies.isEmpty
          ? EmptyHint(
              emoji: switch (kind) {
                MovieListKind.watched => '🍿',
                MovieListKind.watchlist => '🎯',
                MovieListKind.dismissed => '🙈',
              },
              text: switch (kind) {
                MovieListKind.watched => 'Пока ничего не отмечено просмотренным',
                MovieListKind.watchlist => 'Список «к просмотру» пуст',
                MovieListKind.dismissed =>
                  'Здесь копится то, что ты скрыл из рекомендаций',
              },
            )
          : PosterGrid(
              itemCount: movies.length,
              itemBuilder: (context, i) {
                final movie = movies[i];
                return PosterCard(
                  title: movie.title,
                  subtitle: _subtitle(movie),
                  imageUrl: movie.posterUrl,
                  badge: movie.rating,
                  onTap: () => _openDetails(context, movie),
                  onLongPress: () => _showActions(context, movie),
                );
              },
            ),
    );
  }

  /// В списке «к просмотру» вместо года полезнее видеть категорию —
  /// по ней и решают, что включить сегодня.
  String? _subtitle(Movie movie) {
    if (kind != MovieListKind.watchlist) return movie.shortMeta;
    final category = WatchlistCategory.byValue(movie.category);
    if (category == null) return movie.shortMeta;
    return '${category.emoji} ${category.label}';
  }

  void _openDetails(BuildContext context, Movie movie) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: movie)),
    );
  }

  void _showActions(BuildContext context, Movie movie) {
    final repo = context.read<MovieRepository>();

    showActionSheet(
      context,
      title: movie.title,
      actions: (sheetContext) => [
        if (kind == MovieListKind.dismissed)
          ListTile(
            leading: Icon(Icons.undo, color: AppColors.green),
            title: const Text('Вернуть в рекомендации'),
            onTap: () {
              Navigator.pop(sheetContext);
              repo.undismiss(movie.id, mediaType: movie.mediaType);
            },
          ),
        if (kind == MovieListKind.watchlist) ...[
          ListTile(
            leading: Icon(Icons.check_circle_outline, color: AppColors.green),
            title: const Text('Отметить просмотренным'),
            onTap: () {
              Navigator.pop(sheetContext);
              repo.markWatched(movie);
            },
          ),
          ...WatchlistCategory.all.map((category) => ListTile(
                leading: Text(category.emoji, style: const TextStyle(fontSize: 18)),
                title: Text(category.label),
                trailing: movie.category == category.value
                    ? Icon(Icons.check, size: 18, color: AppColors.gold)
                    : null,
                onTap: () {
                  Navigator.pop(sheetContext);
                  repo.setWatchlistCategory(movie, category.value);
                },
              )),
        ],
        if (kind != MovieListKind.dismissed)
          ListTile(
            leading: Icon(Icons.star_outline, color: AppColors.gold),
            title: Text(movie.rating == null ? 'Поставить оценку' : 'Изменить оценку'),
            onTap: () async {
              Navigator.pop(sheetContext);
              final rating = await pickRating(context, title: movie.title, current: movie.rating);
              if (rating != null && context.mounted) {
                await repo.rate(movie, rating);
              }
            },
          ),
        if (kind == MovieListKind.watchlist)
          ListTile(
            leading: Icon(Icons.visibility_off_outlined, color: AppColors.textDim),
            title: const Text('Скрыть из рекомендаций'),
            onTap: () {
              Navigator.pop(sheetContext);
              repo.dismiss(movie);
            },
          ),
        ListTile(
          leading: Icon(Icons.delete_outline, color: AppColors.red),
          title: const Text('Удалить'),
          onTap: () {
            Navigator.pop(sheetContext);
            switch (kind) {
              case MovieListKind.watched:
                repo.removeFromWatched(movie.id, mediaType: movie.mediaType);
              case MovieListKind.watchlist:
                repo.removeFromWatchlist(movie.id, mediaType: movie.mediaType);
              case MovieListKind.dismissed:
                repo.undismiss(movie.id, mediaType: movie.mediaType);
            }
          },
        ),
      ],
    );
  }
}

/// Карточка из подборки AI: обложка плюс объяснение, почему это предложено.
class _SuggestedMovieCard extends StatelessWidget {
  final Movie movie;

  const _SuggestedMovieCard({required this.movie});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: PosterCard(
            title: movie.title,
            subtitle: movie.shortMeta,
            imageUrl: movie.posterUrl,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: movie)),
            ),
          ),
        ),
        if (movie.aiReason != null) AiReasonNote(movie.aiReason!),
      ],
    );
  }
}
