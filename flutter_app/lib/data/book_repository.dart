import 'dart:async';

import '../core/api_client.dart';
import '../models/book.dart';
import '../models/profile_stats.dart';
import 'local_first_repository.dart';

/// Книги: прочитанное, «хочу прочитать» и подборка для открытия.
class BookRepository extends LocalFirstRepository {
  BookRepository({required super.api, required super.session});

  List<Book> _read = [];
  List<Book> _wishlist = [];
  List<Book> _popular = [];

  List<Book> get read => List.unmodifiable(_read);
  List<Book> get wishlist => List.unmodifiable(_wishlist);
  List<Book> get popular => List.unmodifiable(_popular);

  bool isRead(String bookId) => _read.any((b) => b.bookId == bookId);
  bool isInWishlist(String bookId) => _wishlist.any((b) => b.bookId == bookId);

  /// Своя оценка книги, если она уже прочитана. Нужна карточкам из подборок:
  /// там оценки нет, а показать её хочется.
  int? ratingOf(String bookId) {
    for (final b in _read) {
      if (b.bookId == bookId) return b.rating;
    }
    return null;
  }

  String get _readKey => cacheKey('books::read');
  String get _wishKey => cacheKey('books::wishlist');
  String get _popularKey => cacheKey('books::popular');

  Future<void> load({bool forceRefresh = false}) async {
    _readFromCache();
    notifyListeners();
    if (forceRefresh || isStale(_readKey)) await refresh();
  }

  void _readFromCache() {
    _read = readCache(_readKey).map(Book.fromJson).toList();
    _wishlist = readCache(_wishKey).map(Book.fromJson).toList();
    _popular = readCache(_popularKey).map(Book.fromJson).toList();
  }

  Future<void> refresh() => runSync(() async {
        final results = await Future.wait([
          api.get('/books/read'),
          api.get('/books/wishlist'),
        ]);
        await writeCache(_readKey, (results[0] as List?) ?? const [], fromServer: true);
        await writeCache(_wishKey, (results[1] as List?) ?? const [], fromServer: true);
        _readFromCache();
      });

  /// Подборка «Открытие». Тянется отдельно от личных списков: запрос идёт
  /// в Google Books тремя параллельными выборками и ощутимо дольше, а личные
  /// списки нужны сразу — их задерживать нельзя.
  ///
  /// Свой флаг занятости, а не общий runSync: иначе обновление личных списков
  /// и загрузка подборки, стартующие в одном кадре, отменяли бы друг друга.
  bool _loadingPopular = false;
  bool get loadingPopular => _loadingPopular;

  Future<void> loadPopular({bool forceRefresh = false}) async {
    if (_loadingPopular) return;
    if (!forceRefresh && _popular.isNotEmpty && !isStale(_popularKey)) return;

    _loadingPopular = true;
    notifyListeners();
    try {
      final data = await api.get('/books/popular');
      await writeCache(_popularKey, (data as List?) ?? const [], fromServer: true);
      _popular = readCache(_popularKey).map(Book.fromJson).toList();
    } on ApiException {
      // Офлайн или сервер молчит — на экране останется прошлая подборка.
    } finally {
      _loadingPopular = false;
      notifyListeners();
    }
  }

  Future<void> _saveRead() => writeCache(_readKey, _read.map((b) => b.toJson()).toList());
  Future<void> _saveWish() => writeCache(_wishKey, _wishlist.map((b) => b.toJson()).toList());

  Future<void> addToWishlist(Book book) async {
    if (_wishlist.any((b) => b.bookId == book.bookId)) return;
    _wishlist = [book, ..._wishlist];
    notifyListeners();
    await _saveWish();
    await push(() => api.post('/books/wishlist', body: {'book_id': book.bookId}));
  }

  Future<void> removeFromWishlist(String bookId) async {
    final backup = _wishlist;
    _wishlist = _wishlist.where((b) => b.bookId != bookId).toList();
    notifyListeners();
    await _saveWish();
    await push(
      () => api.delete('/books/wishlist/$bookId'),
      rollback: () => _wishlist = backup,
    );
  }

