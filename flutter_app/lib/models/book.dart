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

  /// Оценка пользователя (1–10), не средняя по Google Books.
  final int? rating;
  final String? review;

  final String description;
  final String? publisher;
  final String? language;

  /// Средняя оценка Google Books и число голосов — справочно, в карточке.
  final double? communityRating;
  final int? communityRatingsCount;

  /// Пометки, которые бэкенд добавляет к спискам открытия и поиска.
  final bool isRead;
  final bool isWishlist;

  /// Объяснение от AI, почему книга предложена (только в ✦ Посоветуй).
  final String? aiReason;

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
    this.description = '',
    this.publisher,
    this.language,
    this.communityRating,
    this.communityRatingsCount,
    this.isRead = false,
    this.isWishlist = false,
    this.aiReason,
  });

  /// Google Books отдаёт обложки по http и в мелком размере — чиним и то, и другое.
  String? get coverUrl {
    final c = cover;
    if (c == null || c.isEmpty) return null;
    return c.replaceFirst('http://', 'https://').replaceFirst('&zoom=1', '&zoom=2');
  }

  String get year => (publishedDate ?? '').length >= 4 ? publishedDate!.substring(0, 4) : '';

  /// «2019 · 384 с.» — подпись под названием.
  String get shortMeta => [
        if (year.isNotEmpty) year,
        if (pageCount != null && pageCount! > 0) '$pageCount с.',
      ].join('  ·  ');

  factory Book.fromJson(Map<String, dynamic> j) => Book(
        bookId: asString(j['book_id'] ?? j['id']),
        title: asString(j['title']),
        author: asStringOrNull(j['author'] ?? j['authors']),
        cover: asStringOrNull(j['cover'] ?? j['thumbnail']),
        genres: asStringList(j['genres'] ?? j['categories']),
        pageCount: asIntOrNull(j['page_count'] ?? j['pageCount']),
        publishedDate: asStringOrNull(j['published_date'] ?? j['publishedDate']),
        // user_rating — своя оценка, rating в ответах открытия — средняя
        // по Google Books. Путать их нельзя, поэтому разбираем по отдельности.
        rating: asIntOrNull(j['user_rating']),
        review: asStringOrNull(j['review']),
        description: asString(j['description']),
        publisher: asStringOrNull(j['publisher']),
        language: asStringOrNull(j['language']),
        communityRating: asDoubleOrNull(j['rating']),
        communityRatingsCount: asIntOrNull(j['ratings_count']),
        isRead: asBool(j['is_read']),
        isWishlist: asBool(j['is_wishlist']),
        aiReason: asStringOrNull(j['ai_reason']),
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
        'description': description,
        'publisher': publisher,
        'language': language,
        'rating': communityRating,
        'ratings_count': communityRatingsCount,
        'is_read': isRead,
        'is_wishlist': isWishlist,
        'ai_reason': aiReason,
      };

  Book copyWith({
    int? rating,
    String? review,
    bool? isRead,
    bool? isWishlist,
  }) =>
      Book(
        bookId: bookId,
        title: title,
        author: author,
        cover: cover,
        genres: genres,
        pageCount: pageCount,
        publishedDate: publishedDate,
        rating: rating ?? this.rating,
        review: review ?? this.review,
        description: description,
        publisher: publisher,
        language: language,
        communityRating: communityRating,
        communityRatingsCount: communityRatingsCount,
        isRead: isRead ?? this.isRead,
        isWishlist: isWishlist ?? this.isWishlist,
        aiReason: aiReason,
      );
}
