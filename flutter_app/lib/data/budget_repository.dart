import '../core/api_client.dart';
import '../models/budget.dart';
import '../models/json.dart';
import '../models/trip.dart';
import 'budget_math.dart';
import 'local_first_repository.dart';

export 'budget_math.dart';

/// Бюджет: категории и траты выбранного месяца.
class BudgetRepository extends LocalFirstRepository {
  BudgetRepository({required super.api, required super.session});

  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime get month => _month;

  List<BudgetCategory> _categories = [];
  List<Expense> _expenses = [];

  List<BudgetCategory> get categories => List.unmodifiable(_categories);
  List<Expense> get expenses => List.unmodifiable(_expenses);

  /// Траты поездок, попавшие в этот месяц (по дате самой траты).
  List<TripSpending> _tripSpending = [];
  List<TripSpending> get tripSpending => List.unmodifiable(_tripSpending);

  /// Поездки, пересекающиеся с месяцем, — вместе с городами групп.
  List<Trip> _events = [];

  int get tripTotal => _tripSpending.fold(0, (sum, t) => sum + t.expense.amount);

  int get ownTotal => _expenses.fold(0, (sum, e) => sum + e.amount);

  /// Итог месяца вместе с поездками — деньги-то одни.
  int get total => ownTotal + tripTotal;

  /// Категория «Путешествия» дублирует план поездок: на одни и те же деньги
  /// получалось два плана. Главный — план самих поездок, а категорию
  /// прячем и в план месяца не считаем.
  static bool isTravelCategory(BudgetCategory c) => isTravelBudgetCategory(c);

  /// План повседневных трат — всё, кроме путешествий.
  int get regularPlan => regularPlanOf(_categories);

  /// План поездок этого месяца: поездка целиком относится к месяцу,
  /// в котором началась.
  int get tripPlan => tripLines.fold(0, (sum, t) => sum + t.plan);

  int get plannedTotal => regularPlan + tripPlan;

  /// Поездки месяца с разбивкой по городам и статьям.
  ///
  /// Траты попадают в месяц по своей дате, план — целиком в месяц начала
  /// поездки. Поэтому поездка на стыке месяцев в следующем месяце видна
  /// с тратами, но без плана.
  List<TripBudgetLine> get tripLines =>
      buildTripLines(events: _events, spending: _tripSpending, month: _month);

  /// Сколько потрачено по каждой категории — для полосок выполнения плана.
  /// Траты поездок сюда не входят: у них свой блок и свой план.
  Map<int?, int> get spentByCategory => spentByCategoryOf(_expenses);

  /// Категории, которые есть смысл показывать: с планом или с тратами.
  /// Пустые строки с нулями только зашумляют экран. «Путешествия» видны,
  /// только если в них записали обычную трату, — и уже без плана.
  List<BudgetCategory> get visibleCategories {
    final spent = spentByCategory;
    return _categories
        .where((c) => isTravelCategory(c)
            ? (spent[c.id] ?? 0) > 0
            : c.planMonthly > 0 || (spent[c.id] ?? 0) > 0)
        .toList()
      ..sort((a, b) => b.planMonthly.compareTo(a.planMonthly));
  }

  /// Категории с планом — основной блок.
  List<BudgetCategory> get plannedCategories => visibleCategories
      .where((c) => c.planMonthly > 0 && !isTravelCategory(c))
      .toList();

  /// Есть траты, но плана нет. Показываем отдельно, чтобы деньги
  /// не пропадали из виду, но и не мешались среди плановых.
  List<BudgetCategory> get unplannedCategories => visibleCategories
      .where((c) => c.planMonthly == 0 || isTravelCategory(c))
      .toList();

  /// Потрачено мимо всех категорий.
  int get uncategorized => spentByCategory[null] ?? 0;

