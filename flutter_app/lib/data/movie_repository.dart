import 'dart:async';

import '../models/movie.dart';
import 'local_first_repository.dart';

/// Фильмы и сериалы: просмотренное и список «к просмотру».
class MovieRepository extends LocalFirstRepository {
  MovieRepository({required super.api, required super.session});

  String _mediaType = 'movie';
  String get mediaType => _mediaType;

  List<Movie> _watched = [];
  List<Movie> _watchlist = [];

  List<Movie> get watched => List.unmodifiable(_watched);
  List<Movie> get watchlist => List.unmodifiable(_watchlist);

  DateTime? get lastSyncedAt => syncedAt(_key('watched'));

  String _key(String kind) => cacheKey('$kind::$_mediaType');

  Future<void> load({bool forceRefresh = false}) async {
    _readFromCache();
    notifyListeners();

    if (forceRefresh || isStale(_key('watched'))) {
      await refresh();
    } else {
      unawaited(flushPending());
    }
  }

  Future<void> flushPending() => runSync(() async {});

  void _readFromCache() {
    _watched = readCache(_key('watched')).map(Movie.fromJson).toList();
    _watchlist = readCache(_key('watchlist')).map(Movie.fromJson).toList();
  }

  Future<void> refresh() => runSync(() async {
        final results = await Future.wait([
          api.get('/watched', query: {'media_type': _mediaType}),
          api.get('/watchlist', query: {'media_type': _mediaType}),
        ]);

        await writeCache(_key('watched'), (results[0] as List?) ?? const [], fromServer: true);
        await writeCache(_key('watchlist'), (results[1] as List?) ?? const [], fromServer: true);
        _readFromCache();
      });

  Future<void> setMediaType(String value) async {
    if (_mediaType == value) return;
    _mediaType = value;
    await load();
  }

  Future<void> _saveWatched() =>
      writeCache(_key('watched'), _watched.map((m) => m.toJson()).toList());

  Future<void> _saveWatchlist() =>
      writeCache(_key('watchlist'), _watchlist.map((m) => m.toJson()).toList());

  // ─── Изменения ──────────────────────────────────────────────────────

  Future<void> addToWatchlist(Movie movie) async {
    if (_watchlist.any((m) => m.id == movie.id)) return;
    _watchlist = [movie, ..._watchlist];
    notifyListeners();
    await _saveWatchlist();

    await push(() => api.post('/watchlist', body: {
          'movie_id': movie.id,
          'media_type': _mediaType,
        }));
  }

  Future<void> removeFromWatchlist(int movieId) async {
    final backup = _watchlist;
    _watchlist = _watchlist.where((m) => m.id != movieId).toList();
    notifyListeners();
    await _saveWatchlist();

    await push(
      () => api.delete('/watchlist/$movieId', query: {'media_type': _mediaType}),
      rollback: () => _watchlist = backup,
    );
  }

  Future<void> markWatched(Movie movie) async {
    _watchlist = _watchlist.where((m) => m.id != movie.id).toList();
    if (!_watched.any((m) => m.id == movie.id)) {
      _watched = [movie, ..._watched];
    }
    notifyListeners();
    await _saveWatchlist();
    await _saveWatched();

    await push(() => api.post('/watched', body: {
          'movie_id': movie.id,
          'media_type': _mediaType,
        }));
  }

  Future<void> removeFromWatched(int movieId) async {
    final backup = _watched;
    _watched = _watched.where((m) => m.id != movieId).toList();
    notifyListeners();
    await _saveWatched();

    await push(
      () => api.delete('/watched/$movieId', query: {'media_type': _mediaType}),
      rollback: () => _watched = backup,
    );
  }

  Future<void> rate(Movie movie, int rating, {String? review}) async {
    if (_watched.any((m) => m.id == movie.id)) {
      _watched = _watched
          .map((m) => m.id == movie.id ? m.copyWith(rating: rating, review: review) : m)
          .toList();
    } else {
      // Оценка сама добавляет в просмотренное — так же ведёт себя бэкенд.
      _watched = [movie.copyWith(rating: rating, review: review), ..._watched];
      _watchlist = _watchlist.where((m) => m.id != movie.id).toList();
      await _saveWatchlist();
    }
    notifyListeners();
    await _saveWatched();

    await push(() => api.post('/watched/rate', body: {
          'movie_id': movie.id,
          'rating': rating,
          'media_type': _mediaType,
          'review': ?review,
        }));
  }

  // ─── Поиск ──────────────────────────────────────────────────────────

  Future<List<Movie>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    final data = await api.get('/search', query: {
      'query': query.trim(),
      'media_type': _mediaType,
    });
    final list = data is Map ? (data['results'] as List? ?? const []) : (data as List? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => Movie.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
