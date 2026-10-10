import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/budget_repository.dart';
import '../models/budget.dart';
import '../models/json.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/stats.dart';
import 'budget_category_screen.dart';

/// Бюджет месяца: сколько ушло, по каким категориям и на что конкретно.
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
            const SizedBox(width: 6),
            PopupMenuButton<String>(
              tooltip: 'Ещё',
              icon: const Icon(Icons.more_horiz, color: AppColors.textDim),
              onSelected: (value) {
                if (value == 'category') _addCategory();
                if (value == 'clear') _clearMonth();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'category', child: Text('Новая категория')),
                PopupMenuItem(value: 'clear', child: Text('Очистить месяц')),
              ],
            ),
            const SizedBox(width: 4),
            AddButton(onPressed: () => _addExpense(), tooltip: 'Новая трата'),
          ],
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.gold,
            backgroundColor: AppColors.surface,
            onRefresh: () => context.read<BudgetRepository>().refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
              children: [
                _buildTotal(repo),
                if (repo.categories.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _buildCategories(repo),
                ],
                const SizedBox(height: 8),
                _buildExpenses(repo),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── Итог месяца ────────────────────────────────────────────────────

  Widget _buildTotal(BudgetRepository repo) {
    final planned = repo.plannedTotal;
    final overspent = planned > 0 && repo.total > planned;
    final left = planned - repo.total;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: StatTile(
                value: formatMoney(repo.total),
                label: 'потрачено',
                color: overspent ? AppColors.red : AppColors.gold,
              ),
            ),
            if (planned > 0) ...[
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  value: formatMoney(left.abs()),
                  label: overspent ? 'перерасход' : 'остаток',
                  color: overspent ? AppColors.red : AppColors.green,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  value: formatMoney(planned),
                  label: 'план',
                  color: AppColors.blue,
                ),
              ),
            ],
          ],
        ),
        if (planned > 0) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (repo.total / planned).clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: AppColors.surface,
              valueColor: AlwaysStoppedAnimation(overspent ? AppColors.red : AppColors.gold),
            ),
          ),
        ],
        // Итог месяца включает поездки — иначе он занижен и вводит в
        // заблуждение. Но откуда взялась разница, надо сказать прямо.
        if (repo.tripTotal > 0) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.flight_takeoff, size: 14, color: AppColors.blue),
              const SizedBox(width: 7),
              Text(
                'из них ${formatMoney(repo.tripTotal)} в поездках',
                style: const TextStyle(color: AppColors.blue, fontSize: 12),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ─── Категории ──────────────────────────────────────────────────────

  Widget _buildCategories(BudgetRepository repo) {
    final planned = repo.plannedCategories;
    final unplanned = repo.unplannedCategories;

    // Категории без плана и без трат не показываем вовсе: пустые строки
    // с нулями только зашумляют экран.
    if (planned.isEmpty && unplanned.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'По категориям',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(onPressed: _addCategory, child: const Text('Добавить')),
            ],
          ),
          const SizedBox(height: 4),
          ...planned.map((c) => _buildCategoryRow(repo, c)),

          // Траты есть, а плана нет — деньги не должны пропадать из виду,
          // но и мешаться среди плановых им незачем.
          if (unplanned.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('БЕЗ ПЛАНА', style: kEyebrowStyle),
            const SizedBox(height: 4),
            ...unplanned.map((c) => _buildCategoryRow(repo, c)),
          ],

          if (repo.uncategorized > 0) ...[
            const Divider(height: 22),
            Row(
              children: [
                const Text('💸', style: TextStyle(fontSize: 15)),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    'Без категории',
                    style: TextStyle(color: AppColors.textDim, fontSize: 13.5),
                  ),
                ),
                Text(
                  formatMoney(repo.uncategorized),
                  style: const TextStyle(color: AppColors.textDim, fontSize: 12.5),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryRow(BudgetRepository repo, BudgetCategory c) {
    final value = repo.spentByCategory[c.id] ?? 0;
    final fromTrips = repo
        .tripSpendingOf(c.id)
        .fold<int>(0, (sum, t) => sum + t.expense.amount);
    final over = c.planMonthly > 0 && value > c.planMonthly;

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.small),
      // Нажатие открывает категорию со всеми её тратами. Раньше оно сразу
      // заводило новую — оказалось, что заглянуть внутрь нужнее.
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BudgetCategoryScreen(categoryId: c.id)),
      ),
      onLongPress: () => _categoryMenu(c),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(c.emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.text, fontSize: 14),
                  ),
                ),
                // Отмечаем, что часть суммы пришла из поездки, — иначе
                // непонятно, откуда взялось расхождение со списком трат.
                if (fromTrips > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: AppColors.blue.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      '✈ ${formatMoney(fromTrips)}',
                      style: const TextStyle(
                        color: AppColors.blue,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                Text(
                  c.planMonthly > 0
                      ? '${formatMoney(value)} / ${formatMoney(c.planMonthly)}'
                      : formatMoney(value),
                  style: TextStyle(
                    color: over ? AppColors.red : AppColors.textDim,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 17, color: AppColors.textDim),
              ],
            ),
            if (c.planMonthly > 0) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (value / c.planMonthly).clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: AppColors.bg,
                  valueColor: AlwaysStoppedAnimation(over ? AppColors.red : AppColors.goldDim),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Траты ──────────────────────────────────────────────────────────

  Widget _buildExpenses(BudgetRepository repo) {
    if (repo.expenses.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 44),
        child: Column(
          children: [
            const Text('💸', style: TextStyle(fontSize: 34)),
            const SizedBox(height: 12),
            const Text(
              'Трат за этот месяц пока нет',
              style: TextStyle(color: AppColors.textDim, fontSize: 14),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _addExpense(),
              icon: const Icon(Icons.add, size: 19),
              label: const Text('Добавить первую'),
            ),
          ],
        ),
      );
    }

    final grouped = repo.expensesGrouped;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: grouped.entries.map((entry) {
        final dayTotal = entry.value.fold<int>(0, (sum, e) => sum + e.amount);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 20, 2, 8),
              child: Row(
                children: [
                  Text(_dayLabel(entry.key), style: kEyebrowStyle),
                  const Spacer(),
                  Text(
                    formatMoney(dayTotal),
                    style: const TextStyle(
                      color: AppColors.textDim,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            ...entry.value.map((e) => _buildExpenseTile(repo, e)),
          ],
        );
      }).toList(),
    );
  }

  static const _months = [
    'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
  ];

  String _dayLabel(String date) {
    final d = parseDate(date);
    if (d == null) return date;

    final today = DateTime.now();
    final isToday = d.year == today.year && d.month == today.month && d.day == today.day;
    final yesterday = today.subtract(const Duration(days: 1));
    final isYesterday =
        d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day;

    if (isToday) return 'сегодня';
    if (isYesterday) return 'вчера';
    return '${d.day} ${_months[d.month - 1]}';
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
          borderRadius: BorderRadius.circular(AppRadius.small),
        ),
        child: const Icon(Icons.delete_outline, color: AppColors.red),
      ),
      onDismissed: (_) => context.read<BudgetRepository>().removeExpense(expense),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.small),
        onTap: () => _editExpense(expense),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: cardDecoration(),
          child: Row(
            children: [
              Text(category?.emoji ?? '💸', style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      expense.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.text, fontSize: 14.5),
                    ),
                    if (category != null || (expense.note?.isNotEmpty ?? false)) ...[
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (category != null) category.name,
                          if (expense.merchant != null && (expense.note?.isNotEmpty ?? false))
                            expense.note!,
                        ].join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textDim, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                formatMoney(expense.amount),
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Действия ───────────────────────────────────────────────────────

  Future<void> _addExpense({int? categoryId}) async {
    final repo = context.read<BudgetRepository>();

    final result = await showModalBottomSheet<_ExpenseForm>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _ExpenseSheet(
        repo: repo,
        presetCategoryId: categoryId,
        // Месяц открыт не текущий — логичнее подставить его первое число,
        // чем сегодняшнюю дату из другого месяца.
        initialDate: _defaultDate(repo),
      ),
    );
    if (result == null || !mounted) return;

    await repo.addExpense(
      amount: result.amount,
      date: result.date,
      categoryId: result.categoryId,
      merchant: result.merchant.isEmpty ? null : result.merchant,
      note: result.note.isEmpty ? null : result.note,
    );
  }

  DateTime _defaultDate(BudgetRepository repo) {
    final now = DateTime.now();
    final sameMonth = repo.month.year == now.year && repo.month.month == now.month;
    return sameMonth ? now : DateTime(repo.month.year, repo.month.month);
  }

  Future<void> _editExpense(Expense expense) async {
    final repo = context.read<BudgetRepository>();

    final result = await showModalBottomSheet<_ExpenseForm>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _ExpenseSheet(repo: repo, initial: expense),
    );
    if (result == null || !mounted) return;

    await repo.updateExpense(
      expense,
      amount: result.amount,
      categoryId: result.categoryId,
      merchant: result.merchant,
      note: result.note,
    );
  }

  Future<void> _addCategory() async {
    final result = await showDialog<_CategoryForm>(
      context: context,
      builder: (_) => const _CategoryDialog(),
    );
    if (result == null || !mounted) return;

    await context.read<BudgetRepository>().addCategory(
          result.name,
          emoji: result.emoji,
          planMonthly: result.plan,
        );
  }

  void _categoryMenu(BudgetCategory category) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: AppColors.gold),
              title: const Text('Изменить категорию'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final result = await showDialog<_CategoryForm>(
                  context: context,
                  builder: (_) => _CategoryDialog(initial: category),
                );
                if (result == null || !mounted) return;
                await context.read<BudgetRepository>().updateCategory(
                      category,
                      name: result.name,
                      emoji: result.emoji,
                      planMonthly: result.plan,
                    );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.red),
              title: const Text('Удалить категорию'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final ok = await confirmDelete(context, 'Категория «${category.name}»');
                if (!ok || !mounted) return;
                await context.read<BudgetRepository>().removeCategory(category);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearMonth() async {
    final repo = context.read<BudgetRepository>();
    final ok = await confirmDelete(
      context,
      'Все траты за ${monthNames[repo.month.month - 1].toLowerCase()} ${repo.month.year}. '
      'Категории и планы останутся.',
    );
    if (!ok || !mounted) return;
    await repo.clearMonth();
  }
}

