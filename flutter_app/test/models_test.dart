import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/book.dart';
import 'package:movie_app/models/budget.dart';
import 'package:movie_app/models/json.dart';
import 'package:movie_app/models/task.dart';
import 'package:movie_app/models/wishlist.dart';

void main() {
  group('Разбор значений с бэкенда', () {
    test('NUMERIC приходит строкой — читаем как число', () {
      expect(asDouble('1499.90'), 1499.9);
      expect(asInt('42'), 42);
    });

    test('запятая как разделитель дробной части', () {
      expect(asDouble('10,5'), 10.5);
    });

    test('булево из psycopg может прийти как t/f', () {
      expect(asBool('t'), isTrue);
      expect(asBool('f'), isFalse);
      expect(asBool(1), isTrue);
    });

    test('жанры хранятся в TEXT-колонке JSON-строкой', () {
      expect(asStringList('["Драма","Комедия"]'), ['Драма', 'Комедия']);
      expect(asStringList(['Драма']), ['Драма']);
      expect(asStringList('не json'), isEmpty);
      expect(asStringList(null), isEmpty);
    });

    test('дата приводится к формату эндпоинтов', () {
      expect(ymd(DateTime(2026, 8, 4)), '2026-08-04');
      expect(ymd(DateTime(2026, 12, 31)), '2026-12-31');
    });
  });

  group('TaskItem: выполненность считается по-разному', () {
    test('разовая задача смотрит на status', () {
      final todo = TaskItem.fromJson({'id': 1, 'title': 'Купить хлеб', 'status': 'todo'});
      final done = TaskItem.fromJson({'id': 2, 'title': 'Купить хлеб', 'status': 'done'});

      expect(todo.isDone, isFalse);
      expect(done.isDone, isTrue);
      expect(done.isRecurring, isFalse);
    });

    test('повторяющаяся смотрит на отметку конкретного дня, а не на status', () {
      final task = TaskItem.fromJson({
        'id': 3,
        'title': 'Зарядка',
        'status': 'todo',
        'recurrence': 'daily',
        'done_today': true,
      });

      expect(task.isRecurring, isTrue);
      expect(task.isDone, isTrue, reason: 'done_today важнее status у повторяющейся задачи');
    });

    test('повторяющаяся без отметки считается невыполненной', () {
      final task = TaskItem.fromJson({
        'id': 4,
        'title': 'Зарядка',
        'recurrence': 'weekly:0,2,4',
        'done_today': false,
      });
      expect(task.isDone, isFalse);
    });

    test('дата обрезается до дня — сервер отдаёт её с временем', () {
      final task = TaskItem.fromJson({'id': 5, 'title': 'x', 'date': '2026-08-04T00:00:00'});
      expect(task.date, '2026-08-04');
    });
  });

  group('Book', () {
    test('обложка переводится на https и увеличивается', () {
      final book = Book.fromJson({
        'book_id': 'abc',
        'title': 'Дюна',
        'cover': 'http://books.google.com/img?id=1&zoom=1',
      });
      expect(book.coverUrl, startsWith('https://'));
      expect(book.coverUrl, contains('zoom=2'));
    });

    test('год берётся из даты публикации', () {
      final book = Book.fromJson({'book_id': 'x', 'title': 'y', 'published_date': '1965-08-01'});
      expect(book.year, '1965');
    });

    test('без обложки ссылка пустая, а не битая', () {
      final book = Book.fromJson({'book_id': 'x', 'title': 'y'});
      expect(book.coverUrl, isNull);
    });
  });

  group('WishItem', () {
    test('остаток складчины не уходит в минус', () {
      final item = WishItem.fromJson({
        'id': 1,
        'title': 'Наушники',
        'price': 5000,
        'contributed_total': 7000,
      });
      expect(item.remaining, 0);
    });

    test('остаток считается от цены', () {
      final item = WishItem.fromJson({
        'id': 2,
        'title': 'Наушники',
        'price': 5000,
        'contributed_total': 1500,
      });
      expect(item.remaining, 3500);
    });

    test('без цены остатка нет', () {
      final item = WishItem.fromJson({'id': 3, 'title': 'Сюрприз'});
      expect(item.remaining, isNull);
      expect(item.priority, 2);
    });
  });

  group('Expense', () {
    test('подпись берёт магазин, потом комментарий', () {
      expect(
        Expense.fromJson({'id': 1, 'amount': 100, 'merchant': 'Пятёрочка', 'note': 'хлеб'}).label,
        'Пятёрочка',
      );
      expect(
        Expense.fromJson({'id': 2, 'amount': 100, 'note': 'хлеб'}).label,
        'хлеб',
      );
      expect(
        Expense.fromJson({'id': 3, 'amount': 100}).label,
        'Без описания',
      );
    });
  });

  group('BudgetCategory', () {
    test('план по умолчанию нулевой, а не null', () {
      final category = BudgetCategory.fromJson({'id': 1, 'name': 'Еда'});
      expect(category.planMonthly, 0);
      expect(category.emoji, '💰');
    });
  });
}
