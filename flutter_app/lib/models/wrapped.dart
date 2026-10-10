import '../core/config.dart';
import 'json.dart';

/// «Итоги года» — ответ `/wrapped`. Считает всё сервер, здесь только разбор.
class Wrapped {
  final int year;
  final String title;
  final bool hasData;
  final WrappedCinema cinema;
  final WrappedReading reading;
  final WrappedTravel travel;
  final WrappedMoney money;

  const Wrapped({
    required this.year,
    required this.title,
    required this.hasData,
    required this.cinema,
    required this.reading,
    required this.travel,
    required this.money,
  });

  factory Wrapped.fromJson(Map<String, dynamic> j) => Wrapped(
        year: asInt(j['year']),
        title: asString(j['title']),
        hasData: asBool(j['has_data']),
        cinema: WrappedCinema.fromJson(_map(j['cinema'])),
        reading: WrappedReading.fromJson(_map(j['reading'])),
        travel: WrappedTravel.fromJson(_map(j['travel'])),
        money: WrappedMoney.fromJson(_map(j['money'])),
      );

  /// Итоги одним текстом — чтобы отправить другу в мессенджер.
  String toShareText() {
    final lines = <String>['🐒 Мои итоги $year — «$title»', ''];
    if (cinema.total > 0) {
      lines.add('🎬 ${cinema.movies} фильмов и ${cinema.shows} сериалов');
      if (cinema.topGenres.isNotEmpty) {
        lines.add('   любимый жанр — ${cinema.topGenres.first.name.toLowerCase()}');
      }
      if (cinema.topRated.isNotEmpty) {
        lines.add('   лучшее — ${cinema.topRated.first.title} (${cinema.topRated.first.rating}/10)');
      }
    }
    if (reading.count > 0) {
      lines.add('📚 ${reading.count} книг${reading.pages > 0 ? ', ${reading.pages} страниц' : ''}');
    }
    if (travel.count > 0) {
      lines.add('✈️ ${travel.places.map((p) => p.name).join(' → ')}');
      lines.add('   ${travel.days} дней в пути');
    }
    if (money.total > 0 && money.byCategory.isNotEmpty) {
      lines.add('💸 больше всего ушло на «${money.byCategory.first.name}»');
    }
    return lines.join('\n');
  }
}

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> _list(dynamic v) =>
    v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];

List<int> _ints(dynamic v) =>
    v is List ? v.map(asInt).toList() : List.filled(12, 0);

/// Имя и сколько раз встретилось: жанр, актёр, автор.
class WrappedCount {
  final String name;
  final int count;
  final String? imagePath;

  const WrappedCount({required this.name, required this.count, this.imagePath});

  factory WrappedCount.fromJson(Map<String, dynamic> j) => WrappedCount(
        name: asString(j['name']),
        count: asInt(j['count']),
        imagePath: asStringOrNull(j['profile_path']),
      );

  String? get imageUrl =>
      imagePath == null || imagePath!.isEmpty ? null : '${Config.tmdbProfile}$imagePath';
}

/// Месяц-рекорд: «в марте — 14 фильмов».
class WrappedMonth {
  final int month;
  final String name;
  final int value;

  const WrappedMonth({required this.month, required this.name, required this.value});

  static WrappedMonth? fromJson(dynamic v, String valueKey) {
    if (v is! Map) return null;
    return WrappedMonth(
      month: asInt(v['month']),
      name: asString(v['name']),
      value: asInt(v[valueKey]),
    );
  }
}

class WrappedTitle {
  final int? id;
  final String title;
  final int rating;
  final String? posterPath;
  final String mediaType;

  const WrappedTitle({
    this.id,
    required this.title,
    required this.rating,
    this.posterPath,
    this.mediaType = 'movie',
  });

  factory WrappedTitle.fromJson(Map<String, dynamic> j) => WrappedTitle(
        id: asIntOrNull(j['id']),
        title: asString(j['title']),
        rating: asInt(j['rating']),
        posterPath: asStringOrNull(j['poster_path']),
        mediaType: asString(j['media_type'], 'movie'),
      );

  String? get posterUrl =>
      posterPath == null || posterPath!.isEmpty ? null : '${Config.tmdbPoster}$posterPath';
}

class WrappedCinema {
  final int movies;
  final int shows;
  final double? avgRating;
  final List<WrappedCount> topGenres;
  final List<WrappedCount> topActors;
  final List<WrappedCount> topDirectors;
  final List<WrappedTitle> topRated;
  final WrappedMonth? busiestMonth;
  final List<int> monthly;

  const WrappedCinema({
    this.movies = 0,
    this.shows = 0,
    this.avgRating,
    this.topGenres = const [],
    this.topActors = const [],
    this.topDirectors = const [],
    this.topRated = const [],
    this.busiestMonth,
    this.monthly = const [],
  });

  int get total => movies + shows;

