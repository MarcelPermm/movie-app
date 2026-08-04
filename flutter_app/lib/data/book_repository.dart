import 'dart:async';

import '../models/book.dart';
import 'local_first_repository.dart';

/// Книги: прочитанное и список «хочу прочитать».
class BookRepository extends LocalFirstRepository {
  BookRepository({required super.api, required super.session});

  List<Book> _read = [];
  List<Book> _wishlist = [];

  List<Book> get read => List.unmodifiable(_read);
  List<Book> get wishlist => List.unmodifiable(_wishlist);

  String get _readKey => cacheKey('books::read');
  String get _wishKey => cacheKey('books::wishlist');

  Future<void> load({bool forceRefresh = false}) async {
    _readFromCache();
    notifyListeners();
    if (forceRefresh || isStale(_readKey)) await refresh();
  }

  void _readFromCache() {
    _read = readCache(_readKey).map(Book.fromJson).toList();
    _wishlist = readCache(_wishKey).map(Book.fromJson).toList();
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

  Future<List<Book>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    final data = await api.get('/books/search', query: {'query': query.trim()});
    final list = data is Map ? (data['items'] as List? ?? const []) : (data as List? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => Book.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
