import '../models/budget.dart';
import '../models/json.dart';
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

  int get total => _expenses.fold(0, (sum, e) => sum + e.amount);

  int get plannedTotal => _categories.fold(0, (sum, c) => sum + c.planMonthly);

  /// Сколько потрачено по каждой категории — для полосок выполнения плана.
  Map<int?, int> get spentByCategory {
    final map = <int?, int>{};
    for (final e in _expenses) {
      map[e.categoryId] = (map[e.categoryId] ?? 0) + e.amount;
    }
    return map;
  }

  BudgetCategory? categoryById(int? id) {
    if (id == null) return null;
    for (final c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  String get _catKey => cacheKey('budget::categories');
  String get _expKey => cacheKey('budget::expenses::${_month.year}-${_month.month}');

  Future<void> load({bool forceRefresh = false}) async {
    _categories = readCache(_catKey).map(BudgetCategory.fromJson).toList();
    _expenses = readCache(_expKey).map(Expense.fromJson).toList();
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
        ]);
        await writeCache(_catKey, (results[0] as List?) ?? const [], fromServer: true);
        await writeCache(_expKey, (results[1] as List?) ?? const [], fromServer: true);
        _categories = readCache(_catKey).map(BudgetCategory.fromJson).toList();
        _expenses = readCache(_expKey).map(Expense.fromJson).toList();
      });

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

  Future<void> updateExpense(Expense expense, {int? amount, String? note, int? categoryId}) async {
    _expenses = _expenses
        .map((e) => e.id == expense.id
            ? e.copyWith(amount: amount, note: note, categoryId: categoryId)
            : e)
        .toList();
    notifyListeners();
    await _saveExpenses();

    if (LocalFirstRepository.isTemp(expense.id)) return;
    await push(() => api.patch('/budget/expenses/${expense.id}', body: {
          'amount': ?amount,
          'note': ?note,
          'category_id': ?categoryId,
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