// ─── Форма траты ──────────────────────────────────────────────────────

class _ExpenseForm {
  final int amount;
  final DateTime date;
  final int? categoryId;
  final String merchant;
  final String note;

  const _ExpenseForm({
    required this.amount,
    required this.date,
    this.categoryId,
    this.merchant = '',
    this.note = '',
  });
}

/// Ввод траты: сумма, дата, категория, место и комментарий.
///
/// Шторка, а не диалог: на телефоне под ней остаётся клавиатура, и поля
/// не прыгают. Сумма в фокусе сразу — с неё всегда и начинают.
class _ExpenseSheet extends StatefulWidget {
  final BudgetRepository repo;
  final Expense? initial;
  final int? presetCategoryId;
  final DateTime? initialDate;

  const _ExpenseSheet({
    required this.repo,
    this.initial,
    this.presetCategoryId,
    this.initialDate,
  });

  @override
  State<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<_ExpenseSheet> {
  late final _amount = TextEditingController(
    text: widget.initial == null ? '' : '${widget.initial!.amount}',
  );
  late final _merchant = TextEditingController(text: widget.initial?.merchant ?? '');
  late final _note = TextEditingController(text: widget.initial?.note ?? '');

  late int? _categoryId = widget.initial?.categoryId ?? widget.presetCategoryId;
  late DateTime _date =
      parseDate(widget.initial?.date) ?? widget.initialDate ?? DateTime.now();

  List<String> _hints = const [];

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    _note.dispose();
    super.dispose();
  }

