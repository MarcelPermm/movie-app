import 'package:flutter/material.dart';

import '../theme.dart';

/// Оценка от 1 до 10 — одинаковая для фильмов и книг.
Future<int?> pickRating(BuildContext context, {required String title, int? current}) {
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(10, (i) {
                final value = i + 1;
                final selected = current == value;
                return SizedBox(
                  width: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: selected ? AppColors.gold : AppColors.bg,
                      foregroundColor: selected ? AppColors.bg : AppColors.text,
                    ),
                    onPressed: () => Navigator.pop(sheetContext, value),
                    child: Text('$value'),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Нижняя шторка со списком действий над элементом.
Future<void> showActionSheet(
  BuildContext context, {
  required String title,
  required List<Widget> Function(BuildContext sheetContext) actions,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ...actions(sheetContext),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
