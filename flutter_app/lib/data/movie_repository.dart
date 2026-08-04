import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/config.dart';
import '../core/local_store.dart';
import '../core/session.dart';
import '../core/sync_queue.dart';
import '../models/movie.dart';

/// Репозиторий фильмов, работающий по принципу local-first.
///
/// Правила, из которых берётся «мгновенность»:
///   1. Экран всегда сначала рисуется из локального кэша — синхронно, без сети.
///   2. Сеть дёргается в фоне и только если кэш устарел (Config.syncInterval).
///   3. Любое изменение сперва применяется локально, и только потом уходит
///      на сервер; если сети нет — ложится в очередь и уйдёт позже.
///
/// Источник правды остаётся один — PostgreSQL на сервере. Локальная копия
/// это just кэш, который сходится с сервером при каждой синхронизации.
class MovieRepository extends ChangeNotifier {
  final ApiClient api;
  final Session session;

  MovieRepository({required this.api, required this.session});

  String _mediaType = 'movie';
  String get mediaType => _mediaType;

  List<Movie> _watched = [];
  List<Movie> _watchlist = [];

  List<Movie> get watched => List.unmodifiable(_watched);
  List<Movie> get watchlist => List.unmodifiable(_watchlist);

  bool _syncing = false;
  bool get syncing => _syncing;

  String? _lastError;
  String? get lastError => _lastError;

  int get pendingWrites => SyncQueue.pendingCount;
  DateTime? get lastSyncedAt => LocalStore.syncedAt(_key('watched'));

  String _key(String kind) => 'cache::$kind::$_mediaType::u${session.userId}';

  // ─── Загрузка ───────────────────────────────────────────────────────

  /// Мгновенно поднимает данные из кэша и, если они несвежие, освежает в фоне.
  Future<void> load({bool forceRefresh = false}) async {
    _readFromCache();
    notifyListeners(); // UI уже готов — дальше всё происходит незаметно

    final stale = !LocalStore.isFresh(_key('watched'), Config.syncInterval);
    if (forceRefresh || stale) {
      await refresh();
    } else {
      // Даже без обновления списков стоит попытаться дослать накопленное.
      unawaited(SyncQueue.flush(api));
    }
  }

  void _readFromCache() {
    _watched = (LocalStore.readList(_key('watched')) ?? const [])
        .map(Movie.fromJson)
        .toList();
    _watchlist = (LocalStore.readList(_key('watchlist')) ?? const [])
        .map(Movie.fromJson)
        .toList();
  }

  /// Поход в сеть. UI на него не завязан — он лишь обновляет уже видимые списки.
  Future<void> refresh() async {
    if (_syncing) return;
    _syncing = true;
    _lastError = null;
    notifyListeners();

    try {
      // Сначала дошлём свои изменения, чтобы сервер отдал их же обратно.
      await SyncQueue.flush(api);

      final results = await Future.wait([
        api.get('/watched', query: {'media_type': _mediaType}),
        api.get('/watchlist', query: {'media_type': _mediaType}),
      ]);

      final watchedRaw = (results[0] as List?) ?? const [];
      final watchlistRaw = (results[1] as List?) ?? const [];

      await LocalStore.writeList(_key('watched'), watchedRaw, fromServer: true);
      await LocalStore.writeList(_key('watchlist'), watchlistRaw, fromServer: true);
      _readFromCache();
    } on ApiException catch (e) {
      // Сеть отвалилась — не страшно, на экране остаются данные из кэша.
      _lastError = e.message;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<void> setMediaType(String value) async {
    if (_mediaType == value) return;
    _mediaType = value;
    await load();
  }

  // ─── Изменения (сначала локально, потом на сервер) ───────────────────

  Future<void> addToWatchlist(Movie movie) async {
    if (_watchlist.any((m) => m.id == movie.id)) return;

    _watchlist = [movie, ..._watchlist];
    notifyListeners();
    await LocalStore.writeList(_key('watchlist'), _watchlist.map((m) => m.toJson()).toList());

    await _push(() => api.post('/watchlist', body: {
          'movie_id': movie.id,
          'media_type': _mediaType,
        }));
  }

  Future<void> removeFromWatchlist(int movieId) async {
    final backup = _watchlist;
    _watchlist = _watchlist.where((m) => m.id != movieId).toList();
    notifyListeners();
    await LocalStore.writeList(_key('watchlist'), _watchlist.map((m) => m.toJson()).toList());

    await _push(
      () => api.delete('/watchlist/$movieId', query: {'media_type': _mediaType}),
      rollback: () => _watchlist = backup,
    );
  }

  /// Перенос «к просмотру» → «просмотрено».
  Future<void> markWatched(Movie movie) async {
    _watchlist = _watchlist.where((m) => m.id != movie.id).toList();
    if (!_watched.any((m) => m.id == movie.id)) {
      _watched = [movie, ..._watched];
    }
    notifyListeners();
    await LocalStore.writeList(_key('watchlist'), _watchlist.map((m) => m.toJson()).toList());
    await LocalStore.writeList(_key('watched'), _watched.map((m) => m.toJson()).toList());

    await _push(() => api.post('/watched', body: {
          'movie_id': movie.id,
          'media_type': _mediaType,
        }));
  }

  Future<void> removeFromWatched(int movieId) async {
    final backup = _watched;
    _watched = _watched.where((m) => m.id != movieId).toList();
    notifyListeners();
    await LocalStore.writeList(_key('watched'), _watched.map((m) => m.toJson()).toList());

    await _push(
      () => api.delete('/watched/$movieId', query: {'media_type': _mediaType}),
      rollback: () => _watched = backup,
    );
  }

  Future<void> rate(Movie movie, int rating, {String? review}) async {
    _watched = _watched
        .map((m) => m.id == movie.id ? m.copyWith(rating: rating, review: review) : m)
        .toList();
    if (!_watched.any((m) => m.id == movie.id)) {
      _watched = [movie.copyWith(rating: rating, review: review), ..._watched];
      _watchlist = _watchlist.where((m) => m.id != movie.id).toList();
      await LocalStore.writeList(_key('watchlist'), _watchlist.map((m) => m.toJson()).toList());
    }
    notifyListeners();
    await LocalStore.writeList(_key('watched'), _watched.map((m) => m.toJson()).toList());

    await _push(() => api.post('/watched/rate', body: {
          'movie_id': movie.id,
          'rating': rating,
          'media_type': _mediaType,
          'review': ?review,
        }));
  }

  /// Отправка изменения на сервер. Ошибка сети уже обработана внутри ApiClient
  /// (запрос попал в очередь), поэтому здесь ловим только отказы сервера.
  Future<void> _push(Future<dynamic> Function() call, {VoidCallback? rollback}) async {
    try {
      await call();
    } on ApiException catch (e) {
      // 409 «уже в списке» — рассинхрон, который лечится следующим refresh.
      if (e.statusCode == 409) return;
      _lastError = e.message;
      if (rollback != null) {
        rollback();
        notifyListeners();
      }
    }
  }

  // ─── Поиск (всегда живой, кэшировать нечего) ────────────────────────

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
