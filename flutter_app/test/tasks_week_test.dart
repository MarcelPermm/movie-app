import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/data/goal_repository.dart';
import 'package:movie_app/models/goal.dart';
import 'package:movie_app/models/task.dart';
import 'package:movie_app/widgets/task_bits.dart';

void main() {
  group('Неделя', () {
    test('понедельник недели', () {
      expect(weekStart(DateTime(2026, 10, 10)), DateTime(2026, 10, 5)); // суббота
      expect(weekStart(DateTime(2026, 10, 5)), DateTime(2026, 10, 5)); // сам понедельник
      expect(weekStart(DateTime(2026, 10, 11, 23, 59)), DateTime(2026, 10, 5)); // воскресенье
    });

    test('подпись недели', () {
      expect(weekRangeLabel(DateTime(2026, 10, 10)), '5–11 октября');
      expect(weekRangeLabel(DateTime(2026, 10, 1)), '28 сентября – 4 октября');
    });
  });

  group('Рабочие задачи', () {
    test('распознаются по тегу', () {
      expect(isWorkTag('работа'), isTrue);
      expect(isWorkTag(' Работа '), isTrue);
      expect(isWorkTag('work'), isTrue);
      expect(isWorkTag(''), isFalse);
      expect(isWorkTag(null), isFalse);
      expect(isWorkTag('дом'), isFalse);
    });

    test('задача и цель читают тег с сервера', () {
      final task = TaskItem.fromJson({'id': 1, 'title': 'Отчёт', 'date': '2026-10-10', 'tag': kWorkTag});
      expect(task.isWork, isTrue);
      expect(task.copyWith(tag: '').isWork, isFalse);

      final goal = Goal.fromJson({
        'id': 2,
        'period': 'week',
        'period_key': '2026-10-05',
        'text': 'Сдать квартальный отчёт',
        'tag': 'работа',
      });
      expect(goal.isWork, isTrue);
      expect(goal.copyWith(done: true).isWork, isTrue);
      expect(Goal.fromJson(goal.toJson()).tag, 'работа');
    });
  });
}
