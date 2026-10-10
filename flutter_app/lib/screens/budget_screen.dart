import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/budget_repository.dart';
import '../data/trip_repository.dart';
import '../models/budget.dart';
import '../models/json.dart';
import '../models/trip.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/stats.dart';
import 'budget_category_screen.dart';
import 'trip_detail_screen.dart';

/// Бюджет месяца: сколько ушло, по каким категориям и на что конкретно.
class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  /// Какие поездки раскрыты до городов.
  final Set<int> _expandedTrips = {};

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
          subtitle: _subtitle(repo),
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
                if (repo.tripLines.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _buildTrips(repo),
                ],
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

  String _subtitle(BudgetRepository repo) {
    final parts = ['${repo.expenses.length} трат'];
    final trips = repo.tripLines.length;
    if (trips > 0) parts.add('$trips ${trips == 1 ? 'поездка' : 'поездки'}');
    return '${parts.join(' + ')} за месяц';
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
        if (planned > 0 || repo.tripTotal > 0) ...[
          const SizedBox(height: 12),
          _SplitBar(
            regular: repo.ownTotal,
            trips: repo.tripTotal,
            capacity: planned > repo.total ? planned : repo.total,
            overspent: overspent,
          ),
          const SizedBox(height: 9),
          // Две части месяца живут по своим планам — показываем обе,
          // чтобы было видно, какая из них съела остаток.
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _LegendItem(
                color: AppColors.gold,
                label: 'повседневное',
                spent: repo.ownTotal,
                plan: repo.regularPlan,
              ),
              if (repo.tripTotal > 0 || repo.tripPlan > 0)
                _LegendItem(
                  color: AppColors.blue,
                  label: 'поездки',
                  spent: repo.tripTotal,
                  plan: repo.tripPlan,
                ),
            ],
          ),
        ],
      ],
    );
  }

  // ─── Поездки ────────────────────────────────────────────────────────

  Widget _buildTrips(BudgetRepository repo) {
    final lines = repo.tripLines;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flight_takeoff, size: 17, color: AppColors.blue),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Поездки',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                repo.tripPlan > 0
                    ? '${formatMoney(repo.tripTotal)} / ${formatMoney(repo.tripPlan)}'
                    : formatMoney(repo.tripTotal),
                style: TextStyle(
                  color: repo.tripPlan > 0 && repo.tripTotal > repo.tripPlan
                      ? AppColors.red
                      : AppColors.textDim,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const Divider(height: 14),
            _buildTripLine(lines[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildTripLine(TripBudgetLine line) {
    final trip = line.trip;
    final hasCities = line.cities.isNotEmpty;
    final expanded = _expandedTrips.contains(trip.id);
    final planText = line.plan > 0
        ? '${formatMoney(line.spent)} / ${formatMoney(line.plan)}'
        : formatMoney(line.spent);

    void openTrip() => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TripDetailScreen(tripId: trip.id)),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.small),
          // Нажатие раскрывает города, если они есть; иначе сразу в поездку.
          onTap: hasCities
              ? () => setState(() => expanded
                  ? _expandedTrips.remove(trip.id)
                  : _expandedTrips.add(trip.id))
              : openTrip,
          onLongPress: openTrip,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(trip.emoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            trip.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.text, fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              trip.dateLabel,
                              if (hasCities) _citiesLabel(line.cities.length),
                            ].join('  ·  '),
                            style: const TextStyle(color: AppColors.textDim, fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      planText,
                      style: TextStyle(
                        color: line.overspent ? AppColors.red : AppColors.textDim,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      hasCities
                          ? (expanded ? Icons.expand_less : Icons.expand_more)
                          : Icons.chevron_right,
                      size: 17,
                      color: AppColors.textDim,
                    ),
                  ],
                ),
                if (line.plan > 0) ...[
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: (line.spent / line.plan).clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: AppColors.bg,
                      valueColor: AlwaysStoppedAnimation(
                        line.overspent ? AppColors.red : AppColors.blue,
                      ),
                    ),
                  ),
                ],
                if (line.planCarried && line.fullPlan > 0) ...[
                  const SizedBox(height: 5),
                  Text(
                    'план ${formatMoney(line.fullPlan)} учтён в месяце начала поездки',
                    style: const TextStyle(color: AppColors.textDim, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (expanded) ...[
          ...line.cities.map((c) => _buildCityRow(c, showPlan: !line.planCarried)),
          if (line.byCategory.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildCategoryChips(line.byCategory),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: openTrip,
              icon: const Icon(Icons.open_in_new, size: 15),
              label: const Text('Открыть поездку'),
            ),
          ),
        ] else if (!hasCities && line.byCategory.length > 1) ...[
          _buildCategoryChips(line.byCategory),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _buildCityRow(TripCityLine c, {required bool showPlan}) {
    final plan = showPlan && c.plan > 0;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.small),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TripDetailScreen(tripId: c.city.parentId ?? c.city.id)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(25, 6, 21, 6),
        child: Row(
          children: [
            const Icon(Icons.place_outlined, size: 14, color: AppColors.textDim),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                c.city.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.text, fontSize: 13),
              ),
            ),
            const SizedBox(width: 7),
            Text(
              c.city.dateLabel,
              style: const TextStyle(color: AppColors.textDim, fontSize: 11.5),
            ),
            const Spacer(),
            Text(
              plan ? '${formatMoney(c.spent)} / ${formatMoney(c.plan)}' : formatMoney(c.spent),
              style: TextStyle(
                color: plan && c.overspent ? AppColors.red : AppColors.textDim,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// На что ушли деньги поездки — компактной строкой плашек.
  Widget _buildCategoryChips(Map<String, int> byCategory) {
    return Padding(
      padding: const EdgeInsets.only(left: 25),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: byCategory.entries.map((e) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              '${e.key} ${formatMoney(e.value)}',
              style: const TextStyle(color: AppColors.blue, fontSize: 11.5),
            ),
          );
        }).toList(),
      ),
    );
  }

  static String _citiesLabel(int n) {
    final mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 14) return '$n городов';
    switch (n % 10) {
      case 1:
        return '$n город';
      case 2:
      case 3:
      case 4:
        return '$n города';
      default:
        return '$n городов';
    }
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
    // План «Путешествий» заменён планом поездок — здесь его не показываем.
    final plan = BudgetRepository.isTravelCategory(c) ? 0 : c.planMonthly;
    final over = plan > 0 && value > plan;

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
                Text(
                  plan > 0
                      ? '${formatMoney(value)} / ${formatMoney(plan)}'
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
            if (plan > 0) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (value / plan).clamp(0.0, 1.0),
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
    final grouped = repo.entriesGrouped;
    if (grouped.isEmpty) {
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
            ...entry.value.map((e) => e.own != null
                ? _buildExpenseTile(repo, e.own!)
                : _buildTripExpenseTile(repo, e.trip!)),
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

  /// Трата поездки в общей ленте: синяя подпись с поездкой и городом.
  Widget _buildTripExpenseTile(BudgetRepository repo, TripSpending spending) {
    final expense = spending.expense;
    final where = repo.tripLabelOf(spending.tripId, fallback: spending.tripName);

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
      onDismissed: (_) async {
        await context.read<BudgetRepository>().removeTripExpense(spending);
        _syncTrips(spending.tripId);
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.small),
        onTap: () => _editTripSpending(spending),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: cardDecoration(),
          child: Row(
            children: [
              Text(spending.tripEmoji, style: const TextStyle(fontSize: 18)),
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
                    const SizedBox(height: 3),
                    Text(
                      [
                        '✈ $where',
                        if (expense.category.isNotEmpty && expense.note.isNotEmpty) expense.note,
                      ].join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.blue, fontSize: 12),
                    ),
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

  /// Куда можно записать трату: отдельные поездки и города многогородних.
  /// Берём поездки, задевающие открытый месяц, и ещё не закончившиеся —
  /// билеты на будущую поездку покупают заранее.
  List<_TripTarget> _tripTargets(BudgetRepository budget, {int? includeId}) {
    final trips = context.read<TripRepository>().trips;
    final byId = {for (final t in trips) t.id: t};
    final monthStart = budget.month;
    final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 0);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    bool relevant(Trip t) {
      if (t.id == includeId) return true;
      final a = parseDate(t.startDate);
      final b = parseDate(t.endDate) ?? a;
      if (a == null || b == null) return true;
      // Перепутанные даты (конец раньше начала) не должны прятать поездку.
      final lo = a.isBefore(b) ? a : b;
      final hi = a.isBefore(b) ? b : a;
      final overlaps = !hi.isBefore(monthStart) && !lo.isAfter(monthEnd);
      return overlaps || !hi.isBefore(today);
    }

    final targets = <_TripTarget>[];
    for (final t in trips) {
      // Ещё не сохранённую на сервере поездку пропускаем: тратам некуда лечь.
      if (t.isGroup || t.id < 0) continue;
      final parent = t.parentId == null ? null : byId[t.parentId];
      if (!relevant(t) && !(parent != null && relevant(parent))) continue;
      targets.add(_TripTarget(trip: t, parent: parent));
    }
    targets.sort((a, b) => (a.trip.startDate ?? '').compareTo(b.trip.startDate ?? ''));
    return targets;
  }

  _TripTarget? _targetById(List<_TripTarget> targets, int id) {
    for (final t in targets) {
      if (t.trip.id == id) return t;
    }
    return null;
  }

  /// Записать трату в поездку (в выбранный город).
  Future<void> _saveToTrip(_ExpenseForm result, List<_TripTarget> targets) async {
    final target = _targetById(targets, result.tripId!);
    if (target == null) return;
    await context.read<BudgetRepository>().addTripExpense(
          trip: target.trip,
          parent: target.parent,
          amount: result.amount,
          date: result.date,
          category: result.tripCategory,
          note: result.combinedNote,
        );
    _syncTrips(target.trip.id);
  }

  /// Экран поездок держит свой кэш трат — после правки из бюджета
  /// обновляем его, чтобы суммы там не отставали.
  void _syncTrips(int tripId) {
    if (!mounted) return;
    final trips = context.read<TripRepository>();
    final rootId = trips.tripById(tripId)?.parentId ?? tripId;
    trips.refresh().then((_) => trips.loadTree(rootId, forceRefresh: true));
  }

  Future<void> _editTripSpending(TripSpending spending) async {
    final repo = context.read<BudgetRepository>();
    final targets = _tripTargets(repo, includeId: spending.tripId);

    final result = await showModalBottomSheet<_ExpenseForm>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _ExpenseSheet(
        repo: repo,
        initialTrip: spending,
        tripTargets: targets,
      ),
    );
    if (result == null || !mounted) return;

    if (result.tripId == null) {
      // Трату вынесли из поездки в обычный бюджет месяца.
      await repo.removeTripExpense(spending);
      await repo.addExpense(
        amount: result.amount,
        date: result.date,
        categoryId: result.categoryId,
        merchant: result.merchant.isEmpty ? null : result.merchant,
        note: result.note.isEmpty ? null : result.note,
      );
      _syncTrips(spending.tripId);
      return;
    }
    if (result.tripId != spending.tripId) {
      // Перенесли в другой город или поездку.
      await repo.removeTripExpense(spending);
      _syncTrips(spending.tripId);
      if (!mounted) return;
      await _saveToTrip(result, targets);
      return;
    }
    await repo.updateTripExpense(
      spending,
      amount: result.amount,
      category: result.tripCategory,
      note: result.combinedNote,
      date: result.date,
    );
    _syncTrips(spending.tripId);
  }


  Future<void> _addExpense({int? categoryId}) async {
    final repo = context.read<BudgetRepository>();
    final targets = _tripTargets(repo);

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
        tripTargets: targets,
      ),
    );
    if (result == null || !mounted) return;

    if (result.tripId != null) {
      await _saveToTrip(result, targets);
      return;
    }

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
    final targets = _tripTargets(repo);

    final result = await showModalBottomSheet<_ExpenseForm>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _ExpenseSheet(repo: repo, initial: expense, tripTargets: targets),
    );
    if (result == null || !mounted) return;

    if (result.tripId != null) {
      // Обычную трату отнесли к поездке — переносим её туда.
      await repo.removeExpense(expense);
      if (!mounted) return;
      await _saveToTrip(result, targets);
      return;
    }
    await repo.updateExpense(
      expense,
      amount: result.amount,
      categoryId: result.categoryId,
      merchant: result.merchant,
      note: result.note,
      date: result.date,
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

  /// Поездка или город, куда записать трату. null — обычный бюджет.
  final int? tripId;

  /// Статья траты в поездке: «Жильё», «Еда»…
  final String tripCategory;

  const _ExpenseForm({
    required this.amount,
    required this.date,
    this.categoryId,
    this.merchant = '',
    this.note = '',
    this.tripId,
    this.tripCategory = '',
  });

  /// У трат поездки нет поля «где» — оно уходит в комментарий, как на сайте.
  String get combinedNote =>
      [merchant, note].where((s) => s.trim().isNotEmpty).join(' · ');
}

