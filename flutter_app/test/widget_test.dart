import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/core/local_store.dart';
import 'package:movie_app/core/sync_queue.dart';
import 'package:movie_app/models/movie.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('LocalStore: свежесть считается от сервера, а не от своих правок', () {
    const maxAge = Duration(minutes: 30);

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      await LocalStore.init();
    });

    test('ответ сервера помечает кэш свежим', () async {
      await LocalStore.writeList('server', [
        {'id': 1}
      ], fromServer: true);

      expect(LocalStore.isFresh('server', maxAge), isTrue);
      expect(LocalStore.syncedAt('server'), isNotNull);
    });

    test('локальная правка сохраняет данные, но не выдаёт их за свежие', () async {
      await LocalStore.writeList('local', [
        {'id': 2}
      ]);

      // Данные на месте — офлайн-правка не потерялась.
      expect(LocalStore.readList('local'), hasLength(1));
      // Но повод сходить на сервер остался.
      expect(LocalStore.isFresh('local', maxAge), isFalse);
      expect(LocalStore.syncedAt('local'), isNull);
    });

    test('локальная правка не сдвигает отметку, поставленную сервером', () async {
      await LocalStore.writeList('mixed', [
        {'id': 3}
      ], fromServer: true);
      final syncedAt = LocalStore.syncedAt('mixed');

      await LocalStore.writeList('mixed', [
        {'id': 3},
        {'id': 4}
      ]);

      expect(LocalStore.syncedAt('mixed'), syncedAt);
      expect(LocalStore.readList('mixed'), hasLength(2));
    });
  });

  group('Movie.fromJson', () {
    test('берёт id из movie_id, как это делают /watched и /watchlist', () {
      final movie = Movie.fromJson({'movie_id': 550, 'title': 'Бойцовский клуб'});
      expect(movie.id, 550);
      expect(movie.title, 'Бойцовский клуб');
    });

    test('переживает числа, пришедшие строками и int вместо double', () {
      final movie = Movie.fromJson({
        'id': '13',
        'title': 'Форрест Гамп',
        'vote_average': 8,
        'release_year': '1994',
      });
      expect(movie.id, 13);
      expect(movie.voteAverage, 8.0);
      expect(movie.releaseYear, 1994);
    });

    test('не падает на пустом объекте', () {
      final movie = Movie.fromJson({});
      expect(movie.id, 0);
      expect(movie.title, '');
      expect(movie.genres, isEmpty);
      expect(movie.posterUrl, isNull);
    });

    test('строит абсолютный URL постера из пути TMDB', () {
      final movie = Movie.fromJson({'id': 1, 'poster_path': '/abc.jpg'});
      expect(movie.posterUrl, endsWith('/abc.jpg'));
      expect(movie.posterUrl, startsWith('https://'));
    });
  });

  group('PendingOp', () {
    test('переживает сериализацию в очередь и обратно', () {
      final original = PendingOp(
        method: 'POST',
        path: '/watchlist',
        body: {'movie_id': 42, 'media_type': 'tv'},
        query: {'user_id': '1'},
      );

      final restored = PendingOp.fromJson(original.toJson());

      expect(restored.method, 'POST');
      expect(restored.path, '/watchlist');
      expect(restored.body!['movie_id'], 42);
      expect(restored.query!['user_id'], '1');
      expect(restored.createdAt, original.createdAt);
    });

    test('пустое тело остаётся пустым', () {
      final restored = PendingOp.fromJson(
        PendingOp(method: 'DELETE', path: '/watched/7').toJson(),
      );
      expect(restored.body, isNull);
      expect(restored.query, isNull);
    });
  });
}
