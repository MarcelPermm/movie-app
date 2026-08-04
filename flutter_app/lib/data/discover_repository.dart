import '../models/movie.dart';
import '../models/movie_details.dart';
import 'local_first_repository.dart';

/// Обзор: популярное и рекомендации, плюс всё, что нужно карточке фильма.
///
/// Здесь кэш работает иначе, чем в личных списках: это чужие данные, они
/// меняются сами по себе. Но показать вчерашнюю подборку мгновенно и молча
/// обновить её — всё равно лучше, чем держать пустой экран.
class DiscoverRepository extends LocalFirstRepository {
  DiscoverRepository({required super.api, required super.session});

  List<Movie> _popularMovies = [];
  List<Movie> _popularTv = [];
  List<Movie> _recommendations = [];

  List<Movie> get popularMovies => List.unmodifiable(_popularMovies);
  List<Movie> get popularTv => List.unmodifiable(_popularTv);
  List<Movie> get recommendations => List.unmodifiable(_recommendations);

  bool get isEmpty => _popularMovies.isEmpty && _popularTv.isEmpty;

  /// Первые пять популярных фильмов крутятся в шапке обзора.
  List<Movie> get heroSlides => _popularMovies.take(5).toList();

  String get _moviesKey => cacheKey('discover::popular::movie');
  String get _tvKey => cacheKey('discover::popular::tv');
  String get _recsKey => cacheKey('discover::recs');

  Future<void> load({bool forceRefresh = false}) async {
    _readFromCache();
    notifyListeners();
    if (forceRefresh || isStale(_moviesKey)) await refresh();
  }

  void _readFromCache() {
    _popularMovies = readCache(_moviesKey).map(Movie.fromJson).toList();
    _popularTv = readCache(_tvKey).map(Movie.fromJson).toList();
    _recommendations = readCache(_recsKey).map(Movie.fromJson).toList();
  }

  Future<void> refresh() => runSync(() async {
        final results = await Future.wait([
          api.get('/popular', query: {'media_type': 'movie'}),
          api.get('/popular', query: {'media_type': 'tv'}),
        ]);

        // media_type в ответе /popular не приходит — проставляем сами,
        // иначе карточка сериала откроется как фильм.
        await writeCache(_moviesKey, _tagged(results[0], 'movie'), fromServer: true);
        await writeCache(_tvKey, _tagged(results[1], 'tv'), fromServer: true);
        _readFromCache();
        notifyListeners();

        // Рекомендации считаются дольше и есть не всегда — тянем следом,
        // чтобы они не задерживали появление популярного.
        try {
          final recs = await api.get('/recommendations', query: {'media_type': 'movie'});
          await writeCache(_recsKey, _tagged(recs, 'movie'), fromServer: true);
          _recommendations = readCache(_recsKey).map(Movie.fromJson).toList();
        } catch (_) {
          // Нечего рекомендовать, пока ничего не просмотрено. Это не ошибка.
        }
      });

  List<Map<String, dynamic>> _tagged(dynamic raw, String mediaType) =>
      ((raw as List?) ?? const [])
          .whereType<Map>()
          .map((e) => {...Map<String, dynamic>.from(e), 'media_type': mediaType})
          .toList();

  // ─── Карточка фильма ────────────────────────────────────────────────

  /// Детали фильма. Кэшируются: возврат к уже открытой карточке мгновенный.
  Future<MovieDetails> details(int movieId, String mediaType) async {
    final key = cacheKey('details::$mediaType::$movieId');
    final cached = readCache(key);

    if (cached.isNotEmpty && !isStale(key)) {
      return MovieDetails.fromJson(cached.first, mediaType);
    }

    final data = await api.get('/movie/$movieId/details', query: {'media_type': mediaType});
    final map = Map<String, dynamic>.from(data as Map);
    await writeCache(key, [map], fromServer: true);
    return MovieDetails.fromJson(map, mediaType);
  }

  /// Мгновенный доступ к уже загруженной карточке, если она есть в кэше.
  MovieDetails? cachedDetails(int movieId, String mediaType) {
    final cached = readCache(cacheKey('details::$mediaType::$movieId'));
    if (cached.isEmpty) return null;
    return MovieDetails.fromJson(cached.first, mediaType);
  }

  Future<List<Episode>> episodes(int showId, int season) async {
    final key = cacheKey('episodes::$showId::$season');
    final cached = readCache(key);
    if (cached.isNotEmpty && !isStale(key)) {
      return cached.map(Episode.fromJson).toList();
    }

    final data = await api.get('/tv/$showId/season/$season');
    await writeCache(key, (data as List?) ?? const [], fromServer: true);
    return readCache(key).map(Episode.fromJson).toList();
  }

  Future<List<Movie>> similar(int movieId, String mediaType) async {
    final data = await api.get('/similar/$movieId', query: {'media_type': mediaType});
    return _tagged(data, mediaType).map(Movie.fromJson).toList();
  }

  /// Ключ ролика на YouTube или null, если трейлера нет.
  Future<String?> trailerKey(int movieId, String mediaType) async {
    final data = await api.get('/trailer/$movieId', query: {'media_type': mediaType});
    if (data is Map && data['key'] != null && '${data['key']}'.isNotEmpty) {
      return '${data['key']}';
    }
    return null;
  }
}
