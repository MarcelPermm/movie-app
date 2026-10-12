import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../data/discover_repository.dart';
import '../data/movie_repository.dart';
import '../models/catalog.dart';
import '../models/movie.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/media_filters.dart';
import '../widgets/poster_card.dart';
import '../widgets/rating_sheet.dart';
import 'movie_detail_screen.dart';

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

  MediaFilter _filter = const MediaFilter();
  int? _studioId;

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
      final studiosFuture = discover.studios(mediaType);

      final movies = await moviesFuture;
      final studios = await studiosFuture;

      if (!mounted) return;
      setState(() {
        _all = movies;
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

  /// Фильтры и сортировка поверх загруженного списка — на клиенте.
  List<Movie> get _filtered => _filter.apply(_all);

  @override
  Widget build(BuildContext context) {
    _syncWithMediaType(context.watch<MovieRepository>().mediaType);
    final movies = _filtered;

    return Column(
      children: [
        MediaFilterBar(
          pool: _all,
          filter: _filter,
          onChanged: (f) => setState(() => _filter = f),
          extra: [
            if (_studios.isNotEmpty)
              FilterButton(
                label: _studioName ?? (_mediaType == 'tv' ? 'Площадка' : 'Студия'),
                active: _studioId != null,
                onTap: _pickStudio,
              ),
          ],
        ),
        const Divider(height: 1),
        Expanded(child: _buildBody(movies)),
      ],
    );
  }

  String? get _studioName {
    for (final s in _studios) {
      if (s.id == _studioId) return s.name;
    }
    return null;
  }

  /// Студию считает сервер: выбор перезапрашивает подборку.
  void _pickStudio() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.sheet,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                _mediaType == 'tv' ? 'Площадка' : 'Студия',
                style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            for (final option in [null, ..._studios])
              ListTile(
                dense: true,
                leading: Icon(
                  _studioId == option?.id ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: _studioId == option?.id ? AppColors.gold : AppColors.textDim,
                  size: 20,
                ),
                title: Text(option?.name ?? 'Любая', style: TextStyle(color: AppColors.text)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  if (_studioId == option?.id) return;
                  setState(() => _studioId = option?.id);
                  _ensureLoaded();
                },
              ),
          ],
        ),
      ),
    );
  }

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
            : 'С такими фильтрами пусто — нажми «Сбросить»',
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
