import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/notebook_repository.dart';
import '../models/notebook.dart';
import '../theme.dart';
import '../widgets/common.dart';

class NotebookScreen extends StatefulWidget {
  const NotebookScreen({super.key});

  @override
  State<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends State<NotebookScreen> {
  bool _showNotes = true;

  /// Цвета стикеров совпадают с теми, что на сайте.
  static const _noteColors = {
    'yellow': Color(0xFF3A3320),
    'green': Color(0xFF1F3327),
    'blue': Color(0xFF1E2B3D),
    'pink': Color(0xFF3A2029),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotebookRepository>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<NotebookRepository>();

    return Column(
      children: [
        SectionHeader(
          title: 'Тетрадь',
          actions: [
            AddButton(
              onPressed: _showNotes ? _addNote : _addList,
              tooltip: _showNotes ? 'Новая заметка' : 'Новый список',
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedToggle<bool>(
              value: _showNotes,
              options: {
                true: 'Заметки · ${repo.notes.length}',
                false: 'Списки · ${repo.lists.length}',
              },
              onChanged: (v) => setState(() => _showNotes = v),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.gold,
            backgroundColor: AppColors.surface,
            onRefresh: () => context.read<NotebookRepository>().refresh(),
            child: _showNotes ? _buildNotes(repo) : _buildLists(repo),
          ),
        ),
      ],
    );
  }

  // ─── Заметки ────────────────────────────────────────────────────────

  Widget _buildNotes(NotebookRepository repo) {
    if (repo.notes.isEmpty) {
      return const EmptyHint(emoji: '📝', text: 'Заметок пока нет');
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 260).floor().clamp(1, 5);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: 1.25,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: repo.notes.length,
          itemBuilder: (context, i) => _buildNoteCard(repo.notes[i]),
        );
      },
    );
  }

  Widget _buildNoteCard(Note note) {
    return InkWell(
      onTap: () => _editNote(note),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _noteColors[note.color] ?? _noteColors['yellow'],
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    note.title.isEmpty ? 'Без названия' : note.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: note.title.isEmpty ? AppColors.textDim : AppColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => _deleteNote(note),
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.close, size: 16, color: AppColors.textDim),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                note.body,
                overflow: TextOverflow.fade,
                style: const TextStyle(color: AppColors.text, fontSize: 13, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addNote() async {
    final result = await _noteDialog();
    if (result == null || !mounted) return;
    await context.read<NotebookRepository>().addNote(
          title: result.$1,
          body: result.$2,
          color: result.$3,
        );
  }

  Future<void> _editNote(Note note) async {
    final result = await _noteDialog(note: note);
    if (result == null || !mounted) return;
    await context.read<NotebookRepository>().updateNote(
          note,
          title: result.$1,
          body: result.$2,
          color: result.$3,
        );
  }

  Future<void> _deleteNote(Note note) async {
    final ok = await confirmDelete(context, note.title.isEmpty ? 'Заметка' : note.title);
    if (!ok || !mounted) return;
    await context.read<NotebookRepository>().removeNote(note);
  }

  /// Возвращает (title, body, color).
  Future<(String, String, String)?> _noteDialog({Note? note}) {
    final titleController = TextEditingController(text: note?.title ?? '');
    final bodyController = TextEditingController(text: note?.body ?? '');
    var color = note?.color ?? 'yellow';

    return showDialog<(String, String, String)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocalState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            note == null ? 'Новая заметка' : 'Заметка',
            style: const TextStyle(color: AppColors.text, fontSize: 17),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: note == null,
                  decoration: const InputDecoration(hintText: 'Заголовок'),
                  style: const TextStyle(color: AppColors.text),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: bodyController,
                  minLines: 4,
                  maxLines: 10,
                  decoration: const InputDecoration(hintText: 'Текст'),
                  style: const TextStyle(color: AppColors.text),
                ),
                const SizedBox(height: 14),
                Row(
                  children: _noteColors.entries.map((e) {
                    final selected = color == e.key;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setLocalState(() => color = e.key),
                        child: Container(
                          height: 30,
                          width: 30,
                          decoration: BoxDecoration(
                            color: e.value,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected ? AppColors.gold : AppColors.border,
                              width: selected ? 2 : 1,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена', style: TextStyle(color: AppColors.textDim)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                (titleController.text.trim(), bodyController.text.trim(), color),
              ),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Списки дел ─────────────────────────────────────────────────────

  Widget _buildLists(NotebookRepository repo) {
    if (repo.lists.isEmpty) {
      return const EmptyHint(emoji: '📋', text: 'Списков пока нет');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: repo.lists.map((list) => _buildListCard(repo, list)).toList(),
    );
  }

  Widget _buildListCard(NotebookRepository repo, Checklist list) {
    final items = repo.itemsOf(list.id);
    final done = repo.doneCountOf(list.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Theme(
        // Убираем стандартные разделители раскрывающегося блока.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.only(bottom: 6),
          leading: Text(list.emoji, style: const TextStyle(fontSize: 20)),
          title: Text(
            list.name,
            style: const TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            items.isEmpty ? 'пусто' : '$done из ${items.length}',
            style: const TextStyle(color: AppColors.textDim, fontSize: 12),
          ),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, color: AppColors.textDim),
            color: AppColors.surface,
            onSelected: (value) {
              if (value == 'add') _addItem(list);
              if (value == 'delete') _deleteList(list);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'add', child: Text('Добавить пункт')),
              PopupMenuItem(value: 'delete', child: Text('Удалить список')),
            ],
          ),
          children: [
            ...items.map((item) => ListTile(
                  dense: true,
                  onTap: () => context.read<NotebookRepository>().toggleItem(item),
                  leading: Icon(
                    item.done ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 20,
                    color: item.done ? AppColors.green : AppColors.textDim,
                  ),
                  title: Text(
                    item.title,
                    style: TextStyle(
                      color: item.done ? AppColors.textDim : AppColors.text,
                      fontSize: 14,
                      decoration: item.done ? TextDecoration.lineThrough : null,
                      decorationColor: AppColors.textDim,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 16, color: AppColors.textDim),
                    onPressed: () => context.read<NotebookRepository>().removeItem(item),
                  ),
                )),
            TextButton.icon(
              onPressed: () => _addItem(list),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Добавить пункт'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addList() async {
    final name = await promptText(context, title: 'Новый список', hint: 'Название');
    if (name == null || name.isEmpty || !mounted) return;
    await context.read<NotebookRepository>().addList(name);
  }

  Future<void> _addItem(Checklist list) async {
    final title = await promptText(context, title: list.name, hint: 'Что добавить');
    if (title == null || title.isEmpty || !mounted) return;
    await context.read<NotebookRepository>().addItem(list.id, title);
  }

  Future<void> _deleteList(Checklist list) async {
    final ok = await confirmDelete(context, 'Список «${list.name}» и все его пункты');
    if (!ok || !mounted) return;
    await context.read<NotebookRepository>().removeList(list);
  }
}
