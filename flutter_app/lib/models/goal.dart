import 'json.dart';

/// Цель на месяц или на год.
class Goal {
  final int id;

  /// 'month' | 'year'
  final String period;

  /// '2026-08' для месяца, '2026' для года
  final String periodKey;

  final String text;
  final bool done;
  final int sort;

  const Goal({
    required this.id,
    required this.period,
    required this.periodKey,
    required this.text,
    this.done = false,
    this.sort = 0,
  });

  factory Goal.fromJson(Map<String, dynamic> j) => Goal(
        id: asInt(j['id']),
        period: asString(j['period'], 'month'),
        periodKey: asString(j['period_key']),
        text: asString(j['text']),
        done: asBool(j['done']),
        sort: asInt(j['sort']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'period': period,
        'period_key': periodKey,
        'text': text,
        'done': done,
        'sort': sort,
      };

  Goal copyWith({String? text, bool? done}) => Goal(
        id: id,
        period: period,
        periodKey: periodKey,
        text: text ?? this.text,
        done: done ?? this.done,
        sort: sort,
      );
}
