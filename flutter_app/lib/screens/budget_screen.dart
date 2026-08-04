import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/budget_repository.dart';
import '../models/budget.dart';
import '../theme.dart';
import '../widgets/common.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BudgetRepository>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<BudgetRepository>();

    return Column(
      children: [
        SectionHeader(
          title: 'Бюджет',
          subtitle: '${repo.expenses.length} трат за месяц',
          actions: [
            PeriodStepper(
              label: '${monthNames[repo.month.month - 1]} ${repo.month.year}',
              onPrev: () => context.read<BudgetRepository>().shiftMonth(-1),
              onNext: () => context.read<BudgetRepository>().shiftMonth(1),
            ),
            const SizedBox(width: 8),
            AddButton(onPressed: _addExpense, tooltip: 'Новая трата'),
          ],
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.gold,
            backgroundColor: AppColors.surface,
            onRefresh: () => context.read<BudgetRepository>().refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _buildTotal(repo),
                if (repo.categories.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _buildCategories(repo),
                ],
                const SizedBox(height: 18),
                _buildExpenses(repo),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTotal(BudgetRepository repo) {
    final planned = repo.plannedTotal;
    final overspent = planned > 0 && repo.total > planned;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Потрачено за месяц', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            formatMoney(repo.total),
            style: TextStyle(
              color: overspent ? AppColors.red : AppColors.gold,
              fontSize: 30,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (planned > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (repo.total / planned).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: AppColors.bg,
                valueColor: AlwaysStoppedAnimation(overspent ? AppColors.red : AppColors.gold),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              overspent
                  ? 'Перерасход ${formatMoney(repo.total - planned)} от плана ${formatMoney(planned)}'
                  : 'План ${formatMoney(planned)} · остаток ${formatMoney(planned - repo.total)}',
              style: TextStyle(
                color: overspent ? AppColors.red : AppColors.textDim,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategories(BudgetRepository repo) {
    final spent = repo.spentByCategory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'По категориям',
                style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(onPressed: _addCategory, child: const Text('Добавить')),
          ],
        ),
        const SizedBox(height: 4),
        ...repo.categories.map((c) {
          final value = spent[c.id] ?? 0;
          final over = c.planMonthly > 0 && value > c.planMonthly;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GestureDetector(
              onLongPress: () => _deleteCategory(c),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(c.emoji, style: const TextStyle(fontSize: 15)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          c.name,
                          style: const TextStyle(color: AppColors.text, fontSize: 14),
                        ),
                      ),
                      Text(
                        c.planMonthly > 0
                            ? '${formatMoney(value)} / ${formatMoney(c.planMonthly)}'
                            : formatMoney(value),
                        style: TextStyle(
                          color: over ? AppColors.red : AppColors.textDim,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  if (c.planMonthly > 0) ...[
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (value / c.planMonthly).clamp(0.0, 1.0),
                        minHeight: 4,
                        backgroundColor: AppColors.surface,
                        valueColor: AlwaysStoppedAnimation(over ? AppColors.red : AppColors.goldDim),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildExpenses(BudgetRepository repo) {
    if (repo.expenses.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Text(
          'Трат за этот месяц пока нет',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textDim, fontSize: 14),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Траты',
          style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ...repo.expenses.map((e) => _buildExpenseTile(repo, e)),
      ],
    );
  }

  Widget _buildExpenseTile(BudgetRepository repo, Expense expense) {
    final category = repo.categoryById(expense.categoryId);

    return Dismissible(
      key: ValueKey('expense-${expense.id}'),
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
      onDismissed: (_) => context.read<BudgetRepository>().removeExpense(expense),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          dense: true,
          leading: Text(category?.emoji ?? '💸', style: const TextStyle(fontSize: 18)),
          title: Text(
            expense.label,
            style: const TextStyle(color: AppColors.text, fontSize: 14),
          ),
          subtitle: Text(
            [
              expense.date,
              if (category != null) category.name,
            ].join('  ·  '),
            style: const TextStyle(color: AppColors.textDim, fontSize: 12),
          ),
          trailing: Text(
            formatMoney(expense.amount),
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addExpense() async {
    final repo = context.read<BudgetRepository>();
    final result = await showDialog<(int, String, int?)>(
      context: context,
      builder: (dialogContext) => _ExpenseDialog(categories: repo.categories),
    );
    if (result == null || !mounted) return;
    await repo.addExpense(
      amount: result.$1,
      merchant: result.$2.isEmpty ? null : result.$2,
      categoryId: result.$3,
    );
  }

  Future<void> _addCategory() async {
    final name = await promptText(context, title: 'Новая категория', hint: 'Название');
    if (name == null || name.isEmpty || !mounted) return;

    final plan = await promptText(
      context,
      title: 'План на месяц',
      hint: 'Сумма в рублях, можно пропустить',
      keyboardType: TextInputType.number,
      confirmLabel: 'Готово',
    );
    if (!mounted) return;
    await context.read<BudgetRepository>().addCategory(
          name,
          planMonthly: int.tryParse(plan ?? '') ?? 0,
        );
  }

  Future<void> _deleteCategory(BudgetCategory category) async {
    final ok = await confirmDelete(context, 'Категория «${category.name}»');
    if (!ok || !mounted) return;
    await context.read<BudgetRepository>().removeCategory(category);
  }
}

/// Ввод траты: сумма, описание и категория.
class _ExpenseDialog extends StatefulWidget {
  final List<BudgetCategory> categories;
  const _ExpenseDialog({required this.categories});

  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  final _amount = TextEditingController();
  final _label = TextEditingController();
  int? _categoryId;

  @override
  void dispose() {
    _amount.dispose();
    _label.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = int.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) return;
    Navigator.pop(context, (amount, _label.text.trim(), _categoryId));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Новая трата', style: TextStyle(color: AppColors.text, fontSize: 17)),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Сумма, ₽'),
              style: const TextStyle(color: AppColors.text),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _label,
              decoration: const InputDecoration(hintText: 'Где или на что'),
              style: const TextStyle(color: AppColors.text),
              onSubmitted: (_) => _submit(),
            ),
            if (widget.categories.isNotEmpty) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.categories.map((c) {
                    final selected = _categoryId == c.id;
                    return GestureDetector(
                      onTap: () => setState(() => _categoryId = selected ? null : c.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: selected ? AppColors.gold : AppColors.bg,
                          border: Border.all(color: selected ? AppColors.gold : AppColors.border),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          '${c.emoji} ${c.name}',
                          style: TextStyle(
                            color: selected ? AppColors.bg : AppColors.text,
                            fontSize: 12,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена', style: TextStyle(color: AppColors.textDim)),
        ),
        FilledButton(onPressed: _submit, child: const Text('Добавить')),
      ],
    );
  }
}
