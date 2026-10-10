import '../models/movie.dart';
import '../models/person.dart';
import 'local_first_repository.dart';

/// Актёры: кого ты смотришь чаще всего и кого отметил избранным.
///
/// Топ считает бэкенд по всему просмотренному — это заметно дороже обычного
/// списка (поиск каждого имени в TMDB), поэтому кэш здесь особенно важен:
/// вкладка открывается мгновенно, а обновление идёт фоном.
class ActorRepository extends LocalFirstRepository {
  ActorRepository({required super.api, required super.session});

  List<TopActor> _top = [];
  List<FavoriteActor> _favorites = [];

  List<TopActor> get top => List.unmodifiable(_top);
  List<FavoriteActor> get favorites => List.unmodifiable(_favorites);

  /// Топ, где отметка «избранное» приведена в соответствие с текущим списком
  /// избранных: сервер считает её при выдаче, а мы переключаем локально.
  List<TopActor> get topAnnotated {
    final ids = _favorites.map((f) => f.actorId).toSet();
    return _top.map((a) => a.copyWith(isFavorite: a.id != null && ids.contains(a.id))).toList();
  }

  String get _topKey => cacheKey('actors::top');
  String get _favKey => cacheKey('actors::favorites');

  bool isFavorite(int? actorId) =>
      actorId != null && _favorites.any((f) => f.actorId == actorId);

  Future<void> load({bool forceRefresh = false}) async {
    _readFromCache();
    notifyListeners();
    if (forceRefresh || isStale(_topKey)) await refresh();
  }

  void _readFromCache() {
    _top = readCache(_topKey).map(TopActor.fromJson).toList();
    _favorites = readCache(_favKey).map(FavoriteActor.fromJson).toList();
  }

  Future<void> refresh() => runSync(() async {
        // Избранные приходят быстро — показываем их, не дожидаясь топа.
        final favs = await api.get('/favorite-actors');
        await writeCache(_favKey, (favs as List?) ?? const [], fromServer: true);
        _favorites = readCache(_favKey).map(FavoriteActor.fromJson).toList();
        notifyListeners();

        final top = await api.get('/watched/top-actors', query: {'limit': '30'});
        await writeCache(_topKey, (top as List?) ?? const [], fromServer: true);
        _top = readCache(_topKey).map(TopActor.fromJson).toList();
      });

  Future<void> _saveFavorites() =>
      writeCache(_favKey, _favorites.map((f) => f.toJson()).toList());

  Future<void> toggleFavorite(TopActor actor) async {
    final id = actor.id;
    // Без TMDB-id актёра некуда сохранять — кнопка в UI для таких скрыта,
    // но проверку оставляем, чтобы случайный вызов не ушёл в сеть.
    if (id == null) return;

    if (isFavorite(id)) {
      await removeFavorite(id);
    } else {
      await addFavorite(FavoriteActor(
        actorId: id,
        name: actor.name,
        profilePath: actor.profilePath,
      ));
    }
  }

  Future<void> addFavorite(FavoriteActor actor) async {
    if (isFavorite(actor.actorId)) return;
    final backup = _favorites;
    _favorites = [..._favorites, actor];
    notifyListeners();
    await _saveFavorites();

    await push(
      () => api.post('/favorite-actors', body: {
        'actor_id': actor.actorId,
        'actor_name': actor.name,
        'profile_path': actor.profilePath,
      }),
      rollback: () => _favorites = backup,
    );
  }

  Future<void> removeFavorite(int actorId) async {
    final backup = _favorites;
    _favorites = _favorites.where((f) => f.actorId != actorId).toList();
    notifyListeners();
    await _saveFavorites();

    await push(
      () => api.delete('/favorite-actors/$actorId'),
      rollback: () => _favorites = backup,
    );
  }

  // ─── Разовые запросы ────────────────────────────────────────────────

  /// Что из просмотренного связано с этим человеком — и как ты это оценил.
  Future<List<Movie>> watchedAppearances(int personId) async {
    final data = await api.get('/person/$personId/watched-appearances');
    return ((data as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Movie.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<PersonSearchResult>> searchPerson(String query) async {
    if (query.trim().isEmpty) return const [];
    final data = await api.get('/search/person', query: {'q': query.trim()});
    return ((data as List?) ?? const [])
        .whereType<Map>()
        .map((e) => PersonSearchResult.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
