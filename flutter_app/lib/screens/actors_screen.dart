import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../data/actor_repository.dart';
import '../data/discover_repository.dart';
import '../models/movie.dart';
import '../models/person.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/poster_card.dart';
import 'movie_detail_screen.dart';
import '../widgets/net_image.dart';

/// Вкладка «Актёры»: кого ты смотришь чаще всего и кого отметил избранным.
class ActorsTab extends StatefulWidget {
  const ActorsTab({super.key});

  @override
  State<ActorsTab> createState() => _ActorsTabState();
}

class _ActorsTabState extends State<ActorsTab> {
  bool _onlyFavorites = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ActorRepository>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ActorRepository>();
    final all = repo.topAnnotated;
    final actors = _onlyFavorites ? all.where((a) => a.isFavorite).toList() : all;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Row(
            children: [
              SegmentedToggle<bool>(
                value: _onlyFavorites,
                options: {
                  false: 'Все · ${all.length}',
                  true: '★ Избранные · ${repo.favorites.length}',
                },
                onChanged: (v) => setState(() => _onlyFavorites = v),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Найти человека',
                icon: Icon(Icons.person_search_outlined, color: AppColors.textDim),
                onPressed: _openPersonSearch,
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.gold,
            backgroundColor: AppColors.sheet,
            onRefresh: () => context.read<ActorRepository>().refresh(),
            child: actors.isEmpty
                ? EmptyHint(
                    emoji: '🎭',
                    text: _onlyFavorites
                        ? 'Отметь звёздочкой тех, за кем следишь'
                        : repo.syncing
                            ? 'Считаем, кого ты смотришь чаще всего…'
                            : 'Отметь несколько фильмов просмотренными —\nи здесь появятся их актёры',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                    itemCount: actors.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _ActorRow(actor: actors[i]),
                  ),
          ),
        ),
      ],
    );
  }

  /// Поиск человека в TMDB — чтобы добавить в избранные того,
  /// чьих фильмов ты ещё не отмечал.
  void _openPersonSearch() {
    final repo = context.read<ActorRepository>();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PersonSearchScreen(repo: repo),
    ));
  }
}

class _ActorRow extends StatelessWidget {
  final TopActor actor;

  const _ActorRow({required this.actor});

  @override
  Widget build(BuildContext context) {
    final avg = actor.averageRating;

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      // Без TMDB-id фильмографию не открыть — бэкенд ищет по id, не по имени.
      onTap: actor.id == null
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PersonScreen(
                  personId: actor.id!,
                  name: actor.name,
                  profilePath: actor.profilePath,
                ),
              )),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: cardDecoration(highlighted: actor.isFavorite),
        child: Row(
          children: [
            _Avatar(url: actor.photoUrl, name: actor.name, size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    actor.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    actor.countLabel,
                    style: TextStyle(color: AppColors.textDim, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (avg != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Tooltip(
                  message: 'Твоя средняя оценка фильмам с ним',
                  child: Text(
                    '★ ${avg.toStringAsFixed(1)}',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            if (actor.id != null)
              IconButton(
                tooltip: actor.isFavorite ? 'Убрать из избранных' : 'В избранные',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  actor.isFavorite ? Icons.star : Icons.star_border,
                  color: actor.isFavorite ? AppColors.gold : AppColors.textDim,
                  size: 20,
                ),
                onPressed: () => context.read<ActorRepository>().toggleFavorite(actor),
              ),
          ],
        ),
      ),
    );
  }
}

/// Экран человека: что из просмотренного с ним связано и что ещё можно
/// посмотреть. Открывается и из списка актёров, и из карточки фильма.
class PersonScreen extends StatefulWidget {
  final int personId;
  final String name;
  final String? profilePath;