  BudgetCategory? categoryById(int? id) {
    if (id == null) return null;
    for (final c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Места, где ты уже что-то покупал, — для подсказок при вводе.
  /// Их собирает сервер из истории трат.
  List<String> _merchants = [];
  List<String> get merchants => List.unmodifiable(_merchants);

  /// Подсказки, подходящие под начало ввода.
  List<String> merchantHints(String input) {
    final q = input.trim().toLowerCase();
    if (q.isEmpty) return _merchants.take(8).toList();
    return _merchants
        .where((m) => m.toLowerCase().contains(q))
        .take(8)
        .toList();
  }

  /// Траты выбранного месяца, свежие сверху.
  List<Expense> get expensesByDate {
    final list = [..._expenses];
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  /// Сгруппированные по дню — так список читается, а не превращается
  /// в сплошную ленту одинаковых строк.
  Map<String, List<Expense>> get expensesGrouped {
    final map = <String, List<Expense>>{};
    for (final e in expensesByDate) {
      map.putIfAbsent(e.date, () => []).add(e);
    }
    return map;
  }

  /// Все траты месяца одной лентой — обычные и из поездок, по дням,
  /// свежие сверху. Иначе трата в поездке видна только в итоге, а найти
  /// и поправить её из бюджета нельзя.
  Map<String, List<BudgetEntry>> get entriesGrouped =>
      groupBudgetEntries(_expenses, _tripSpending);

  String get _catKey => cacheKey('budget::categories');
  String get _expKey => cacheKey('budget::expenses::${_month.year}-${_month.month}');
  String get _merchKey => cacheKey('budget::merchants');
  String get _tripKey => cacheKey('budget::trips::${_month.year}-${_month.month}');
  String get _eventsKey => cacheKey('budget::events::${_month.year}-${_month.month}');

  Future<void> load({bool forceRefresh = false}) async {
    _categories = readCache(_catKey).map(BudgetCategory.fromJson).toList();
    _expenses = readCache(_expKey).map(Expense.fromJson).toList();
    _merchants = readCache(_merchKey).map((m) => asString(m['name'])).toList();
    _tripSpending = readCache(_tripKey).map(TripSpending.fromJson).toList();
    _events = readCache(_eventsKey).map(Trip.fromJson).toList();
    notifyListeners();
    if (forceRefresh || isStale(_expKey)) await refresh();
  }

  Future<void> refresh() => runSync(() async {
        final results = await Future.wait([
          api.get('/budget/categories'),
          api.get('/budget/expenses', query: {
            'year': '${_month.year}',
            'month': '${_month.month}',
          }),
          api.get('/budget/merchants'),
        ]);
        await writeCache(_catKey, (results[0] as List?) ?? const [], fromServer: true);
        await writeCache(_expKey, (results[1] as List?) ?? const [], fromServer: true);

        // Мерчанты приходят простым списком строк, а кэш умеет только
        // список объектов — оборачиваем, чтобы не заводить второе хранилище.
        final rawMerchants = (results[2] as List?) ?? const [];
        await writeCache(
          _merchKey,
          rawMerchants.map((m) => {'name': '$m'}).toList(),
          fromServer: true,
        );

        _categories = readCache(_catKey).map(BudgetCategory.fromJson).toList();
        _expenses = readCache(_expKey).map(Expense.fromJson).toList();
        _merchants = readCache(_merchKey).map((m) => asString(m['name'])).toList();

        // Поездки тянем следом: их обычно ноль или одна, и задерживать
        // из-за них основные траты незачем.
        await _refreshTripSpending();
      });

  /// Поездки месяца и их траты, чьи даты попали в открытый месяц.
  ///
  /// Сервер отдаёт поездки месяца одним запросом (с городами групп), а
  /// траты — по одной поездке. Запросы трат идут параллельно.
  Future<void> _refreshTripSpending() async {
    try {
      final events = await api.get('/budget/events', query: {
        'year': '${_month.year}',
        'month': '${_month.month}',
      });
      final rawEvents = ((events as List?) ?? const []).whereType<Map>().toList();
      await writeCache(_eventsKey, rawEvents, fromServer: true);
      final trips = readCache(_eventsKey).map(Trip.fromJson).toList();

      // У группы своих трат обычно нет — они в городах, — но сайт позволяет
      // записать трату и на саму группу, поэтому спрашиваем всех.
      final results = await Future.wait(
        trips.map((t) => api.get('/trips/${t.id}/expenses')),
      );

      final collected = <TripSpending>[];
      for (var i = 0; i < trips.length; i++) {
        final trip = trips[i];
        for (final item in ((results[i] as List?) ?? const []).whereType<Map>()) {
          final expense = TripExpense.fromJson(Map<String, dynamic>.from(item));
          if (expense.amount <= 0) continue; // только план, денег ещё не было

          final date = parseDate(expense.date);
          if (date == null) continue;
          if (date.year != _month.year || date.month != _month.month) continue;

          collected.add(TripSpending(
            tripId: trip.id,
            tripName: trip.name,
            tripEmoji: trip.emoji,
            expense: expense,
          ));
        }
      }

      await writeCache(
        _tripKey,
        collected.map((t) => t.toJson()).toList(),
        fromServer: true,
      );
      _tripSpending = collected;
      _events = trips;
    } on ApiException {
      // Не смогли получить поездки — месяц всё равно показываем,
      // просто без их трат.
    }
  }

  Future<void> shiftMonth(int delta) async {
    _month = DateTime(_month.year, _month.month + delta);
    await load();
  }

  Future<void> _saveExpenses() =>
      writeCache(_expKey, _expenses.map((e) => e.toJson()).toList());

  Future<void> _saveCategories() =>
      writeCache(_catKey, _categories.map((c) => c.toJson()).toList());

  // ─── Траты ──────────────────────────────────────────────────────────

  Future<void> addExpense({
    required int amount,
    DateTime? date,
    int? categoryId,
    String? note,
    String? merchant,
  }) async {
    if (amount <= 0) return;
    final dateStr = ymd(date ?? DateTime.now());

    final temp = Expense(
      id: LocalFirstRepository.nextTempId(),
      date: dateStr,
      amount: amount,
      categoryId: categoryId,
      note: note,
      merchant: merchant,
    );
    _expenses = [temp, ..._expenses];
    notifyListeners();
    await _saveExpenses();

    final created = await push(() => api.post('/budget/expenses', body: {
          'date': dateStr,
          'amount': amount,
          'category_id': ?categoryId,
          'note': ?note,
          'merchant': ?merchant,
        }));
    if (created is Map) {
      final real = Expense.fromJson(Map<String, dynamic>.from(created));
      _expenses = _expenses.map((e) => e.id == temp.id ? real : e).toList();
      notifyListeners();
      await _saveExpenses();
    }
  }

  Future<void> updateExpense(
    Expense expense, {
    int? amount,
    String? note,
    int? categoryId,
    String? merchant,
    DateTime? date,
  }) async {
    final dateStr = date == null ? null : ymd(date);
    _expenses = _expenses
        .map((e) => e.id == expense.id
            ? e.copyWith(
                amount: amount,
                note: note,
                categoryId: categoryId,
                merchant: merchant,
                date: dateStr,
              )
            : e)
        // Трату перенесли в другой месяц — из этого она уходит.
        .where((e) => _inMonth(e.date))
        .toList();
    notifyListeners();
    await _saveExpenses();

    if (LocalFirstRepository.isTemp(expense.id)) return;
    await push(() => api.patch('/budget/expenses/${expense.id}', body: {
          'amount': ?amount,
          'note': ?note,
          'category_id': ?categoryId,
          'merchant': ?merchant,
          'date': ?dateStr,
        }));
  }

  bool _inMonth(String date) {
    final d = parseDate(date);
    return d != null && d.year == _month.year && d.month == _month.month;
  }

  // ─── Траты поездок прямо из бюджета ────────────────────────────────
  //
  // Трата поездки живёт в trip_expenses, а не в budget_expenses, — как на
  // сайте, когда в форме траты выбрана поездка. Здесь меняем её на сервере
  // и сразу у себя, чтобы блок поездок и список трат обновились мгновенно.

  /// Подпись поездки для трат: «Вкусная еда · Тбилиси» у города.
  String tripLabelOf(int tripId, {String fallback = ''}) {
    Trip? find(int? id) {
      for (final t in _events) {
        if (t.id == id) return t;
      }
      return null;
    }

    final trip = find(tripId);
    if (trip == null) return fallback;
    final parent = find(trip.parentId);
    return parent == null ? trip.name : '${parent.name} · ${trip.name}';
  }

  /// Поездка (или её группа) должна быть в списке месяца, иначе её трата
  /// не попадёт в блок поездок.
  void _ensureEvent(Trip trip, Trip? parent) {
    final ids = _events.map((t) => t.id).toSet();
    _events = [
      ..._events,
      if (parent != null && !ids.contains(parent.id)) parent,
      if (!ids.contains(trip.id)) trip,
    ];
  }

  Future<void> _saveTripState() async {
    await writeCache(_tripKey, _tripSpending.map((t) => t.toJson()).toList());
    await writeCache(_eventsKey, _events.map((t) => t.toJson()).toList());
  }

  Future<void> addTripExpense({
    required Trip trip,
    Trip? parent,
    required int amount,
    required DateTime date,
    String category = '',
    String note = '',
  }) async {
    if (amount <= 0) return;
    final dateStr = ymd(date);
    final temp = TripExpense(
      id: LocalFirstRepository.nextTempId(),
      tripId: trip.id,
      date: dateStr,
      amount: amount,
      category: category,
      note: note,
    );
    if (_inMonth(dateStr)) {
      _ensureEvent(trip, parent);
      _tripSpending = [
        ..._tripSpending,
        TripSpending(tripId: trip.id, tripName: trip.name, tripEmoji: trip.emoji, expense: temp),
      ];
      notifyListeners();
      await _saveTripState();
    }

    final created = await push(() => api.post('/trips/${trip.id}/expenses', body: {
          'date': dateStr,
          'amount': amount,
          'category': category,
          'note': note,
        }));
    if (created is Map) {
      final real = TripExpense.fromJson(Map<String, dynamic>.from(created));
      _tripSpending = _tripSpending
          .map((t) => t.expense.id == temp.id
              ? TripSpending(
                  tripId: t.tripId, tripName: t.tripName, tripEmoji: t.tripEmoji, expense: real)
              : t)
          .toList();
      notifyListeners();
      await _saveTripState();
    }
  }

  Future<void> updateTripExpense(
    TripSpending spending, {
    int? amount,
    String? category,
    String? note,
    DateTime? date,
  }) async {
    final dateStr = date == null ? null : ymd(date);
    final updated = spending.expense.copyWith(
      amount: amount,
      category: category,
      note: note,
      date: dateStr,
    );
    _tripSpending = _tripSpending
        .map((t) => t.expense.id == spending.expense.id
            ? TripSpending(
                tripId: t.tripId, tripName: t.tripName, tripEmoji: t.tripEmoji, expense: updated)
            : t)
        .where((t) => _inMonth(t.expense.date))
        .toList();
    notifyListeners();
    await _saveTripState();

    if (LocalFirstRepository.isTemp(spending.expense.id)) return;
    await push(() => api.patch('/trip-expenses/${spending.expense.id}', body: {
          'amount': ?amount,
          'category': ?category,
          'note': ?note,
          'date': ?dateStr,
        }));
  }

  Future<void> removeTripExpense(TripSpending spending) async {
    final backup = _tripSpending;
    _tripSpending =
        _tripSpending.where((t) => t.expense.id != spending.expense.id).toList();
    notifyListeners();
    await _saveTripState();

    if (LocalFirstRepository.isTemp(spending.expense.id)) return;
    await push(
      () => api.delete('/trip-expenses/${spending.expense.id}'),
      rollback: () => _tripSpending = backup,
    );
  }

  Future<void> removeExpense(Expense expense) async {
    final backup = _expenses;
    _expenses = _expenses.where((e) => e.id != expense.id).toList();
    notifyListeners();
    await _saveExpenses();

    if (LocalFirstRepository.isTemp(expense.id)) return;
    await push(
      () => api.delete('/budget/expenses/${expense.id}'),
      rollback: () => _expenses = backup,
    );
  }

  // ─── Категории ──────────────────────────────────────────────────────

  Future<void> addCategory(String name, {String emoji = '💰', int planMonthly = 0}) async {
    final name0 = name.trim();
    if (name0.isEmpty) return;

    final temp = BudgetCategory(
      id: LocalFirstRepository.nextTempId(),
      name: name0,
      emoji: emoji,
      planMonthly: planMonthly,
    );
    _categories = [..._categories, temp];
    notifyListeners();
    await _saveCategories();

    final created = await push(() => api.post('/budget/categories', body: {
          'name': name0,
          'emoji': emoji,
          'plan_monthly': planMonthly,
        }));
    if (created is Map) {
      final real = BudgetCategory.fromJson(Map<String, dynamic>.from(created));
      _categories = _categories.map((c) => c.id == temp.id ? real : c).toList();
      notifyListeners();
      await _saveCategories();
    }
  }

  Future<void> updateCategory(
    BudgetCategory category, {
    String? name,
    String? emoji,
    int? planMonthly,
  }) async {
    _categories = _categories
        .map((c) => c.id == category.id
            ? c.copyWith(name: name, emoji: emoji, planMonthly: planMonthly)
            : c)
        .toList();
    notifyListeners();
    await _saveCategories();

    if (LocalFirstRepository.isTemp(category.id)) return;
    await push(() => api.patch('/budget/categories/${category.id}', body: {
          'name': ?name,
          'emoji': ?emoji,
          'plan_monthly': ?planMonthly,
        }));
  }

  /// Стереть все траты открытого месяца. Категории и планы остаются.
  Future<void> clearMonth() async {
    final backup = _expenses;
    _expenses = [];
    notifyListeners();
    await _saveExpenses();

    await push(
      () => api.delete('/budget/expenses/month', query: {
        'year': '${_month.year}',
        'month': '${_month.month}',
      }),
      rollback: () => _expenses = backup,
    );
  }

  Future<void> removeCategory(BudgetCategory category) async {
    final backup = _categories;
    _categories = _categories.where((c) => c.id != category.id).toList();
    notifyListeners();
    await _saveCategories();

    if (LocalFirstRepository.isTemp(category.id)) return;
    await push(
      () => api.delete('/budget/categories/${category.id}'),
      rollback: () => _categories = backup,
    );
  }
}
