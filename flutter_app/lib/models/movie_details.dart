import '../core/config.dart';
import 'json.dart';
import 'movie.dart';

/// Актёр в карточке фильма.
class CastMember {
  final int id;
  final String name;
  final String character;
  final String? profilePath;

  const CastMember({
    required this.id,
    required this.name,
    this.character = '',
    this.profilePath,
  });

  String? get photoUrl =>
      profilePath == null || profilePath!.isEmpty ? null : '${Config.tmdbProfile}$profilePath';

  factory CastMember.fromJson(Map<String, dynamic> j) => CastMember(
        id: asInt(j['id']),
        name: asString(j['name']),
        character: asString(j['character']),
        profilePath: asStringOrNull(j['profile_path']),
      );
}

/// Студия-производитель.
class Studio {
  final int id;
  final String name;
  final String? logoPath;

  const Studio({required this.id, required this.name, this.logoPath});

  String? get logoUrl =>
      logoPath == null || logoPath!.isEmpty ? null : '${Config.tmdbLogo}$logoPath';

  factory Studio.fromJson(Map<String, dynamic> j) => Studio(
        id: asInt(j['id']),
        name: asString(j['name']),
        logoPath: asStringOrNull(j['logo_path']),
      );
}

/// Сезон сериала — то, что приходит в деталях.
class SeasonInfo {
  final int seasonNumber;
  final String name;
  final int episodeCount;

  const SeasonInfo({
    required this.seasonNumber,
    required this.name,
    this.episodeCount = 0,
  });

  factory SeasonInfo.fromJson(Map<String, dynamic> j) => SeasonInfo(
        seasonNumber: asInt(j['season_number']),
        name: asString(j['name']),
        episodeCount: asInt(j['episode_count']),
      );
}

/// Серия. Приходит отдельным запросом за сезон.
class Episode {
  final int episodeNumber;
  final String name;
  final String overview;
  final String airDate;
  final int? runtime;
  final double voteAverage;
  final String? stillPath;

  const Episode({
    required this.episodeNumber,
    required this.name,
    this.overview = '',
    this.airDate = '',
    this.runtime,
    this.voteAverage = 0,
    this.stillPath,
  });

  String? get stillUrl =>
      stillPath == null || stillPath!.isEmpty ? null : '${Config.tmdbStill}$stillPath';

  String get year => airDate.length >= 4 ? airDate.substring(0, 4) : '';

  /// «24 мин · 8.1» — подпись под названием серии.
  String get meta => [
        if (airDate.isNotEmpty) airDate,
        if (runtime != null && runtime! > 0) '$runtime мин',
        if (voteAverage > 0) '★ ${voteAverage.toStringAsFixed(1)}',
      ].join('  ·  ');

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
        episodeNumber: asInt(j['episode_number']),
        name: asString(j['name']),
        overview: asString(j['overview']),
        airDate: asString(j['air_date']),
        runtime: asIntOrNull(j['runtime']),
        voteAverage: asDouble(j['vote_average']),
        stillPath: asStringOrNull(j['still_path']),
      );
}

/// Полная карточка фильма или сериала — то, что показывает модалка на сайте.
class MovieDetails {
  final Movie movie;
  final String? originalTitle;
  final int? runtime;
  final double? imdbRating;
  final int? imdbVoteCount;
  final int? directorId;
  final List<CastMember> cast;
  final List<Studio> studios;
  final List<SeasonInfo> seasons;
  final int? seasonsCount;
  final int? episodesCount;

  /// Что пользователь уже поставил этому фильму.
  final int? userRating;
  final String? userReview;

  const MovieDetails({
    required this.movie,
    this.originalTitle,
    this.runtime,
    this.imdbRating,
    this.imdbVoteCount,
    this.directorId,
    this.cast = const [],
    this.studios = const [],
    this.seasons = const [],
    this.seasonsCount,
    this.episodesCount,
    this.userRating,
    this.userReview,
  });

  bool get isTv => movie.isTv;

  /// «2 сез · 16 эп» для сериала, «142 мин» для фильма.
  String? get lengthLabel {
    if (seasonsCount != null) {
      return '$seasonsCount сез · ${episodesCount ?? '?'} эп';
    }
    return runtime != null && runtime! > 0 ? '$runtime мин' : null;
  }

  /// Сезоны без «нулевого» — в нём лежат спецвыпуски, на сайте их тоже нет.
  List<SeasonInfo> get realSeasons =>
      seasons.where((s) => s.seasonNumber > 0 && s.episodeCount > 0).toList();

  factory MovieDetails.fromJson(Map<String, dynamic> j, String mediaType) {
    final watchedInfo = j['watched_info'];
    final rawSeasons = j['seasons'];

    return MovieDetails(
      movie: Movie.fromJson({...j, 'media_type': mediaType}),
      originalTitle: asStringOrNull(j['original_title'] ?? j['original_name']),
      runtime: asIntOrNull(j['runtime']),
      imdbRating: asDoubleOrNull(j['imdb_rating']),
      imdbVoteCount: asIntOrNull(j['imdb_vote_count']),
      directorId: asIntOrNull(j['director_id']),
      cast: (j['cast'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => CastMember.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      studios: (j['studios'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Studio.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      seasons: rawSeasons is List
          ? rawSeasons
              .whereType<Map>()
              .map((e) => SeasonInfo.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      seasonsCount: asIntOrNull(j['seasons_count']),
      episodesCount: asIntOrNull(j['episodes_count']),
      userRating: watchedInfo is Map ? asIntOrNull(watchedInfo['user_rating']) : null,
      userReview: watchedInfo is Map ? asStringOrNull(watchedInfo['review']) : null,
    );
  }
}
