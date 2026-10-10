import '../core/api_client.dart';
import '../models/json.dart';
import '../models/trip.dart';
import 'budget_math.dart';
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

  /// Города многогородней поездки — по датам.
  List<Trip> citiesOf(int groupId) {
    final list = childrenOf(groupId);
    list.sort((a, b) => (a.startDate ?? '').compareTo(b.startDate ?? ''));
    return list;
  }

  /// Сколько потрачено всего. У группы сами траты лежат в городах,
  /// поэтому её собственный итог почти всегда ноль — складываем детей.
  int actualOf(Trip trip) =>
      trip.isGroup ? groupActualOf(trip, childrenOf(trip.id)) : trip.actualTotal;

  /// План поездки. У группы — сумма планов городов, как на сайте:
  /// план самой группы фиксируется в момент объединения и потом устаревает.
  int plannedOf(Trip trip) =>
      trip.isGroup ? groupPlanOf(trip, childrenOf(trip.id)) : trip.plannedTotal;

  /// Все траты поездки вместе с тратами её городов.
  List<TripExpense> expensesOfTree(Trip trip) => [
        ...expensesOf(trip.id),
        if (trip.isGroup) for (final c in childrenOf(trip.id)) ...expensesOf(c.id),
      ];

  /// Траты поездки и всех её городов за один заход в сеть.
  ///
  /// Отдельные loadExpenses тут не годятся: runSync не пускает второе
  /// обновление, пока идёт первое, и города загрузились бы через один.
  Future<void> loadTree(int tripId, {bool forceRefresh = false}) async {
    final trip = tripById(tripId);
    final ids = [
      tripId,
      if (trip != null && trip.isGroup) ...childrenOf(tripId).map((c) => c.id),
    ];

    for (final id in ids) {
      _expenses[id] = readCache(_expensesKey(id)).map(TripExpense.fromJson).toList();
    }
    notifyListeners();

    final stale = ids.any((id) => isStale(_expensesKey(id)));
    if (!forceRefresh && !stale) return;

    await runSync(() async {
      final results = await Future.wait(
        ids.map((id) => api.get('/trips/$id/expenses')),
      );
      for (var i = 0; i < ids.length; i++) {
        final key = _expensesKey(ids[i]);
        await writeCache(key, (results[i] as List?) ?? const [], fromServer: true);
        _expenses[ids[i]] = readCache(key).map(TripExpense.fromJson).toList();
      }
    });
  }

  // ─── Несколько городов в одной поездке ─────────────────────────────
  //
  // На сервере многогородняя поездка — это группа, а города — обычные
  // поездки внутри неё. Объединение требует настоящих id с сервера, поэтому
  // эти операции работают только при наличии сети и не ложатся в очередь.

  /// Добавить город. Если [parent] — обычная поездка, она превращается в
  /// первый город новой группы с тем же названием.
  ///
  /// Возвращает id группы, в которой теперь лежит город, или null при ошибке
  /// (текст ошибки — в [lastError]).
  Future<int?> addCity(
    Trip parent, {
    required String name,
    String emoji = '📍',
    String? startDate,
    String? endDate,
    int plannedTotal = 0,
  }) async {
    try {
      final created = await api.post('/trips', queueOnFailure: false, body: {
        'name': name.trim(),
        'emoji': emoji,
        'start_date': ?startDate,
        'end_date': ?endDate,
        'planned_total': plannedTotal,
        'event_type': 'trip',
      });
      if (created is! Map) throw ApiException('Сервер не вернул новый город');
      final cityId = asInt(created['id']);
      final group = await api.post('/trips/group', queueOnFailure: false, body: {
        'trip_a': parent.id,
        'trip_b': cityId,
        if (!parent.isGroup) 'name': parent.name,
        if (!parent.isGroup) 'emoji': parent.emoji,
      });
      await _reloadTrips();
      return group is Map ? asInt(group['id']) : null;
    } on ApiException catch (e) {
      _reportError(e.message);
      return null;
    }
  }

  /// Объединить две поездки в одну многогороднюю.
  Future<int?> groupWith(Trip a, Trip b) async {
    try {
      final group = await api.post('/trips/group', queueOnFailure: false, body: {
        'trip_a': a.id,
        'trip_b': b.id,
        if (!a.isGroup && !b.isGroup) 'name': a.name,
        if (!a.isGroup && !b.isGroup) 'emoji': a.emoji,
      });
      await _reloadTrips();
      return group is Map ? asInt(group['id']) : null;
    } on ApiException catch (e) {
      _reportError(e.message);
      return null;
    }
  }

  /// Вынести город из поездки — он снова станет отдельной поездкой.
  Future<bool> ungroup(Trip city) async {
    try {
      await api.post('/trips/${city.id}/ungroup', queueOnFailure: false);
      await _reloadTrips();
      return true;
    } on ApiException catch (e) {
      _reportError(e.message);
      return false;
    }
  }

  /// Перечитать список поездок сразу, в обход runSync: тот молча
  /// пропускает обновление, если параллельно уже идёт другое.
  Future<void> _reloadTrips() async {
    final data = await api.get('/trips');
    await writeCache(_tripsKey, (data as List?) ?? const [], fromServer: true);
    _trips = readCache(_tripsKey).map(Trip.fromJson).toList();
    _error = null;
    notifyListeners();
  }

  String? _error;

  /// Последняя ошибка операций с городами — для подсказки на экране.
  String? get cityError => _error;

  void _reportError(String message) {
    _error = message;
    notifyListeners();
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
    String? startDate,
    String? endDate,
  }) async {
    _trips = _trips
        .map((t) => t.id == trip.id
            ? t.copyWith(
                name: name,
                emoji: emoji,
                subtitle: subtitle,
                plannedTotal: plannedTotal,
                startDate: startDate,
                endDate: endDate,
              )
            : t)
        .toList();
    // Город поменял даты или план — у группы они складываются из городов,
    // пересчитываем сразу, не дожидаясь сервера.
    if (trip.parentId != null) _recalcGroup(trip.parentId!);
    notifyListeners();
    await _saveTrips();

    if (LocalFirstRepository.isTemp(trip.id)) return;
    await push(() => api.patch('/trips/${trip.id}', body: {
          'name': ?name,
          'emoji': ?emoji,
          'subtitle': ?subtitle,
          'planned_total': ?plannedTotal,
          'start_date': ?startDate,
          'end_date': ?endDate,
        }));
  }

  /// Даты группы — от первого города до последнего, план — сумма городов.
  /// Так же считает сервер.
  void _recalcGroup(int groupId) {
    final kids = childrenOf(groupId);
    if (kids.isEmpty) return;
    final rollup = groupRollup(kids);
    _trips = _trips
        .map((t) => t.id == groupId
            ? t.copyWith(
                startDate: rollup.start,
                endDate: rollup.end,
                plannedTotal: rollup.plan,
              )
            : t)
        .toList();
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
