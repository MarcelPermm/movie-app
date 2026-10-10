import '../models/json.dart';
import '../models/trip.dart';
import 'local_first_repository.dart';

/// Поездки и события с собственным бюджетом.
///
/// Список поездок кэшируется целиком, расходы — отдельно по каждой поездке.
/// Так открытие поездки не тянет за собой чужие траты, а список остаётся
/// лёгким: в нём достаточно итоговых сумм, которые считает сервер.
class TripRepository extends LocalFirstRepository {
  TripRepository({required super.api, required super.session});

  List<Trip> _trips = [];
  List<Trip> get trips => List.unmodifiable(_trips);

  /// Поездки верхнего уровня: то, что лежит внутри групп, показывается
  /// уже внутри самой группы.
  List<Trip> get rootTrips => _trips.where((t) => t.parentId == null).toList();

  List<Trip> childrenOf(int groupId) =>
      _trips.where((t) => t.parentId == groupId).toList();

  /// Ближайшие предстоящие — их выносим наверх списка.
  List<Trip> get upcoming {
    final list = rootTrips.where((t) => t.daysUntil != null).toList()
      ..sort((a, b) => (a.daysUntil ?? 0).compareTo(b.daysUntil ?? 0));
    return list;
  }

  final Map<int, List<TripExpense>> _expenses = {};

  List<TripExpense> expensesOf(int tripId) =>
      List.unmodifiable(_expenses[tripId] ?? const []);

  Trip? tripById(int id) {
    for (final t in _trips) {
      if (t.id == id) return t;
    }
    return null;
  }

  String get _tripsKey => cacheKey('trips');
  String _expensesKey(int tripId) => cacheKey('trip::$tripId::expenses');

  Future<void> load({bool forceRefresh = false}) async {
    _trips = readCache(_tripsKey).map(Trip.fromJson).toList();
    notifyListeners();
    if (forceRefresh || isStale(_tripsKey)) await refresh();
  }

  Future<void> refresh() => runSync(() async {
        final data = await api.get('/trips');
        await writeCache(_tripsKey, (data as List?) ?? const [], fromServer: true);
        _trips = readCache(_tripsKey).map(Trip.fromJson).toList();
      });

  Future<void> _saveTrips() =>
      writeCache(_tripsKey, _trips.map((t) => t.toJson()).toList());

  // ─── Поездки ────────────────────────────────────────────────────────

  Future<void> addTrip({
    required String name,
    String emoji = '✈️',
    String? startDate,
    String? endDate,
    int plannedTotal = 0,
    String eventType = 'trip',
    String subtitle = '',
  }) async {
    final title = name.trim();
    if (title.isEmpty) return;

    final temp = Trip(
      id: LocalFirstRepository.nextTempId(),
      name: title,
      emoji: emoji,
      startDate: startDate,
      endDate: endDate,
      plannedTotal: plannedTotal,
      eventType: eventType,
      subtitle: subtitle,
    );
    _trips = [temp, ..._trips];
    notifyListeners();
    await _saveTrips();

    final created = await push(() => api.post('/trips', body: {
          'name': title,
          'emoji': emoji,
          'start_date': ?startDate,
          'end_date': ?endDate,
          'planned_total': plannedTotal,
          'event_type': eventType,
          'subtitle': subtitle,
        }));
    if (created is Map) {
      final real = Trip.fromJson(Map<String, dynamic>.from(created));
      _trips = _trips.map((t) => t.id == temp.id ? real : t).toList();
      notifyListeners();
      await _saveTrips();
    }
  }

  Future<void> updateTrip(
    Trip trip, {
    String? name,
    String? emoji,
    String? subtitle,
    int? plannedTotal,
  }) async {
    _trips = _trips
        .map((t) => t.id == trip.id
            ? t.copyWith(
                name: name,
                emoji: emoji,
                subtitle: subtitle,
                plannedTotal: plannedTotal,
              )
            : t)
        .toList();
    notifyListeners();
    await _saveTrips();

    if (LocalFirstRepository.isTemp(trip.id)) return;
    await push(() => api.patch('/trips/${trip.id}', body: {
          'name': ?name,
          'emoji': ?emoji,
          'subtitle': ?subtitle,
          'planned_total': ?plannedTotal,
        }));
  }

