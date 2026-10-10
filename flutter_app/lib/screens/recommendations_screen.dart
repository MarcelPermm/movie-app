import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../data/discover_repository.dart';
import '../data/movie_repository.dart';
import '../models/catalog.dart';
import '../models/movie.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/poster_card.dart';
import '../widgets/rating_sheet.dart';
import '../widgets/sub_tabs.dart';
import 'movie_detail_screen.dart';

/// Как отсортирована подборка.
enum RecSort { relevance, rating, year }

/// Вкладка «Рекомендации» с фильтрами.
///
/// Подборку считает сервер (это дорого — до двух тысяч кандидатов), а вот
/// фильтры и сортировка работают на клиенте по уже полученному списку.
/// Так же устроена и веб-версия: перебор фильтров не гоняет сервер заново.
class RecommendationsTab extends StatefulWidget {
  const RecommendationsTab({super.key});

  @override
  State<RecommendationsTab> createState() => _RecommendationsTabState();
}

class _RecommendationsTabState extends State<RecommendationsTab> {
  List<Movie> _all = const [];
  bool _loading = false;
  String? _error;

  /// Тип, для которого загружена текущая подборка. Переключение
  /// «фильмы / сериалы» в шапке раздела должно её перезапросить.
  String? _loadedFor;

  final _includeGenres = <String>{};
  final _excludeGenres = <String>{};
  final _countries = <String>{};
  int? _studioId;
  double _minRating = 0;
  RecSort _sort = RecSort.relevance;
  bool _filtersOpen = false;

  List<CatalogOption> _genres = const [];
  List<CatalogOption> _studios = const [];

