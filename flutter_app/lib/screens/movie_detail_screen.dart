import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_client.dart';
import '../core/config.dart';
import '../data/discover_repository.dart';
import '../data/movie_repository.dart';
import '../models/movie.dart';
import '../models/movie_details.dart';
import '../theme.dart';
import '../widgets/episode_card.dart';
import '../widgets/poster_card.dart';

/// Карточка фильма или сериала — то же, что модалка на сайте.
class MovieDetailScreen extends StatefulWidget {
  final Movie movie;
  const MovieDetailScreen({super.key, required this.movie});

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  MovieDetails? _details;
  List<Movie> _similar = const [];
  List<Episode> _episodes = const [];

  int _season = 1;
  int? _playingEpisode;
  String _source = 'vidsrc';

  String? _error;

  String get _mediaType => widget.movie.mediaType;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<DiscoverRepository>();

    // Если карточку уже открывали, показываем её мгновенно из кэша,
    // а свежие данные подтягиваем следом.
    final cached = repo.cachedDetails(widget.movie.id, _mediaType);
    if (cached != null) {
      setState(() => _details = cached);
      _loadSeason(cached);
    }

    try {
      final details = await repo.details(widget.movie.id, _mediaType);
      if (!mounted) return;
      setState(() => _details = details);
      _loadSeason(details);
    } on ApiException catch (e) {
      if (!mounted) return;
      // Кэш уже на экране — ошибку показываем, только если показывать нечего.
      if (cached == null) setState(() => _error = e.message);
    }

