import 'json.dart';

/// Задача из планировщика.
///
/// Разовые и повторяющиеся задачи отмечаются выполненными по-разному:
/// у разовой меняется `status`, у повторяющейся ставится отметка на
/// конкретную дату и приезжает в `done_today`.
class TaskItem {
  final int id;
  final String title;
  final String date;
  final String status;
  final String? timeStr;
  final String? tag;
  final String priority;

  /// null | 'daily' | 'weekly:0,2,4'
  final String? recurrence;

  /// Только для повторяющихся: выполнена ли она в запрошенный день.
  final bool? doneToday;

  const TaskItem({
    required this.id,
    required this.title,
    required this.date,
    this.status = 'todo',
    this.timeStr,
    this.tag,
    this.priority = 'normal',
    this.recurrence,
    this.doneToday,
  });

  bool get isRecurring => recurrence != null && recurrence!.isNotEmpty;

  bool get isDone => isRecurring ? (doneToday ?? false) : status == 'done';

  bool get isCancelled => status == 'cancelled';

  bool get isHighPriority => priority == 'high';

  factory TaskItem.fromJson(Map<String, dynamic> j) => TaskItem(
        id: asInt(j['id']),
        title: asString(j['title']),
        date: asString(j['date']).split('T').first,
        status: asString(j['status'], 'todo'),
        timeStr: asStringOrNull(j['time_str']),
        tag: asStringOrNull(j['tag']),
        priority: asString(j['priority'], 'normal'),
        recurrence: asStringOrNull(j['recurrence']),
        doneToday: j['done_today'] == null ? null : asBool(j['done_today']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'date': date,
        'status': status,
        'time_str': timeStr,
        'tag': tag,
        'priority': priority,
        'recurrence': recurrence,
        'done_today': doneToday,
      };

  TaskItem copyWith({String? status, bool? doneToday, String? title, String? timeStr, String? tag}) =>
      TaskItem(
        id: id,
        title: title ?? this.title,
        date: date,
        status: status ?? this.status,
        timeStr: timeStr ?? this.timeStr,
        tag: tag ?? this.tag,
        priority: priority,
        recurrence: recurrence,
        doneToday: doneToday ?? this.doneToday,
      );
}
