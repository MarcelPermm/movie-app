import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/trip_repository.dart';
import '../models/json.dart';
import '../models/trip.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/stats.dart';

/// Экран поездки: сколько заложено, сколько ушло и на что.
///
/// Траты сгруппированы по датам — в поездке это единственная группировка,
/// которая имеет смысл: вспоминаешь не «сколько на еду за всё», а «что было
/// во второй день».
class TripDetailScreen extends StatefulWidget {
  final int tripId;

  const TripDetailScreen({super.key, required this.tripId});

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TripRepository>().loadExpenses(widget.tripId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<TripRepository>();
    final trip = repo.tripById(widget.tripId);

    if (trip == null) {
      return const Scaffold(
        body: EmptyHint(emoji: '🧳', text: 'Поездка не найдена'),
      );
    }

    final expenses = repo.expensesOf(trip.id);
    final byDate = _groupByDate(expenses);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(trip.emoji, style: const TextStyle(fontSize: 19)),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                trip.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Добавить трату',
            icon: const Icon(Icons.add, color: AppColors.gold),
            onPressed: () => _addExpense(trip),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.gold,
        backgroundColor: AppColors.surface,
        onRefresh: () =>
            context.read<TripRepository>().loadExpenses(trip.id, forceRefresh: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
          children: [
            _buildSummary(trip, expenses),
            const SizedBox(height: 18),
            if (expenses.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Text(
                  'Трат пока нет.\nДобавь первую — кнопкой сверху',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textDim, fontSize: 14, height: 1.6),
                ),
              )
            else
              ...byDate.entries.map((entry) => _buildDay(entry.key, entry.value)),
          ],
        ),
      ),
    );
  }

  /// Траты по датам, свежие сверху.
  Map<String, List<TripExpense>> _groupByDate(List<TripExpense> expenses) {
    final map = <String, List<TripExpense>>{};
    for (final e in expenses) {
      map.putIfAbsent(e.date, () => []).add(e);
    }
    final keys = map.keys.toList()..sort((a, b) => b.compareTo(a));
    return {for (final k in keys) k: map[k]!};
  }

  Widget _buildSummary(Trip trip, List<TripExpense> expenses) {
    final planned = trip.plannedTotal;
    final spent = expenses.fold<int>(0, (sum, e) => sum + e.amount);
    // План по отдельным тратам: то, что записали заранее, но ещё не оплатили.
    final reserved = expenses
        .where((e) => !e.isPaid)
        .fold<int>(0, (sum, e) => sum + (e.plannedAmount ?? 0));

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: StatTile(
                value: formatMoney(spent),
                label: 'потрачено',
                color: trip.overspent ? AppColors.red : AppColors.gold,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                value: planned > 0 ? formatMoney(planned - spent) : '—',
                label: 'осталось',
                color: AppColors.green,
              ),
            ),
            if (reserved > 0) ...[
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  value: formatMoney(reserved),
                  label: 'запланировано',
                  color: AppColors.blue,
                ),
              ),
            ],
          ],
        ),
        if (planned > 0) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      trip.dateLabel,
                      style: const TextStyle(color: AppColors.textDim, fontSize: 12.5),
                    ),
                    const Spacer(),
                    Text(
                      'план ${formatMoney(planned)}',
                      style: const TextStyle(color: AppColors.textDim, fontSize: 12.5),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (spent / planned).clamp(0.0, 1.0),
                    minHeight: 7,
                    backgroundColor: AppColors.bg,
                    valueColor: AlwaysStoppedAnimation(
                      trip.overspent ? AppColors.red : AppColors.gold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDay(String date, List<TripExpense> expenses) {
    final total = expenses.fold<int>(0, (sum, e) => sum + e.amount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
          child: Row(
            children: [
              Text(_dayLabel(date), style: kEyebrowStyle),
              const Spacer(),
              Text(
                formatMoney(total),
                style: const TextStyle(
                  color: AppColors.textDim,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        ...expenses.map(_buildExpenseTile),
      ],
    );
  }

  static const _months = [
    'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
  ];

  String _dayLabel(String date) {
    final d = parseDate(date);
    if (d == null) return date;
    return '${d.day} ${_months[d.month - 1]}';
  }

  Widget _buildExpenseTile(TripExpense expense) {
    final planned = expense.plannedAmount;

    return Dismissible(
      key: ValueKey('trip-expense-${expense.id}'),
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
      onDismissed: (_) => context.read<TripRepository>().removeExpense(expense),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.small),
        onTap: () => _editExpense(expense),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                      style: const TextStyle(color: AppColors.text, fontSize: 14.5),
                    ),
                    if (expense.note.isNotEmpty || expense.city.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (expense.city.isNotEmpty) expense.city,
                          if (expense.note.isNotEmpty) expense.note,
                        ].join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textDim, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    expense.isPaid ? formatMoney(expense.amount) : '—',
                    style: TextStyle(
                      color: expense.isPaid ? AppColors.text : AppColors.textDim,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (planned != null && planned > 0)
                    Text(
                      'план ${formatMoney(planned)}',
                      style: const TextStyle(color: AppColors.textDim, fontSize: 11),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addExpense(Trip trip) async {
    final result = await showModalBottomSheet<_TripExpenseForm>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _TripExpenseSheet(
        initialDate: parseDate(trip.startDate) ?? DateTime.now(),
      ),
    );
    if (result == null || !mounted) return;

    await context.read<TripRepository>().addExpense(
          trip.id,
          amount: result.amount,
          plannedAmount: result.planned,
          date: result.date,
          category: result.category,
          note: result.note,
          city: result.city,
        );
  }

  Future<void> _editExpense(TripExpense expense) async {
    final result = await showModalBottomSheet<_TripExpenseForm>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _TripExpenseSheet(initial: expense),
    );
    if (result == null || !mounted) return;

    await context.read<TripRepository>().updateExpense(
          expense,
          amount: result.amount,
          plannedAmount: result.planned,
          category: result.category,
          note: result.note,
          city: result.city,
        );
  }
}

class _TripExpenseForm {
  final int amount;
  final int? planned;
  final DateTime date;
  final String category;
  final String note;
  final String city;

  const _TripExpenseForm({
    required this.amount,
    required this.date,
    this.planned,
    this.category = '',
    this.note = '',
    this.city = '',
  });
}

/// Ввод траты поездки. Отдельно сумма факта и сумма плана: в поездке сначала
/// записывают, сколько собираются потратить, и только потом — сколько вышло.
class _TripExpenseSheet extends StatefulWidget {
  final TripExpense? initial;
  final DateTime? initialDate;

  const _TripExpenseSheet({this.initial, this.initialDate});

  @override
  State<_TripExpenseSheet> createState() => _TripExpenseSheetState();
}

class _TripExpenseSheetState extends State<_TripExpenseSheet> {
  late final _amount = TextEditingController(
    text: (widget.initial?.amount ?? 0) > 0 ? '${widget.initial!.amount}' : '',
  );
  late final _planned = TextEditingController(
    text: (widget.initial?.plannedAmount ?? 0) > 0 ? '${widget.initial!.plannedAmount}' : '',
  );
  late final _category = TextEditingController(text: widget.initial?.category ?? '');
  late final _note = TextEditingController(text: widget.initial?.note ?? '');
  late final _city = TextEditingController(text: widget.initial?.city ?? '');

  late DateTime _date =
      parseDate(widget.initial?.date) ?? widget.initialDate ?? DateTime.now();

  static const _presets = [
    ('🏨', 'Жильё'),
    ('✈️', 'Дорога'),
    ('🍽️', 'Еда'),
    ('🎟️', 'Развлечения'),
    ('🚕', 'Транспорт'),
    ('🛍️', 'Покупки'),
  ];

  @override
  void dispose() {
    _amount.dispose();
    _planned.dispose();
    _category.dispose();
    _note.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _submit() {
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    final planned = int.tryParse(_planned.text.trim());
    // Пустая запись бессмысленна: либо потратили, либо запланировали.
    if (amount <= 0 && (planned == null || planned <= 0)) return;

    Navigator.pop(
      context,
      _TripExpenseForm(
        amount: amount,
        planned: planned,
        date: _date,
        category: _category.text.trim(),
        note: _note.text.trim(),
        city: _city.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              widget.initial == null ? 'Трата в поездке' : 'Изменить трату',
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amount,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: 'Потрачено, ₽',
                      prefixIcon: Icon(Icons.payments_outlined, size: 19),
                    ),
                    style: const TextStyle(color: AppColors.text, fontSize: 16),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _planned,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'План, ₽'),
                    style: const TextStyle(color: AppColors.text, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text('НА ЧТО', style: kEyebrowStyle),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presets.map((p) {
                final selected = _category.text.trim() == p.$2;
                return GestureDetector(
                  onTap: () => setState(() => _category.text = selected ? '' : p.$2),
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
                      '${p.$1} ${p.$2}',
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
            const SizedBox(height: 12),
            TextField(
              controller: _category,
              decoration: const InputDecoration(hintText: 'Или своё название'),
              style: const TextStyle(color: AppColors.text),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _city,
              decoration: const InputDecoration(
                hintText: 'Город',
                prefixIcon: Icon(Icons.place_outlined, size: 19),
              ),
              style: const TextStyle(color: AppColors.text),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              decoration: const InputDecoration(hintText: 'Комментарий'),
              style: const TextStyle(color: AppColors.text),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text(ymd(_date)),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                child: Text(widget.initial == null ? 'Добавить' : 'Сохранить'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
