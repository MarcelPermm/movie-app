import '../core/config.dart';

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
  final double voteAverage;
  final List<String> genres;
  final String mediaType;
  final int? releaseYear;
  final String? director;

  /// Только для просмотренного.
  final int? rating;
  final String? review;

  /// Только для списка «к просмотру»: must_see / not_sure / last_resort.
  final String? category;

  const Movie({
    required this.id,
    required this.title,
    this.overview = '',
    this.posterPath,
    this.voteAverage = 0,
    this.genres = const [],
    this.mediaType = 'movie',
    this.releaseYear,
    this.director,
    this.rating,
    this.review,
    this.category,
  });

  bool get isTv => mediaType == 'tv';

  String? get posterUrl {
    final p = posterPath;
    if (p == null || p.isEmpty) return null;
    return p.startsWith('http') ? p : '${Config.tmdbCard}$p';
  }

  static int _asInt(dynamic v, [int fallback = 0]) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  static int? _asIntOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static double _asDouble(dynamic v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  factory Movie.fromJson(Map<String, dynamic> j) {
    final rawGenres = j['genres'];
    return Movie(
      // /watched и /watchlist дублируют id в movie_id — берём то, что есть.
      id: _asInt(j['id'] ?? j['movie_id']),
      title: (j['title'] ?? j['name'] ?? '') as String,
      overview: (j['overview'] ?? '') as String,
      posterPath: j['poster_path'] as String?,
      voteAverage: _asDouble(j['vote_average']),
      genres: rawGenres is List ? rawGenres.map((g) => '$g').toList() : const [],
      mediaType: (j['media_type'] ?? 'movie') as String,
      releaseYear: _asIntOrNull(j['release_year']),
      director: j['director'] as String?,
      rating: _asIntOrNull(j['rating']),
      review: j['review'] as String?,
      category: j['category'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'overview': overview,
        'poster_path': posterPath,
        'vote_average': voteAverage,
        'genres': genres,
        'media_type': mediaType,
        'release_year': releaseYear,
        'director': director,
        'rating': rating,
        'review': review,
        'category': category,
      };

  Movie copyWith({int? rating, String? review, String? category}) => Movie(
        id: id,
        title: title,
        overview: overview,
        posterPath: posterPath,
        voteAverage: voteAverage,
        genres: genres,
        mediaType: mediaType,
        releaseYear: releaseYear,
        director: director,
        rating: rating ?? this.rating,
        review: review ?? this.review,
        category: category ?? this.category,
      );
}
