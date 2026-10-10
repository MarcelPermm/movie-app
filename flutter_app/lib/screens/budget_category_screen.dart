import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/budget_repository.dart';
import '../models/budget.dart';
import '../models/json.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/stats.dart';

/// Одна категория за месяц: сколько ушло, из чего сложилось и как это
/// соотносится с планом.
///
/// Отдельный экран, а не раскрывающаяся строка: у категории вроде «еды»
/// за месяц набирается полсотни трат, и внутри общего списка они бы его
/// затопили.
class BudgetCategoryScreen extends StatelessWidget {
  final int categoryId;

  const BudgetCategoryScreen({super.key, required this.categoryId});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<BudgetRepository>();
    final category = repo.categoryById(categoryId);

    if (category == null) {
      return const Scaffold(body: EmptyHint(emoji: '💸', text: 'Категория не найдена'));
    }

    final own = repo.expenses.where((e) => e.categoryId == categoryId).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    // Траты поездок сюда не подмешиваются: у поездок свой блок и свой
    // план в бюджете, иначе одни и те же деньги считались бы дважды.
    final total = own.fold<int>(0, (sum, e) => sum + e.amount);
    final over = category.planMonthly > 0 && total > category.planMonthly;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(category.emoji, style: const TextStyle(fontSize: 19)),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                category.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Text(
                '${monthNames[repo.month.month - 1]} ${repo.month.year}',
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: StatTile(
                  value: formatMoney(total),
                  label: 'потрачено',
                  color: over ? AppColors.red : AppColors.gold,
                ),
              ),
              if (category.planMonthly > 0) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: StatTile(
                    value: formatMoney((category.planMonthly - total).abs()),
                    label: over ? 'перерасход' : 'остаток',
                    color: over ? AppColors.red : AppColors.green,
                  ),
                ),
              ],
            ],
          ),
          if (category.planMonthly > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (total / category.planMonthly).clamp(0.0, 1.0),
                minHeight: 7,
                backgroundColor: AppColors.sheet,
                valueColor: AlwaysStoppedAnimation(over ? AppColors.red : AppColors.gold),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'План ${formatMoney(category.planMonthly)} на месяц',
              style: TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ],

          if (own.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 60),
              child: Text(
                'В этой категории за месяц ничего нет',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textDim, fontSize: 14),
              ),
            ),

          if (own.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('ТРАТЫ МЕСЯЦА', style: kEyebrowStyle),
            const SizedBox(height: 10),
            ...own.map((e) => _ExpenseRow(expense: e)),
          ],
        ],
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  final Expense expense;

  const _ExpenseRow({required this.expense});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: cardDecoration(),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.text, fontSize: 14.5),
                ),
                const SizedBox(height: 3),
                Text(
                  _dayLabel(expense.date),
                  style: TextStyle(color: AppColors.textDim, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            formatMoney(expense.amount),
            style: TextStyle(
              color: AppColors.text,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

const _monthsShort = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

String _dayLabel(String date) {
  final d = parseDate(date);
  if (d == null) return date;
  return '${d.day} ${_monthsShort[d.month - 1]}';
}
