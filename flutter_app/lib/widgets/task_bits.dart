import 'package:flutter/material.dart';

import '../data/goal_repository.dart' show weekStart;
import '../theme.dart';
import 'common.dart';

/// Пометка «Работа» у задачи или цели — одна и та же везде:
/// в списке задач, на «Сегодня» и в целях недели.
class WorkPill extends StatelessWidget {
  final bool dense;

  const WorkPill({super.key, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final paper = AppTheme.spec.id == AppThemeId.paper;
    final color = AppColors.blue;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: dense ? 2 : 3),
      decoration: BoxDecoration(
        color: paper ? null : color.withValues(alpha: AppTheme.spec.isDark ? 0.16 : 0.10),
        border: paper ? Border.all(color: color.withValues(alpha: 0.7)) : null,
        borderRadius: BorderRadius.circular(paper ? 0 : AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.work_outline, size: dense ? 11 : 12, color: color),
          SizedBox(width: dense ? 3 : 4),
          Text(
            paper ? 'РАБОТА' : 'Работа',
            style: TextStyle(
              color: color,
              fontSize: dense ? 10.5 : 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: paper ? 1.2 : 0,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// «6–12 октября» или «29 сентября – 5 октября».
String weekRangeLabel(DateTime day) {
  final from = weekStart(day);
  final to = DateTime(from.year, from.month, from.day + 6);
  if (from.month == to.month) return '${from.day}–${to.day} ${monthGenitive[to.month - 1]}';
  return '${from.day} ${monthGenitive[from.month - 1]} – ${to.day} ${monthGenitive[to.month - 1]}';
}

const monthGenitive = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

/// Что ввели в окне «Новая задача».
class TaskDraft {
  final String title;

  /// true — цель на неделю, false — задача на выбранный день.
  final bool forWeek;
  final bool work;
  final bool important;

  const TaskDraft({required this.title, required this.forWeek, required this.work, required this.important});
}

/// Окно добавления: одна строка текста и три переключателя —
/// день или неделя, личное или работа, обычная или важная.
Future<TaskDraft?> showTaskComposer(
  BuildContext context, {
  required String dayLabel,
  required String weekLabel,
  bool forWeek = false,
  bool work = false,
}) {
  final controller = TextEditingController();
  var week = forWeek;
  var isWork = work;
  var important = false;

  return showModalBottomSheet<TaskDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.sheet,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
    ),
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setState) {
        void submit() {
          final title = controller.text.trim();
          if (title.isEmpty) return;
          Navigator.pop(
            sheetContext,
            TaskDraft(title: title, forWeek: week, work: isWork, important: important && !week),
          );
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(week ? 'Цель на неделю' : 'Новая задача', style: AppText.display(22)),
                  const SizedBox(height: 4),
                  Text(
                    week ? weekLabel : dayLabel,
                    style: TextStyle(color: AppColors.textDim, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(color: AppColors.text, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: week ? 'Чего хочется добиться за неделю' : 'Что нужно сделать',
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SegmentedToggle<bool>(
                        value: week,
                        options: const {false: 'На день', true: 'На неделю'},
                        onChanged: (v) => setState(() => week = v),
                      ),
                      SegmentedToggle<bool>(
                        value: isWork,
                        options: const {false: 'Личное', true: 'Работа'},
                        onChanged: (v) => setState(() => isWork = v),
                      ),
                      if (!week)
                        _FlagChip(
                          selected: important,
                          onTap: () => setState(() => important = !important),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: Text('Отмена', style: TextStyle(color: AppColors.textDim)),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(onPressed: submit, child: const Text('Добавить')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// Флажок «Важно»: выделяет задачу красной отметкой.
class _FlagChip extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;

  const _FlagChip({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.red : AppColors.textDim;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.red.withValues(alpha: 0.12) : AppColors.surface,
          border: Border.all(color: selected ? AppColors.red.withValues(alpha: 0.6) : AppColors.border),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? Icons.flag : Icons.outlined_flag, size: 16, color: color),
            const SizedBox(width: 6),
            Text('Важно', style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// Отметка задачи в духе темы: квадрат в газете и бенто, круг в остальных.
class TaskCheck extends StatelessWidget {
  final bool done;
  final bool important;
  final double size;

  const TaskCheck({super.key, required this.done, this.important = false, this.size = 20});

  @override
  Widget build(BuildContext context) {
    final spec = AppTheme.spec;
    final square = spec.cardStyle == CardStyle.ruled || spec.cardStyle == CardStyle.tile;
    final color = done ? (spec.id == AppThemeId.paper ? AppColors.gold : AppColors.green) : Colors.transparent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: square ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: square ? BorderRadius.circular(spec.id == AppThemeId.paper ? 0 : size * 0.3) : null,
        border: Border.all(
          color: done ? color : (important ? AppColors.red : AppColors.textDim),
          width: 1.6,
        ),
      ),
      child: done ? Icon(Icons.check, size: size * 0.7, color: spec.isDark ? AppColors.bg : Colors.white) : null,
    );
  }
}

/// Тонкая полоса прогресса «сделано из запланированного».
class ThinProgress extends StatelessWidget {
  final double value;

  const ThinProgress({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    final paper = AppTheme.spec.id == AppThemeId.paper;
    return ClipRRect(
      borderRadius: BorderRadius.circular(paper ? 0 : 3),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1).toDouble(),
        minHeight: paper ? 3 : 5,
        backgroundColor: AppColors.surfaceHigh,
        valueColor: AlwaysStoppedAnimation(paper ? AppColors.gold : AppColors.green),
      ),
    );
  }
}
