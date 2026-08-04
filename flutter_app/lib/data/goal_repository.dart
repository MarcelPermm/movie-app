import '../models/goal.dart';
import 'local_first_repository.dart';

/// Цели на месяц и на год.
class GoalRepository extends LocalFirstRepository {
  GoalRepository({required super.api, required super.session});

  String _period = 'month';
  DateTime _anchor = DateTime.now();

  String get period => _period;
  DateTime get anchor => _anchor;

  List<Goal> _goals = [];
  List<Goal> get goals => List.unmodifiable(_goals);

  int get doneCount => _goals.where((g) => g.done).length;

  /// '2026-08' для месяца, '2026' для года.
  String get periodKey => _period == 'year'
      ? '${_anchor.year}'
      : '${_anchor.year}-${_anchor.month.toString().padLeft(2, '0')}';

  String get _key => cacheKey('goals::$_period::$periodKey');

  Future<void> load({bool forceRefresh = false}) async {
    _goals = readCache(_key).map(Goal.fromJson).toList();
    notifyListeners();
    if (forceRefresh || isStale(_key)) await refresh();
  }

  Future<void> refresh() => runSync(() async {
        final data = await api.get('/goals', query: {'period': _period, 'period_key': periodKey});
        await writeCache(_key, (data as List?) ?? const [], fromServer: true);
        _goals = readCache(_key).map(Goal.fromJson).toList();
      });

  Future<void> setPeriod(String value) async {
    if (_period == value) return;
    _period = value;
    await load();
  }

  Future<void> shift(int delta) async {
    _anchor = _period == 'year'
        ? DateTime(_anchor.year + delta, _anchor.month)
        : DateTime(_anchor.year, _anchor.month + delta);
    await load();
  }

  Future<void> _save() => writeCache(_key, _goals.map((g) => g.toJson()).toList());

  Future<void> add(String text) async {
    final text0 = text.trim();
    if (text0.isEmpty) return;

    final temp = Goal(
      id: LocalFirstRepository.nextTempId(),
      period: _period,
      periodKey: periodKey,
      text: text0,
    );
    _goals = [..._goals, temp];
    notifyListeners();
    await _save();

    final created = await push(() => api.post('/goals', body: {
          'period': _period,
          'period_key': periodKey,
          'text': text0,
        }));
    if (created is Map) {
      final real = Goal.fromJson(Map<String, dynamic>.from(created));
      _goals = _goals.map((g) => g.id == temp.id ? real : g).toList();
      notifyListeners();
      await _save();
    }
  }

  Future<void> toggle(Goal goal) async {
    final next = !goal.done;
    _goals = _goals.map((g) => g.id == goal.id ? g.copyWith(done: next) : g).toList();
    notifyListeners();
    await _save();

    if (LocalFirstRepository.isTemp(goal.id)) return;
    await push(() => api.patch('/goals/${goal.id}', body: {'done': next}));
  }

  Future<void> rename(Goal goal, String text) async {
    final text0 = text.trim();
    if (text0.isEmpty || text0 == goal.text) return;
    _goals = _goals.map((g) => g.id == goal.id ? g.copyWith(text: text0) : g).toList();
    notifyListeners();
    await _save();

    if (LocalFirstRepository.isTemp(goal.id)) return;
    await push(() => api.patch('/goals/${goal.id}', body: {'text': text0}));
  }

  Future<void> remove(Goal goal) async {
    final backup = _goals;
    _goals = _goals.where((g) => g.id != goal.id).toList();
    notifyListeners();
    await _save();

    if (LocalFirstRepository.isTemp(goal.id)) return;
    await push(
      () => api.delete('/goals/${goal.id}'),
      rollback: () => _goals = backup,
    );
  }
}
