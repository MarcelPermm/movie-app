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
/// Многогородняя поездка (на сервере — группа) показывается как на сайте:
/// сверху сводка по статьям за всю поездку, ниже — каждый город со своим
/// планом и тратами. У обычной поездки траты разбиваются по городам из
/// поля «город», если оно заполнено, иначе — по датам.
class TripDetailScreen extends StatefulWidget {
  final int tripId;

  const TripDetailScreen({super.key, required this.tripId});

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  bool _busy = false;

  /// Свёрнутые города — их траты спрятаны, виден только заголовок.
  final Set<String> _collapsed = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TripRepository>().loadTree(widget.tripId);
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

    final cities = trip.isGroup ? repo.citiesOf(trip.id) : const <Trip>[];
    final expenses = repo.expensesOfTree(trip);
    final planned = repo.plannedOf(trip);

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
          if (_busy)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
              ),
            ),
          IconButton(
            tooltip: 'Изменить поездку',
            icon: Icon(Icons.edit_outlined, color: AppColors.textDim),
            onPressed: () => _editTrip(trip),
          ),
          IconButton(
            tooltip: 'Добавить город',
            icon: Icon(Icons.add_location_alt_outlined, color: AppColors.textDim),
            onPressed: _busy ? null : () => _addCity(trip),
          ),
          IconButton(
            tooltip: 'Добавить трату',
            icon: Icon(Icons.add, color: AppColors.gold),
            onPressed: () => _addExpense(trip, cities),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.gold,
        backgroundColor: AppColors.sheet,
        onRefresh: () =>
            context.read<TripRepository>().loadTree(trip.id, forceRefresh: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
          children: [
            _buildSummary(trip, expenses, planned),
            if (expenses.any((e) => e.isPaid)) ...[
              const SizedBox(height: 14),
              _buildCategories(expenses),
            ],
            const SizedBox(height: 8),
            if (trip.isGroup)
              ..._buildCityBlocks(repo, trip, cities)
            else if (expenses.isEmpty)
              Padding(
                padding: EdgeInsets.only(top: 40),
                child: Text(
                  'Трат пока нет.\nДобавь первую — кнопкой сверху',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textDim, fontSize: 14, height: 1.6),
                ),
              )
            else
              ..._buildSingleTrip(expenses),
          ],
        ),
      ),
    );
  }

  // ─── Сводка ─────────────────────────────────────────────────────────

  Widget _buildSummary(Trip trip, List<TripExpense> expenses, int planned) {
    final spent = expenses.fold<int>(0, (sum, e) => sum + e.amount);
    final overspent = planned > 0 && spent > planned;
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
                color: overspent ? AppColors.red : AppColors.gold,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                value: planned > 0 ? formatMoney((planned - spent).abs()) : '—',
                label: overspent ? 'перерасход' : 'осталось',
                color: overspent ? AppColors.red : AppColors.green,
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
                      style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
                    ),
                    const Spacer(),
                    Text(
                      'план ${formatMoney(planned)}',
                      style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
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
                      overspent ? AppColors.red : AppColors.gold,
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

  /// Сводка по статьям за всю поездку: куда ушли деньги.
  Widget _buildCategories(List<TripExpense> expenses) {
    final sums = <String, int>{};
    for (final e in expenses.where((e) => e.isPaid)) {
      final key = e.category.trim().isEmpty ? 'Прочее' : e.category.trim();
      sums[key] = (sums[key] ?? 0) + e.amount;
    }
    final entries = sums.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final max = entries.first.value;
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ПО СТАТЬЯМ', style: kEyebrowStyle),
          const SizedBox(height: 8),
          ...entries.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.key,
                            style: TextStyle(color: AppColors.text, fontSize: 13.5),
                          ),
                        ),
                        Text(
                          '${formatMoney(e.value)}  ·  ${(e.value * 100 / total).round()}%',
                          style: TextStyle(color: AppColors.textDim, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: e.value / max,
                        minHeight: 4,
                        backgroundColor: AppColors.bg,
                        valueColor: AlwaysStoppedAnimation(AppColors.blue),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ─── Города ─────────────────────────────────────────────────────────

  List<Widget> _buildCityBlocks(TripRepository repo, Trip group, List<Trip> cities) {
    final direct = repo.expensesOf(group.id);
    return [
      if (cities.isEmpty)
        Padding(
          padding: EdgeInsets.only(top: 30),
          child: Text(
            'В поездке пока нет городов.\nДобавь первый — значком с булавкой сверху',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textDim, fontSize: 14, height: 1.6),
          ),
        ),
      for (final city in cities)
        _buildCityBlock(
          key: 'trip-${city.id}',
          title: city.name,
          emoji: city.emoji,
          dates: city.dateLabel,
          plan: city.plannedTotal,
          expenses: repo.expensesOf(city.id),
          onMenu: () => _cityMenu(city),
          onEdit: () => _editCity(city),
        ),
      // Траты, записанные на саму группу (так умеет сайт), не теряем.
      if (direct.isNotEmpty)
        _buildCityBlock(
          key: 'direct',
          title: 'Без города',
          emoji: '🧳',
          dates: '',
          plan: 0,
          expenses: direct,
        ),
    ];
  }

  /// Обычная поездка: города берутся из поля «город» у трат.
  List<Widget> _buildSingleTrip(List<TripExpense> expenses) {
    final cities = <String, List<TripExpense>>{};
    for (final e in expenses) {
      cities.putIfAbsent(e.city.trim(), () => []).add(e);
    }
    final named = cities.keys.where((k) => k.isNotEmpty).toList();
    if (named.isEmpty) {
      return _groupByDate(expenses).entries.map((e) => _buildDay(e.key, e.value)).toList();
    }
    return [
      for (final name in [...named, if (cities.containsKey('')) ''])
        _buildCityBlock(
          key: 'name-$name',
          title: name.isEmpty ? 'Без города' : name,
          emoji: name.isEmpty ? '🧳' : '📍',
          dates: '',
          plan: 0,
          expenses: cities[name]!,
        ),
    ];
  }

  Widget _buildCityBlock({
    required String key,
    required String title,
    required String emoji,
    required String dates,
    required int plan,
    required List<TripExpense> expenses,
    VoidCallback? onMenu,
    VoidCallback? onEdit,
  }) {
    final spent = expenses.fold<int>(0, (sum, e) => sum + e.amount);
    final over = plan > 0 && spent > plan;
    final collapsed = _collapsed.contains(key);
    final subtitle = [
      if (dates.isNotEmpty) dates,
      // Свёрнутый город всё равно говорит, сколько в нём трат.
      if (collapsed && expenses.isNotEmpty) _expensesLabel(expenses.length),
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.small),
            // Нажатие сворачивает траты города, долгое — меню.
            onTap: () => setState(() =>
                collapsed ? _collapsed.remove(key) : _collapsed.add(key)),
            onLongPress: onMenu,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
              decoration: cardDecoration(highlighted: true),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        collapsed ? Icons.chevron_right : Icons.expand_more,
                        size: 20,
                        color: AppColors.textDim,
                      ),
                      const SizedBox(width: 4),
                      Text(emoji, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                color: AppColors.text,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (subtitle.isNotEmpty)
                              Text(
                                subtitle,
                                style: TextStyle(color: AppColors.textDim, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        plan > 0
                            ? '${formatMoney(spent)} / ${formatMoney(plan)}'
                            : formatMoney(spent),
                        style: TextStyle(
                          color: over ? AppColors.red : AppColors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (onEdit != null)
                        IconButton(
                          tooltip: 'Изменить город',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.edit_outlined, size: 17, color: AppColors.textDim),
                          onPressed: onEdit,
                        ),
                      if (onMenu != null)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.more_vert, size: 18, color: AppColors.textDim),
                          onPressed: onMenu,
                        )
                      else
                        const SizedBox(width: 8),
                    ],
                  ),
                  if (plan > 0) ...[
                    const SizedBox(height: 9),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (spent / plan).clamp(0.0, 1.0),
                          minHeight: 4,
                          backgroundColor: AppColors.bg,
                          valueColor: AlwaysStoppedAnimation(
                            over ? AppColors.red : AppColors.gold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (collapsed)
            const SizedBox.shrink()
          else if (expenses.isEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(4, 10, 4, 0),
              child: Text(
                'нет трат по этому городу',
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
              ),
            )
          else
            ..._groupByDate(expenses).entries.map((e) => _buildDay(e.key, e.value)),
        ],
      ),
    );
  }

  void _cityMenu(Trip city) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.sheet,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.edit_outlined, color: AppColors.gold),
              title: const Text('Изменить город'),
              onTap: () {
                Navigator.pop(sheetContext);
                _editCity(city);
              },
            ),
            ListTile(
              leading: Icon(Icons.call_split, color: AppColors.gold),
              title: const Text('Вынести в отдельную поездку'),
              onTap: () async {
                Navigator.pop(sheetContext);
                setState(() => _busy = true);
                final ok = await context.read<TripRepository>().ungroup(city);
                if (!mounted) return;
                setState(() => _busy = false);
                if (!ok) _showCityError();
              },
            ),
          ],
        ),
      ),
    );
  }

  static String _expensesLabel(int n) {
    final mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 14) return '$n трат';
    switch (n % 10) {
      case 1:
        return '$n трата';
      case 2:
      case 3:
      case 4:
        return '$n траты';
      default:
        return '$n трат';
    }
  }

  /// Название, даты и план города. Даты и план группы сервер и репозиторий
  /// пересчитают сами — из городов.
  Future<void> _editCity(Trip city) async {
    final result = await showDialog<_CityForm>(
      context: context,
      builder: (_) => _CityDialog(initial: city),
    );
    if (result == null || !mounted) return;

    await context.read<TripRepository>().updateTrip(
          city,
          name: result.name,
          plannedTotal: result.planned,
          startDate: result.startDate,
          endDate: result.endDate,
        );
  }

  /// Сама поездка. У многогородней даты и план складываются из городов,
  /// поэтому меняется только название.
  Future<void> _editTrip(Trip trip) async {
    final result = await showDialog<_CityForm>(
      context: context,
      builder: (_) => _CityDialog(
        initial: trip,
        title: 'Изменить поездку',
        nameOnly: trip.isGroup,
        hint: trip.isGroup ? 'Даты и план поездки складываются из её городов' : null,
      ),
    );
    if (result == null || !mounted) return;

    final repo = context.read<TripRepository>();
    if (trip.isGroup) {
      await repo.updateTrip(trip, name: result.name);
    } else {
      await repo.updateTrip(
        trip,
        name: result.name,
        plannedTotal: result.planned,
        startDate: result.startDate,
        endDate: result.endDate,
      );
    }
  }

  Future<void> _addCity(Trip trip) async {
    final result = await showDialog<_CityForm>(
      context: context,
      builder: (_) => _CityDialog(
        hint: trip.isGroup
            ? null
            : '«${trip.name}» станет первым городом, а поездка — многогородней',
      ),
    );
    if (result == null || !mounted) return;

    setState(() => _busy = true);
    final repo = context.read<TripRepository>();
    final groupId = await repo.addCity(
      trip,
      name: result.name,
      startDate: result.startDate,
      endDate: result.endDate,
      plannedTotal: result.planned,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (groupId == null) {
      _showCityError();
      return;
    }
    await repo.loadTree(groupId, forceRefresh: true);
    if (!mounted) return;
    // Обычная поездка превратилась в город новой группы — открываем группу.
    if (groupId != widget.tripId) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => TripDetailScreen(tripId: groupId)),
      );
    }
  }

  void _showCityError() {
    final error = context.read<TripRepository>().cityError;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Нужна связь с сервером${error == null ? '' : ': $error'}'),
    ));
  }

  // ─── Траты по дням ──────────────────────────────────────────────────

  /// Траты по датам, свежие сверху.
  Map<String, List<TripExpense>> _groupByDate(List<TripExpense> expenses) {
    final map = <String, List<TripExpense>>{};
    for (final e in expenses) {
      map.putIfAbsent(e.date, () => []).add(e);
    }
    final keys = map.keys.toList()..sort((a, b) => b.compareTo(a));
    return {for (final k in keys) k: map[k]!};
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
                style: TextStyle(
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
        child: Icon(Icons.delete_outline, color: AppColors.red),
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
                      style: TextStyle(color: AppColors.text, fontSize: 14.5),
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
                        style: TextStyle(color: AppColors.textDim, fontSize: 12),
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
                      style: TextStyle(color: AppColors.textDim, fontSize: 11),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addExpense(Trip trip, List<Trip> cities) async {
    if (trip.isGroup && cities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Сначала добавь город — траты многогородней поездки живут в городах'),
      ));
      return;
    }
    final result = await showModalBottomSheet<_TripExpenseForm>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.sheet,
      builder: (_) => _TripExpenseSheet(
        initialDate: _defaultDate(trip),
        cities: cities,
      ),
    );
    if (result == null || !mounted) return;

    await context.read<TripRepository>().addExpense(
          result.tripId ?? trip.id,
          amount: result.amount,
          plannedAmount: result.planned,
          date: result.date,
          category: result.category,
          note: result.note,
          city: result.city,
        );
  }

  /// Сегодня, если поездка идёт сейчас, иначе — её первый день.
  DateTime _defaultDate(Trip trip) {
    final now = DateTime.now();
    final start = parseDate(trip.startDate);
    final end = parseDate(trip.endDate);
    if (start != null && end != null && !now.isBefore(start) && !now.isAfter(end)) {
      return now;
    }
    return start ?? now;
  }

  Future<void> _editExpense(TripExpense expense) async {
    final result = await showModalBottomSheet<_TripExpenseForm>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.sheet,
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

  /// Город многогородней поездки, в который ложится трата.
  final int? tripId;

  const _TripExpenseForm({
    required this.amount,
    required this.date,
    this.planned,
    this.category = '',
    this.note = '',
    this.city = '',
    this.tripId,
  });
}

