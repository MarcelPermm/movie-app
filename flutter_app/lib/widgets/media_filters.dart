import 'package:flutter/material.dart';

import '../models/catalog.dart';
import '../models/movie.dart';
import '../theme.dart';

/// Порядок карточек в подборке.
enum MediaSort { relevance, rating, newest, title }

/// Десятилетие выхода. [from] включительно, [to] — не включая.
class Decade {
  final String label;
  final int? from;
  final int? to;

  const Decade(this.label, this.from, this.to);

  bool contains(int? year) {
    if (year == null) return false;
    if (from != null && year < from!) return false;
    if (to != null && year >= to!) return false;
    return true;
  }

  static const all = <Decade>[
    Decade('2020-е', 2020, null),
    Decade('2010-е', 2010, 2020),
    Decade('2000-е', 2000, 2010),
    Decade('1990-е', 1990, 2000),
    Decade('Раньше', null, 1990),
  ];
}

/// Что выбрано в фильтрах. Неизменяемое: каждое изменение — новый объект,
/// так шторка может показывать «Показать 34», не трогая экран под собой.
class MediaFilter {
  final Set<String> genres;
  final Set<String> hiddenGenres;
  final Set<String> countries;
  final Decade? decade;
  final double minRating;
  final MediaSort sort;

  const MediaFilter({
    this.genres = const {},
    this.hiddenGenres = const {},
    this.countries = const {},
    this.decade,
    this.minRating = 0,
    this.sort = MediaSort.relevance,
  });

  MediaFilter copyWith({
    Set<String>? genres,
    Set<String>? hiddenGenres,
    Set<String>? countries,
    Decade? decade,
    bool clearDecade = false,
    double? minRating,
    MediaSort? sort,
  }) =>
      MediaFilter(
        genres: genres ?? this.genres,
        hiddenGenres: hiddenGenres ?? this.hiddenGenres,
        countries: countries ?? this.countries,
        decade: clearDecade ? null : (decade ?? this.decade),
        minRating: minRating ?? this.minRating,
        sort: sort ?? this.sort,
      );

  /// Сколько фильтров включено (сортировка не считается — это не отбор).
  int get activeCount =>
      (genres.isEmpty ? 0 : 1) +
      (hiddenGenres.isEmpty ? 0 : 1) +
      (countries.isEmpty ? 0 : 1) +
      (decade == null ? 0 : 1) +
      (minRating > 0 ? 1 : 0);

  MediaFilter cleared() => MediaFilter(sort: sort);

  bool _keeps(Movie m) {
    if (genres.isNotEmpty && !m.genres.any(genres.contains)) return false;
    if (hiddenGenres.isNotEmpty && m.genres.any(hiddenGenres.contains)) return false;
    if (countries.isNotEmpty && !m.originCountries.any(countries.contains)) return false;
    if (decade != null && !decade!.contains(m.releaseYear)) return false;
    if (minRating > 0 && m.voteAverage < minRating) return false;
    return true;
  }

  /// Отбор и сортировка. Исходный порядок — это «по вкусу» от сервера.
  List<Movie> apply(List<Movie> items) {
    final out = items.where(_keeps).toList();
    switch (sort) {
      case MediaSort.rating:
        out.sort((a, b) => b.voteAverage.compareTo(a.voteAverage));
      case MediaSort.newest:
        out.sort((a, b) => (b.releaseYear ?? 0).compareTo(a.releaseYear ?? 0));
      case MediaSort.title:
        out.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case MediaSort.relevance:
        break;
    }
    return out;
  }
}

