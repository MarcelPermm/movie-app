import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/goal_repository.dart';
import '../models/goal.dart';
import '../theme.dart';
import '../widgets/common.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GoalRepository>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<GoalRepository>();
    final goals = repo.goals;

    return Column(
      children: [
        SectionHeader(
          title: 'Цели',
          subtitle: goals.isEmpty ? null : 'Выполнено ${repo.doneCount} из ${goals.length}',
          actions: [
            SegmentedToggle<String>(
              value: repo.period,
              options: const {'month': 'Месяц', 'year': 'Год'},
              onChanged: (v) => context.read<GoalRepository>().setPeriod(v),
            ),
            const SizedBox(width: 8),
            AddButton(onPressed: _addGoal, tooltip: 'Новая цель'),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: PeriodStepper(
              label: _periodLabel(repo),
              onPrev: () => context.read<GoalRepository>().shift(-1),
              onNext: () => context.read<GoalRepository>().shift(1),
            ),
          ),
        ),
        if (goals.isNotEmpty) _buildProgress(repo),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.gold,
            backgroundColor: AppColors.surface,
            onRefresh: () => context.read<GoalRepository>().refresh(),
            child: goals.isEmpty
                ? const EmptyHint(emoji: '🎯', text: 'На этот период целей пока нет')
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: goals.map(_buildTile).toList(),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgress(GoalRepository repo) {
    final fraction = repo.goals.isEmpty ? 0.0 : repo.doneCount / repo.goals.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: fraction,
          minHeight: 6,
          backgroundColor: AppColors.surface,
          valueColor: const AlwaysStoppedAnimation(AppColors.gold),
        ),
      ),
    );
  }

  Widget _buildTile(Goal goal) {
    return Dismissible(
      key: ValueKey('goal-${goal.id}'),
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
      onDismissed: (_) => context.read<GoalRepository>().remove(goal),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          onTap: () => context.read<GoalRepository>().toggle(goal),
          onLongPress: () => _rename(goal),
          leading: Icon(
            goal.done ? Icons.check_circle : Icons.circle_outlined,
            color: goal.done ? AppColors.green : AppColors.textDim,
          ),
          title: Text(
            goal.text,
            style: TextStyle(
              color: goal.done ? AppColors.textDim : AppColors.text,
              fontSize: 15,
              decoration: goal.done ? TextDecoration.lineThrough : null,
              decorationColor: AppColors.textDim,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addGoal() async {
    final text = await promptText(context, title: 'Новая цель', hint: 'Чего хочется достичь');
    if (text == null || text.isEmpty || !mounted) return;
    await context.read<GoalRepository>().add(text);
  }

  Future<void> _rename(Goal goal) async {
    final text = await promptText(
      context,
      title: 'Изменить цель',
      initial: goal.text,
      confirmLabel: 'Сохранить',
    );
    if (text == null || text.isEmpty || !mounted) return;
    await context.read<GoalRepository>().rename(goal, text);
  }

  String _periodLabel(GoalRepository repo) => repo.period == 'year'
      ? '${repo.anchor.year}'
      : '${monthNames[repo.anchor.month - 1]} ${repo.anchor.year}';
}
