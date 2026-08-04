import 'package:flutter/material.dart';

import '../data/local_first_repository.dart';
import '../theme.dart';

/// Состояние синхронизации: крутилка, счётчик неотправленного или «офлайн».
/// Ничего не показывает, когда всё в порядке — чтобы не мельтешить.
class SyncBadge extends StatelessWidget {
  final LocalFirstRepository repo;
  const SyncBadge(this.repo, {super.key});

  @override
  Widget build(BuildContext context) {
    if (repo.syncing) {
      return const SizedBox(
        height: 13,
        width: 13,
        child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.goldDim),
      );
    }
    if (repo.pendingWrites > 0) {
      return _pill('↑ ${repo.pendingWrites}', AppColors.blue, 'Ждёт отправки на сервер');
    }
    if (repo.lastError != null) {
      return _pill('офлайн', AppColors.textDim, repo.lastError!);
    }
    return const SizedBox.shrink();
  }

  Widget _pill(String text, Color color, String tooltip) => Tooltip(
        message: tooltip,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(text, style: TextStyle(color: color, fontSize: 11)),
        ),
      );
}

/// Заголовок раздела с кнопками справа.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: const TextStyle(color: AppColors.textDim, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Подсказка на месте пустого списка. Внутри ListView, чтобы работал
/// жест «потянуть вниз».
class EmptyHint extends StatelessWidget {
  final String text;
  final String emoji;

  const EmptyHint({super.key, required this.text, this.emoji = '🌱'});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 100),
      children: [
        Text(emoji, textAlign: TextAlign.center, style: const TextStyle(fontSize: 34)),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textDim, fontSize: 14),
        ),
      ],
    );
  }
}

/// Переключатель из двух-трёх вариантов — тот же, что в шапке сайта.
class SegmentedToggle<T> extends StatelessWidget {
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  const SegmentedToggle({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.entries.map((e) {
          final active = e.key == value;
          return GestureDetector(
            onTap: () => onChanged(e.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: active ? AppColors.gold : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                e.value,
                style: TextStyle(
                  color: active ? AppColors.bg : AppColors.textDim,
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Переключение периода стрелками: «‹ Август 2026 ›».
class PeriodStepper extends StatelessWidget {
  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const PeriodStepper({
    super.key,
    required this.label,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left, color: AppColors.textDim),
          visualDensity: VisualDensity.compact,
        ),
        Text(
          label,
          style: const TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right, color: AppColors.textDim),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

/// Круглая кнопка «добавить» в заголовке раздела.
class AddButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String tooltip;

  const AddButton({super.key, required this.onPressed, this.tooltip = 'Добавить'});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: const Icon(Icons.add, color: AppColors.bg),
      style: IconButton.styleFrom(
        backgroundColor: AppColors.gold,
        minimumSize: const Size(36, 36),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// Диалог с одним текстовым полем — им создаётся почти всё:
/// задача, цель, список, категория.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String hint = '',
  String initial = '',
  String confirmLabel = 'Добавить',
  TextInputType? keyboardType,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(title, style: const TextStyle(color: AppColors.text, fontSize: 17)),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: keyboardType,
        decoration: InputDecoration(hintText: hint),
        style: const TextStyle(color: AppColors.text),
        onSubmitted: (v) => Navigator.pop(dialogContext, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Отмена', style: TextStyle(color: AppColors.textDim)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

/// Подтверждение удаления — везде одинаковое.
Future<bool> confirmDelete(BuildContext context, String what) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Удалить?', style: TextStyle(color: AppColors.text, fontSize: 17)),
      content: Text(what, style: const TextStyle(color: AppColors.textDim)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Отмена', style: TextStyle(color: AppColors.textDim)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Удалить'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Разбивка сумм по разрядам: 12 500 ₽.
String formatMoney(num value) {
  final digits = value.round().abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return '${value < 0 ? '−' : ''}$buffer ₽';
}

const monthNames = [
  'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
  'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
];
