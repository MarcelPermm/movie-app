import 'json.dart';

/// Свободная заметка.
class Note {
  final int id;
  final String title;
  final String body;
  final String color;

  const Note({
    required this.id,
    this.title = '',
    this.body = '',
    this.color = 'yellow',
  });

  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty;

  factory Note.fromJson(Map<String, dynamic> j) => Note(
        id: asInt(j['id']),
        title: asString(j['title']),
        body: asString(j['body']),
        color: asString(j['color'], 'yellow'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'color': color,
      };

  Note copyWith({String? title, String? body, String? color}) => Note(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        color: color ?? this.color,
      );
}

/// Список дел («Купить», «Взять в поездку» и т.п.).
class Checklist {
  final int id;
  final String name;
  final String emoji;

  const Checklist({required this.id, required this.name, this.emoji = '📋'});

  factory Checklist.fromJson(Map<String, dynamic> j) => Checklist(
        id: asInt(j['id']),
        name: asString(j['name']),
        emoji: asString(j['emoji'], '📋'),
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'emoji': emoji};

  Checklist copyWith({String? name, String? emoji}) =>
      Checklist(id: id, name: name ?? this.name, emoji: emoji ?? this.emoji);
}

/// Пункт внутри списка дел.
class ChecklistItem {
  final int id;
  final int listId;
  final String title;
  final bool done;

  const ChecklistItem({
    required this.id,
    required this.listId,
    required this.title,
    this.done = false,
  });

  factory ChecklistItem.fromJson(Map<String, dynamic> j) => ChecklistItem(
        id: asInt(j['id']),
        listId: asInt(j['list_id']),
        title: asString(j['title']),
        done: asBool(j['done']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'list_id': listId,
        'title': title,
        'done': done,
      };

  ChecklistItem copyWith({String? title, bool? done}) => ChecklistItem(
        id: id,
        listId: listId,
        title: title ?? this.title,
        done: done ?? this.done,
      );
}
