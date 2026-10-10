import 'dart:async';

import '../models/movie.dart';
import 'local_first_repository.dart';

/// Фильмы и сериалы: просмотренное, «к просмотру» и отклонённое.
class MovieRepository extends LocalFirstRepository {
  MovieRepository({required super.api, required super.session});

  String _mediaType = 'movie';
  String get mediaType => _mediaType;

  List<Movie> _watched = [];
  List<Movie> _watchlist = [];
  List<Movie> _dismissed = [];

  List<Movie> get watched => List.unmodifiable(_watched);
  List<Movie> get watchlist => List.unmodifiable(_watchlist);
  List<Movie> get dismissed => List.unmodifiable(_dismissed);

  DateTime? get lastSyncedAt => syncedAt(_key('watched'));

  /// Быстрые проверки для карточек: показать «уже смотрел» без запроса.
  bool isWatched(int movieId) => _watched.any((m) => m.id == movieId);
  bool isInWatchlist(int movieId) => _watchlist.any((m) => m.id == movieId);
  bool isDismissed(int movieId) => _dismissed.any((m) => m.id == movieId);

  /// Список «к просмотру», сгруппированный по категории.
  /// Ключ null — карточки, которым категорию ещё не поставили.
  Map<String?, List<Movie>> get watchlistByCategory {
    final grouped = <String?, List<Movie>>{};
    for (final m in _watchlist) {
      grouped.putIfAbsent(m.category, () => []).add(m);
    }
    return grouped;
  }

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
    _dismissed = readCache(_key('dismissed')).map(Movie.fromJson).toList();
  }

  Future<void> refresh() => runSync(() async {
        final results = await Future.wait([
          api.get('/watched', query: {'media_type': _mediaType}),
          api.get('/watchlist', query: {'media_type': _mediaType}),
          api.get('/dismissed', query: {'media_type': _mediaType}),
        ]);

        await writeCache(_key('watched'), (results[0] as List?) ?? const [], fromServer: true);
        await writeCache(_key('watchlist'), (results[1] as List?) ?? const [], fromServer: true);
        await writeCache(_key('dismissed'), (results[2] as List?) ?? const [], fromServer: true);
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

  Future<void> _saveDismissed() =>
      writeCache(_key('dismissed'), _dismissed.map((m) => m.toJson()).toList());

  // ─── Изменения ──────────────────────────────────────────────────────
  //
  // Карточку сериала можно открыть, пока списки показывают фильмы. Поэтому
  // тип берётся от самого фильма, а локальные списки трогаем только когда
  // он совпадает с открытым — иначе запись легла бы в чужой кэш. Данные при
  // этом не теряются: сервер их принял, и они появятся при переключении типа.

  bool _affectsCurrentLists(String type) => type == _mediaType;

  Future<void> addToWatchlist(Movie movie) async {
    final type = movie.mediaType;
    if (_affectsCurrentLists(type)) {
      if (_watchlist.any((m) => m.id == movie.id)) return;
      _watchlist = [movie, ..._watchlist];
      notifyListeners();
      await _saveWatchlist();
    }

    await push(() => api.post('/watchlist', body: {
          'movie_id': movie.id,
          'media_type': type,
        }));
  }

  Future<void> removeFromWatchlist(int movieId, {String? mediaType}) async {
    final type = mediaType ?? _mediaType;
    final backup = _watchlist;
    if (_affectsCurrentLists(type)) {
      _watchlist = _watchlist.where((m) => m.id != movieId).toList();
      notifyListeners();
      await _saveWatchlist();
    }

    await push(
      () => api.delete('/watchlist/$movieId', query: {'media_type': type}),
      rollback: () => _watchlist = backup,
    );
  }

  Future<void> markWatched(Movie movie) async {
    final type = movie.mediaType;
    if (_affectsCurrentLists(type)) {
      _watchlist = _watchlist.where((m) => m.id != movie.id).toList();
      if (!_watched.any((m) => m.id == movie.id)) {
        _watched = [movie, ..._watched];
      }
      notifyListeners();
      await _saveWatchlist();
      await _saveWatched();
    }

    await push(() => api.post('/watched', body: {
          'movie_id': movie.id,
          'media_type': type,
        }));
  }

  Future<void> removeFromWatched(int movieId, {String? mediaType}) async {
    final type = mediaType ?? _mediaType;
    final backup = _watched;
    if (_affectsCurrentLists(type)) {
      _watched = _watched.where((m) => m.id != movieId).toList();
      notifyListeners();
      await _saveWatched();
    }

    await push(
      () => api.delete('/watched/$movieId', query: {'media_type': type}),
      rollback: () => _watched = backup,
    );
  }

  Future<void> rate(Movie movie, int rating, {String? review}) async {
    final type = movie.mediaType;
    if (_affectsCurrentLists(type)) {
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
    }

    await push(() => api.post('/watched/rate', body: {
          'movie_id': movie.id,
          'rating': rating,
          'media_type': type,
          'review': ?review,
        }));
  }

  /// Категория в списке «к просмотру»: must_see / not_sure / last_resort.
  /// Сбросить категорию нельзя — бэкенд принимает только эти три значения.
  Future<void> setWatchlistCategory(Movie movie, String category) async {
    final backup = _watchlist;
    if (_affectsCurrentLists(movie.mediaType)) {
      _watchlist = _watchlist
          .map((m) => m.id == movie.id ? m.copyWith(category: category) : m)
          .toList();
      notifyListeners();
      await _saveWatchlist();
    }

    await push(
      () => api.patch('/watchlist/${movie.id}/category', body: {
        'category': category,
        'media_type': movie.mediaType,
      }),
      rollback: () => _watchlist = backup,
    );
  }

  // ─── Отклонённые ────────────────────────────────────────────────────
  //
  // «Скрыть» убирает фильм из рекомендаций навсегда. Список отклонённого
  // видно отдельной вкладкой, оттуда же его можно вернуть.

  Future<void> dismiss(Movie movie) async {
    final type = movie.mediaType;
    if (_affectsCurrentLists(type)) {
      if (!_dismissed.any((m) => m.id == movie.id)) {
        _dismissed = [movie, ..._dismissed];
      }
      _watchlist = _watchlist.where((m) => m.id != movie.id).toList();
      notifyListeners();
      await _saveDismissed();
      await _saveWatchlist();
    }

    await push(() => api.post('/dismiss', body: {
          'movie_id': movie.id,
          'media_type': type,
        }));
  }

  Future<void> undismiss(int movieId, {String? mediaType}) async {
    final type = mediaType ?? _mediaType;
    final backup = _dismissed;
    if (_affectsCurrentLists(type)) {
      _dismissed = _dismissed.where((m) => m.id != movieId).toList();
      notifyListeners();
      await _saveDismissed();
    }

    await push(
      () => api.delete('/dismissed/$movieId', query: {'media_type': type}),
      rollback: () => _dismissed = backup,
    );
  }

  // ─── Поиск ──────────────────────────────────────────────────────────

  /// Параметр называется `q` — так его ждёт эндпоинт /search.
  Future<List<Movie>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    final data = await api.get('/search', query: {
      'q': query.trim(),
      'media_type': _mediaType,
    });
    final list = data is Map ? (data['results'] as List? ?? const []) : (data as List? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => Movie.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
