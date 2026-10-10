import '../core/config.dart';
import 'json.dart';

/// Появление актёра в конкретном просмотренном фильме — из /watched/top-actors.
class ActorAppearance {
  final int movieId;
  final String title;
  final int? userRating;
  final String? posterPath;
  final String mediaType;

  const ActorAppearance({
    required this.movieId,
    required this.title,
    this.userRating,
    this.posterPath,
    this.mediaType = 'movie',
  });

  String? get posterUrl => posterPath == null || posterPath!.isEmpty
      ? null
      : '${Config.tmdbCard}$posterPath';

  factory ActorAppearance.fromJson(Map<String, dynamic> j) => ActorAppearance(
        movieId: asInt(j['movie_id'] ?? j['id']),
        title: asString(j['title'] ?? j['name']),
        userRating: asIntOrNull(j['user_rating']),
        posterPath: asStringOrNull(j['poster_path']),
        mediaType: asString(j['media_type'], 'movie'),
      );

  Map<String, dynamic> toJson() => {
        'movie_id': movieId,
        'title': title,
        'user_rating': userRating,
        'poster_path': posterPath,
        'media_type': mediaType,
      };
}

/// Актёр, посчитанный по просмотренному: сколько раз встречался и в чём.
///
/// `id` может быть null — бэкенд ищет человека в TMDB по имени, и для редких
/// имён поиск иногда ничего не находит. Без id актёра нельзя добавить
/// в избранные и открыть фильмографию, поэтому UI на это смотрит.
class TopActor {
  final String name;
  final int? id;
  final String? profilePath;
  final int movieCount;
  final int tvCount;
  final bool isFavorite;
  final List<ActorAppearance> appearances;

  const TopActor({
    required this.name,
    this.id,
    this.profilePath,
    this.movieCount = 0,
    this.tvCount = 0,
    this.isFavorite = false,
    this.appearances = const [],
  });

  int get total => movieCount + tvCount;

  String? get photoUrl => profilePath == null || profilePath!.isEmpty
      ? null
      : '${Config.tmdbProfile}$profilePath';

  /// «7 фильмов · 2 сериала» — подпись под именем.
  String get countLabel => [
        if (movieCount > 0) '$movieCount ${_plural(movieCount, 'фильм', 'фильма', 'фильмов')}',
        if (tvCount > 0) '$tvCount ${_plural(tvCount, 'сериал', 'сериала', 'сериалов')}',
      ].join('  ·  ');

  /// Средняя оценка, которую пользователь ставил фильмам с этим актёром.
  double? get averageRating {
    final rated = appearances.where((a) => a.userRating != null).toList();
    if (rated.isEmpty) return null;
    return rated.map((a) => a.userRating!).reduce((a, b) => a + b) / rated.length;
  }

  TopActor copyWith({bool? isFavorite}) => TopActor(
        name: name,
        id: id,
        profilePath: profilePath,
        movieCount: movieCount,
        tvCount: tvCount,
        isFavorite: isFavorite ?? this.isFavorite,
        appearances: appearances,
      );

  factory TopActor.fromJson(Map<String, dynamic> j) => TopActor(
        name: asString(j['name']),
        id: asIntOrNull(j['id']),
        profilePath: asStringOrNull(j['profile_path']),
        movieCount: asInt(j['movie_count']),
        tvCount: asInt(j['tv_count']),
        isFavorite: asBool(j['is_favorite']),
        appearances: (j['movies'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => ActorAppearance.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'id': id,
        'profile_path': profilePath,
        'movie_count': movieCount,
        'tv_count': tvCount,
        'is_favorite': isFavorite,
        'movies': appearances.map((a) => a.toJson()).toList(),
      };
}

/// Запись в списке избранных актёров (/favorite-actors).
class FavoriteActor {
  final int actorId;
  final String name;
  final String? profilePath;

  const FavoriteActor({required this.actorId, required this.name, this.profilePath});

  String? get photoUrl => profilePath == null || profilePath!.isEmpty
      ? null
      : '${Config.tmdbProfile}$profilePath';

  factory FavoriteActor.fromJson(Map<String, dynamic> j) => FavoriteActor(
        actorId: asInt(j['actor_id']),
        name: asString(j['actor_name'] ?? j['name']),
        profilePath: asStringOrNull(j['profile_path']),
      );

  Map<String, dynamic> toJson() => {
        'actor_id': actorId,
        'actor_name': name,
        'profile_path': profilePath,
      };
}

/// Человек из /search/person — по нему открывается фильмография.
class PersonSearchResult {
  final int id;
  final String name;
  final String? profilePath;

  /// Названия известных работ — подсказка, тот ли это человек.
  final List<String> knownFor;

  const PersonSearchResult({
    required this.id,
    required this.name,
    this.profilePath,
    this.knownFor = const [],
  });

  String? get photoUrl => profilePath == null || profilePath!.isEmpty
      ? null
      : '${Config.tmdbProfile}$profilePath';

  factory PersonSearchResult.fromJson(Map<String, dynamic> j) => PersonSearchResult(
        id: asInt(j['id']),
        name: asString(j['name']),
        profilePath: asStringOrNull(j['profile_path']),
        knownFor: (j['known_for'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => asString(e['title'] ?? e['name']))
            .where((t) => t.isNotEmpty)
            .toList(),
      );
}

String _plural(int n, String one, String few, String many) {
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 14) return many;
  switch (n % 10) {
    case 1:
      return one;
    case 2:
    case 3:
    case 4:
      return few;
    default:
      return many;
  }
}
