import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/trip_repository.dart';
import '../models/json.dart';
import '../models/trip.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'trip_detail_screen.dart';

/// Список поездок и событий с собственным бюджетом.
class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TripRepository>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<TripRepository>();
    final trips = repo.rootTrips;

    return Column(
      children: [
        SectionHeader(
          title: 'Поездки',
          subtitle: trips.isEmpty ? null : '${trips.length} в списке',
          actions: [AddButton(onPressed: _addTrip, tooltip: 'Новая поездка')],
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.gold,
            backgroundColor: AppColors.surface,
            onRefresh: () => context.read<TripRepository>().refresh(),
            child: trips.isEmpty
                ? const EmptyHint(
                    emoji: '🧳',
                    text: 'Пока ни одной поездки.\nДобавь — и планируй бюджет отдельно от месячного',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                    itemCount: trips.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) => _TripCard(
                      trip: trips[i],
                      children: repo.childrenOf(trips[i].id),
                      onOpen: _openTrip,
                      onEdit: _editTrip,
                      onDelete: _deleteTrip,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  void _openTrip(Trip trip) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TripDetailScreen(tripId: trip.id)),
    );
  }

  Future<void> _addTrip() async {
    final result = await showDialog<_TripForm>(
      context: context,
      builder: (_) => const _TripDialog(),
    );
    if (result == null || !mounted) return;

    await context.read<TripRepository>().addTrip(
          name: result.name,
          emoji: result.emoji,
          startDate: result.startDate,
          endDate: result.endDate,
          plannedTotal: result.planned,
          eventType: result.eventType,
        );
  }

  Future<void> _editTrip(Trip trip) async {
    final result = await showDialog<_TripForm>(
      context: context,
      builder: (_) => _TripDialog(initial: trip),
    );
    if (result == null || !mounted) return;

    await context.read<TripRepository>().updateTrip(
          trip,
          name: result.name,
          emoji: result.emoji,
          plannedTotal: result.planned,
        );
  }

  Future<void> _deleteTrip(Trip trip) async {
    final ok = await confirmDelete(
      context,
      'Поездка «${trip.name}» и все её траты',
    );
    if (!ok || !mounted) return;
    await context.read<TripRepository>().removeTrip(trip);
  }
}

/// Карточка поездки: даты, бюджет и полоска выполнения.
class _TripCard extends StatelessWidget {
  final Trip trip;
  final List<Trip> children;
  final void Function(Trip) onOpen;
  final void Function(Trip) onEdit;
  final void Function(Trip) onDelete;

  const _TripCard({
    required this.trip,
    required this.children,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final progress = trip.progress;
    final days = trip.daysUntil;

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      onTap: () => onOpen(trip),
      onLongPress: () => _menu(context),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: cardDecoration(highlighted: days != null && days <= 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trip.emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trip.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          trip.dateLabel,
                          if (trip.subtitle.isNotEmpty) trip.subtitle,
                          if (children.isNotEmpty) '${children.length} внутри',
                        ].join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textDim, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                if (days != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.goldWash(0.15),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(color: AppColors.goldWash(0.4)),
                    ),
                    child: Text(
                      'через $days ${_plural(days)}',
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatMoney(trip.actualTotal),
                  style: TextStyle(
                    color: trip.overspent ? AppColors.red : AppColors.gold,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (trip.plannedTotal > 0) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      'из ${formatMoney(trip.plannedTotal)}',
                      style: const TextStyle(color: AppColors.textDim, fontSize: 12.5),
                    ),
                  ),
                ],
                const Spacer(),
                if (trip.overspent)
                  Text(
                    '+${formatMoney(trip.actualTotal - trip.plannedTotal)}',
                    style: const TextStyle(
                      color: AppColors.red,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: AppColors.bg,
                  valueColor: AlwaysStoppedAnimation(
                    trip.overspent ? AppColors.red : AppColors.gold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _plural(int days) {
    final mod100 = days % 100;
    if (mod100 >= 11 && mod100 <= 14) return 'дней';
    switch (days % 10) {
      case 1:
        return 'день';
      case 2:
      case 3:
      case 4:
        return 'дня';
      default:
        return 'дней';
    }
  }

  void _menu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: AppColors.gold),
              title: const Text('Изменить'),
              onTap: () {
                Navigator.pop(sheetContext);
                onEdit(trip);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.red),
              title: const Text('Удалить'),
              onTap: () {
                Navigator.pop(sheetContext);
                onDelete(trip);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Результат заполнения формы поездки.
class _TripForm {
  final String name;
  final String emoji;
  final String? startDate;
  final String? endDate;
  final int planned;
  final String eventType;

  const _TripForm({
    required this.name,
    required this.emoji,
    required this.planned,
    required this.eventType,
    this.startDate,
    this.endDate,
  });
}

class _TripDialog extends StatefulWidget {
  final Trip? initial;

  const _TripDialog({this.initial});

  @override
  State<_TripDialog> createState() => _TripDialogState();
}

class _TripDialogState extends State<_TripDialog> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _planned = TextEditingController(
    text: (widget.initial?.plannedTotal ?? 0) > 0 ? '${widget.initial!.plannedTotal}' : '',
  );

  late String _emoji = widget.initial?.emoji ?? '✈️';
  late String _type = widget.initial?.eventType ?? 'trip';
  late DateTime? _start = parseDate(widget.initial?.startDate);
  late DateTime? _end = parseDate(widget.initial?.endDate);

  static const _emojis = ['✈️', '🏖️', '🏔️', '🚗', '🚂', '🎄', '🎉', '💍', '🏠', '🎓'];

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
      initialDateRange: _start != null && _end != null
          ? DateTimeRange(start: _start!, end: _end!)
          : null,
      builder: (context, child) => Theme(
        data: Theme.of(context),
        child: child!,
      ),
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
      _TripForm(
        name: name,
        emoji: _emoji,
        startDate: _start == null ? null : ymd(_start!),
        endDate: _end == null ? null : ymd(_end!),
        planned: int.tryParse(_planned.text.trim()) ?? 0,
        eventType: _type,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;

    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        editing ? 'Изменить поездку' : 'Новая поездка',
        style: const TextStyle(color: AppColors.text, fontSize: 17),
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Куда или что за событие'),
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
                      height: 40,
                      width: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? AppColors.goldWash(0.2) : AppColors.bg,
                        border: Border.all(
                          color: selected ? AppColors.gold : AppColors.border,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.small),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 19)),
                    ),
                  );
                }).toList(),
              ),
              if (!editing) ...[
                const SizedBox(height: 16),
                const Text('ТИП', style: kEyebrowStyle),
                const SizedBox(height: 8),
                SegmentedToggle<String>(
                  value: _type,
                  options: const {'trip': '🧳 Поездка', 'event': '🎉 Событие'},
                  onChanged: (v) => setState(() => _type = v),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _pickRange,
                  icon: const Icon(Icons.date_range_outlined, size: 18),
                  label: Text(
                    _start == null
                        ? 'Выбрать даты'
                        : '${ymd(_start!)} — ${_end == null ? '?' : ymd(_end!)}',
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _planned,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'Бюджет, ₽ — можно пропустить',
                ),
                style: const TextStyle(color: AppColors.text),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена', style: TextStyle(color: AppColors.textDim)),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(editing ? 'Сохранить' : 'Создать'),
        ),
      ],
    );
  }
}
