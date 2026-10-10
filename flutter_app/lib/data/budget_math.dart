import '../models/budget.dart';
import '../models/trip.dart';

/// Расчёты бюджета и поездок — чистые функции без сети и кэша.
///
/// Репозитории только хранят данные и зовут эти функции, поэтому самую
/// запутанную часть — что и в каком месяце считать — можно проверить
/// тестами напрямую (test/budget_trips_test.dart).

/// Категория «Путешествия» дублирует план поездок: на одни и те же деньги
/// получалось бы два плана. Главный — план самих поездок.
bool isTravelBudgetCategory(BudgetCategory c) {
  final name = c.name.toLowerCase();
  return name.contains('путешеств') || name.contains('поездк');
}

/// План повседневных трат — всё, кроме путешествий.
int regularPlanOf(List<BudgetCategory> categories) => categories
    .where((c) => !isTravelBudgetCategory(c))
    .fold(0, (sum, c) => sum + c.planMonthly);

/// Сколько потрачено по каждой категории. Траты поездок сюда не входят:
/// у них свой блок и свой план.
Map<int?, int> spentByCategoryOf(List<Expense> expenses) {
  final map = <int?, int>{};
  for (final e in expenses) {
    map[e.categoryId] = (map[e.categoryId] ?? 0) + e.amount;
  }
  return map;
}

int _sortByStart(Trip a, Trip b) => (a.startDate ?? '').compareTo(b.startDate ?? '');

/// Поездки месяца с разбивкой по городам и статьям.
///
/// [events] — поездки, пересекающиеся с месяцем, вместе с городами групп;
/// [spending] — траты поездок, чья дата попала в [month].
///
/// Траты попадают в месяц по своей дате, план — целиком в месяц начала
/// поездки. Поэтому поездка на стыке месяцев в следующем месяце видна
/// с тратами, но без плана.
List<TripBudgetLine> buildTripLines({
  required List<Trip> events,
  required List<TripSpending> spending,
  required DateTime month,
}) {
  final ids = events.map((t) => t.id).toSet();
  final roots = events
      .where((t) => t.parentId == null || !ids.contains(t.parentId))
      .toList()
    ..sort(_sortByStart);

  final lines = <TripBudgetLine>[];
  for (final root in roots) {
    final cities = root.isGroup
        ? (events.where((t) => t.parentId == root.id).toList()..sort(_sortByStart))
        : const <Trip>[];
    final treeIds = {root.id, ...cities.map((c) => c.id)};
    final own = spending.where((t) => treeIds.contains(t.tripId)).toList();

    final kidsPlan = cities.fold<int>(0, (sum, c) => sum + c.plannedTotal);
    final fullPlan = root.isGroup && kidsPlan > 0 ? kidsPlan : root.plannedTotal;

    final start = root.start;
    final startsHere =
        start == null || (start.year == month.year && start.month == month.month);

    final byCategory = <String, int>{};
    for (final t in own) {
      final key = t.expense.category.trim().isEmpty ? 'Прочее' : t.expense.category.trim();
      byCategory[key] = (byCategory[key] ?? 0) + t.expense.amount;
    }

    final line = TripBudgetLine(
      trip: root,
      plan: startsHere ? fullPlan : 0,
      fullPlan: fullPlan,
      planCarried: !startsHere,
      spent: own.fold(0, (sum, t) => sum + t.expense.amount),
      cities: [
        for (final c in cities)
          TripCityLine(
            city: c,
            plan: c.plannedTotal,
            spent: own
                .where((t) => t.tripId == c.id)
                .fold(0, (sum, t) => sum + t.expense.amount),
          ),
      ],
      byCategory: Map.fromEntries(
        byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
      ),
    );
    // Поездка задела месяц краем, но ни плана, ни трат в нём нет — шум.
    if (line.plan == 0 && line.spent == 0) continue;
    lines.add(line);
  }
  return lines;
}

/// Все траты месяца одной лентой — обычные и из поездок, по дням,
/// свежие сверху.
Map<String, List<BudgetEntry>> groupBudgetEntries(
  List<Expense> expenses,
  List<TripSpending> tripSpending,
) {
  final all = [
    for (final e in expenses) BudgetEntry.own(e),
    for (final t in tripSpending) BudgetEntry.trip(t),
  ]..sort((a, b) => b.date.compareTo(a.date));
  final map = <String, List<BudgetEntry>>{};
  for (final e in all) {
    map.putIfAbsent(e.date, () => []).add(e);
  }
  return map;
}

// ─── Многогородние поездки ────────────────────────────────────────────

/// План группы — сумма планов городов, как на сайте. План самой группы
/// фиксируется при объединении и потом устаревает, поэтому он лишь запасной.
int groupPlanOf(Trip group, List<Trip> cities) {
  final kids = cities.fold<int>(0, (sum, c) => sum + c.plannedTotal);
  return kids > 0 ? kids : group.plannedTotal;
}

/// Потрачено в группе: свои траты группы плюс траты всех городов.
int groupActualOf(Trip group, List<Trip> cities) =>
    cities.fold<int>(group.actualTotal, (sum, c) => sum + c.actualTotal);

/// Даты группы — от первого города до последнего, план — сумма городов.
/// Так же пересчитывает сервер после правки города.
({String? start, String? end, int plan}) groupRollup(List<Trip> cities) {
  final starts = cities.map((c) => c.startDate).whereType<String>().toList()..sort();
  final ends = cities.map((c) => c.endDate).whereType<String>().toList()..sort();
  return (
    start: starts.isEmpty ? null : starts.first,
    end: ends.isEmpty ? null : ends.last,
    plan: cities.fold<int>(0, (sum, c) => sum + c.plannedTotal),
  );
}

/// Поездка в бюджете месяца.
class TripBudgetLine {
  final Trip trip;

  /// План, учтённый в этом месяце: весь план поездки или ноль, если
  /// поездка началась в другом месяце.
  final int plan;

  /// План поездки целиком — для подписи «план учтён в …».
  final int fullPlan;

  /// План уже учтён в месяце начала поездки.
  final bool planCarried;

  /// Потрачено в этом месяце.
  final int spent;

  final List<TripCityLine> cities;

  /// На что ушли деньги: статья → сумма, по убыванию.
  final Map<String, int> byCategory;

  const TripBudgetLine({
    required this.trip,
    required this.plan,
    required this.fullPlan,
    required this.planCarried,
    required this.spent,
    required this.cities,
    required this.byCategory,
  });

  bool get overspent => plan > 0 && spent > plan;
}

/// Город многогородней поездки в бюджете месяца.
class TripCityLine {
  final Trip city;
  final int plan;
  final int spent;

  const TripCityLine({required this.city, required this.plan, required this.spent});

  bool get overspent => plan > 0 && spent > plan;
}

/// Строка в ленте трат бюджета: обычная трата или трата поездки.
class BudgetEntry {
  final Expense? own;
  final TripSpending? trip;

  const BudgetEntry.own(Expense e) : own = e, trip = null;
  const BudgetEntry.trip(TripSpending t) : own = null, trip = t;

  String get date => own?.date ?? trip!.expense.date;
  int get amount => own?.amount ?? trip!.expense.amount;
}
