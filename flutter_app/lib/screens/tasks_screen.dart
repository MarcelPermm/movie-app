import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/goal_repository.dart';
import '../data/task_repository.dart';
import '../models/goal.dart';
import '../models/json.dart';
import '../models/task.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/task_bits.dart';

/// Какие задачи показывать: все, только личные или только рабочие.
enum TaskFilter { all, personal, work }

extension on TaskFilter {
  bool accepts(bool isWork) => switch (this) {
        TaskFilter.all => true,
        TaskFilter.personal => !isWork,
        TaskFilter.work => isWork,
      };
}

/// Задачи: цели недели сверху, под ними дела выбранного дня.
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  TaskFilter _filter = TaskFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tasks = context.read<TaskRepository>();
      tasks.load();
      // Неделя всегда та, в которую попадает открытый день.
      context.read<WeekGoalRepository>().showPeriodOf(tasks.day);
    });
  }

  Future<void> _goToDay(DateTime day) async {
    final week = context.read<WeekGoalRepository>();
    await context.read<TaskRepository>().setDay(day);
    await week.showPeriodOf(day);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<TaskRepository>();
    final week = context.watch<WeekGoalRepository>();

    final visible = repo.tasks.where((t) => !t.isCancelled && _filter.accepts(t.isWork)).toList();
    final pending = visible.where((t) => !t.isDone).toList();
    final done = visible.where((t) => t.isDone).toList();
    final workCount = repo.tasks.where((t) => t.isWork && !t.isCancelled).length;
    final isToday = ymd(repo.day) == ymd(DateTime.now());

    return Column(
      children: [
        SectionHeader(
          title: 'Задачи',
          subtitle: _dayLabel(repo.day),
          actions: [
            if (!isToday)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: TextButton(
                  onPressed: () => _goToDay(DateTime.now()),
                  child: const Text('Сегодня'),
                ),
              ),
            PeriodStepper(
              label: _shortDate(repo.day),
              onPrev: () => _goToDay(repo.day.subtract(const Duration(days: 1))),
              onNext: () => _goToDay(repo.day.add(const Duration(days: 1))),
            ),
            const SizedBox(width: 8),
            AddButton(onPressed: () => _compose(), tooltip: 'Новая задача'),
          ],
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.gold,
            backgroundColor: AppColors.sheet,
            onRefresh: () => Future.wait([
              context.read<TaskRepository>().refresh(),
              context.read<WeekGoalRepository>().refresh(),
            ]),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedToggle<TaskFilter>(
                    value: _filter,
                    options: {
                      TaskFilter.all: 'Все',
                      TaskFilter.personal: 'Личное',
                      TaskFilter.work: workCount > 0 ? 'Работа · $workCount' : 'Работа',
                    },
                    onChanged: (v) => setState(() => _filter = v),
                  ),
                ),
                const SizedBox(height: 14),
                _WeekPanel(
                  repo: week,
                  filter: _filter,
                  onAdd: () => _compose(forWeek: true),
                  onActions: _goalActions,
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isToday ? 'НА СЕГОДНЯ' : 'НА ${repo.day.day} ${monthGenitive[repo.day.month - 1].toUpperCase()}',
                        style: kEyebrowStyle,
                      ),
                    ),
                    if (visible.isNotEmpty)
                      Text(
                        '${done.length} из ${visible.length}',
                        style: TextStyle(color: AppColors.textDim, fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (visible.isEmpty)
                  _EmptyDay(
                    text: switch (_filter) {
                      TaskFilter.work => 'Рабочих задач на этот день нет',
                      TaskFilter.personal => 'Личных задач на этот день нет',
                      TaskFilter.all => 'На этот день задач нет',
                    },
                    onAdd: () => _compose(),
                  )
                else ...[
                  ...pending.map(_buildTile),
                  if (done.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
                      child: Text(
                        'Сделано · ${done.length}',
                        style: TextStyle(color: AppColors.textDim, fontSize: 12),
                      ),
                    ),
                    ...done.map(_buildTile),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTile(TaskItem task) {
    final meta = <Widget>[
      if (task.isWork) const WorkPill(dense: true),
      if (task.timeStr != null && task.timeStr!.isNotEmpty)
        Text(task.timeStr!, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
      if (task.tag != null && task.tag!.isNotEmpty && !task.isWork)
        Text('#${task.tag}', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
      if (task.isRecurring)
        Tooltip(
          message: 'Повторяющаяся задача',
          child: Icon(Icons.repeat, size: 14, color: AppColors.textDim),
        ),
    ];

    return Dismissible(
      key: ValueKey('task-${task.id}'),
      direction: DismissDirection.endToStart,
      background: _deleteBackground(),
      onDismissed: (_) => context.read<TaskRepository>().remove(task),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.medium),
            onTap: () => context.read<TaskRepository>().toggleDone(task),
            onLongPress: () => _taskActions(task),
            onSecondaryTap: () => _taskActions(task),
            child: Ink(
              padding: const EdgeInsets.fromLTRB(14, 13, 6, 13),
              decoration: cardDecoration(highlighted: task.isHighPriority && !task.isDone),
              child: Row(
                children: [
                  TaskCheck(done: task.isDone, important: task.isHighPriority),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: TextStyle(
                            color: task.isDone ? AppColors.textDim : AppColors.text,
                            fontSize: 15,
                            decoration: task.isDone ? TextDecoration.lineThrough : null,
                            decorationColor: AppColors.textDim,
                          ),
                        ),
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: meta,
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Действия',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.more_horiz, size: 20, color: AppColors.textDim),
                    onPressed: () => _taskActions(task),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _compose({bool forWeek = false}) async {
    final repo = context.read<TaskRepository>();
    final draft = await showTaskComposer(
      context,
      dayLabel: _dayLabel(repo.day),
      weekLabel: 'Неделя ${weekRangeLabel(repo.day)}',
      forWeek: forWeek,
      work: _filter == TaskFilter.work,
    );
    if (draft == null || !mounted) return;

    final tag = draft.work ? kWorkTag : null;
    if (draft.forWeek) {
      await context.read<WeekGoalRepository>().add(draft.title, tag: tag);
    } else {
      await repo.add(draft.title, tag: tag, priority: draft.important ? 'high' : 'normal');
    }
  }

  Future<void> _taskActions(TaskItem task) async {
    final repo = context.read<TaskRepository>();
    final action = await _pickAction(
      title: task.title,
      work: task.isWork,
    );
    if (!mounted) return;
    switch (action) {
      case _Action.rename:
        final title = await promptText(context, title: 'Переименовать', initial: task.title, confirmLabel: 'Сохранить');
        if (title != null && title.isNotEmpty) await repo.rename(task, title);
      case _Action.toggleWork:
        await repo.setWork(task, !task.isWork);
      case _Action.delete:
        await repo.remove(task);
      case null:
        break;
    }
  }

  Future<void> _goalActions(Goal goal) async {
    final repo = context.read<WeekGoalRepository>();
    final action = await _pickAction(title: goal.text, work: goal.isWork);
    if (!mounted) return;
    switch (action) {
      case _Action.rename:
        final text = await promptText(context, title: 'Изменить цель', initial: goal.text, confirmLabel: 'Сохранить');
        if (text != null && text.isNotEmpty) await repo.rename(goal, text);
      case _Action.toggleWork:
        await repo.setWork(goal, !goal.isWork);
      case _Action.delete:
        await repo.remove(goal);
      case null:
        break;
    }
  }

  Future<_Action?> _pickAction({required String title, required bool work}) {
    return showModalBottomSheet<_Action>(
      context: context,
      backgroundColor: AppColors.sheet,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textDim, fontSize: 13),
              ),
            ),
            ListTile(
              leading: Icon(Icons.edit_outlined, color: AppColors.text),
              title: Text('Переименовать', style: TextStyle(color: AppColors.text)),
              onTap: () => Navigator.pop(sheetContext, _Action.rename),
            ),
            ListTile(
              leading: Icon(work ? Icons.person_outline : Icons.work_outline, color: AppColors.blue),
              title: Text(
                work ? 'Сделать личной' : 'Сделать рабочей',
                style: TextStyle(color: AppColors.text),
              ),
              onTap: () => Navigator.pop(sheetContext, _Action.toggleWork),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppColors.red),
              title: Text('Удалить', style: TextStyle(color: AppColors.red)),
              onTap: () => Navigator.pop(sheetContext, _Action.delete),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static const _weekdays = [
    'понедельник', 'вторник', 'среда', 'четверг', 'пятница', 'суббота', 'воскресенье',
  ];

  String _dayLabel(DateTime d) {
    final today = DateTime.now();
    final isToday = ymd(d) == ymd(today);
    final weekday = _weekdays[d.weekday - 1];
    return isToday ? 'Сегодня, $weekday' : '${d.day} ${monthGenitive[d.month - 1]}, $weekday';
  }

  String _shortDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
}

enum _Action { rename, toggleWork, delete }

Widget _deleteBackground() => Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Icon(Icons.delete_outline, color: AppColors.red),
    );

/// Цели недели: прогресс и короткий список, который видно всю неделю.
class _WeekPanel extends StatelessWidget {
  final WeekGoalRepository repo;
  final TaskFilter filter;
  final VoidCallback onAdd;
  final ValueChanged<Goal> onActions;

  const _WeekPanel({required this.repo, required this.filter, required this.onAdd, required this.onActions});

  @override
  Widget build(BuildContext context) {
    final goals = repo.goals.where((g) => filter.accepts(g.isWork)).toList()
      ..sort((a, b) => (a.done ? 1 : 0) - (b.done ? 1 : 0));
    final done = goals.where((g) => g.done).length;
    final thisWeek = repo.periodKey == ymd(weekStart(DateTime.now()));

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 12),
      decoration: cardDecoration(raised: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(thisWeek ? 'ЦЕЛИ ЭТОЙ НЕДЕЛИ' : 'ЦЕЛИ НЕДЕЛИ', style: kEyebrowStyle),
                    const SizedBox(height: 4),
                    Text(weekRangeLabel(repo.anchor), style: AppText.display(20)),
                  ],
                ),
              ),
              if (goals.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 2),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '$done', style: AppText.number(22)),
                      TextSpan(
                        text: ' из ${goals.length}',
                        style: TextStyle(color: AppColors.textDim, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ),
                ),
            ],
          ),
          if (goals.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ThinProgress(value: done / goals.length),
            ),
            const SizedBox(height: 6),
            for (final g in goals)
              InkWell(
                borderRadius: BorderRadius.circular(AppRadius.small),
                onTap: () => repo.toggle(g),
                onLongPress: () => onActions(g),
                onSecondaryTap: () => onActions(g),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      TaskCheck(done: g.done, size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          g.text,
                          style: TextStyle(
                            color: g.done ? AppColors.textDim : AppColors.text,
                            fontSize: 14.5,
                            decoration: g.done ? TextDecoration.lineThrough : null,
                            decorationColor: AppColors.textDim,
                          ),
                        ),
                      ),
                      if (g.isWork) ...[const SizedBox(width: 8), const WorkPill(dense: true)],
                      IconButton(
                        tooltip: 'Действия',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.more_horiz, size: 18, color: AppColors.textDim),
                        onPressed: () => onActions(g),
                      ),
                    ],
                  ),
                ),
              ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 8),
              child: Text(
                'Две-три цели на неделю — они будут видны каждый день, '
                'и на главном экране тоже.',
                style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.4),
              ),
            ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Цель на неделю'),
          ),
        ],
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  final String text;
  final VoidCallback onAdd;

  const _EmptyDay({required this.text, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
      decoration: cardDecoration(),
      child: Column(
        children: [
          Text('✅', style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 8),
          Text(text, style: TextStyle(color: AppColors.textDim, fontSize: 14)),
          const SizedBox(height: 6),
          TextButton(onPressed: onAdd, child: const Text('Добавить задачу')),
        ],
      ),
    );
  }
}