  Future<void> removeTrip(Trip trip) async {
    final backup = _trips;
    _trips = _trips.where((t) => t.id != trip.id && t.parentId != trip.id).toList();
    _expenses.remove(trip.id);
    notifyListeners();
    await _saveTrips();

    if (LocalFirstRepository.isTemp(trip.id)) return;
    await push(
      () => api.delete('/trips/${trip.id}'),
      rollback: () => _trips = backup,
    );
  }

  // ─── Расходы поездки ────────────────────────────────────────────────

  /// Читает траты из кэша сразу, за свежими идёт в сеть только при нужде.
  Future<void> loadExpenses(int tripId, {bool forceRefresh = false}) async {
    final key = _expensesKey(tripId);
    _expenses[tripId] = readCache(key).map(TripExpense.fromJson).toList();
    notifyListeners();

    if (!forceRefresh && !isStale(key)) return;

    await runSync(() async {
      final data = await api.get('/trips/$tripId/expenses');
      await writeCache(key, (data as List?) ?? const [], fromServer: true);
      _expenses[tripId] = readCache(key).map(TripExpense.fromJson).toList();
    });
  }

  Future<void> _saveExpenses(int tripId) => writeCache(
        _expensesKey(tripId),
        (_expenses[tripId] ?? const []).map((e) => e.toJson()).toList(),
      );

  /// Пересчёт итога поездки на месте.
  ///
  /// Сервер считает сумму сам, но ответа мы не ждём: карточка в списке
  /// должна обновиться сразу, как только добавили трату.
  void _recalcTotal(int tripId) {
    final total = (_expenses[tripId] ?? const [])
        .fold<int>(0, (sum, e) => sum + e.amount);
    _trips = _trips
        .map((t) => t.id == tripId ? t.copyWith(actualTotal: total) : t)
        .toList();
  }

  Future<void> addExpense(
    int tripId, {
    required int amount,
    DateTime? date,
    int? plannedAmount,
    String category = '',
    String note = '',
    String city = '',
    String day = '',
  }) async {
    final dateStr = ymd(date ?? DateTime.now());

    final temp = TripExpense(
      id: LocalFirstRepository.nextTempId(),
      tripId: tripId,
      date: dateStr,
      amount: amount,
      plannedAmount: plannedAmount,
      category: category,
      note: note,
      city: city,
      day: day,
    );
    _expenses[tripId] = [...(_expenses[tripId] ?? const []), temp];
    _recalcTotal(tripId);
    notifyListeners();
    await _saveExpenses(tripId);
    await _saveTrips();

    final created = await push(() => api.post('/trips/$tripId/expenses', body: {
          'date': dateStr,
          'amount': amount,
          'planned_amount': ?plannedAmount,
          'category': category,
          'note': note,
          'city': city,
          'day': day,
        }));
    if (created is Map) {
      final real = TripExpense.fromJson(Map<String, dynamic>.from(created));
      _expenses[tripId] =
          (_expenses[tripId] ?? const []).map((e) => e.id == temp.id ? real : e).toList();
      notifyListeners();
      await _saveExpenses(tripId);
    }
  }

  Future<void> updateExpense(
    TripExpense expense, {
    int? amount,
    int? plannedAmount,
    String? category,
    String? note,
    String? city,
  }) async {
    _expenses[expense.tripId] = (_expenses[expense.tripId] ?? const [])
        .map((e) => e.id == expense.id
            ? e.copyWith(
                amount: amount,
                plannedAmount: plannedAmount,
                category: category,
                note: note,
                city: city,
              )
            : e)
        .toList();
    _recalcTotal(expense.tripId);
    notifyListeners();
    await _saveExpenses(expense.tripId);
    await _saveTrips();

    if (LocalFirstRepository.isTemp(expense.id)) return;
    await push(() => api.patch('/trip-expenses/${expense.id}', body: {
          'amount': ?amount,
          'planned_amount': ?plannedAmount,
          'category': ?category,
          'note': ?note,
          'city': ?city,
        }));
  }

  Future<void> removeExpense(TripExpense expense) async {
    final backup = _expenses[expense.tripId] ?? const <TripExpense>[];
    _expenses[expense.tripId] =
        backup.where((e) => e.id != expense.id).toList();
    _recalcTotal(expense.tripId);
    notifyListeners();
    await _saveExpenses(expense.tripId);
    await _saveTrips();

    if (LocalFirstRepository.isTemp(expense.id)) return;
    await push(
      () => api.delete('/trip-expenses/${expense.id}'),
      rollback: () => _expenses[expense.tripId] = backup,
    );
  }
}