  void _onMerchantChanged(String value) {
    setState(() => _hints = value.trim().isEmpty ? const [] : widget.repo.merchantHints(value));
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _submit() {
    final amount = int.tryParse(_amount.text.trim().replaceAll(' ', ''));
    if (amount == null || amount <= 0) return;

    Navigator.pop(
      context,
      _ExpenseForm(
        amount: amount,
        date: _date,
        categoryId: _categoryId,
        merchant: _merchant.text.trim(),
        note: _note.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.repo.categories;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.initial == null ? 'Новая трата' : 'Изменить трату',
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),

            // Сумма крупно: это главное поле, и в него же попадает фокус.
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: '0',
                suffixText: '₽',
                suffixStyle: TextStyle(color: AppColors.textDim, fontSize: 20),
              ),
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
              onSubmitted: (_) => _submit(),
            ),

            const SizedBox(height: 16),
            const Text('КАТЕГОРИЯ', style: kEyebrowStyle),
            const SizedBox(height: 8),
            if (categories.isEmpty)
              const Text(
                'Категорий пока нет — трату можно записать и без неё',
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: categories.map((c) {
                  final selected = _categoryId == c.id;
                  return GestureDetector(
                    onTap: () => setState(() => _categoryId = selected ? null : c.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: selected ? AppColors.goldGradient : null,
                        color: selected ? null : AppColors.bg,
                        border: Border.all(
                          color: selected ? Colors.transparent : AppColors.border,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        '${c.emoji} ${c.name}',
                        style: TextStyle(
                          color: selected ? AppColors.bg : AppColors.text,
                          fontSize: 12.5,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

            const SizedBox(height: 16),
            TextField(
              controller: _merchant,
              onChanged: _onMerchantChanged,
              decoration: const InputDecoration(
                hintText: 'Где — магазин, кафе, сервис',
                prefixIcon: Icon(Icons.storefront_outlined, size: 19),
              ),
              style: const TextStyle(color: AppColors.text),
            ),
            // Подсказки из истории: чаще всего тратят там же, где и вчера.
            if (_hints.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: _hints
                    .map((h) => GestureDetector(
                          onTap: () => setState(() {
                            _merchant.text = h;
                            _hints = const [];
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.bg,
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                            ),
                            child: Text(
                              h,
                              style: const TextStyle(color: AppColors.textDim, fontSize: 12),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],

            const SizedBox(height: 10),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                hintText: 'Комментарий',
                prefixIcon: Icon(Icons.notes_outlined, size: 19),
              ),
              style: const TextStyle(color: AppColors.text),
              onSubmitted: (_) => _submit(),
            ),

            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text(_dateLabel()),
            ),

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                child: Text(widget.initial == null ? 'Добавить трату' : 'Сохранить'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _dateLabel() {
    final now = DateTime.now();
    if (_date.year == now.year && _date.month == now.month && _date.day == now.day) {
      return 'Сегодня';
    }
    return '${_date.day} ${monthNames[_date.month - 1].toLowerCase()} ${_date.year}';
  }
}

// ─── Форма категории ──────────────────────────────────────────────────

class _CategoryForm {
  final String name;
  final String emoji;
  final int plan;

  const _CategoryForm({required this.name, required this.emoji, required this.plan});
}

class _CategoryDialog extends StatefulWidget {
  final BudgetCategory? initial;

  const _CategoryDialog({this.initial});

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _plan = TextEditingController(
    text: (widget.initial?.planMonthly ?? 0) > 0 ? '${widget.initial!.planMonthly}' : '',
  );
  late String _emoji = widget.initial?.emoji ?? '💰';

  static const _emojis = [
    '🛒', '🍽️', '🚕', '🏠', '💊', '👕',
    '🎬', '📚', '🎁', '💇', '🐾', '💰',
  ];

  @override
  void dispose() {
    _name.dispose();
    _plan.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(
      context,
      _CategoryForm(
        name: name,
        emoji: _emoji,
        plan: int.tryParse(_plan.text.trim()) ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        widget.initial == null ? 'Новая категория' : 'Изменить категорию',
        style: const TextStyle(color: AppColors.text, fontSize: 17),
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Название'),
              style: const TextStyle(color: AppColors.text),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 14),
            const Text('ЗНАЧОК', style: kEyebrowStyle),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _emojis.map((e) {
                final selected = e == _emoji;
                return GestureDetector(
                  onTap: () => setState(() => _emoji = e),
                  child: Container(
                    height: 38,
                    width: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.goldWash(0.2) : AppColors.bg,
                      border: Border.all(color: selected ? AppColors.gold : AppColors.border),
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    child: Text(e, style: const TextStyle(fontSize: 18)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _plan,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'План на месяц, ₽ — необязательно'),
              style: const TextStyle(color: AppColors.text),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена', style: TextStyle(color: AppColors.textDim)),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.initial == null ? 'Добавить' : 'Сохранить'),
        ),
      ],
    );
  }
}
