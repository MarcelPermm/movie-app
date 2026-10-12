import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/core/config.dart';

void main() {
  test('картинки TMDB идут через наш сервер, а не напрямую', () {
    // У части провайдеров image.tmdb.org не открывается — см. /img на бэкенде.
    for (final base in [
      Config.tmdbCard,
      Config.tmdbPoster,
      Config.tmdbBackdrop,
      Config.tmdbStill,
      Config.tmdbProfile,
      Config.tmdbLogo,
    ]) {
      expect(base, startsWith('${Config.apiBaseUrl}/img/w'));
      expect(base, isNot(contains('image.tmdb.org')));
    }
  });
}
