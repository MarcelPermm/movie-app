import '../core/api_client.dart';
import '../models/json.dart';
import '../models/series.dart';
import 'local_first_repository.dart';

/// Сериалы: где остановился, какие серии отмечены, что выходит.
///
/// «Продолжить просмотр» и новые серии показываются на «Сегодня», отметки
/// серий — в карточке сериала. Всё по общим правилам local-first: экран
/// читает кэш сразу, отметка ставится мгновенно, запрос уходит следом.
class SeriesRepository extends LocalFirstRepository {
  SeriesRepository({required super.api, required super.session});

  List<TvProgress> _progress = [];
  List<UpcomingEpisode> _upcoming = [];

  /// Избранные сериалы: о их новых сериях напоминает «Сегодня».
  Set<int> _follows = {};

  bool isFollowed(int showId) => _follows.contains(showId);

  /// Отмеченные серии по сериалам: showId → {(сезон, серия)}.
  final Map<int, Set<(int, int)>> _seen = {};

  List<TvProgress> get progress => List.unmodifiable(_progress);
  List<UpcomingEpisode> get upcoming => List.unmodifiable(_upcoming);

  String get _progressKey => cacheKey('tv_progress');
  String get _upcomingKey => cacheKey('tv_upcoming');
  String get _followsKey => cacheKey('tv_follows');
  String _seenKey(int showId) => cacheKey('tv_seen::$showId');

  TvProgress? progressOf(int showId) {
    for (final p in _progress) {
      if (p.showId == showId) return p;
    }
    return null;
  }

  Future<void> load({bool forceRefresh = false}) async {
    _seen.clear(); // после смены пользователя — его собственные отметки
    _readCache();
    notifyListeners();
    if (forceRefresh || isStale(_progressKey) || isStale(_upcomingKey)) await refresh();
  }

  void _readCache() {
    _progress = readCache(_progressKey).map(TvProgress.fromJson).toList();
    _upcoming = readCache(_upcomingKey).map(UpcomingEpisode.tryParse).whereType<UpcomingEpisode>().toList();
    _follows = readCache(_followsKey).map((j) => asInt(j['show_id'])).toSet();
  }

  Future<void> refresh() => runSync(() async {
        final progress = await api.get('/tv/progress');
        await writeCache(_progressKey, (progress as List?) ?? const [], fromServer: true);
        final follows = await api.get('/tv/follows');
        await writeCache(_followsKey, (follows as List?) ?? const [], fromServer: true);
        // Новые серии — отдельным запросом: он ходит в TMDB и бывает
        // медленным, но «Продолжить» не должно его ждать.
        _progress = readCache(_progressKey).map(TvProgress.fromJson).toList();
        notifyListeners();
        final upcoming = await api.get('/tv/upcoming');
        await writeCache(_upcomingKey, (upcoming as List?) ?? const [], fromServer: true);
        _readCache();
      });

  Future<void> _saveProgress() => writeCache(_progressKey, _progress.map((p) => p.toJson()).toList());

  /// Плеер открыт на серии — запоминаем, чтобы продолжить с неё.
  Future<void> recordOpen({
    required int showId,
    required String title,
    String? posterPath,
    String? backdropPath,
    required int season,
    required int episode,
    String? source,
  }) async {
    final old = progressOf(showId);
    final next = old?.copyWith(season: season, episode: episode, source: source) ??
        TvProgress(
          showId: showId,
          title: title,
          posterPath: posterPath,
          backdropPath: backdropPath,
          season: season,
          episode: episode,
          source: source,
          updatedAt: DateTime.now(),
        );
    _progress = [next, ..._progress.where((p) => p.showId != showId)];
    notifyListeners();
    await _saveProgress();

    await push(() => api.put('/tv/progress/$showId', body: {
          'title': title,
          'poster_path': ?posterPath,
          'backdrop_path': ?backdropPath,
          'season': season,
          'episode': episode,
          'source': ?source,
        }));
  }

  /// Сдвинуть «Продолжить» на следующую серию — после того как текущую
  /// отметили просмотренной. Без запроса в плеер: человек мог отметить
  /// серию, просто листая список.
  Future<void> advance(int showId, {required int season, required int episode}) async {
    final old = progressOf(showId);
    if (old == null) return;
    final next = old.copyWith(season: season, episode: episode);
    _progress = _progress.map((p) => p.showId == showId ? next : p).toList();
    notifyListeners();
    await _saveProgress();
    await push(() => api.put('/tv/progress/$showId', body: {
          'title': old.title,
          'season': season,
          'episode': episode,
        }));
  }

