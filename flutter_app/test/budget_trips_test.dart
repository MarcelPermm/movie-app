import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/data/budget_math.dart';
import 'package:movie_app/data/profile_repository.dart';
import 'package:movie_app/models/budget.dart';
import 'package:movie_app/models/movie.dart';
import 'package:movie_app/models/trip.dart';
import 'package:movie_app/models/wrapped.dart';

// Небольшие фабрики, чтобы тесты читались как сценарии.

Trip trip(
  int id,
  String name, {
  String? from,
  String? to,
  int plan = 0,
  int actual = 0,
  String type = 'trip',
  int? parent,
}) =>
    Trip(
      id: id,
      name: name,
      startDate: from,
      endDate: to,
      plannedTotal: plan,
      actualTotal: actual,
      eventType: type,
      parentId: parent,
    );

TripSpending spend(int tripId, String date, int amount, {String category = ''}) => TripSpending(
      tripId: tripId,
      tripName: 'поездка $tripId',
      tripEmoji: '✈️',
      expense: TripExpense(
        id: tripId * 1000 + amount,
        tripId: tripId,
        date: date,
        amount: amount,
        category: category,
      ),
    );

void main() {
  // Сентябрьская поездка «Вкусная еда» из четырёх городов — как в жизни.
  final group = trip(1, 'Вкусная еда', from: '2026-09-17', to: '2026-10-01', type: 'group', plan: 1);
  final piter = trip(2, 'Питер', from: '2026-09-17', to: '2026-09-19', plan: 20000, parent: 1);
  final tbilisi = trip(3, 'Тбилиси', from: '2026-09-26', to: '2026-09-28', plan: 20000, parent: 1);
  final batumi = trip(4, 'Батуми', from: '2026-09-28', to: '2026-10-01', plan: 20000, parent: 1);
  final events = [group, piter, tbilisi, batumi];

  group('Категория «Путешествия»', () {
    test('узнаётся по названию в любом регистре', () {
      expect(isTravelBudgetCategory(const BudgetCategory(id: 1, name: 'Путешествия')), isTrue);
      expect(isTravelBudgetCategory(const BudgetCategory(id: 2, name: 'поездки')), isTrue);
      expect(isTravelBudgetCategory(const BudgetCategory(id: 3, name: 'Продукты')), isFalse);
    });

    test('её план не входит в план повседневных трат', () {
      const categories = [
        BudgetCategory(id: 1, name: 'Путешествия', planMonthly: 40000),
        BudgetCategory(id: 2, name: 'Продукты', planMonthly: 15000),
        BudgetCategory(id: 3, name: 'Кафе', planMonthly: 8000),
      ];
      expect(regularPlanOf(categories), 23000);
    });
  });

  group('Траты по категориям', () {
    test('считаются только обычные траты, без категории — под null', () {
      const expenses = [
        Expense(id: 1, date: '2026-09-01', amount: 500, categoryId: 2),
        Expense(id: 2, date: '2026-09-02', amount: 700, categoryId: 2),
        Expense(id: 3, date: '2026-09-03', amount: 300),
      ];
      final map = spentByCategoryOf(expenses);
      expect(map[2], 1200);
      expect(map[null], 300);
    });
  });

  group('Поездки в бюджете месяца', () {
    test('группа — одна строка с городами по датам и планом из городов', () {
      final lines = buildTripLines(
        events: [batumi, group, tbilisi, piter],
        spending: [spend(2, '2026-09-18', 31900), spend(3, '2026-09-27', 7300)],
        month: DateTime(2026, 9),
      );
      expect(lines, hasLength(1));
      final line = lines.single;
      expect(line.trip.name, 'Вкусная еда');
      expect(line.cities.map((c) => c.city.name), ['Питер', 'Тбилиси', 'Батуми']);
      // План группы (1 ₽) устарел — берётся сумма городов.
      expect(line.plan, 60000);
      expect(line.spent, 39200);
      expect(line.cities.first.spent, 31900);
      expect(line.cities.first.overspent, isTrue);
    });

    test('поездка на стыке месяцев: в следующем месяце траты есть, плана нет', () {
      final october = buildTripLines(
        events: events,
        spending: [spend(4, '2026-10-01', 1200)],
        month: DateTime(2026, 10),
      );
      expect(october.single.plan, 0);
      expect(october.single.planCarried, isTrue);
      expect(october.single.fullPlan, 60000);
      expect(october.single.spent, 1200);
    });

    test('поездка, задевшая месяц без плана и трат, не показывается', () {
      final lines = buildTripLines(events: events, spending: const [], month: DateTime(2026, 10));
      expect(lines, isEmpty);
    });

    test('статьи поездки суммируются, пустая статья — «Прочее»', () {
      final line = buildTripLines(
        events: [trip(9, 'Казань', from: '2026-09-05', to: '2026-09-07', plan: 30000)],
        spending: [
          spend(9, '2026-09-05', 9000, category: 'Жильё'),
          spend(9, '2026-09-06', 1500, category: 'Еда'),
          spend(9, '2026-09-06', 2000, category: 'Еда'),
          spend(9, '2026-09-07', 400),
        ],
        month: DateTime(2026, 9),
      ).single;
      expect(line.byCategory.keys, ['Жильё', 'Еда', 'Прочее']);
      expect(line.byCategory['Еда'], 3500);
      expect(line.cities, isEmpty);
    });

    test('чужие траты не попадают в поездку', () {
      final line = buildTripLines(
        events: [trip(9, 'Казань', from: '2026-09-05', plan: 10000)],
        spending: [spend(9, '2026-09-05', 100), spend(77, '2026-09-05', 5000)],
        month: DateTime(2026, 9),
      ).single;
      expect(line.spent, 100);
    });
  });

  group('Лента трат бюджета', () {
    test('обычные траты и траты поездок вперемешку по дням, свежие сверху', () {
      final grouped = groupBudgetEntries(
        const [
          Expense(id: 1, date: '2026-09-18', amount: 500),
          Expense(id: 2, date: '2026-09-20', amount: 700),
        ],
        [spend(2, '2026-09-18', 3000)],
      );
      expect(grouped.keys, ['2026-09-20', '2026-09-18']);
      final day = grouped['2026-09-18']!;
      expect(day.map((e) => e.amount), containsAll([500, 3000]));
      expect(day.where((e) => e.trip != null), hasLength(1));
      expect(day.where((e) => e.own != null), hasLength(1));
    });
  });

  group('Многогородняя поездка', () {
    test('план группы — сумма городов, иначе свой', () {
      expect(groupPlanOf(group, [piter, tbilisi, batumi]), 60000);
      expect(groupPlanOf(trip(5, 'Пусто', type: 'group', plan: 9000), const []), 9000);
    });

    test('потрачено в группе — свои траты плюс траты городов', () {
      final g = trip(1, 'Группа', type: 'group', actual: 100);
      final kids = [trip(2, 'А', actual: 1000, parent: 1), trip(3, 'Б', actual: 2000, parent: 1)];
      expect(groupActualOf(g, kids), 3100);
    });

    test('после правки города даты группы — от первого до последнего', () {
      final rollup = groupRollup([
        trip(2, 'Питер', from: '2026-09-17', to: '2026-09-19', plan: 20000),
        trip(3, 'Алания', from: '2026-09-25', to: '2026-09-27', plan: 30000),
        trip(4, 'Без дат', plan: 5000),
      ]);
      expect(rollup.start, '2026-09-17');
      expect(rollup.end, '2026-09-27');
      expect(rollup.plan, 55000);
    });
  });

  group('Трата поездки', () {
    test('план без факта — ещё не оплачено', () {
      const planned = TripExpense(id: 1, tripId: 1, date: '2026-09-01', plannedAmount: 5000);
      expect(planned.isPaid, isFalse);
      expect(planned.copyWith(amount: 4800).isPaid, isTrue);
    });

    test('подпись: статья, иначе комментарий', () {
      const a = TripExpense(id: 1, tripId: 1, date: '2026-09-01', category: 'Жильё', note: 'отель');
      const b = TripExpense(id: 2, tripId: 1, date: '2026-09-01', note: 'такси до аэропорта');
      expect(a.label, 'Жильё');
      expect(b.label, 'такси до аэропорта');
    });

    test('дата меняется через copyWith', () {
      const e = TripExpense(id: 1, tripId: 1, date: '2026-09-01', amount: 100);
      expect(e.copyWith(date: '2026-09-02').date, '2026-09-02');
      expect(e.copyWith(amount: 200).date, '2026-09-01');
    });
  });

  group('Что посмотреть вечером', () {
    TonightPick pick(int? minutes) => TonightPick(
          movie: Movie.fromJson(const {'id': 1, 'title': 'Фильм'}),
          runtime: minutes,
        );

    test('длительность пишется по-человечески', () {
      expect(pick(42).runtimeLabel, '42 мин');
      expect(pick(88).runtimeLabel, '1 ч 28 мин');
      expect(pick(120).runtimeLabel, '2 ч');
      expect(pick(null).runtimeLabel, isNull);
      expect(pick(0).runtimeLabel, isNull);
    });
  });

  group('Итоги года', () {
    test('разбираются и складываются в текст, чтобы поделиться', () {
      final w = Wrapped.fromJson({
        'year': 2026,
        'title': 'Кочевник года',
        'has_data': true,
        'cinema': {
          'movies': 40,
          'shows': 5,
          'top_genres': [
            {'name': 'Драма', 'count': 12},
          ],
          'top_rated': [
            {'title': 'Дюна', 'rating': 10},
          ],
          'monthly': [1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 0, 0],
        },
        'reading': {'count': 7, 'pages': 2300},
        'travel': {
          'count': 2,
          'days': 6,
          'places': [
            {'name': 'Питер'},
            {'name': 'Тбилиси'},
          ],
        },
        'money': {
          'total': 100000,
          'by_category': [
            {'name': 'Поездки', 'emoji': '✈️', 'amount': 60000},
          ],
          'top_merchant': {'name': 'Пятёрочка', 'count': 54, 'amount': 30000},
          'biggest_month': {'month': 9, 'name': 'сентябрь', 'amount': 70000},
        },
      });

      expect(w.cinema.total, 45);
      expect(w.money.topMerchant, 'Пятёрочка');
      expect(w.money.biggestMonth!.value, 70000);
      expect(w.money.monthly, hasLength(12));

      final text = w.toShareText();
      expect(text, contains('Кочевник года'));
      expect(text, contains('40 фильмов и 5 сериалов'));
      expect(text, contains('Дюна (10/10)'));
      expect(text, contains('Питер → Тбилиси'));
      expect(text, contains('«Поездки»'));
    });

    test('пустой ответ не роняет разбор', () {
      final w = Wrapped.fromJson(const {'year': 2025});
      expect(w.hasData, isFalse);
      expect(w.cinema.total, 0);
      expect(w.money.topMerchant, isNull);
      expect(w.money.biggestMonth, isNull);
      expect(w.travel.places, isEmpty);
    });
  });
}
