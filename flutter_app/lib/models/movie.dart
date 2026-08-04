import '../core/config.dart';
import 'json.dart';

/// Фильм или сериал в том виде, в каком его отдаёт бэкенд.
///
/// Парсер намеренно снисходительный: разные эндпоинты возвращают чуть разные
/// наборы полей (`/watched` кладёт id в movie_id, `/popular` — в id),
/// а числа приходят то int, то double.
class Movie {
  final int id;
  final String title;
  final String overview;
  final String? posterPath;
  final String? backdropPath;
  final double voteAverage;
  final int voteCount;
  final List<String> genres;
  final String mediaType;
  final int? releaseYear;
  final String? director;

  /// Только для просмотренного.
  final int? rating;
  final String? review;

  /// Только для списка «к просмотру»: must_see / not_sure / last_resort.
  final String? category;

  /// Пометки, которые бэкенд добавляет к спискам обзора.
  final bool isWatched;
  final bool isWatchlist;

  const Movie({
    required this.id,
    required this.title,
    this.overview = '',
    this.posterPath,
    this.backdropPath,
    this.voteAverage = 0,
    this.voteCount = 0,
    this.genres = const [],
    this.mediaType = 'movie',
    this.releaseYear,
    this.director,
    this.rating,
    this.review,
    this.category,
    this.isWatched = false,
    this.isWatchlist = false,
  });

  bool get isTv => mediaType == 'tv';

  String? get posterUrl => _image(posterPath, Config.tmdbCard);
  String? get posterLargeUrl => _image(posterPath, Config.tmdbPoster);
  String? get backdropUrl => _image(backdropPath, Config.tmdbBackdrop) ?? posterLargeUrl;

  static String? _image(String? path, String base) {
    if (path == null || path.isEmpty) return null;
    return path.startsWith('http') ? path : '$base$path';
  }

  /// «2019 · 8.4» — короткая подпись под названием.
  String get shortMeta => [
        if (releaseYear != null) '$releaseYear',
        if (voteAverage > 0) voteAverage.toStringAsFixed(1),
      ].join('  ·  ');

  factory Movie.fromJson(Map<String, dynamic> j) {
    final rawGenres = j['genres'];
    // Год приходит по-разному: полем release_year из своей БД либо датой из TMDB.
    final date = asString(j['release_date'] ?? j['first_air_date']);
    return Movie(
      id: asInt(j['id'] ?? j['movie_id']),
      title: asString(j['title'] ?? j['name']),
      overview: asString(j['overview']),
      posterPath: asStringOrNull(j['poster_path']),
      backdropPath: asStringOrNull(j['backdrop_path']),
      voteAverage: asDouble(j['vote_average']),
      voteCount: asInt(j['vote_count']),
      genres: rawGenres is List
          ? rawGenres.map((g) => g is Map ? asString(g['name']) : '$g').where((g) => g.isNotEmpty).toList()
          : asStringList(rawGenres),
      mediaType: asString(j['media_type'], 'movie'),
      releaseYear: asIntOrNull(j['release_year']) ??
          (date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null),
      director: asStringOrNull(j['director']),
      rating: asIntOrNull(j['rating'] ?? j['user_rating']),
      review: asStringOrNull(j['review']),
      category: asStringOrNull(j['category']),
      isWatched: asBool(j['is_watched']),
      isWatchlist: asBool(j['is_watchlist']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'overview': overview,
        'poster_path': posterPath,
        'backdrop_path': backdropPath,
        'vote_average': voteAverage,
        'vote_count': voteCount,
        'genres': genres,
        'media_type': mediaType,
        'release_year': releaseYear,
        'director': director,
        'rating': rating,
        'review': review,
        'category': category,
        'is_watched': isWatched,
        'is_watchlist': isWatchlist,
      };

  Movie copyWith({
    int? rating,
    String? review,
    String? category,
    bool? isWatched,
    bool? isWatchlist,
  }) =>
      Movie(
        id: id,
        title: title,
        overview: overview,
        posterPath: posterPath,
        backdropPath: backdropPath,
        voteAverage: voteAverage,
        voteCount: voteCount,
        genres: genres,
        mediaType: mediaType,
        releaseYear: releaseYear,
        director: director,
        rating: rating ?? this.rating,
        review: review ?? this.review,
        category: category ?? this.category,
        isWatched: isWatched ?? this.isWatched,
        isWatchlist: isWatchlist ?? this.isWatchlist,
      );
}