/// TMDB отдаёт русские жанры со строчной: «драма». В интерфейсе — «Драма».
String capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Сколько раз значение встречается в подборке — от частых к редким.
/// В шторке показываем только то, что реально есть: выбрать жанр, после
/// которого не останется ни одной карточки, нельзя.
List<MapEntry<String, int>> countValues(Iterable<Movie> items, Iterable<String> Function(Movie) pick) {
  final counts = <String, int>{};
  for (final m in items) {
    for (final v in pick(m)) {
      if (v.isNotEmpty) counts[v] = (counts[v] ?? 0) + 1;
    }
  }
  return counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

const _sortLabels = {
  MediaSort.relevance: 'По вкусу',
  MediaSort.rating: 'По рейтингу',
  MediaSort.newest: 'Сначала новые',
  MediaSort.title: 'По алфавиту',
};

/// Полоса фильтров над плиткой: по кнопке на каждый фильтр.
///
/// Раньше фильтры жили в раскрывающейся панели на полэкрана, а жанр
/// исключался «повторным нажатием» — об этом никто не догадывался. Теперь
/// у каждой кнопки своя шторка с понятным выбором и счётчиком результата.
class MediaFilterBar extends StatelessWidget {
  final List<Movie> pool;
  final MediaFilter filter;
  final ValueChanged<MediaFilter> onChanged;

  /// Название первого порядка сортировки: «По вкусу» для рекомендаций,
  /// «По подборке» для обычных списков.
  final String relevanceLabel;

  /// Дополнительные кнопки в конце полосы (например, студия у рекомендаций).
  final List<Widget> extra;

  const MediaFilterBar({
    super.key,
    required this.pool,
    required this.filter,
    required this.onChanged,
    this.relevanceLabel = 'По вкусу',
    this.extra = const [],
  });

  @override
  Widget build(BuildContext context) {
    final f = filter;
    final genreValue = [
      if (f.genres.isNotEmpty) _short(f.genres.map(capitalize)),
      if (f.hiddenGenres.isNotEmpty) '−${_short(f.hiddenGenres.map(capitalize))}',
    ].join(' · ');
    final countryNames = f.countries.map(_countryName).toSet();

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        children: [
          FilterButton(
            icon: Icons.swap_vert,
            label: f.sort == MediaSort.relevance ? relevanceLabel : _sortLabels[f.sort]!,
            active: f.sort != MediaSort.relevance,
            onTap: () => _pickSort(context),
          ),
          FilterButton(
            label: genreValue.isEmpty ? 'Жанры' : genreValue,
            active: genreValue.isNotEmpty,
            onTap: () => _pickGenres(context),
          ),
          FilterButton(
            label: f.decade?.label ?? 'Годы',
            active: f.decade != null,
            onTap: () => _pickDecade(context),
          ),
          FilterButton(
            label: f.minRating > 0 ? '★ от ${f.minRating.toStringAsFixed(0)}' : 'Рейтинг',
            active: f.minRating > 0,
            onTap: () => _pickRating(context),
          ),
          FilterButton(
            label: countryNames.isEmpty ? 'Страна' : _short(countryNames),
            active: countryNames.isNotEmpty,
            onTap: () => _pickCountries(context),
          ),
          ...extra,
          if (f.activeCount > 0)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: TextButton.icon(
                onPressed: () => onChanged(f.cleared()),
                icon: Icon(Icons.close, size: 16, color: AppColors.textDim),
                label: Text('Сбросить', style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
              ),
            ),
        ],
      ),
    );
  }

  static String _short(Iterable<String> values) {
    final list = values.toList();
    return list.length == 1 ? list.first : '${list.first} +${list.length - 1}';
  }

  static String _countryName(String code) {
    for (final c in CountryOption.all) {
      if (c.code == code) return c.name;
    }
    return code;
  }

  // ─── Шторки ─────────────────────────────────────────────────────────

  void _pickSort(BuildContext context) {
    final labels = {..._sortLabels, MediaSort.relevance: relevanceLabel};
    showFilterSheet(
      context,
      title: 'Сортировка',
      pool: pool,
      initial: filter,
      onApply: onChanged,
      showCount: false,
      builder: (draft, update) => Column(
        children: labels.entries
            .map((e) => _ChoiceRow(
                  label: e.value,
                  selected: draft.sort == e.key,
                  onTap: () => update(draft.copyWith(sort: e.key), close: true),
                ))
            .toList(),
      ),
    );
  }

  void _pickDecade(BuildContext context) {
    showFilterSheet(
      context,
      title: 'Годы выхода',
      pool: pool,
      initial: filter,
      onApply: onChanged,
      builder: (draft, update) {
        final counts = {
          for (final d in Decade.all) d.label: pool.where((m) => d.contains(m.releaseYear)).length,
        };
        return Column(
          children: [
            _ChoiceRow(
              label: 'Любые',
              selected: draft.decade == null,
              onTap: () => update(draft.copyWith(clearDecade: true)),
            ),
            for (final d in Decade.all)
              if (counts[d.label]! > 0)
                _ChoiceRow(
                  label: d.label,
                  count: counts[d.label],
                  selected: draft.decade?.label == d.label,
                  onTap: () => update(draft.copyWith(decade: d)),
                ),
          ],
        );
      },
    );
  }

  void _pickRating(BuildContext context) {
    showFilterSheet(
      context,
      title: 'Рейтинг TMDB',
      pool: pool,
      initial: filter,
      onApply: onChanged,
      builder: (draft, update) => Column(
        children: [
          for (final r in const [0.0, 6.0, 7.0, 7.5, 8.0])
            _ChoiceRow(
              label: r == 0 ? 'Любой' : 'от ${r % 1 == 0 ? r.toStringAsFixed(0) : r.toStringAsFixed(1)}',
              count: r == 0 ? null : pool.where((m) => m.voteAverage >= r).length,
              selected: draft.minRating == r,
              onTap: () => update(draft.copyWith(minRating: r)),
            ),
        ],
      ),
    );
  }

  void _pickCountries(BuildContext context) {
    final present = countValues(pool, (m) => m.originCountries);
    showFilterSheet(
      context,
      title: 'Страна',
      subtitle: 'Можно выбрать несколько',
      pool: pool,
      initial: filter,
      onApply: onChanged,
      builder: (draft, update) {
        if (present.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('В этой подборке страна не указана',
                style: TextStyle(color: AppColors.textDim)),
          );
        }
        return Column(
          children: present.map((e) {
            final on = draft.countries.contains(e.key);
            final known = CountryOption.all.where((c) => c.code == e.key);
            return _CheckRow(
              label: known.isEmpty ? e.key : known.first.label,
              count: e.value,
              checked: on,
              onTap: () {
                final next = {...draft.countries};
                on ? next.remove(e.key) : next.add(e.key);
                update(draft.copyWith(countries: next));
              },
            );
          }).toList(),
        );
      },
    );
  }

  void _pickGenres(BuildContext context) {
    final present = countValues(pool, (m) => m.genres);
    showFilterSheet(
      context,
      title: 'Жанры',
      subtitle: 'Галочка — показать только эти. Глаз — спрятать жанр.',
      pool: pool,
      initial: filter,
      onApply: onChanged,
      builder: (draft, update) => Column(
        children: present.map((e) {
          final shown = draft.genres.contains(e.key);
          final hidden = draft.hiddenGenres.contains(e.key);
          return _GenreRow(
            label: e.key,
            count: e.value,
            shown: shown,
            hidden: hidden,
            onToggleShow: () {
              final g = {...draft.genres};
              final h = {...draft.hiddenGenres}..remove(e.key);
              shown ? g.remove(e.key) : g.add(e.key);
              update(draft.copyWith(genres: g, hiddenGenres: h));
            },
            onToggleHide: () {
              final h = {...draft.hiddenGenres};
              final g = {...draft.genres}..remove(e.key);
              hidden ? h.remove(e.key) : h.add(e.key);
              update(draft.copyWith(genres: g, hiddenGenres: h));
            },
          );
        }).toList(),
      ),
    );
  }
}

