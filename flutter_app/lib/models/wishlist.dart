import 'json.dart';

/// Вещь из виш-листа.
///
/// Резерв и складчина приходят только когда список смотрит друг: своему
/// владельцу бэкенд их не отдаёт, чтобы не испортить сюрприз.
class WishItem {
  final int id;
  final String title;
  final String? url;
  final String? image;
  final double? price;
  final String currency;
  final String? note;

  /// 1 — очень хочу, 4 — так, мысль вслух.
  final int priority;

  final bool isReserved;
  final bool reservedByMe;
  final String? reserverName;
  final double contributedTotal;
  final double? myContribution;

  const WishItem({
    required this.id,
    required this.title,
    this.url,
    this.image,
    this.price,
    this.currency = 'RUB',
    this.note,
    this.priority = 2,
    this.isReserved = false,
    this.reservedByMe = false,
    this.reserverName,
    this.contributedTotal = 0,
    this.myContribution,
  });

  static const priorityLabels = {
    1: 'Очень хочу',
    2: 'Хочу',
    3: 'Было бы славно',
    4: 'Просто мысль',
  };

  String get priorityLabel => priorityLabels[priority] ?? 'Хочу';

  /// Сколько ещё не собрано складчиной.
  double? get remaining {
    final p = price;
    if (p == null) return null;
    final left = p - contributedTotal;
    return left > 0 ? left : 0;
  }

  factory WishItem.fromJson(Map<String, dynamic> j) => WishItem(
        id: asInt(j['id']),
        title: asString(j['title']),
        url: asStringOrNull(j['url']),
        image: asStringOrNull(j['image']),
        price: asDoubleOrNull(j['price']),
        currency: asString(j['currency'], 'RUB'),
        note: asStringOrNull(j['note']),
        priority: asInt(j['priority'], 2),
        isReserved: asBool(j['is_reserved']),
        reservedByMe: asBool(j['reserved_by_me']),
        reserverName: asStringOrNull(j['reserver_name']),
        contributedTotal: asDouble(j['contributed_total']),
        myContribution: asDoubleOrNull(j['my_contribution']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'image': image,
        'price': price,
        'currency': currency,
        'note': note,
        'priority': priority,
        'is_reserved': isReserved,
        'reserved_by_me': reservedByMe,
        'reserver_name': reserverName,
        'contributed_total': contributedTotal,
        'my_contribution': myContribution,
      };

  WishItem copyWith({
    String? title,
    String? url,
    String? image,
    double? price,
    String? note,
    int? priority,
    bool? isReserved,
    bool? reservedByMe,
  }) =>
      WishItem(
        id: id,
        title: title ?? this.title,
        url: url ?? this.url,
        image: image ?? this.image,
        price: price ?? this.price,
        currency: currency,
        note: note ?? this.note,
        priority: priority ?? this.priority,
        isReserved: isReserved ?? this.isReserved,
        reservedByMe: reservedByMe ?? this.reservedByMe,
        reserverName: reserverName,
        contributedTotal: contributedTotal,
        myContribution: myContribution,
      );
}

/// Друг — то есть принятая дружба.
class Friend {
  final int id;
  final String username;
  final String displayName;

  const Friend({required this.id, required this.username, required this.displayName});

  factory Friend.fromJson(Map<String, dynamic> j) => Friend(
        id: asInt(j['id']),
        username: asString(j['username']),
        displayName: asString(j['display_name']),
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'username': username, 'display_name': displayName};
}

/// Заявка в друзья. `id` — идентификатор дружбы (им её принимают),
/// `userId` — тот, кто на другой стороне.
class FriendRequest {
  final int id;
  final int userId;
  final String username;
  final String displayName;

  const FriendRequest({
    required this.id,
    required this.userId,
    required this.username,
    required this.displayName,
  });

  factory FriendRequest.fromJson(Map<String, dynamic> j) => FriendRequest(
        id: asInt(j['id']),
        userId: asInt(j['user_id']),
        username: asString(j['username']),
        displayName: asString(j['display_name']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'username': username,
        'display_name': displayName,
      };
}