  String get _mediaType => context.read<MovieRepository>().mediaType;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureLoaded());
  }

  /// Тип задаётся в шапке раздела, выше по дереву. Заметить его смену можно
  /// только при перестроении — отсюда и проверка в build.
  void _syncWithMediaType(String mediaType) {
    if (_loadedFor == null || _loadedFor == mediaType || _loading) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureLoaded();
    });
  }

  Future<void> _ensureLoaded() async {
    final mediaType = _mediaType;
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
      _loadedFor = mediaType;
    });

    final discover = context.read<DiscoverRepository>();
    try {
      // Справочники почти всегда приходят из кэша, поэтому берём их
      // вместе с подборкой — отдельного ожидания не возникает.
      // Типы результатов разные, поэтому ждём их по отдельности, а не одним
      // Future.wait со списком разнородных футур — так не теряется типизация.
      final moviesFuture = _studioId == null
          ? discover.fetchRecommendations(mediaType: mediaType)
          : discover.studioMovies(_studioId!, mediaType);
      final genresFuture = discover.genres(mediaType);
      final studiosFuture = discover.studios(mediaType);

      final movies = await moviesFuture;
      final genres = await genresFuture;
      final studios = await studiosFuture;

      if (!mounted) return;
      setState(() {
        _all = movies;
        _genres = genres;
        _studios = studios;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      // 400 «добавь хотя бы один фильм» — не ошибка, а нормальный старт.
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Фильтры и сортировка поверх загруженного списка.
  List<Movie> get _filtered {
    var pool = _all.where((m) {
      if (_minRating > 0 && m.voteAverage < _minRating) return false;

      if (_includeGenres.isNotEmpty && !m.genres.any(_includeGenres.contains)) return false;
      if (_excludeGenres.isNotEmpty && m.genres.any(_excludeGenres.contains)) return false;

      if (_countries.isNotEmpty && !m.originCountries.any(_countries.contains)) return false;

      return true;
    }).toList();

    switch (_sort) {
      case RecSort.rating:
        pool.sort((a, b) => b.voteAverage.compareTo(a.voteAverage));
      case RecSort.year:
        pool.sort((a, b) => (b.releaseYear ?? 0).compareTo(a.releaseYear ?? 0));
      case RecSort.relevance:
        break; // порядок сервера и есть релевантность
    }
    return pool;
  }

  int get _activeFilterCount =>
      _includeGenres.length +
      _excludeGenres.length +
      _countries.length +
      (_minRating > 0 ? 1 : 0) +
      (_studioId != null ? 1 : 0);

  void _resetFilters() {
    // Студия — единственный фильтр, который считает сервер: его сброс
    // требует нового запроса, остальные пересчитываются на месте.
    final hadStudio = _studioId != null;
    setState(() {
      _includeGenres.clear();
      _excludeGenres.clear();
      _countries.clear();
      _minRating = 0;
      _sort = RecSort.relevance;
      _studioId = null;
    });
    if (hadStudio) _ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    _syncWithMediaType(context.watch<MovieRepository>().mediaType);
    final movies = _filtered;

    return Column(
      children: [
        _buildToolbar(),
        if (_filtersOpen) _buildFilterPanel(),
        const Divider(height: 1),
        Expanded(child: _buildBody(movies)),
      ],
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
      child: Row(
        children: [
          SegmentedToggle<RecSort>(
            value: _sort,
            options: const {
              RecSort.relevance: 'По вкусу',
              RecSort.rating: 'По рейтингу',
              RecSort.year: 'По году',
            },
            onChanged: (v) => setState(() => _sort = v),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => setState(() => _filtersOpen = !_filtersOpen),
            icon: Icon(
              _filtersOpen ? Icons.expand_less : Icons.tune,
              size: 18,
              color: _activeFilterCount > 0 ? AppColors.gold : AppColors.textDim,
            ),
            label: Text(
              _activeFilterCount > 0 ? 'Фильтры · $_activeFilterCount' : 'Фильтры',
              style: TextStyle(
                color: _activeFilterCount > 0 ? AppColors.gold : AppColors.textDim,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _filterLabel('Жанры', 'нажми ещё раз — исключить'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: _genres.map((g) {
              final included = _includeGenres.contains(g.name);
              final excluded = _excludeGenres.contains(g.name);
              return GestureDetector(
                // Три состояния по кругу: нейтрально → включить → исключить.
                // Это ровно тот же жест, что в панелях фильтров на сайте.
                onTap: () => setState(() {
                  if (included) {
                    _includeGenres.remove(g.name);
                    _excludeGenres.add(g.name);
                  } else if (excluded) {
                    _excludeGenres.remove(g.name);
                  } else {
                    _includeGenres.add(g.name);
                  }
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: included
                        ? AppColors.gold
                        : excluded
                            ? AppColors.red.withValues(alpha: 0.18)
                            : AppColors.bg,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(
                      color: included
                          ? AppColors.gold
                          : excluded
                              ? AppColors.red
                              : AppColors.border,
                    ),
                  ),
                  child: Text(
                    excluded ? '− ${g.name}' : g.name,
                    style: TextStyle(
                      color: included
                          ? AppColors.bg
                          : excluded
                              ? AppColors.red
                              : AppColors.textDim,
                      fontSize: 12,
                      fontWeight: included ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          _filterLabel('Страна'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: CountryOption.all
                .map((c) => FilterChipPill(
                      label: c.label,
                      selected: _countries.contains(c.code),
                      onTap: () => setState(() {
                        _countries.contains(c.code)
                            ? _countries.remove(c.code)
                            : _countries.add(c.code);
                      }),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          _filterLabel(
            _mediaType == 'tv' ? 'Площадка' : 'Студия',
            'подборка перезапросится',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              FilterChipPill(
                label: 'Любая',
                selected: _studioId == null,
                onTap: () {
                  if (_studioId == null) return;
                  setState(() => _studioId = null);
                  _ensureLoaded();
                },
              ),
              ..._studios.map((s) => FilterChipPill(
                    label: s.name,
                    selected: _studioId == s.id,
                    onTap: () {
                      setState(() => _studioId = _studioId == s.id ? null : s.id);
                      _ensureLoaded();
                    },
                  )),
            ],
          ),
          const SizedBox(height: 16),
          _filterLabel(
            'Рейтинг TMDB',
            _minRating == 0 ? 'любой' : 'от ${_minRating.toStringAsFixed(1)}',
          ),
          Slider(
            value: _minRating,
            min: 0,
            max: 9,
            divisions: 18,
            activeColor: AppColors.gold,
            inactiveColor: AppColors.border,
            label: _minRating == 0 ? 'любой' : _minRating.toStringAsFixed(1),
            onChanged: (v) => setState(() => _minRating = v),
          ),
          if (_activeFilterCount > 0)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _resetFilters,
                child: Text('Сбросить всё', style: TextStyle(color: AppColors.textDim)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterLabel(String text, [String? hint]) => Row(
        children: [
          Text(
            text.toUpperCase(),
            style: TextStyle(
              color: AppColors.textDim,
              fontSize: 10,
              letterSpacing: 0.9,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(width: 8),
            Text(hint, style: TextStyle(color: AppColors.textDim, fontSize: 10.5)),
          ],
        ],
      );

  Widget _buildBody(List<Movie> movies) {
    if (_loading && _all.isEmpty) {
      return Center(child: CircularProgressIndicator(color: AppColors.gold));
    }

    if (_error != null && _all.isEmpty) {
      return EmptyHint(emoji: '🎬', text: _error!);
    }

    if (movies.isEmpty) {
      return EmptyHint(
        emoji: '◌',
        text: _all.isEmpty
            ? 'Подборка пока пуста'
            : 'С такими фильтрами ничего не осталось',
      );
    }

    return RefreshIndicator(
      color: AppColors.gold,
      backgroundColor: AppColors.sheet,
      onRefresh: _ensureLoaded,
      child: PosterGrid(
        itemCount: movies.length,
        itemBuilder: (context, i) {
          final movie = movies[i];
          return PosterCard(
            title: movie.title,
            subtitle: movie.shortMeta,
            imageUrl: movie.posterUrl,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: movie)),
            ),
            onLongPress: () => _showActions(movie),
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
            // Убираем сразу: ждать следующей подборки, чтобы карточка исчезла,
            // — значит смотреть на то, что ты только что отклонил.
            setState(() => _all = _all.where((m) => m.id != movie.id).toList());
          },
        ),
      ],
    );
  }
}
