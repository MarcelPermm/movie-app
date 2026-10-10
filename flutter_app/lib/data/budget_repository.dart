import '../core/api_client.dart';
import '../models/budget.dart';
import '../models/json.dart';
import '../models/trip.dart';
import 'local_first_repository.dart';

/// Бюджет: категории и траты выбранного месяца.
class BudgetRepository extends LocalFirstRepository {
  BudgetRepository({required super.api, required super.session});

  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime get month => _month;

  List<BudgetCategory> _categories = [];
  List<Expense> _expenses = [];

  List<BudgetCategory> get categories => List.unmodifiable(_categories);
  List<Expense> get expenses => List.unmodifiable(_expenses);

  /// Траты поездок, попавшие в этот месяц.
  List<TripSpending> _tripSpending = [];
  List<TripSpending> get tripSpending => List.unmodifiable(_tripSpending);

  int get tripTotal => _tripSpending.fold(0, (sum, t) => sum + t.expense.amount);

  int get ownTotal => _expenses.fold(0, (sum, e) => sum + e.amount);

  /// Итог месяца вместе с поездками — деньги-то одни.
  int get total => ownTotal + tripTotal;

  int get plannedTotal => _categories.fold(0, (sum, c) => sum + c.planMonthly);

  /// Сопоставление названия категории поездки с категорией месяца.
  ///
  /// В поездке категория — просто строка («Еда»), в месяце — запись со
  /// своим id. Связываем по названию: это единственное, что у них общего,
  /// и ровно так их и заводят руками.
  int? _matchCategory(String name) {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final c in _categories) {
      if (c.name.trim().toLowerCase() == key) return c.id;
    }
    return null;
  }

  /// Сколько потрачено по каждой категории — для полосок выполнения плана.
  /// Учитываются и обычные траты, и то, что ушло в поездках.
  Map<int?, int> get spentByCategory {
    final map = <int?, int>{};
    for (final e in _expenses) {
      map[e.categoryId] = (map[e.categoryId] ?? 0) + e.amount;
    }
    for (final t in _tripSpending) {
      final id = _matchCategory(t.expense.category);
      map[id] = (map[id] ?? 0) + t.expense.amount;
    }
    return map;
  }

  /// Траты поездок, отнесённые к конкретной категории месяца.
  List<TripSpending> tripSpendingOf(int? categoryId) => _tripSpending
      .where((t) => _matchCategory(t.expense.category) == categoryId)
      .toList();

  /// Категории, которые есть смысл показывать: с планом или с тратами.
  /// Пустые строки с нулями только зашумляют экран.
  List<BudgetCategory> get visibleCategories {
    final spent = spentByCategory;
    return _categories
        .where((c) => c.planMonthly > 0 || (spent[c.id] ?? 0) > 0)
        .toList()
      ..sort((a, b) => b.planMonthly.compareTo(a.planMonthly));
  }

  /// Категории с планом — основной блок.
  List<BudgetCategory> get plannedCategories =>
      visibleCategories.where((c) => c.planMonthly > 0).toList();

  /// Есть траты, но плана нет. Показываем отдельно, чтобы деньги
  /// не пропадали из виду, но и не мешались среди плановых.
  List<BudgetCategory> get unplannedCategories =>
      visibleCategories.where((c) => c.planMonthly == 0).toList();

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

  String get _catKey => cacheKey('budget::categories');
  String get _expKey => cacheKey('budget::expenses::${_month.year}-${_month.month}');
  String get _merchKey => cacheKey('budget::merchants');
  String get _tripKey => cacheKey('budget::trips::${_month.year}-${_month.month}');

  Future<void> load({bool forceRefresh = false}) async {
    _categories = readCache(_catKey).map(BudgetCategory.fromJson).toList();
    _expenses = readCache(_expKey).map(Expense.fromJson).toList();
    _merchants = readCache(_merchKey).map((m) => asString(m['name'])).toList();
    _tripSpending = readCache(_tripKey).map(TripSpending.fromJson).toList();
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

  /// Траты поездок, чьи даты попали в открытый месяц.
  ///
  /// Сервер отдаёт поездки месяца одним запросом, а траты — по одной
  /// поездке за раз. Поездок в месяце обычно ноль или одна, поэтому
  /// отдельного эндпоинта под это заводить не стоило.
  Future<void> _refreshTripSpending() async {
    try {
      final events = await api.get('/budget/events', query: {
        'year': '${_month.year}',
        'month': '${_month.month}',
      });

      final trips = ((events as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Trip.fromJson(Map<String, dynamic>.from(e)))
          .where((t) => !t.isGroup)
          .toList();

      final collected = <TripSpending>[];
      for (final trip in trips) {
        final raw = await api.get('/trips/${trip.id}/expenses');
        for (final item in ((raw as List?) ?? const []).whereType<Map>()) {
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
  }) async {
    _expenses = _expenses
        .map((e) => e.id == expense.id
            ? e.copyWith(
                amount: amount,
                note: note,
                categoryId: categoryId,
                merchant: merchant,
              )
            : e)
        .toList();
    notifyListeners();
    await _saveExpenses();

    if (LocalFirstRepository.isTemp(expense.id)) return;
    await push(() => api.patch('/budget/expenses/${expense.id}', body: {
          'amount': ?amount,
          'note': ?note,
          'category_id': ?categoryId,
          'merchant': ?merchant,
        }));
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