  /// Убрать сериал из «Продолжить просмотр».
  Future<void> dismiss(int showId) async {
    final backup = _progress;
    _progress = _progress.where((p) => p.showId != showId).toList();
    notifyListeners();
    await _saveProgress();
    await push(
      () => api.delete('/tv/progress/$showId'),
      rollback: () => _progress = backup,
    );
  }

  // ─── Избранное ──────────────────────────────────────────────────────

  /// Добавить сериал в избранное или убрать оттуда.
  ///
  /// После добавления сразу освежаем ленту новых серий: человек ждёт, что
  /// ближайшая серия появится на «Сегодня», а не через полчаса.
  Future<void> toggleFollow({required int showId, required String title, String? posterPath}) async {
    final follow = !isFollowed(showId);
    final backup = {..._follows};
    follow ? _follows.add(showId) : _follows.remove(showId);
    if (!follow) {
      _upcoming = _upcoming
          .map((u) => u.showId == showId ? u.withFavorite(false) : u)
          .toList();
    }
    notifyListeners();
    await writeCache(_followsKey, _follows.map((id) => {'show_id': id}).toList());

    final ok = await push(
      () => follow
          ? api.put('/tv/follows/$showId', body: {'title': title, 'poster_path': ?posterPath})
          : api.delete('/tv/follows/$showId'),
      rollback: () => _follows = backup,
    );
    if (ok == null && lastError != null) return;
    try {
      final upcoming = await api.get('/tv/upcoming');
      await writeCache(_upcomingKey, (upcoming as List?) ?? const [], fromServer: true);
      _upcoming = readCache(_upcomingKey).map(UpcomingEpisode.tryParse).whereType<UpcomingEpisode>().toList();
      notifyListeners();
    } on ApiException {
      // Обновится при следующей синхронизации.
    }
  }

  // ─── Отметки серий ──────────────────────────────────────────────────

  Set<(int, int)> seenOf(int showId) {
    return _seen.putIfAbsent(showId, () {
      return readCache(_seenKey(showId))
          .map((j) => (asInt(j['season']), asInt(j['episode'])))
          .toSet();
    });
  }

  bool isSeen(int showId, int season, int episode) => seenOf(showId).contains((season, episode));

  int seenInSeason(int showId, int season) => seenOf(showId).where((e) => e.$1 == season).length;

  /// Освежить отметки сериала с сервера. Не через runSync: карточку
  /// открывают, пока идёт общее обновление, и ждать его она не должна.
  Future<void> loadSeen(int showId) async {
    seenOf(showId);
    notifyListeners();
    try {
      final data = await api.get('/tv/$showId/watched-episodes');
      await writeCache(_seenKey(showId), (data as List?) ?? const [], fromServer: true);
      _seen.remove(showId);
      seenOf(showId);
      notifyListeners();
    } on ApiException {
      // Остаются отметки из кэша.
    }
  }

  Future<void> _saveSeen(int showId) => writeCache(
        _seenKey(showId),
        seenOf(showId).map((e) => {'season': e.$1, 'episode': e.$2}).toList(),
      );

  /// Отметить или снять серии одного сезона (одну или весь сезон разом).
  Future<void> setWatched(int showId, int season, List<int> episodes, bool watched) async {
    if (episodes.isEmpty) return;
    final seen = seenOf(showId);
    final backup = {...seen};
    for (final e in episodes) {
      watched ? seen.add((season, e)) : seen.remove((season, e));
    }
    if (watched) {
      // Отмеченная свежая серия больше не «новая».
      _upcoming = _upcoming
          .where((u) => !(u.showId == showId && u.season == season && episodes.contains(u.episode)))
          .toList();
      await writeCache(_upcomingKey, _upcoming.map(_upcomingJson).toList());
    }
    notifyListeners();
    await _saveSeen(showId);

    await push(
      () => api.post('/tv/$showId/watched-episodes', body: {
        'season': season,
        'episodes': episodes,
        'watched': watched,
      }),
      rollback: () {
        _seen[showId] = backup;
        _saveSeen(showId);
      },
    );
  }

  static Map<String, dynamic> _upcomingJson(UpcomingEpisode u) => {
        'show_id': u.showId,
        'title': u.title,
        'poster_path': u.posterPath,
        'backdrop_path': u.backdropPath,
        'season': u.season,
        'episode': u.episode,
        'name': u.name,
        'air_date': u.airDate.toIso8601String().substring(0, 10),
        'watching': u.watching,
        'favorite': u.favorite,
      };
}
