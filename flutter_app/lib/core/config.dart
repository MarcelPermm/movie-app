/// Единая точка настройки бэкенда.
///
/// Тот же сервер, что использует веб-версия (frontend/config.js).
/// Переопределяется при сборке:
///   flutter run --dart-define=API_BASE_URL=http://localhost:8000
class Config {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://movie-app-xwuo.onrender.com',
  );

  /// Базовые URL картинок TMDB (совпадают с фронтендом).
  static const String tmdbCard = 'https://image.tmdb.org/t/p/w342';
  static const String tmdbPoster = 'https://image.tmdb.org/t/p/w500';
  static const String tmdbBackdrop = 'https://image.tmdb.org/t/p/w1280';
  static const String tmdbStill = 'https://image.tmdb.org/t/p/w300';
  static const String tmdbProfile = 'https://image.tmdb.org/t/p/w185';
  static const String tmdbLogo = 'https://image.tmdb.org/t/p/w154';

  /// Как часто фоновая синхронизация освежает данные сама по себе.
  /// Всё, что свежее этого срока, читается из локального кэша без похода в сеть.
  static const Duration syncInterval = Duration(minutes: 30);

  /// Таймаут одного сетевого запроса. Render может просыпаться из сна,
  /// поэтому запас щедрый — но UI на него не смотрит, он уже отрисован из кэша.
  static const Duration requestTimeout = Duration(seconds: 60);

  /// Источники плеера — те же, что на сайте.
  static const watchSources = {
    'vidsrc': 'VidSrc',
    'videasy': 'Videasy',
    '2embed': '2Embed',
  };

  /// Ссылка на плеер конкретной серии или фильма.
  static String embedUrl(
    String source,
    String mediaType,
    int tmdbId, {
    int season = 1,
    int episode = 1,
  }) {
    final isTv = mediaType == 'tv';
    switch (source) {
      case 'videasy':
        return isTv
            ? 'https://player.videasy.net/tv/$tmdbId/$season/$episode'
            : 'https://player.videasy.net/movie/$tmdbId';
      case '2embed':
        return isTv
            ? 'https://www.2embed.cc/embedtv/$tmdbId&s=$season&e=$episode'
            : 'https://www.2embed.cc/embed/$tmdbId';
      case 'vidsrc':
      default:
        return isTv
            ? 'https://vidsrc.to/embed/tv/$tmdbId/$season/$episode'
            : 'https://vidsrc.to/embed/movie/$tmdbId';
    }
  }

  static String youtubeUrl(String key) => 'https://www.youtube.com/watch?v=$key';
}