/// Ввод траты поездки. Отдельно сумма факта и сумма плана: в поездке сначала
/// записывают, сколько собираются потратить, и только потом — сколько вышло.
class _TripExpenseSheet extends StatefulWidget {
  final TripExpense? initial;
  final DateTime? initialDate;

  /// Города многогородней поездки. Если не пусто — город выбирается
  /// из них, а не вписывается текстом.
  final List<Trip> cities;

  const _TripExpenseSheet({this.initial, this.initialDate, this.cities = const []});

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

  /// Выбранный город: по умолчанию тот, в чьи даты попадает трата.
  late int? _cityId = _cityForDate(_date);

  int? _cityForDate(DateTime date) {
    if (widget.cities.isEmpty) return null;
    final day = ymd(date);
    for (final c in widget.cities) {
      final from = c.startDate ?? '';
      final to = c.endDate ?? from;
      if (from.isNotEmpty && day.compareTo(from) >= 0 && day.compareTo(to) <= 0) return c.id;
    }
    return widget.cities.first.id;
  }

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
    if (picked != null) {
      setState(() {
        _date = picked;
        _cityId = _cityForDate(picked);
      });
    }
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
        city: widget.cities.isEmpty ? _city.text.trim() : '',
        tripId: _cityId,
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
              style: TextStyle(
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
                    style: TextStyle(color: AppColors.text, fontSize: 16),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _planned,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'План, ₽'),
                    style: TextStyle(color: AppColors.text, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text('НА ЧТО', style: kEyebrowStyle),
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
              style: TextStyle(color: AppColors.text),
            ),
            const SizedBox(height: 10),
            if (widget.cities.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('ГОРОД', style: kEyebrowStyle),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.cities.map((c) {
                  final selected = c.id == _cityId;
                  return GestureDetector(
                    onTap: () => setState(() => _cityId = c.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.goldWash(0.2) : AppColors.bg,
                        border: Border.all(
                          color: selected ? AppColors.gold : AppColors.border,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        '📍 ${c.name}',
                        style: TextStyle(
                          color: selected ? AppColors.gold : AppColors.text,
                          fontSize: 12.5,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ] else
              TextField(
                controller: _city,
                decoration: const InputDecoration(
                  hintText: 'Город',
                  prefixIcon: Icon(Icons.place_outlined, size: 19),
                ),
                style: TextStyle(color: AppColors.text),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              decoration: const InputDecoration(hintText: 'Комментарий'),
              style: TextStyle(color: AppColors.text),
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

class _CityForm {
  final String name;
  final String? startDate;
  final String? endDate;
  final int planned;

  const _CityForm({required this.name, required this.planned, this.startDate, this.endDate});
}

/// Новый город в поездке: название, даты и свой бюджет.
class _CityDialog extends StatefulWidget {
  /// Пояснение под заголовком: что будет с поездкой или откуда её даты.
  final String? hint;

  /// Город или поездка, которые правим. null — создаём новый город.
  final Trip? initial;

  /// Заголовок окна, если это не город.
  final String? title;

  /// Только название — для многогородней поездки.
  final bool nameOnly;

  const _CityDialog({this.hint, this.initial, this.title, this.nameOnly = false});

  @override
  State<_CityDialog> createState() => _CityDialogState();
}

class _CityDialogState extends State<_CityDialog> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _planned = TextEditingController(
    text: (widget.initial?.plannedTotal ?? 0) > 0 ? '${widget.initial!.plannedTotal}' : '',
  );
  late DateTime? _start = parseDate(widget.initial?.startDate);
  late DateTime? _end = parseDate(widget.initial?.endDate);

  @override
  void dispose() {
    _name.dispose();
    _planned.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
      // Перепутанные даты (конец раньше начала) пикер не примет — меняем местами.
      initialDateRange: _start != null && _end != null
          ? (_end!.isBefore(_start!)
              ? DateTimeRange(start: _end!, end: _start!)
              : DateTimeRange(start: _start!, end: _end!))
          : null,
    );
    if (range == null) return;
    setState(() {
      _start = range.start;
      _end = range.end;
    });
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(
      context,
      _CityForm(
        name: name,
        startDate: _start == null ? null : ymd(_start!),
        endDate: _end == null ? null : ymd(_end!),
        planned: int.tryParse(_planned.text.trim()) ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.sheet,
      title: Text(
        widget.title ?? (widget.initial == null ? 'Новый город' : 'Изменить город'),
        style: TextStyle(color: AppColors.text, fontSize: 17),
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.hint != null) ...[
              Text(
                widget.hint!,
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: widget.title == null ? 'Город' : 'Название',
                hintText: widget.title == null ? 'Тбилиси' : null,
                prefixIcon: const Icon(Icons.place_outlined, size: 19),
              ),
              style: TextStyle(color: AppColors.text),
            ),
            if (!widget.nameOnly) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range_outlined, size: 18),
                label: Text(
                  _start == null
                      ? 'Выбрать даты'
                      : '${ymd(_start!)} — ${_end == null ? '?' : ymd(_end!)}',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _planned,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'План, ₽',
                  hintText: 'можно пропустить',
                ),
                style: TextStyle(color: AppColors.text),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Отмена', style: TextStyle(color: AppColors.textDim)),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.initial == null ? 'Добавить' : 'Сохранить'),
        ),
      ],
    );
  }
}