  Future<void> markRead(Book book) async {
    _wishlist = _wishlist.where((b) => b.bookId != book.bookId).toList();
    if (!_read.any((b) => b.bookId == book.bookId)) {
      _read = [book, ..._read];
    }
    notifyListeners();
    await _saveWish();
    await _saveRead();
    await push(() => api.post('/books/read', body: {'book_id': book.bookId}));
  }

  Future<void> removeFromRead(String bookId) async {
    final backup = _read;
    _read = _read.where((b) => b.bookId != bookId).toList();
    notifyListeners();
    await _saveRead();
    await push(
      () => api.delete('/books/read/$bookId'),
      rollback: () => _read = backup,
    );
  }

  Future<void> rate(Book book, int rating, {String? review}) async {
    if (_read.any((b) => b.bookId == book.bookId)) {
      _read = _read
          .map((b) => b.bookId == book.bookId ? b.copyWith(rating: rating, review: review) : b)
          .toList();
    } else {
      // Как и на бэкенде, оценка сама переносит книгу в прочитанные.
      _read = [book.copyWith(rating: rating, review: review), ..._read];
      _wishlist = _wishlist.where((b) => b.bookId != book.bookId).toList();
      await _saveWish();
    }
    notifyListeners();
    await _saveRead();

    await push(() => api.post('/books/read/rate', body: {
          'book_id': book.bookId,
          'rating': rating,
          'review': ?review,
        }));
  }

  /// Параметр называется `q` — так его ждёт эндпоинт /books/search.
  Future<List<Book>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    final data = await api.get('/books/search', query: {'q': query.trim()});
    final list = data is Map ? (data['items'] as List? ?? const []) : (data as List? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => Book.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  // ─── Карточка книги ─────────────────────────────────────────────────

  /// Полные данные книги: описание, издатель, своя оценка.
  /// Кэшируются — возврат к уже открытой карточке мгновенный и без сети.
  Future<Book> details(String bookId) async {
    final key = cacheKey('books::details::$bookId');
    final cached = readCache(key);

    if (cached.isNotEmpty && !isStale(key)) return Book.fromJson(cached.first);

    try {
      final data = await api.get('/books/$bookId/details');
      final map = Map<String, dynamic>.from(data as Map);
      await writeCache(key, [map], fromServer: true);
      return Book.fromJson(map);
    } on ApiException {
      // Офлайн — отдаём что было, а если не было ничего, то запись из списков.
      if (cached.isNotEmpty) return Book.fromJson(cached.first);
      final local = [..._read, ..._wishlist].where((b) => b.bookId == bookId);
      if (local.isNotEmpty) return local.first;
      rethrow;
    }
  }

  Future<List<Book>> similar(String bookId) async {
    final data = await api.get('/books/$bookId/similar');
    return ((data as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Book.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  // ─── Профиль ────────────────────────────────────────────────────────

  /// Сводка по прочитанному. Бэкенд её не считает — собираем на клиенте,
  /// повторяя то, что делает книжный профиль на сайте.
  BookStats get stats {
    if (_read.isEmpty && _wishlist.isEmpty) return const BookStats();

    final rated = _read.where((b) => b.rating != null).toList();
    final genreCount = <String, int>{};
    final authorCount = <String, int>{};
    var pages = 0;

    for (final b in _read) {
      pages += b.pageCount ?? 0;
      for (final g in b.genres) {
        if (g.isNotEmpty) genreCount[g] = (genreCount[g] ?? 0) + 1;
      }
      final author = b.author;
      if (author != null && author.isNotEmpty) {
        authorCount[author] = (authorCount[author] ?? 0) + 1;
      }
    }

    List<NamedCount> top(Map<String, int> source, int limit) {
      final entries = source.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return entries.take(limit).map((e) => NamedCount(e.key, e.value)).toList();
    }

    return BookStats(
      readCount: _read.length,
      wishlistCount: _wishlist.length,
      ratedCount: rated.length,
      avgRating: rated.isEmpty
          ? null
          : rated.map((b) => b.rating!).reduce((a, b) => a + b) / rated.length,
      totalPages: pages,
      topGenres: top(genreCount, 6),
      topAuthors: top(authorCount, 6),
    );
  }
}