  const PersonScreen({
    super.key,
    required this.personId,
    required this.name,
    this.profilePath,
  });

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen> {
  List<Movie>? _watched;
  List<Movie>? _filmography;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final actors = context.read<ActorRepository>();
    final discover = context.read<DiscoverRepository>();
    try {
      // Оба списка независимы — тянем разом, экран собирается за один шаг.
      final results = await Future.wait([
        actors.watchedAppearances(widget.personId),
        discover.personMovies(widget.personId, 'movie'),
      ]);
      if (!mounted) return;
      setState(() {
        _watched = results[0];
        _filmography = results[1];
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final favorite = context.watch<ActorRepository>().isFavorite(widget.personId);
    final watched = _watched;
    final filmography = _filmography;
    final watchedIds = (watched ?? const <Movie>[]).map((m) => m.id).toSet();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name, style: const TextStyle(fontSize: 17)),
        actions: [
          IconButton(
            tooltip: favorite ? 'Убрать из избранных' : 'В избранные',
            icon: Icon(
              favorite ? Icons.star : Icons.star_border,
              color: favorite ? AppColors.gold : AppColors.textDim,
            ),
            onPressed: () {
              final repo = context.read<ActorRepository>();
              favorite
                  ? repo.removeFavorite(widget.personId)
                  : repo.addFavorite(FavoriteActor(
                      actorId: widget.personId,
                      name: widget.name,
                      profilePath: widget.profilePath,
                    ));
            },
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.red, fontSize: 13.5),
                ),
              ),
            )
          : watched == null
              ? Center(child: CircularProgressIndicator(color: AppColors.gold))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    if (watched.isNotEmpty)
                      _MovieStrip(
                        title: 'Ты уже смотрел',
                        subtitle: '${watched.length} из просмотренного',
                        movies: watched,
                      ),
                    if (filmography != null && filmography.isNotEmpty)
                      _MovieStrip(
                        title: 'Фильмография',
                        movies: filmography.where((m) => !watchedIds.contains(m.id)).toList(),
                      ),
                    if (watched.isEmpty && (filmography?.isEmpty ?? true))
                      Padding(
                        padding: EdgeInsets.only(top: 80),
                        child: Text(
                          'По этому человеку ничего не нашлось',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textDim),
                        ),
                      ),
                  ],
                ),
    );
  }
}

/// Горизонтальная лента постеров с заголовком.
class _MovieStrip extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Movie> movies;

  const _MovieStrip({required this.title, required this.movies, this.subtitle});

  @override
  Widget build(BuildContext context) {
    if (movies.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title, subtitle: subtitle),
        SizedBox(
          height: 230,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: movies.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => SizedBox(
              width: 118,
              child: PosterCard(
                title: movies[i].title,
                subtitle: movies[i].shortMeta,
                imageUrl: movies[i].posterUrl,
                badge: movies[i].rating,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: movies[i])),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Поиск человека по имени — прямой вход в TMDB, минуя просмотренное.
class _PersonSearchScreen extends StatefulWidget {
  final ActorRepository repo;

  const _PersonSearchScreen({required this.repo});

  @override
  State<_PersonSearchScreen> createState() => _PersonSearchScreenState();
}

class _PersonSearchScreenState extends State<_PersonSearchScreen> {
  final _controller = TextEditingController();
  List<PersonSearchResult> _results = const [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final found = await widget.repo.searchPerson(query);
      if (!mounted) return;
      setState(() => _results = found);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _run(),
          decoration: const InputDecoration(
            hintText: 'Имя актёра или режиссёра',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
          style: TextStyle(color: AppColors.text, fontSize: 16),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: _run),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.gold))
          : _error != null
              ? Center(
                  child: Text(_error!, style: TextStyle(color: AppColors.red)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _results.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final person = _results[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.medium),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PersonScreen(
                          personId: person.id,
                          name: person.name,
                          profilePath: person.profilePath,
                        ),
                      )),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: cardDecoration(),
                        child: Row(
                          children: [
                            _Avatar(url: person.photoUrl, name: person.name, size: 46),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    person.name,
                                    style: TextStyle(
                                      color: AppColors.text,
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (person.knownFor.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Text(
                                        person.knownFor.take(3).join(' · '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: AppColors.textDim,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

/// Круглое фото с заглушкой-инициалом: у части людей в TMDB фото нет.
class _Avatar extends StatelessWidget {
  final String? url;
  final String name;
  final double size;

  const _Avatar({required this.name, required this.size, this.url});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url == null || url!.isEmpty
            ? _initialBox(initial)
            : NetImage(
                imageUrl: url!,
                placeholder: (_, _) => Container(color: AppColors.surfaceHigh),
                errorWidget: (_, _, _) => _initialBox(initial),
              ),
      ),
    );
  }

  Widget _initialBox(String initial) => Container(
        color: AppColors.surfaceHigh,
        alignment: Alignment.center,
        child: Text(
          initial,
          style: TextStyle(
            color: AppColors.goldDim,
            fontSize: size * 0.4,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}
