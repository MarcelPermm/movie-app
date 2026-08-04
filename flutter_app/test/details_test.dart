import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/core/config.dart';
import 'package:movie_app/models/movie.dart';
import 'package:movie_app/models/movie_details.dart';

void main() {
  group('Movie: картинки и подпись', () {
    test('бэкдроп берётся в большом размере', () {
      final movie = Movie.fromJson({'id': 1, 'backdrop_path': '/bd.jpg'});
      expect(movie.backdropUrl, contains('w1280'));
      expect(movie.backdropUrl, endsWith('/bd.jpg'));
    });

    test('без бэкдропа подставляется постер — шапка не остаётся пустой', () {
      final movie = Movie.fromJson({'id': 1, 'poster_path': '/p.jpg'});
      expect(movie.backdropUrl, isNotNull);
      expect(movie.backdropUrl, contains('/p.jpg'));
    });

    test('год вытаскивается из даты TMDB, когда своего поля нет', () {
      expect(Movie.fromJson({'id': 1, 'release_date': '1999-03-31'}).releaseYear, 1999);
      expect(Movie.fromJson({'id': 1, 'first_air_date': '2011-04-17'}).releaseYear, 2011);
      expect(Movie.fromJson({'id': 1, 'release_year': 2020}).releaseYear, 2020);
    });

    test('жанры приходят и объектами, и строками', () {
      final fromObjects = Movie.fromJson({
        'id': 1,
        'genres': [
          {'id': 18, 'name': 'Драма'}
        ]
      });
      final fromStrings = Movie.fromJson({
        'id': 1,
        'genres': ['Драма']
      });
      expect(fromObjects.genres, ['Драма']);
      expect(fromStrings.genres, ['Драма']);
    });

    test('подпись собирается из года и рейтинга', () {
      final movie = Movie.fromJson({'id': 1, 'release_year': 2019, 'vote_average': 8.5});
      expect(movie.shortMeta, '2019  ·  8.5');
    });

    test('без года и рейтинга подпись пустая, а не из разделителей', () {
      expect(Movie.fromJson({'id': 1}).shortMeta, '');
    });
  });

  group('MovieDetails', () {
    test('у сериала длительность считается сезонами', () {
      final details = MovieDetails.fromJson({
        'id': 1,
        'name': 'Сериал',
        'seasons_count': 3,
        'episodes_count': 24,
      }, 'tv');
      expect(details.lengthLabel, '3 сез · 24 эп');
      expect(details.isTv, isTrue);
    });

    test('у фильма — минутами', () {
      final details = MovieDetails.fromJson({'id': 1, 'title': 'Фильм', 'runtime': 142}, 'movie');
      expect(details.lengthLabel, '142 мин');
    });

    test('нулевой сезон со спецвыпусками отбрасывается', () {
      final details = MovieDetails.fromJson({
        'id': 1,
        'name': 'Сериал',
        'seasons': [
          {'season_number': 0, 'name': 'Спецэпизоды', 'episode_count': 5},
          {'season_number': 1, 'name': 'Сезон 1', 'episode_count': 10},
          {'season_number': 2, 'name': 'Сезон 2', 'episode_count': 0},
        ],
      }, 'tv');

      expect(details.realSeasons.map((s) => s.seasonNumber), [1]);
    });

    test('оценка пользователя достаётся из watched_info', () {
      final details = MovieDetails.fromJson({
        'id': 1,
        'title': 'Фильм',
        'watched_info': {'user_rating': 9, 'review': 'Хорошо'},
      }, 'movie');
      expect(details.userRating, 9);
      expect(details.userReview, 'Хорошо');
    });

    test('без watched_info оценки просто нет', () {
      final details = MovieDetails.fromJson({'id': 1, 'title': 'Фильм'}, 'movie');
      expect(details.userRating, isNull);
    });
  });

  group('Episode', () {
    test('подпись собирается из даты, длительности и рейтинга', () {
      final ep = Episode.fromJson({
        'episode_number': 3,
        'name': 'Серия',
        'air_date': '2011-05-01',
        'runtime': 55,
        'vote_average': 8.6,
      });
      expect(ep.meta, '2011-05-01  ·  55 мин  ·  ★ 8.6');
    });

    test('пустые поля не оставляют висящих точек', () {
      final ep = Episode.fromJson({'episode_number': 1, 'name': 'Серия'});
      expect(ep.meta, '');
    });
  });

  group('Config.embedUrl: у источников разный формат ссылок', () {
    test('фильм не содержит сезон и серию', () {
      expect(Config.embedUrl('vidsrc', 'movie', 550), 'https://vidsrc.to/embed/movie/550');
      expect(Config.embedUrl('videasy', 'movie', 550), 'https://player.videasy.net/movie/550');
      expect(Config.embedUrl('2embed', 'movie', 550), 'https://www.2embed.cc/embed/550');
    });

    test('сериал подставляет сезон и серию', () {
      expect(
        Config.embedUrl('vidsrc', 'tv', 1399, season: 2, episode: 5),
        'https://vidsrc.to/embed/tv/1399/2/5',
      );
      expect(
        Config.embedUrl('2embed', 'tv', 1399, season: 2, episode: 5),
        'https://www.2embed.cc/embedtv/1399&s=2&e=5',
      );
    });

    test('неизвестный источник не ломает ссылку, а падает на vidsrc', () {
      expect(Config.embedUrl('нет-такого', 'movie', 1), contains('vidsrc.to'));
    });
  });
}
