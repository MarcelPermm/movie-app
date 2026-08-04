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

  /// Базовый URL постеров TMDB (совпадает с фронтендом).
  static const String tmdbCard = 'https://image.tmdb.org/t/p/w342';
  static const String tmdbPoster = 'https://image.tmdb.org/t/p/w500';

  /// Как часто фоновая синхронизация освежает данные сама по себе.
  /// Всё, что свежее этого срока, читается из локального кэша без похода в сеть.
  static const Duration syncInterval = Duration(minutes: 30);

  /// Таймаут одного сетевого запроса. Render может просыпаться из сна,
  /// поэтому запас щедрый — но UI на него не смотрит, он уже отрисован из кэша.
  static const Duration requestTimeout = Duration(seconds: 60);
}