/// Кнопка фильтра: «Жанры ▾», а когда выбрано — «Драма +2 ▾» золотом.
class FilterButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;

  const FilterButton({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final fg = active ? AppColors.bg : AppColors.text;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: active ? AppColors.gold : AppColors.surface,
        shape: StadiumBorder(side: BorderSide(color: active ? AppColors.gold : AppColors.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 5),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 190),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                Icon(Icons.arrow_drop_down, size: 20, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

typedef FilterUpdate = void Function(MediaFilter next, {bool close});

/// Шторка одного фильтра. Выбор копится в черновике, а кнопка внизу сразу
/// говорит, сколько останется: «Показать 34». Так не нужно закрывать
/// шторку, чтобы понять, не пусто ли получилось.
Future<void> showFilterSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<Movie> pool,
  required MediaFilter initial,
  required ValueChanged<MediaFilter> onApply,
  required Widget Function(MediaFilter draft, FilterUpdate update) builder,
  bool showCount = true,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.sheet,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (sheetContext) {
      var draft = initial;
      return StatefulBuilder(
        builder: (context, setSheet) {
          void update(MediaFilter next, {bool close = false}) {
            setSheet(() => draft = next);
            if (close) {
              onApply(next);
              Navigator.pop(sheetContext);
            }
          }

          final count = showCount ? draft.apply(pool).length : 0;
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Text(title,
                      style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(subtitle, style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                  ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: builder(draft, update),
                  ),
                ),
                if (showCount)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                    child: FilledButton(
                      onPressed: count == 0
                          ? null
                          : () {
                              onApply(draft);
                              Navigator.pop(sheetContext);
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: AppColors.bg,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(count == 0 ? 'Ничего не найдено' : 'Показать $count'),
                    ),
                  ),
              ],
            ),
          );
        },
      );
    },
  );
}

