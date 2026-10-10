import 'package:flutter/material.dart';

import '../theme.dart';

/// Крупное число с подписью — из таких плиток собрана шапка профиля.
class StatTile extends StatelessWidget {
  final String value;
  final String label;
  final Color? color;

  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: AppText.number(26, color: color ?? AppColors.gold),
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: AppColors.textDim,
              fontSize: 10,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Строка рейтинга: название, полоса и счётчик.
///
/// Полоса делится на две части — фильмы и сериалы, — потому что бэкенд
/// считает их отдельно, и смешивать их в одну цифру значило бы терять смысл.
class SplitBarRow extends StatelessWidget {
  final String label;
  final int primary;
  final int secondary;
  final int max;
  final Color? _primaryColor;
  final Color? _secondaryColor;

  Color get primaryColor => _primaryColor ?? AppColors.gold;
  Color get secondaryColor => _secondaryColor ?? AppColors.blue;

  const SplitBarRow({
    super.key,
    required this.label,
    required this.primary,
    required this.max,
    this.secondary = 0,
    Color? primaryColor,
    Color? secondaryColor,
  })  : _primaryColor = primaryColor,
        _secondaryColor = secondaryColor;

  @override
  Widget build(BuildContext context) {
    final total = primary + secondary;
    final safeMax = max <= 0 ? 1 : max;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.text, fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final unit = constraints.maxWidth / safeMax;
                return SizedBox(
                  height: 9,
                  child: Row(
                    children: [
                      if (primary > 0)
                        Container(
                          width: (primary * unit).clamp(2.0, constraints.maxWidth),
                          decoration: BoxDecoration(
                            color: primaryColor,
                            borderRadius: const BorderRadius.horizontal(
                              left: Radius.circular(4),
                              right: Radius.circular(4),
                            ),
                          ),
                        ),
                      if (secondary > 0) ...[
                        const SizedBox(width: 2),
                        Container(
                          width: (secondary * unit).clamp(2.0, constraints.maxWidth),
                          decoration: BoxDecoration(
                            color: secondaryColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 30,
            child: Text(
              '$total',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: AppColors.textDim,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Вертикальные столбики — гистограмма оценок и график по месяцам.
class ColumnChart extends StatelessWidget {
  final List<ColumnBar> bars;
  final double height;

  const ColumnChart({super.key, required this.bars, this.height = 110});

  @override
  Widget build(BuildContext context) {
    final max = bars.fold<int>(0, (m, b) => b.total > m ? b.total : m);
    if (max == 0) {
      return SizedBox(
        height: 60,
        child: Center(
          child: Text('Пока нет данных', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
        ),
      );
    }

    return SizedBox(
      height: height + 22,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: bars.map((bar) {
          return Expanded(
            child: Tooltip(
              message: '${bar.label}: ${bar.total}',
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Пустой столбец всё равно занимает пиксель — иначе шкала
                  // «проваливается» и выглядит поломанной.
                  Container(
                    height: (bar.total / max * height).clamp(1.0, height),
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [bar.color, bar.color.withValues(alpha: 0.55)],
                      ),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    bar.label,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(color: AppColors.textDim, fontSize: 9.5),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class ColumnBar {
  final String label;
  final int total;
  final Color? _color;

  Color get color => _color ?? AppColors.gold;

  const ColumnBar({required this.label, required this.total, Color? color}) : _color = color;
}

/// Заголовок блока внутри профиля.
class StatBlock extends StatelessWidget {
  final String title;
  final String? hint;
  final Widget child;

  const StatBlock({super.key, required this.title, required this.child, this.hint});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (hint != null)
                Text(hint!, style: TextStyle(color: AppColors.textDim, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Подпись к цветам на графиках: «■ фильмы ■ сериалы».
class ChartLegend extends StatelessWidget {
  final Map<String, Color> items;

  const ChartLegend(this.items, {super.key});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      children: items.entries
          .map((e) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: e.value,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(e.key, style: TextStyle(color: AppColors.textDim, fontSize: 11)),
                ],
              ))
          .toList(),
    );
  }
}
