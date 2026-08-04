import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/task_repository.dart';
import '../models/json.dart';
import '../models/task.dart';
import '../theme.dart';
import '../widgets/common.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TaskRepository>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<TaskRepository>();
    final pending = repo.pending;
    final done = repo.done;

    return Column(
      children: [
        SectionHeader(
          title: 'Задачи',
          subtitle: _dayLabel(repo.day),
          actions: [
            PeriodStepper(
              label: _shortDate(repo.day),
              onPrev: () => context.read<TaskRepository>().setDay(
                    repo.day.subtract(const Duration(days: 1)),
                  ),
              onNext: () => context.read<TaskRepository>().setDay(
                    repo.day.add(const Duration(days: 1)),
                  ),
            ),
            const SizedBox(width: 8),
            AddButton(onPressed: _addTask, tooltip: 'Новая задача'),
          ],
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.gold,
            backgroundColor: AppColors.surface,
            onRefresh: () => context.read<TaskRepository>().refresh(),
            child: repo.tasks.isEmpty
                ? const EmptyHint(emoji: '✅', text: 'На этот день задач нет')
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      ...pending.map(_buildTile),
                      if (done.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
                          child: Text(
                            'Сделано · ${done.length}',
                            style: const TextStyle(color: AppColors.textDim, fontSize: 12),
                          ),
                        ),
                        ...done.map(_buildTile),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildTile(TaskItem task) {
    return Dismissible(
      key: ValueKey('task-${task.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.red.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: AppColors.red),
      ),
      onDismissed: (_) => context.read<TaskRepository>().remove(task),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(
            color: task.isHighPriority && !task.isDone ? AppColors.goldDim : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          onTap: () => context.read<TaskRepository>().toggleDone(task),
          onLongPress: () => _rename(task),
          leading: Icon(
            task.isDone ? Icons.check_circle : Icons.radio_button_unchecked,
            color: task.isDone ? AppColors.green : AppColors.textDim,
          ),
          title: Text(
            task.title,
            style: TextStyle(
              color: task.isDone ? AppColors.textDim : AppColors.text,
              fontSize: 15,
              decoration: task.isDone ? TextDecoration.lineThrough : null,
              decorationColor: AppColors.textDim,
            ),
          ),
          subtitle: _buildMeta(task),
          trailing: task.isRecurring
              ? const Tooltip(
                  message: 'Повторяющаяся задача',
                  child: Icon(Icons.repeat, size: 16, color: AppColors.textDim),
                )
              : null,
        ),
      ),
    );
  }

  Widget? _buildMeta(TaskItem task) {
    final parts = <String>[
      if (task.timeStr != null && task.timeStr!.isNotEmpty) task.timeStr!,
      if (task.tag != null && task.tag!.isNotEmpty) '#${task.tag}',
    ];
    if (parts.isEmpty) return null;
    return Text(
      parts.join('  ·  '),
      style: const TextStyle(color: AppColors.textDim, fontSize: 12),
    );
  }

  Future<void> _addTask() async {
    final title = await promptText(
      context,
      title: 'Новая задача',
      hint: 'Что нужно сделать',
    );
    if (title == null || title.isEmpty || !mounted) return;
    await context.read<TaskRepository>().add(title);
  }

  Future<void> _rename(TaskItem task) async {
    final title = await promptText(
      context,
      title: 'Переименовать',
      initial: task.title,
      confirmLabel: 'Сохранить',
    );
    if (title == null || title.isEmpty || !mounted) return;
    await context.read<TaskRepository>().rename(task, title);
  }

  static const _weekdays = [
    'понедельник', 'вторник', 'среда', 'четверг', 'пятница', 'суббота', 'воскресенье',
  ];

  String _dayLabel(DateTime d) {
    final today = DateTime.now();
    final isToday = ymd(d) == ymd(today);
    final weekday = _weekdays[d.weekday - 1];
    return isToday ? 'Сегодня, $weekday' : '${d.day} ${monthNames[d.month - 1].toLowerCase()}, $weekday';
  }

  String _shortDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
}