/// Куда можно отнести трату: поездка или город многогородней поездки.
class _TripTarget {
  final Trip trip;
  final Trip? parent;

  const _TripTarget({required this.trip, this.parent});

  String get label => parent == null ? trip.name : '${parent!.name} · ${trip.name}';
  String get emoji => parent?.emoji ?? trip.emoji;
}

/// Ввод траты: сумма, дата, категория, место и комментарий.
///
/// Шторка, а не диалог: на телефоне под ней остаётся клавиатура, и поля
/// не прыгают. Сумма в фокусе сразу — с неё всегда и начинают.
class _ExpenseSheet extends StatefulWidget {
  final BudgetRepository repo;
  final Expense? initial;

  /// Правим трату поездки, а не обычную.
  final TripSpending? initialTrip;

  final int? presetCategoryId;
  final DateTime? initialDate;

  /// Поездки и города, к которым можно отнести трату.
  final List<_TripTarget> tripTargets;

  const _ExpenseSheet({
    required this.repo,
    this.initial,
    this.initialTrip,
    this.presetCategoryId,
    this.initialDate,
    this.tripTargets = const [],
  });

  @override
  State<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<_ExpenseSheet> {
  late final _amount = TextEditingController(
    text: widget.initial != null
        ? '${widget.initial!.amount}'
        : widget.initialTrip != null
            ? '${widget.initialTrip!.expense.amount}'
            : '',
  );
  late final _merchant = TextEditingController(text: widget.initial?.merchant ?? '');
  late final _note = TextEditingController(
    text: widget.initial?.note ?? widget.initialTrip?.expense.note ?? '',
  );

  late int? _categoryId = widget.initial?.categoryId ?? widget.presetCategoryId;
  late DateTime _date = parseDate(widget.initial?.date) ??
      parseDate(widget.initialTrip?.expense.date) ??
      widget.initialDate ??
      DateTime.now();

  late int? _tripId = widget.initialTrip?.tripId;
  late String _tripCategory = widget.initialTrip?.expense.category ?? '';

  static const _tripPresets = [
    ('🏨', 'Жильё'),
    ('✈️', 'Дорога'),
    ('🍽️', 'Еда'),
    ('🎟️', 'Развлечения'),
    ('🚕', 'Транспорт'),
    ('🛍️', 'Покупки'),
  ];

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
        tripId: _tripId,
        tripCategory: _tripCategory,
      ),
    );
  }

  Widget _chip({
    required String text,
    required bool selected,
    required VoidCallback onTap,
    bool accent = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected && !accent ? AppColors.goldGradient : null,
          color: selected
              ? (accent ? AppColors.blue.withValues(alpha: 0.22) : null)
              : AppColors.bg,
          border: Border.all(
            color: selected
                ? (accent ? AppColors.blue : Colors.transparent)
                : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: selected ? (accent ? AppColors.blue : AppColors.bg) : AppColors.text,
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  /// Куда записать: обычный бюджет или поездка с городом.
  Widget _buildTripPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text('ПОЕЗДКА', style: kEyebrowStyle),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(
              text: 'Без поездки',
              selected: _tripId == null,
              onTap: () => setState(() => _tripId = null),
            ),
            ...widget.tripTargets.map((t) => _chip(
                  text: '${t.emoji} ${t.label}',
                  selected: _tripId == t.trip.id,
                  accent: true,
                  onTap: () => setState(() => _tripId = t.trip.id),
                )),
          ],
        ),
      ],
    );
  }

  /// Статьи поездки вместо категорий месяца: у поездки свой план.
  Widget _buildTripCategories() {
    final presets = _tripPresets.map((p) => p.$2).toSet();
    final custom = _tripCategory.trim();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ..._tripPresets.map((p) => _chip(
              text: '${p.$1} ${p.$2}',
              selected: _tripCategory == p.$2,
              onTap: () => setState(() => _tripCategory = _tripCategory == p.$2 ? '' : p.$2),
            )),
        if (custom.isNotEmpty && !presets.contains(custom))
          _chip(text: custom, selected: true, onTap: () => setState(() => _tripCategory = '')),
      ],
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
              widget.initial == null && widget.initialTrip == null
                  ? 'Новая трата'
                  : 'Изменить трату',
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

            if (widget.tripTargets.isNotEmpty) _buildTripPicker(),

            const SizedBox(height: 16),
            Text(_tripId == null ? 'КАТЕГОРИЯ' : 'НА ЧТО', style: kEyebrowStyle),
            const SizedBox(height: 8),
            if (_tripId != null)
              _buildTripCategories()
            else if (categories.isEmpty)
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
                child: Text(
                  widget.initial == null && widget.initialTrip == null
                      ? 'Добавить трату'
                      : 'Сохранить',
                ),
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

