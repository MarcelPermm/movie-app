import '../core/config.dart';
import 'json.dart';
import 'movie.dart';

/// Где человек остановился в сериале: последняя открытая в плеере серия.
class TvProgress {
  final int showId;
  final String title;
  final String? posterPath;
  final String? backdropPath;
  final int season;
  final int episode;
  final String? source;
  final DateTime? updatedAt;

  const TvProgress({
    required this.showId,
    required this.title,
    this.posterPath,
    this.backdropPath,
    this.season = 1,
    this.episode = 1,
    this.source,
    this.updatedAt,
  });

  factory TvProgress.fromJson(Map<String, dynamic> j) => TvProgress(
        showId: asInt(j['show_id']),
        title: asString(j['title']),
        posterPath: asStringOrNull(j['poster_path']),
        backdropPath: asStringOrNull(j['backdrop_path']),
        season: asInt(j['season'], 1),
        episode: asInt(j['episode'], 1),
        source: asStringOrNull(j['source']),
        updatedAt: DateTime.tryParse(asString(j['updated_at'])),
      );

  Map<String, dynamic> toJson() => {
        'show_id': showId,
        'title': title,
        'poster_path': posterPath,
        'backdrop_path': backdropPath,
        'season': season,
        'episode': episode,
        'source': source,
        'updated_at': updatedAt?.toIso8601String(),
      };

  TvProgress copyWith({int? season, int? episode, String? source}) => TvProgress(
        showId: showId,
        title: title,
        posterPath: posterPath,
        backdropPath: backdropPath,
        season: season ?? this.season,
        episode: episode ?? this.episode,
        source: source ?? this.source,
        updatedAt: DateTime.now(),
      );

  /// «S2E5» — коротко, как принято у сериалов.
  String get code => episodeCode(season, episode);

  String? get stillUrl => backdropPath != null && backdropPath!.isNotEmpty
      ? '${Config.tmdbStill}$backdropPath'
      : null;

  /// Карточка сериала для перехода в MovieDetailScreen.
  Movie get asMovie => Movie(
        id: showId,
        title: title,
        posterPath: posterPath,
        backdropPath: backdropPath,
        mediaType: 'tv',
      );
}

/// Серия, которая вышла недавно или скоро выйдет.
class UpcomingEpisode {
  final int showId;
  final String title;
  final String? posterPath;
  final String? backdropPath;
  final int season;
  final int episode;
  final String name;
  final DateTime airDate;

  /// Сериал уже смотрят (он в «Продолжить»), а не только ждут в списке.
  final bool watching;

  const UpcomingEpisode({
    required this.showId,
    required this.title,
    this.posterPath,
    this.backdropPath,
    required this.season,
    required this.episode,
    this.name = '',
    required this.airDate,
    this.watching = false,
  });

  static UpcomingEpisode? tryParse(Map<String, dynamic> j) {
    final air = DateTime.tryParse(asString(j['air_date']));
    if (air == null) return null;
    return UpcomingEpisode(
      showId: asInt(j['show_id']),
      title: asString(j['title']),
      posterPath: asStringOrNull(j['poster_path']),
      backdropPath: asStringOrNull(j['backdrop_path']),
      season: asInt(j['season'], 1),
      episode: asInt(j['episode'], 1),
      name: asString(j['name']),
      airDate: DateTime(air.year, air.month, air.day),
      watching: asBool(j['watching']),
    );
  }

  String get code => episodeCode(season, episode);

  /// Сколько дней до выхода: 0 — сегодня, отрицательное — уже вышла.
  int daysFrom(DateTime now) => airDate.difference(DateTime(now.year, now.month, now.day)).inDays;

  /// «Сегодня», «Завтра», «Через 5 дней», «Вышла вчера», «Вышла 3 дня назад».
  String whenLabel(DateTime now) {
    final d = daysFrom(now);
    if (d == 0) return 'Сегодня';
    if (d == 1) return 'Завтра';
    if (d == -1) return 'Вышла вчера';
    if (d < 0) return 'Вышла ${-d} ${daysWord(-d)} назад';
    return 'Через $d ${daysWord(d)}';
  }

  String? get posterUrl => posterPath != null && posterPath!.isNotEmpty
      ? '${Config.tmdbCard}$posterPath'
      : null;

  Movie get asMovie => Movie(
        id: showId,
        title: title,
        posterPath: posterPath,
        backdropPath: backdropPath,
        mediaType: 'tv',
      );
}

String episodeCode(int season, int episode) => 'S${season}E$episode';

String daysWord(int n) {
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 14) return 'дней';
  return switch (n % 10) {
    1 => 'день',
    2 || 3 || 4 => 'дня',
    _ => 'дней',
  };
}
