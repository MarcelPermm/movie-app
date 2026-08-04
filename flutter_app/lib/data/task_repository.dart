import '../models/json.dart';
import '../models/task.dart';
import 'local_first_repository.dart';

/// Задачи на выбранный день.
///
/// Кэш ведётся отдельно на каждую дату: открывая вчерашний день, ты видишь
/// его сразу, без ожидания сети.
class TaskRepository extends LocalFirstRepository {
  TaskRepository({required super.api, required super.session});

  DateTime _day = DateTime.now();
  DateTime get day => _day;

  List<TaskItem> _tasks = [];
  List<TaskItem> get tasks => List.unmodifiable(_tasks);

  List<TaskItem> get pending => _tasks.where((t) => !t.isDone && !t.isCancelled).toList();
  List<TaskItem> get done => _tasks.where((t) => t.isDone).toList();

  String get _dateStr => ymd(_day);
  String get _key => cacheKey('tasks::$_dateStr');

  Future<void> load({bool forceRefresh = false}) async {
    _tasks = readCache(_key).map(TaskItem.fromJson).toList();
    notifyListeners();
    if (forceRefresh || isStale(_key)) await refresh();
  }

  Future<void> refresh() => runSync(() async {
        final data = await api.get('/tasks', query: {'date': _dateStr});
        await writeCache(_key, (data as List?) ?? const [], fromServer: true);
        _tasks = readCache(_key).map(TaskItem.fromJson).toList();
      });

  Future<void> setDay(DateTime value) async {
    final normalized = DateTime(value.year, value.month, value.day);
    if (ymd(normalized) == _dateStr) return;
    _day = normalized;
    await load();
  }

  Future<void> _save() => writeCache(_key, _tasks.map((t) => t.toJson()).toList());

  Future<void> add(String title, {String? timeStr, String? tag, String priority = 'normal', String? recurrence}) async {
    final title0 = title.trim();
    if (title0.isEmpty) return;

    // Настоящий id придёт от сервера, но задача должна появиться сразу.
    final temp = TaskItem(
      id: LocalFirstRepository.nextTempId(),
      title: title0,
      date: _dateStr,
      timeStr: timeStr,
      tag: tag,
      priority: priority,
      recurrence: recurrence,
      doneToday: recurrence != null ? false : null,
    );
    _tasks = [..._tasks, temp];
    notifyListeners();
    await _save();

    final created = await push(() => api.post('/tasks', body: {
          'title': title0,
          'date': _dateStr,
          'time_str': ?timeStr,
          'tag': ?tag,
          'priority': priority,
          'recurrence': ?recurrence,
        }));

    if (created is Map) {
      final real = TaskItem.fromJson(Map<String, dynamic>.from(created));
      _tasks = _tasks.map((t) => t.id == temp.id ? real : t).toList();
      notifyListeners();
      await _save();
    }
  }

  Future<void> toggleDone(TaskItem task) async {
    final nowDone = !task.isDone;

    _tasks = _tasks
        .map((t) => t.id != task.id
            ? t
            : (t.isRecurring
                ? t.copyWith(doneToday: nowDone)
                : t.copyWith(status: nowDone ? 'done' : 'todo')))
        .toList();
    notifyListeners();
    await _save();

    // Задача, ещё не доехавшая до сервера, своего id не имеет — отметку
    // отправим после того, как она создастся и обновится список.
    if (LocalFirstRepository.isTemp(task.id)) return;

    if (task.isRecurring) {
      // У повторяющейся задачи отметка привязана к конкретному дню.
      await push(() => nowDone
          ? api.post('/tasks/${task.id}/complete', query: {'date': _dateStr})
          : api.delete('/tasks/${task.id}/complete', query: {'date': _dateStr}));
    } else {
      await push(() => api.patch('/tasks/${task.id}', body: {'status': nowDone ? 'done' : 'todo'}));
    }
  }

  Future<void> rename(TaskItem task, String title) async {
    final title0 = title.trim();
    if (title0.isEmpty || title0 == task.title) return;
    _tasks = _tasks.map((t) => t.id == task.id ? t.copyWith(title: title0) : t).toList();
    notifyListeners();
    await _save();

    if (LocalFirstRepository.isTemp(task.id)) return;
    await push(() => api.patch('/tasks/${task.id}', body: {'title': title0}));
  }

  Future<void> remove(TaskItem task) async {
    final backup = _tasks;
    _tasks = _tasks.where((t) => t.id != task.id).toList();
    notifyListeners();
    await _save();

    if (LocalFirstRepository.isTemp(task.id)) return;
    await push(
      () => api.delete('/tasks/${task.id}'),
      rollback: () => _tasks = backup,
    );
  }
}