/// Полоса месяца из двух частей: повседневное и поездки.
class _SplitBar extends StatelessWidget {
  final int regular;
  final int trips;
  final int capacity;
  final bool overspent;

  const _SplitBar({
    required this.regular,
    required this.trips,
    required this.capacity,
    required this.overspent,
  });

  @override
  Widget build(BuildContext context) {
    final cap = capacity <= 0 ? 1 : capacity;
    final free = cap - regular - trips;
    final rest = free > 0 ? free : 0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 7,
        color: AppColors.surface,
        child: Row(
          children: [
            if (regular > 0)
              Expanded(
                flex: regular,
                child: Container(color: overspent ? AppColors.red : AppColors.gold),
              ),
            if (regular > 0 && trips > 0) const SizedBox(width: 2),
            if (trips > 0)
              Expanded(
                flex: trips,
                child: Container(
                  color: overspent ? AppColors.red.withValues(alpha: 0.7) : AppColors.blue,
                ),
              ),
            if (rest > 0) Expanded(flex: rest, child: const SizedBox()),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final int spent;
  final int plan;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.spent,
    required this.plan,
  });

  @override
  Widget build(BuildContext context) {
    final over = plan > 0 && spent > plan;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text(
          plan > 0
              ? '$label ${formatMoney(spent)} / ${formatMoney(plan)}'
              : '$label ${formatMoney(spent)}',
          style: TextStyle(color: over ? AppColors.red : AppColors.textDim, fontSize: 12),
        ),
      ],
    );
  }
}
