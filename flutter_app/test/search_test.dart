import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/data/movie_repository.dart';
import 'package:movie_app/models/movie.dart';

Movie m(String title, int votes, {String type = 'movie'}) =>
    Movie(id: title.hashCode, title: title, voteCount: votes, mediaType: type);

void main() {
  test('популярный сериал выше фильмов-спутников', () {
    final out = rankSearch('Breaking Bad', [
      m('El Camino', 5000),
      m('Breaking Bad Wolf', 10),
      m('Во все тяжкие', 15000, type: 'tv'),
    ]);
    expect(out.first.title, 'Во все тяжкие');
    expect(out.first.isTv, isTrue);
  });

  test('точное совпадение — первым, остальное по популярности', () {
    final out = rankSearch('Дюна', [
      m('Дюна: Часть вторая', 9000),
      m('Пески Дюны', 50),
      m('Дюна', 100, type: 'tv'),
    ]);
    expect(out.map((e) => e.title), ['Дюна', 'Дюна: Часть вторая', 'Пески Дюны']);
  });

  test('при равенстве сохраняется исходный порядок', () {
    final out = rankSearch('x', [m('a', 1), m('b', 1), m('c', 1)]);
    expect(out.map((e) => e.title), ['a', 'b', 'c']);
  });
}
