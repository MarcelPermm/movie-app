import '../core/api_client.dart';
import '../models/catalog.dart';
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
  List<Movie> _recommendationsTv = [];

  List<Movie> get popularMovies => List.unmodifiable(_popularMovies);
  List<Movie> get popularTv => List.unmodifiable(_popularTv);
  List<Movie> get recommendations => List.unmodifiable(_recommendations);

  /// Сериалы «для тебя» — по просмотренным сериалам, отдельно от фильмов.
  List<Movie> get recommendationsTv => List.unmodifiable(_recommendationsTv);

  bool get isEmpty => _popularMovies.isEmpty && _popularTv.isEmpty;

  /// Первые пять популярных фильмов крутятся в шапке обзора.
  List<Movie> get heroSlides => _popularMovies.take(5).toList();

  String get _moviesKey => cacheKey('discover::popular::movie');
  String get _tvKey => cacheKey('discover::popular::tv');
  String get _recsKey => cacheKey('discover::recs');
  String get _recsTvKey => cacheKey('discover::recs::tv');

  Future<void> load({bool forceRefresh = false}) async {
    _readFromCache();
    notifyListeners();
    if (forceRefresh || isStale(_moviesKey)) await refresh();
  }

  void _readFromCache() {
    _popularMovies = readCache(_moviesKey).map(Movie.fromJson).toList();
    _popularTv = readCache(_tvKey).map(Movie.fromJson).toList();
    _recommendations = readCache(_recsKey).map(Movie.fromJson).toList();
    _recommendationsTv = readCache(_recsTvKey).map(Movie.fromJson).toList();
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
        // Фильмы и сериалы — отдельно: у каждого своя подборка по своим
        // просмотренным. Нет просмотренных сериалов — нет и блока.
        for (final (type, key) in [('movie', _recsKey), ('tv', _recsTvKey)]) {
          try {
            final recs = await api.get('/recommendations', query: {'media_type': type});
            await writeCache(key, _tagged(recs, type), fromServer: true);
          } catch (_) {
            // Нечего рекомендовать, пока ничего не просмотрено. Это не ошибка.
          }
        }
        _recommendations = readCache(_recsKey).map(Movie.fromJson).toList();
        _recommendationsTv = readCache(_recsTvKey).map(Movie.fromJson).toList();
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

  // ─── Справочники для фильтров ───────────────────────────────────────
  //
  // Жанры и студии меняются раз в год, поэтому кэш живёт долго и почти
  // всегда отдаётся без сети. Пустой ответ не кэшируем — иначе фильтры
  // останутся пустыми до конца срока.

  Future<List<CatalogOption>> genres(String mediaType) =>
      _catalog('/genres', 'genres::$mediaType', {'media_type': mediaType});

  Future<List<CatalogOption>> studios(String mediaType) =>
      _catalog('/studios', 'studios::$mediaType', {'media_type': mediaType});

  Future<List<CatalogOption>> _catalog(
    String path,
    String cacheName,
    Map<String, String> query,
  ) async {
    final key = cacheKey(cacheName);
    final cached = readCache(key);
    if (cached.isNotEmpty && !isStale(key)) {
      return cached.map(CatalogOption.fromJson).toList();
    }

    try {
      final data = await api.get(path, query: query);
      final list = ((data as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (list.isNotEmpty) await writeCache(key, list, fromServer: true);
      return list.map(CatalogOption.fromJson).toList();
    } on ApiException {
      // Сети нет — лучше показать вчерашний справочник, чем пустой список.
      return cached.map(CatalogOption.fromJson).toList();
    }
  }

  // ─── Рекомендации с фильтрами ───────────────────────────────────────

  /// Подборка под заданные страну и студию.
  ///
  /// Кэшируется только подборка без фильтров — она же показывается на обзоре
  /// через геттер [recommendations]. Фильтрованные выборки разовые, держать
  /// их между запусками смысла нет.
  Future<List<Movie>> fetchRecommendations({
    String mediaType = 'movie',
    List<String> countries = const [],
    int studioId = 0,
  }) async {
    final query = {
      'media_type': mediaType,
      if (countries.isNotEmpty) 'country': countries.join(','),
      if (studioId != 0) 'studio_id': '$studioId',
    };

    final data = await api.get('/recommendations', query: query);
    final list = _tagged(data, mediaType);

    if (countries.isEmpty && studioId == 0) {
      final tv = mediaType == 'tv';
      await writeCache(tv ? _recsTvKey : _recsKey, list, fromServer: true);
      final parsed = list.map(Movie.fromJson).toList();
      tv ? _recommendationsTv = parsed : _recommendations = parsed;
      notifyListeners();
    }
    return list.map(Movie.fromJson).toList();
  }

  /// Фильмы конкретной студии — открывается из карточки фильма.
  Future<List<Movie>> studioMovies(int studioId, String mediaType) async {
    final data = await api.get('/studio/$studioId/movies', query: {'media_type': mediaType});
    return _tagged(data, mediaType).map(Movie.fromJson).toList();
  }

  /// Фильмография человека — открывается из блока актёров.
  Future<List<Movie>> personMovies(int personId, String mediaType) async {
    final data = await api.get('/person/$personId/movies', query: {'media_type': mediaType});
    return _tagged(data, mediaType).map(Movie.fromJson).toList();
  }
}
