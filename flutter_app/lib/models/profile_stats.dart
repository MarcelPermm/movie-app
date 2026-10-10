import '../core/config.dart';
import 'json.dart';

/// Жанр в разрезе «фильмы / сериалы» — из /profile/stats.
class GenreStat {
  final String name;
  final int movieCount;
  final int tvCount;

  const GenreStat({required this.name, this.movieCount = 0, this.tvCount = 0});

  int get total => movieCount + tvCount;

  factory GenreStat.fromJson(Map<String, dynamic> j) => GenreStat(
        name: asString(j['name']),
        movieCount: asInt(j['movie_count']),
        tvCount: asInt(j['tv_count']),
      );

  Map<String, dynamic> toJson() =>
      {'name': name, 'movie_count': movieCount, 'tv_count': tvCount, 'total': total};
}

/// Имя + счётчик: режиссёры, площадки просмотра.
class NamedCount {
  final String name;
  final int count;

  const NamedCount(this.name, this.count);

  factory NamedCount.fromJson(Map<String, dynamic> j) =>
      NamedCount(asString(j['name']), asInt(j['count']));

  Map<String, dynamic> toJson() => {'name': name, 'count': count};
}

/// Фильм из блока «лучшее по моей оценке».
class TopRatedItem {
  final String title;
  final int rating;
  final String? posterPath;

  const TopRatedItem({required this.title, required this.rating, this.posterPath});

  String? get posterUrl => posterPath == null || posterPath!.isEmpty
      ? null
      : '${Config.tmdbCard}$posterPath';

  factory TopRatedItem.fromJson(Map<String, dynamic> j) => TopRatedItem(
        title: asString(j['title']),
        rating: asInt(j['rating']),
        posterPath: asStringOrNull(j['poster']),
      );

  Map<String, dynamic> toJson() => {'title': title, 'rating': rating, 'poster': posterPath};
}

/// Одно деление гистограммы оценок: сколько фильмов и сериалов на балл N.
class RatingBucket {
  final int score;
  final int movieCount;
  final int tvCount;

  const RatingBucket(this.score, this.movieCount, this.tvCount);

  int get total => movieCount + tvCount;
}

/// Точка на графике «сколько смотрел по месяцам».
class MonthPoint {
  /// Ключ вида «2026-08».
  final String key;
  final int movieCount;
  final int tvCount;

  const MonthPoint(this.key, this.movieCount, this.tvCount);

  int get total => movieCount + tvCount;

  int get year => int.tryParse(key.split('-').first) ?? 0;
  int get month => int.tryParse(key.split('-').last) ?? 1;

  /// «авг 26» — компактная подпись под столбцом.
  String get shortLabel {
    const names = [
      'янв', 'фев', 'мар', 'апр', 'май', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
    ];
    final m = month.clamp(1, 12);
    return '${names[m - 1]} ${year % 100}';
  }
}

/// Полная статистика профиля (/profile/stats).
///
/// Бэкенд для пустого профиля отдаёт короткий объект `{total, movies, tv}` —
/// поэтому все поля, кроме счётчиков, необязательные.
class ProfileStats {
  final int total;
  final int movies;
  final int tv;
  final int ratedCount;
  final double? avgRating;
  final List<RatingBucket> ratingDistribution;
  final List<GenreStat> topGenres;
  final List<NamedCount> topDirectors;
  final List<TopRatedItem> topRated;
  final List<MonthPoint> monthly;
  final List<NamedCount> platforms;

  const ProfileStats({
    this.total = 0,
    this.movies = 0,
    this.tv = 0,
    this.ratedCount = 0,
    this.avgRating,
    this.ratingDistribution = const [],
    this.topGenres = const [],
    this.topDirectors = const [],
    this.topRated = const [],
    this.monthly = const [],
    this.platforms = const [],
  });

  bool get isEmpty => total == 0;

  /// Максимум по гистограмме — нужен, чтобы нормировать высоту столбцов.
  int get maxRatingBucket =>
      ratingDistribution.fold(0, (max, b) => b.total > max ? b.total : max);

  int get maxMonth => monthly.fold(0, (max, m) => m.total > max ? m.total : max);

  factory ProfileStats.fromJson(Map<String, dynamic> j) {
    final dist = j['rating_distribution'];
    final monthlyRaw = j['monthly_stats'];
    final platformRaw = j['platform_stats'];

    return ProfileStats(
      total: asInt(j['total']),
      movies: asInt(j['movies']),
      tv: asInt(j['tv']),
      ratedCount: asInt(j['rated_count']),
      avgRating: asDoubleOrNull(j['avg_rating']),
      ratingDistribution: dist is Map
          ? [
              for (var i = 1; i <= 10; i++)
                RatingBucket(
                  i,
                  asInt((dist['$i'] as Map?)?['movie']),
                  asInt((dist['$i'] as Map?)?['tv']),
                ),
            ]
          : const [],
      topGenres: (j['top_genres'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => GenreStat.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      topDirectors: (j['top_directors'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => NamedCount.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      topRated: (j['top_rated'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => TopRatedItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      // Месяцы приходят объектом {"2026-08": {...}} — раскладываем и сортируем
      // по возрастанию, чтобы график читался слева направо.
      monthly: monthlyRaw is Map
          ? (monthlyRaw.entries
              .map((e) => MonthPoint(
                    '${e.key}',
                    asInt((e.value as Map?)?['movie']),
                    asInt((e.value as Map?)?['tv']),
                  ))
              .toList()
            ..sort((a, b) => a.key.compareTo(b.key)))
          : const [],
      platforms: platformRaw is Map
          ? platformRaw.entries.map((e) => NamedCount('${e.key}', asInt(e.value))).toList()
          : const [],
    );
  }

  /// Кэш хранит ровно то, что пришло с сервера, — поэтому обратно собираем
  /// тот же формат, что и разбирали.
  Map<String, dynamic> toJson() => {
        'total': total,
        'movies': movies,
        'tv': tv,
        'rated_count': ratedCount,
        'avg_rating': avgRating,
        'rating_distribution': {
          for (final b in ratingDistribution)
            '${b.score}': {'movie': b.movieCount, 'tv': b.tvCount},
        },
        'top_genres': topGenres.map((g) => g.toJson()).toList(),
        'top_directors': topDirectors.map((d) => d.toJson()).toList(),
        'top_rated': topRated.map((t) => t.toJson()).toList(),
        'monthly_stats': {
          for (final m in monthly) m.key: {'movie': m.movieCount, 'tv': m.tvCount},
        },
        'platform_stats': {for (final p in platforms) p.name: p.count},
      };
}

/// Сводка по книгам. Бэкенд её не считает — собираем на клиенте
/// из списка прочитанного, как это делает loadBooksProfile() на сайте.
class BookStats {
  final int readCount;
  final int wishlistCount;
  final int ratedCount;
  final double? avgRating;
  final int totalPages;
  final List<NamedCount> topGenres;
  final List<NamedCount> topAuthors;

  const BookStats({
    this.readCount = 0,
    this.wishlistCount = 0,
    this.ratedCount = 0,
    this.avgRating,
    this.totalPages = 0,
    this.topGenres = const [],
    this.topAuthors = const [],
  });

  bool get isEmpty => readCount == 0 && wishlistCount == 0;
}
