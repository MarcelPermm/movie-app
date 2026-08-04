import '../models/notebook.dart';
import 'local_first_repository.dart';

/// Тетрадь: заметки и списки дел.
class NotebookRepository extends LocalFirstRepository {
  NotebookRepository({required super.api, required super.session});

  List<Note> _notes = [];
  List<Checklist> _lists = [];

  /// Пункты хранятся по спискам: `{listId: [items]}`.
  final Map<int, List<ChecklistItem>> _items = {};

  List<Note> get notes => List.unmodifiable(_notes);
  List<Checklist> get lists => List.unmodifiable(_lists);

  List<ChecklistItem> itemsOf(int listId) => List.unmodifiable(_items[listId] ?? const []);

  int doneCountOf(int listId) => (_items[listId] ?? const []).where((i) => i.done).length;

  String get _notesKey => cacheKey('notebook::notes');
  String get _listsKey => cacheKey('notebook::lists');
  String _itemsKey(int listId) => cacheKey('notebook::items::$listId');

  Future<void> load({bool forceRefresh = false}) async {
    _notes = readCache(_notesKey).map(Note.fromJson).toList();
    _lists = readCache(_listsKey).map(Checklist.fromJson).toList();
    for (final l in _lists) {
      _items[l.id] = readCache(_itemsKey(l.id)).map(ChecklistItem.fromJson).toList();
    }
    notifyListeners();
    if (forceRefresh || isStale(_notesKey)) await refresh();
  }

  Future<void> refresh() => runSync(() async {
        final results = await Future.wait([
          api.get('/notebook/notes'),
          api.get('/notebook/lists'),
        ]);
        await writeCache(_notesKey, (results[0] as List?) ?? const [], fromServer: true);
        await writeCache(_listsKey, (results[1] as List?) ?? const [], fromServer: true);

        _notes = readCache(_notesKey).map(Note.fromJson).toList();
        _lists = readCache(_listsKey).map(Checklist.fromJson).toList();

        // Пункты всех списков тянем разом — их немного, зато потом
        // любой список открывается мгновенно.
        await Future.wait(_lists.map(_refreshItems));
      });

  Future<void> _refreshItems(Checklist list) async {
    final data = await api.get('/notebook/lists/${list.id}/items');
    await writeCache(_itemsKey(list.id), (data as List?) ?? const [], fromServer: true);
    _items[list.id] = readCache(_itemsKey(list.id)).map(ChecklistItem.fromJson).toList();
  }

  Future<void> _saveNotes() => writeCache(_notesKey, _notes.map((n) => n.toJson()).toList());
  Future<void> _saveLists() => writeCache(_listsKey, _lists.map((l) => l.toJson()).toList());
  Future<void> _saveItems(int listId) =>
      writeCache(_itemsKey(listId), (_items[listId] ?? const []).map((i) => i.toJson()).toList());

  // ─── Заметки ────────────────────────────────────────────────────────

  Future<void> addNote({String title = '', String body = '', String color = 'yellow'}) async {
    final temp = Note(id: LocalFirstRepository.nextTempId(), title: title, body: body, color: color);
    _notes = [temp, ..._notes];
    notifyListeners();
    await _saveNotes();

    final created = await push(() => api.post('/notebook/notes', body: {
          'title': title,
          'body': body,
          'color': color,
        }));
    if (created is Map) {
      final real = Note.fromJson(Map<String, dynamic>.from(created));
      _notes = _notes.map((n) => n.id == temp.id ? real : n).toList();
      notifyListeners();
      await _saveNotes();
    }
  }

  Future<void> updateNote(Note note, {String? title, String? body, String? color}) async {
    _notes = _notes
        .map((n) => n.id == note.id ? n.copyWith(title: title, body: body, color: color) : n)
        .toList();
    notifyListeners();
    await _saveNotes();

    if (LocalFirstRepository.isTemp(note.id)) return;
    await push(() => api.patch('/notebook/notes/${note.id}', body: {
          'title': ?title,
          'body': ?body,
          'color': ?color,
        }));
  }

  Future<void> removeNote(Note note) async {
    final backup = _notes;
    _notes = _notes.where((n) => n.id != note.id).toList();
    notifyListeners();
    await _saveNotes();

    if (LocalFirstRepository.isTemp(note.id)) return;
    await push(
      () => api.delete('/notebook/notes/${note.id}'),
      rollback: () => _notes = backup,
    );
  }

  // ─── Списки дел ─────────────────────────────────────────────────────

  Future<void> addList(String name, {String emoji = '📋'}) async {
    final name0 = name.trim();
    if (name0.isEmpty) return;

    final temp = Checklist(id: LocalFirstRepository.nextTempId(), name: name0, emoji: emoji);
    _lists = [..._lists, temp];
    _items[temp.id] = [];
    notifyListeners();
    await _saveLists();

    final created = await push(() => api.post('/notebook/lists', body: {
          'name': name0,
          'emoji': emoji,
        }));
    if (created is Map) {
      final real = Checklist.fromJson(Map<String, dynamic>.from(created));
      _lists = _lists.map((l) => l.id == temp.id ? real : l).toList();
      _items[real.id] = _items.remove(temp.id) ?? [];
      notifyListeners();
      await _saveLists();
    }
  }

  Future<void> removeList(Checklist list) async {
    final backup = _lists;
    _lists = _lists.where((l) => l.id != list.id).toList();
    _items.remove(list.id);
    notifyListeners();
    await _saveLists();

    if (LocalFirstRepository.isTemp(list.id)) return;
    await push(
      () => api.delete('/notebook/lists/${list.id}'),
      rollback: () => _lists = backup,
    );
  }

  // ─── Пункты списка ──────────────────────────────────────────────────

  Future<void> addItem(int listId, String title) async {
    final title0 = title.trim();
    if (title0.isEmpty) return;

    final temp = ChecklistItem(
      id: LocalFirstRepository.nextTempId(),
      listId: listId,
      title: title0,
    );
    _items[listId] = [...(_items[listId] ?? const []), temp];
    notifyListeners();
    await _saveItems(listId);

    // Список ещё не создан на сервере — пункт уедет вместе со следующим обновлением.
    if (LocalFirstRepository.isTemp(listId)) return;

    final created = await push(() => api.post('/notebook/lists/$listId/items', body: {'title': title0}));
    if (created is Map) {
      final real = ChecklistItem.fromJson(Map<String, dynamic>.from(created));
      _items[listId] = (_items[listId] ?? const []).map((i) => i.id == temp.id ? real : i).toList();
      notifyListeners();
      await _saveItems(listId);
    }
  }

  Future<void> toggleItem(ChecklistItem item) async {
    final next = !item.done;
    _items[item.listId] =
        (_items[item.listId] ?? const []).map((i) => i.id == item.id ? i.copyWith(done: next) : i).toList();
    notifyListeners();
    await _saveItems(item.listId);

    if (LocalFirstRepository.isTemp(item.id)) return;
    await push(() => api.patch('/notebook/list-items/${item.id}', body: {'done': next}));
  }

  Future<void> removeItem(ChecklistItem item) async {
    _items[item.listId] = (_items[item.listId] ?? const []).where((i) => i.id != item.id).toList();
    notifyListeners();
    await _saveItems(item.listId);

    if (LocalFirstRepository.isTemp(item.id)) return;
    await push(() => api.delete('/notebook/list-items/${item.id}'));
  }
}
