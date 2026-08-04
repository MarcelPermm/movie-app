import 'json.dart';

/// Книга из Google Books. Ключ здесь строковый (`book_id`), а не числовой,
/// в отличие от фильмов.
class Book {
  final String bookId;
  final String title;
  final String? author;
  final String? cover;
  final List<String> genres;
  final int? pageCount;
  final String? publishedDate;
  final int? rating;
  final String? review;

  const Book({
    required this.bookId,
    required this.title,
    this.author,
    this.cover,
    this.genres = const [],
    this.pageCount,
    this.publishedDate,
    this.rating,
    this.review,
  });

  /// Google Books отдаёт обложки по http и в мелком размере — чиним и то, и другое.
  String? get coverUrl {
    final c = cover;
    if (c == null || c.isEmpty) return null;
    return c.replaceFirst('http://', 'https://').replaceFirst('&zoom=1', '&zoom=2');
  }

  String get year => (publishedDate ?? '').length >= 4 ? publishedDate!.substring(0, 4) : '';

  factory Book.fromJson(Map<String, dynamic> j) => Book(
        bookId: asString(j['book_id'] ?? j['id']),
        title: asString(j['title']),
        author: asStringOrNull(j['author'] ?? j['authors']),
        cover: asStringOrNull(j['cover'] ?? j['thumbnail']),
        genres: asStringList(j['genres'] ?? j['categories']),
        pageCount: asIntOrNull(j['page_count'] ?? j['pageCount']),
        publishedDate: asStringOrNull(j['published_date'] ?? j['publishedDate']),
        rating: asIntOrNull(j['user_rating'] ?? j['rating']),
        review: asStringOrNull(j['review']),
      );

  Map<String, dynamic> toJson() => {
        'book_id': bookId,
        'title': title,
        'author': author,
        'cover': cover,
        'genres': genres,
        'page_count': pageCount,
        'published_date': publishedDate,
        'user_rating': rating,
        'review': review,
      };

  Book copyWith({int? rating, String? review}) => Book(
        bookId: bookId,
        title: title,
        author: author,
        cover: cover,
        genres: genres,
        pageCount: pageCount,
        publishedDate: publishedDate,
        rating: rating ?? this.rating,
        review: review ?? this.review,
      );
}