class _ChoiceRow extends StatelessWidget {
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceRow({required this.label, required this.selected, required this.onTap, this.count});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      dense: true,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? AppColors.gold : AppColors.textDim,
        size: 20,
      ),
      title: Text(label, style: TextStyle(color: AppColors.text, fontSize: 14.5)),
      trailing: count == null ? null : _Count(count!),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String label;
  final int count;
  final bool checked;
  final VoidCallback onTap;

  const _CheckRow({required this.label, required this.count, required this.checked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      dense: true,
      leading: Icon(
        checked ? Icons.check_box : Icons.check_box_outline_blank,
        color: checked ? AppColors.gold : AppColors.textDim,
        size: 20,
      ),
      title: Text(label, style: TextStyle(color: AppColors.text, fontSize: 14.5)),
      trailing: _Count(count),
    );
  }
}

/// Строка жанра: галочка «только эти» и отдельная кнопка «спрятать».
class _GenreRow extends StatelessWidget {
  final String label;
  final int count;
  final bool shown;
  final bool hidden;
  final VoidCallback onToggleShow;
  final VoidCallback onToggleHide;

  const _GenreRow({
    required this.label,
    required this.count,
    required this.shown,
    required this.hidden,
    required this.onToggleShow,
    required this.onToggleHide,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onToggleShow,
      dense: true,
      leading: Icon(
        shown ? Icons.check_box : Icons.check_box_outline_blank,
        color: shown ? AppColors.gold : AppColors.textDim,
        size: 20,
      ),
      title: Text(
        capitalize(label),
        style: TextStyle(
          color: hidden ? AppColors.textDim : AppColors.text,
          fontSize: 14.5,
          decoration: hidden ? TextDecoration.lineThrough : null,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Count(count),
          IconButton(
            tooltip: hidden ? 'Снова показывать' : 'Спрятать этот жанр',
            onPressed: onToggleHide,
            icon: Icon(
              hidden ? Icons.visibility_off : Icons.visibility_outlined,
              size: 19,
              color: hidden ? AppColors.red : AppColors.textDim,
            ),
          ),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  final int value;

  const _Count(this.value);

  @override
  Widget build(BuildContext context) =>
      Text('$value', style: TextStyle(color: AppColors.textDim, fontSize: 12.5));
}
