import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/movie.dart';
import 'package:movie_app/widgets/media_filters.dart';

Movie m(String title, {List<String> genres = const [], int? year, double rating = 7, List<String> countries = const []}) =>
    Movie(id: title.hashCode, title: title, genres: genres, releaseYear: year, voteAverage: rating, originCountries: countries);

void main() {
  final pool = [
    m('Дюна', genres: ['Фантастика', 'Драма'], year: 2021, rating: 7.8, countries: ['US']),
    m('Паразиты', genres: ['Драма', 'Триллер'], year: 2019, rating: 8.5, countries: ['KR']),
    m('Шрек', genres: ['Мультфильм', 'Комедия'], year: 2001, rating: 7.7, countries: ['US']),
    m('Солярис', genres: ['Фантастика', 'Драма'], year: 1972, rating: 7.9, countries: ['SU']),
  ];

  List<String> titles(MediaFilter f) => f.apply(pool).map((e) => e.title).toList();

  test('без фильтров — всё и в исходном порядке', () {
    expect(titles(const MediaFilter()), ['Дюна', 'Паразиты', 'Шрек', 'Солярис']);
  });

  test('жанр: показать только и спрятать', () {
    expect(titles(const MediaFilter(genres: {'Фантастика'})), ['Дюна', 'Солярис']);
    expect(titles(const MediaFilter(hiddenGenres: {'Драма'})), ['Шрек']);
    expect(titles(const MediaFilter(genres: {'Драма'}, hiddenGenres: {'Фантастика'})), ['Паразиты']);
  });

  test('десятилетие, рейтинг и страна', () {
    expect(titles(const MediaFilter(decade: Decade('2010-е', 2010, 2020))), ['Паразиты']);
    expect(titles(const MediaFilter(decade: Decade('Раньше', null, 1990))), ['Солярис']);
    expect(titles(const MediaFilter(minRating: 7.9)), ['Паразиты', 'Солярис']);
    expect(titles(const MediaFilter(countries: {'US'})), ['Дюна', 'Шрек']);
  });

  test('сортировка и счётчик активных фильтров', () {
    expect(titles(const MediaFilter(sort: MediaSort.newest)).first, 'Дюна');
    expect(titles(const MediaFilter(sort: MediaSort.rating)).first, 'Паразиты');
    expect(titles(const MediaFilter(sort: MediaSort.title)).first, 'Дюна');
    const f = MediaFilter(genres: {'Драма', 'Триллер'}, minRating: 7, sort: MediaSort.rating);
    expect(f.activeCount, 2);
    expect(f.cleared().activeCount, 0);
    expect(f.cleared().sort, MediaSort.rating);
  });

  test('в шторке — только жанры из подборки, частые первыми', () {
    final genres = countValues(pool, (x) => x.genres);
    expect(genres.first.key, 'Драма');
    expect(genres.first.value, 3);
    expect(genres.map((e) => e.key), isNot(contains('Вестерн')));
  });
}