    try {
      final similar = await repo.similar(widget.movie.id, _mediaType);
      if (mounted) setState(() => _similar = similar);
    } on ApiException {
      // Похожее — приятное дополнение, без него карточка полноценна.
    }
  }

  Future<void> _loadSeason(MovieDetails details) async {
    if (!details.isTv) return;
    try {
      final episodes = await context.read<DiscoverRepository>().episodes(widget.movie.id, _season);
      if (mounted) setState(() => _episodes = episodes);
    } on ApiException {
      if (mounted) setState(() => _episodes = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = _details;

    return Scaffold(
      body: _error != null && details == null
          ? _buildError()
          : CustomScrollView(
              slivers: [
                _buildHero(details),
                if (details == null)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator(color: AppColors.gold)),
                  )
                else
                  SliverToBoxAdapter(child: _buildBody(details)),
              ],
            ),
    );
  }

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.red, fontSize: 14)),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Назад')),
            ],
          ),
        ),
      );

  // ─── Шапка с кадром из фильма ───────────────────────────────────────

  Widget _buildHero(MovieDetails? details) {
    final movie = details?.movie ?? widget.movie;

    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      backgroundColor: AppColors.bg,
      leading: IconButton(
        icon: const CircleAvatar(
          radius: 16,
          backgroundColor: Color(0xCC0A0A0F),
          child: Icon(Icons.arrow_back, color: AppColors.text, size: 18),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
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
            // Затемнение снизу, чтобы кадр переходил в фон страницы.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.45, 1.0],
                  colors: [Color(0x330A0A0F), Color(0xAA0A0A0F), AppColors.bg],
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 18,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (movie.posterUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedNetworkImage(
                        imageUrl: movie.posterUrl!,
                        width: 92,
                        height: 138,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(color: AppColors.surface),
                        errorWidget: (_, _, _) => Container(color: AppColors.surface),
                      ),
                    ),
                  const SizedBox(width: 14),
                  Expanded(child: _buildPlayButtons()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayButtons() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: _openPlayer,
          icon: const Icon(Icons.play_arrow, size: 20),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: AppColors.bg,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          label: const Text('Смотреть'),
        ),
        FilledButton.icon(
          onPressed: _openTrailer,
          icon: const Icon(Icons.smart_display_outlined, size: 20),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xCC12121A),
            foregroundColor: AppColors.text,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          label: const Text('Трейлер'),
        ),
        // Источники те же, что на сайте: если один не отдаёт видео,
        // выручает другой.
        PopupMenuButton<String>(
          initialValue: _source,
          color: AppColors.surface,
          tooltip: 'Источник плеера',
          onSelected: (value) => setState(() => _source = value),
          itemBuilder: (_) => Config.watchSources.entries
              .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xCC12121A),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  Config.watchSources[_source] ?? _source,
                  style: const TextStyle(color: AppColors.textDim, fontSize: 13),
                ),
                const Icon(Icons.arrow_drop_down, color: AppColors.textDim, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── Тело карточки ──────────────────────────────────────────────────

  Widget _buildBody(MovieDetails details) {
    final movie = details.movie;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            movie.title,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          if (details.originalTitle != null && details.originalTitle != movie.title)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                details.originalTitle!,
                style: const TextStyle(color: AppColors.textDim, fontSize: 14),
              ),
            ),
          if (movie.genres.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: movie.genres.map((g) => _Tag(g)).toList(),
            ),
          ],
          const SizedBox(height: 16),
          _buildStats(details),
          if (movie.overview.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              movie.overview,
              style: const TextStyle(color: AppColors.text, fontSize: 14, height: 1.55),
            ),
          ],
          if (details.studios.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildStudios(details),
          ],
          const SizedBox(height: 20),
          _buildActions(movie),
          const SizedBox(height: 22),
          _RatingBlock(
            movie: movie,
            initialRating: details.userRating,
            initialReview: details.userReview,
          ),
          if (details.cast.isNotEmpty) ...[
            const SizedBox(height: 26),
            const _SectionTitle('В ролях'),
            const SizedBox(height: 12),
            _buildCast(details),
          ],
          if (details.isTv && details.realSeasons.isNotEmpty) ...[
            const SizedBox(height: 26),
            _buildSeasons(details),
          ],
          if (_similar.isNotEmpty) ...[
            const SizedBox(height: 26),
            const _SectionTitle('Похожее'),
            const SizedBox(height: 12),
            _buildSimilar(),
          ],
        ],
      ),
    );
  }

  Widget _buildStats(MovieDetails details) {
    final movie = details.movie;
    return Wrap(
      spacing: 22,
      runSpacing: 12,
      children: [
        if (movie.voteAverage > 0)
          _Stat('TMDB', '★ ${movie.voteAverage.toStringAsFixed(1)}', votes: movie.voteCount),
        if (details.imdbRating != null)
          _Stat('IMDb', '★ ${details.imdbRating}', votes: details.imdbVoteCount ?? 0),
        if (movie.releaseYear != null) _Stat('Год', '${movie.releaseYear}'),
        if (details.lengthLabel != null) _Stat('Длительность', details.lengthLabel!),
        if (movie.director != null) _Stat('Режиссёр', movie.director!),
      ],
    );
  }

  Widget _buildStudios(MovieDetails details) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: details.studios.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final studio = details.studios[i];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Text(
              studio.name,
              style: const TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActions(Movie movie) {
    final repo = context.watch<MovieRepository>();
    final watched = repo.watched.any((m) => m.id == movie.id) || movie.isWatched;
    final inList = repo.watchlist.any((m) => m.id == movie.id) || movie.isWatchlist;

    return Row(
      children: [
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: watched ? AppColors.green : AppColors.surface,
              foregroundColor: watched ? AppColors.bg : AppColors.text,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            onPressed: () {
              final r = context.read<MovieRepository>();
              watched ? r.removeFromWatched(movie.id, mediaType: _mediaType) : r.markWatched(movie);
            },
            child: Text(watched ? '✓ Просмотрено' : 'Отметить просмотренным'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: inList ? AppColors.goldDim : AppColors.surface,
              foregroundColor: inList ? AppColors.bg : AppColors.text,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            onPressed: () {
              final r = context.read<MovieRepository>();
              inList
                  ? r.removeFromWatchlist(movie.id, mediaType: _mediaType)
                  : r.addToWatchlist(movie);
            },
            child: Text(inList ? 'Убрать из списка' : 'К просмотру'),
          ),
        ),
      ],
    );
  }

  Widget _buildCast(MovieDetails details) {
    return SizedBox(
      height: 152,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: details.cast.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final person = details.cast[i];
          return SizedBox(
            width: 84,
            child: Column(
              children: [
                ClipOval(
                  child: SizedBox(
                    height: 84,
                    width: 84,
                    child: person.photoUrl == null
                        ? Container(
                            color: AppColors.surface,
                            alignment: Alignment.center,
                            child: const Text('👤', style: TextStyle(fontSize: 26)),
                          )
                        : CachedNetworkImage(
                            imageUrl: person.photoUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => Container(color: AppColors.surface),
                            errorWidget: (_, _, _) => Container(color: AppColors.surface),
                          ),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  person.name,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                if (person.character.isNotEmpty)
                  Text(
                    person.character,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textDim, fontSize: 10),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSeasons(MovieDetails details) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SectionTitle('Серии'),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(9),
              ),
              child: DropdownButton<int>(
                value: _season,
                underline: const SizedBox.shrink(),
                dropdownColor: AppColors.surface,
                style: const TextStyle(color: AppColors.text, fontSize: 13),
                items: details.realSeasons
                    .map((s) => DropdownMenuItem(
                          value: s.seasonNumber,
                          child: Text('Сезон ${s.seasonNumber}  ·  ${s.episodeCount} эп'),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _season = value;
                    _episodes = const [];
                    _playingEpisode = null;
                  });
                  _loadSeason(details);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_episodes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(child: CircularProgressIndicator(color: AppColors.goldDim)),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = (constraints.maxWidth / 280).floor().clamp(1, 4);
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  childAspectRatio: 0.82,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: _episodes.length,
                itemBuilder: (context, i) => EpisodeCard(
                  episode: _episodes[i],
                  isPlaying: _playingEpisode == _episodes[i].episodeNumber,
                  onPlay: () {
                    setState(() => _playingEpisode = _episodes[i].episodeNumber);
                    _openPlayer(episode: _episodes[i].episodeNumber);
                  },
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildSimilar() {
    return SizedBox(
      height: 250,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _similar.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) => SizedBox(
          width: 130,
          child: PosterCard(
            title: _similar[i].title,
            subtitle: _similar[i].shortMeta,
            imageUrl: _similar[i].posterUrl,
            onTap: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: _similar[i])),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Плеер и трейлер ────────────────────────────────────────────────

  /// Плеер открывается во внешнем браузере: источники отдают страницу
  /// с рекламой и своим интерфейсом, встраивать её внутрь приложения
  /// смысла мало, а на части платформ и нельзя.
  Future<void> _openPlayer({int? episode}) async {
    final url = Config.embedUrl(
      _source,
      _mediaType,
      widget.movie.id,
      season: _season,
      episode: episode ?? _playingEpisode ?? 1,
    );

    if (_mediaType == 'tv' && episode == null && _playingEpisode == null) {
      setState(() => _playingEpisode = 1);
    }

    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть плеер')),
      );
    }
  }

  Future<void> _openTrailer() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final key = await context.read<DiscoverRepository>().trailerKey(widget.movie.id, _mediaType);
      if (key == null) {
        messenger.showSnackBar(const SnackBar(content: Text('Трейлер не найден')));
        return;
      }
      await launchUrl(Uri.parse(Config.youtubeUrl(key)), mode: LaunchMode.externalApplication);
    } on ApiException {
      messenger.showSnackBar(const SnackBar(content: Text('Трейлер не найден')));
    }
  }
}

// ─── Мелкие части ─────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: AppColors.text,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      );
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text, style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
      );
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final int votes;

  const _Stat(this.label, this.value, {this.votes = 0});

  /// 12 500 → 12.5K, 1 300 000 → 1.3M
  static String _fmtVotes(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(color: AppColors.textDim, fontSize: 10, letterSpacing: 0.8)),
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: const TextStyle(
                      color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w700)),
              if (votes > 0)
                Text('  ${_fmtVotes(votes)}',
                    style: const TextStyle(color: AppColors.textDim, fontSize: 11)),
            ],
          ),
        ],
      );
}