  factory WrappedCinema.fromJson(Map<String, dynamic> j) => WrappedCinema(
        movies: asInt(j['movies']),
        shows: asInt(j['shows']),
        avgRating: j['avg_rating'] == null ? null : asDouble(j['avg_rating']),
        topGenres: _list(j['top_genres']).map(WrappedCount.fromJson).toList(),
        topActors: _list(j['top_actors']).map(WrappedCount.fromJson).toList(),
        topDirectors: _list(j['top_directors']).map(WrappedCount.fromJson).toList(),
        topRated: _list(j['top_rated']).map(WrappedTitle.fromJson).toList(),
        busiestMonth: WrappedMonth.fromJson(j['busiest_month'], 'count'),
        monthly: _ints(j['monthly']),
      );
}

class WrappedBook {
  final String title;
  final String? author;
  final String? cover;
  final int rating;

  const WrappedBook({required this.title, this.author, this.cover, required this.rating});

  factory WrappedBook.fromJson(Map<String, dynamic> j) => WrappedBook(
        title: asString(j['title']),
        author: asStringOrNull(j['author']),
        cover: asStringOrNull(j['cover']),
        rating: asInt(j['rating']),
      );
}

class WrappedReading {
  final int count;
  final int pages;
  final List<WrappedCount> topAuthors;
  final List<WrappedCount> topGenres;
  final List<WrappedBook> topRated;

  const WrappedReading({
    this.count = 0,
    this.pages = 0,
    this.topAuthors = const [],
    this.topGenres = const [],
    this.topRated = const [],
  });

  factory WrappedReading.fromJson(Map<String, dynamic> j) => WrappedReading(
        count: asInt(j['count']),
        pages: asInt(j['pages']),
        topAuthors: _list(j['top_authors']).map(WrappedCount.fromJson).toList(),
        topGenres: _list(j['top_genres']).map(WrappedCount.fromJson).toList(),
        topRated: _list(j['top_rated']).map(WrappedBook.fromJson).toList(),
      );
}

class WrappedPlace {
  final String name;
  final String emoji;

  /// Многогородняя поездка, в которую входит город.
  final String? trip;
  final String startDate;
  final String endDate;
  final int spent;

  const WrappedPlace({
    required this.name,
    this.emoji = '📍',
    this.trip,
    this.startDate = '',
    this.endDate = '',
    this.spent = 0,
  });

  factory WrappedPlace.fromJson(Map<String, dynamic> j) => WrappedPlace(
        name: asString(j['name']),
        emoji: asString(j['emoji'], '📍'),
        trip: asStringOrNull(j['trip']),
        startDate: asString(j['start_date']),
        endDate: asString(j['end_date']),
        spent: asInt(j['spent']),
      );
}

class WrappedTravel {
  final int count;
  final int days;
  final int spent;
  final List<WrappedPlace> places;

  const WrappedTravel({this.count = 0, this.days = 0, this.spent = 0, this.places = const []});

  factory WrappedTravel.fromJson(Map<String, dynamic> j) => WrappedTravel(
        count: asInt(j['count']),
        days: asInt(j['days']),
        spent: asInt(j['spent']),
        places: _list(j['places']).map(WrappedPlace.fromJson).toList(),
      );
}

class WrappedSpend {
  final String name;
  final String emoji;
  final int amount;

  const WrappedSpend({required this.name, this.emoji = '💸', required this.amount});

  factory WrappedSpend.fromJson(Map<String, dynamic> j) => WrappedSpend(
        name: asString(j['name']),
        emoji: asString(j['emoji'], '💸'),
        amount: asInt(j['amount']),
      );
}

class WrappedMoney {
  final int total;
  final int ownTotal;
  final int tripsTotal;
  final List<WrappedSpend> byCategory;

  /// Самое частое место трат и сколько раз туда заходил.
  final String? topMerchant;
  final int topMerchantCount;
  final int topMerchantAmount;
  final WrappedMonth? biggestMonth;
  final List<int> monthly;

  const WrappedMoney({
    this.total = 0,
    this.ownTotal = 0,
    this.tripsTotal = 0,
    this.byCategory = const [],
    this.topMerchant,
    this.topMerchantCount = 0,
    this.topMerchantAmount = 0,
    this.biggestMonth,
    this.monthly = const [],
  });

  factory WrappedMoney.fromJson(Map<String, dynamic> j) {
    final merchant = _map(j['top_merchant']);
    return WrappedMoney(
      total: asInt(j['total']),
      ownTotal: asInt(j['own_total']),
      tripsTotal: asInt(j['trips_total']),
      byCategory: _list(j['by_category']).map(WrappedSpend.fromJson).toList(),
      topMerchant: merchant.isEmpty ? null : asStringOrNull(merchant['name']),
      topMerchantCount: asInt(merchant['count']),
      topMerchantAmount: asInt(merchant['amount']),
      biggestMonth: WrappedMonth.fromJson(j['biggest_month'], 'amount'),
      monthly: _ints(j['monthly']),
    );
  }
}
