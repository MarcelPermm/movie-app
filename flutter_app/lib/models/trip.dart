import 'json.dart';

/// Поездка или событие: отпуск, свадьба, ремонт — всё, у чего есть даты
/// и свой бюджет, отдельный от месячного.
///
/// На бэкенде это одна таблица `trips`, а `event_type` различает обычную
/// поездку, разовое событие и группу, объединяющую несколько поездок.
class Trip {
  final int id;
  final String name;
  final String emoji;
  final String? startDate;
  final String? endDate;

  /// Сколько заложено и сколько уже потрачено (сумму считает сервер).
  final int plannedTotal;
  final int actualTotal;

  /// trip | event | group
  final String eventType;
  final String subtitle;

  /// Для поездки внутри группы — id родителя.
  final int? parentId;

  const Trip({
    required this.id,
    required this.name,
    this.emoji = '✈️',
    this.startDate,
    this.endDate,
    this.plannedTotal = 0,
    this.actualTotal = 0,
    this.eventType = 'trip',
    this.subtitle = '',
    this.parentId,
  });

  bool get isGroup => eventType == 'group';

  /// Доля потраченного от плана — для полоски. null, если плана нет.
  double? get progress {
    if (plannedTotal <= 0) return null;
    return (actualTotal / plannedTotal).clamp(0.0, 1.0);
  }

  bool get overspent => plannedTotal > 0 && actualTotal > plannedTotal;

  /// «12 мар — 20 мар» или одна дата, если вторая не задана.
  String get dateLabel {
    final from = _short(startDate);
    final to = _short(endDate);
    if (from == null && to == null) return 'Даты не заданы';
    if (from != null && to != null) return from == to ? from : '$from — $to';
    return (from ?? to)!;
  }

  /// Сколько дней осталось до начала. null — уже началась или дат нет.
  int? get daysUntil {
    final start = parseDate(startDate);
    if (start == null) return null;
    final today = DateTime.now();
    final days = DateTime(start.year, start.month, start.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
    return days > 0 ? days : null;
  }

  static const _months = [
    'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
    'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];

  static String? _short(String? raw) {
    final d = parseDate(raw);
    if (d == null) return null;
    return '${d.day} ${_months[d.month - 1]}';
  }

  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
        id: asInt(j['id']),
        name: asString(j['name']),
        emoji: asString(j['emoji'], '✈️'),
        startDate: asStringOrNull(j['start_date'])?.split('T').first,
        endDate: asStringOrNull(j['end_date'])?.split('T').first,
        plannedTotal: asInt(j['planned_total']),
        actualTotal: asInt(j['actual_total']),
        eventType: asString(j['event_type'], 'trip'),
        subtitle: asString(j['subtitle']),
        parentId: asIntOrNull(j['parent_id']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'start_date': startDate,
        'end_date': endDate,
        'planned_total': plannedTotal,
        'actual_total': actualTotal,
        'event_type': eventType,
        'subtitle': subtitle,
        'parent_id': parentId,
      };

  Trip copyWith({
    String? name,
    String? emoji,
    String? startDate,
    String? endDate,
    int? plannedTotal,
    int? actualTotal,
    String? subtitle,
  }) =>
      Trip(
        id: id,
        name: name ?? this.name,
        emoji: emoji ?? this.emoji,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
        plannedTotal: plannedTotal ?? this.plannedTotal,
        actualTotal: actualTotal ?? this.actualTotal,
        eventType: eventType,
        subtitle: subtitle ?? this.subtitle,
        parentId: parentId,
      );
}

/// Трата поездки, попавшая в месячный бюджет.
///
/// Поездки живут отдельно от месяца, но деньги-то одни и те же: ужин в
/// отпуске — это всё равно «еда». Чтобы категории месяца не врали, такие
/// траты подмешиваются к обычным, но помнят, из какой поездки пришли.
class TripSpending {
  final int tripId;
  final String tripName;
  final String tripEmoji;
  final TripExpense expense;

  const TripSpending({
    required this.tripId,
    required this.tripName,
    required this.tripEmoji,
    required this.expense,
  });

  factory TripSpending.fromJson(Map<String, dynamic> j) => TripSpending(
        tripId: asInt(j['trip_id']),
        tripName: asString(j['trip_name']),
        tripEmoji: asString(j['trip_emoji'], '✈️'),
        expense: TripExpense.fromJson(
          Map<String, dynamic>.from(j['expense'] as Map),
        ),
      );

  Map<String, dynamic> toJson() => {
        'trip_id': tripId,
        'trip_name': tripName,
        'trip_emoji': tripEmoji,
        'expense': expense.toJson(),
      };
}

/// Трата внутри поездки.
///
/// У неё, в отличие от обычной, есть план: сначала записываешь, сколько
/// собираешься потратить на жильё и билеты, а потом — сколько вышло.
class TripExpense {
  final int id;
  final int tripId;
  final String date;
  final int amount;
  final int? plannedAmount;
  final int? plannedMax;
  final String category;
  final String subcategory;

  /// Свободная пометка дня — «день 3», «дорога туда».
  final String day;

  final String note;
  final String emoji;
  final String city;

  const TripExpense({
    required this.id,
    required this.tripId,
    required this.date,
    this.amount = 0,
    this.plannedAmount,
    this.plannedMax,
    this.category = '',
    this.subcategory = '',
    this.day = '',
    this.note = '',
    this.emoji = '',
    this.city = '',
  });

  /// Что показать в строке: категория, комментарий или прочерк.
  String get label {
    if (category.trim().isNotEmpty) return category.trim();
    if (note.trim().isNotEmpty) return note.trim();
    return 'Без названия';
  }

  /// Потрачено ли уже. Пока сумма нулевая — это только план.
  bool get isPaid => amount > 0;

  factory TripExpense.fromJson(Map<String, dynamic> j) => TripExpense(
        id: asInt(j['id']),
        tripId: asInt(j['trip_id']),
        date: asString(j['date']).split('T').first,
        amount: asInt(j['amount']),
        plannedAmount: asIntOrNull(j['planned_amount']),
        plannedMax: asIntOrNull(j['planned_max']),
        category: asString(j['category']),
        subcategory: asString(j['subcategory']),
        day: asString(j['day']),
        note: asString(j['note']),
        emoji: asString(j['emoji']),
        city: asString(j['city']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'trip_id': tripId,
        'date': date,
        'amount': amount,
        'planned_amount': plannedAmount,
        'planned_max': plannedMax,
        'category': category,
        'subcategory': subcategory,
        'day': day,
        'note': note,
        'emoji': emoji,
        'city': city,
      };

  TripExpense copyWith({
    int? amount,
    int? plannedAmount,
    String? category,
    String? note,
    String? city,
    String? day,
  }) =>
      TripExpense(
        id: id,
        tripId: tripId,
        date: date,
        amount: amount ?? this.amount,
        plannedAmount: plannedAmount ?? this.plannedAmount,
        plannedMax: plannedMax,
        category: category ?? this.category,
        subcategory: subcategory,
        day: day ?? this.day,
        note: note ?? this.note,
        emoji: emoji,
        city: city ?? this.city,
      );
}
