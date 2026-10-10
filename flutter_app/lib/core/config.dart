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

  /// Источники плеера — как в Streambert (github.com/truelockmc/streambert),
  /// где они проверены на десктопе. Прежние адреса (vidsrc.to,
  /// player.videasy.net, 2embed.cc) устарели: страница плеера открывалась,
  /// но отвечала «We couldn't find that». Первый в списке — по умолчанию.
  static const watchSources = {
    'videasy': 'Videasy',
    'vidsrc': 'VidSrc',
    'vidking': 'Vidking',
  };

  static const defaultWatchSource = 'videasy';

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
      case 'vidsrc':
        return isTv
            ? 'https://vsembed.su/embed/tv/$tmdbId/$season/$episode'
            : 'https://vsembed.su/embed/movie/$tmdbId';
      case 'vidking':
        return isTv
            ? 'https://www.vidking.net/embed/tv/$tmdbId/$season/$episode?autoPlay=true'
            : 'https://www.vidking.net/embed/movie/$tmdbId?autoPlay=true';
      case 'videasy':
      default:
        return isTv
            ? 'https://player.videasy.to/tv/$tmdbId/$season/$episode?overlay=true'
            : 'https://player.videasy.to/movie/$tmdbId?overlay=true';
    }
  }

  static String youtubeUrl(String key) => 'https://www.youtube.com/watch?v=$key';
}