/// Оценка с отзывом — как на сайте: цифры 1–10, окрашенные по значению.
class _RatingBlock extends StatefulWidget {
  final Movie movie;
  final int? initialRating;
  final String? initialReview;

  const _RatingBlock({
    required this.movie,
    this.initialRating,
    this.initialReview,
  });

  @override
  State<_RatingBlock> createState() => _RatingBlockState();
}

class _RatingBlockState extends State<_RatingBlock> {
  late int? _rating = widget.initialRating;
  late final _review = TextEditingController(text: widget.initialReview ?? '');
  bool _saved = false;

  @override
  void dispose() {
    _review.dispose();
    super.dispose();
  }

  static Color _colorFor(int n) {
    if (n >= 8) return AppColors.green;
    if (n >= 6) return AppColors.gold;
    if (n >= 4) return const Color(0xFFC98A4C);
    return AppColors.red;
  }

  Future<void> _save() async {
    final rating = _rating;
    if (rating == null) return;
    await context.read<MovieRepository>().rate(
          widget.movie,
          rating,
          review: _review.text.trim().isEmpty ? null : _review.text.trim(),
        );
    if (!mounted) return;
    setState(() => _saved = true);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Моя оценка',
              style: TextStyle(color: AppColors.textDim, fontSize: 12, letterSpacing: 0.4)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(10, (i) {
              final n = i + 1;
              final active = _rating == n;
              final color = _colorFor(n);
              return GestureDetector(
                onTap: () => setState(() {
                  _rating = n;
                  _saved = false;
                }),
                child: Container(
                  height: 38,
                  width: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? color : AppColors.bg,
                    border: Border.all(color: active ? color : AppColors.border),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    '$n',
                    style: TextStyle(
                      color: active ? AppColors.bg : AppColors.textDim,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _review,
            minLines: 2,
            maxLines: 5,
            style: const TextStyle(color: AppColors.text, fontSize: 14),
            decoration: const InputDecoration(hintText: 'Написать отзыв (необязательно)…'),
            onChanged: (_) => setState(() => _saved = false),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                onPressed: _rating == null ? null : _save,
                child: Text(_saved ? 'Сохранено' : 'Сохранить оценку'),
              ),
              if (_saved) ...[
                const SizedBox(width: 10),
                const Icon(Icons.check_circle, color: AppColors.green, size: 18),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
