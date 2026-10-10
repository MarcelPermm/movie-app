import 'package:flutter/material.dart';

import '../theme.dart';

/// Одна вкладка внутри раздела.
///
/// Содержимое строится лениво: пока вкладку не открыли, её экран не создаётся
/// и запросов не делает. Это важно для тяжёлых вкладок вроде «Актёров»
/// и «✦ Посоветуй» — иначе один заход в «Кино» дёргал бы половину API.
class SubTab {
  final String label;
  final WidgetBuilder builder;

  /// Счётчик справа от названия («Дневник · 128»).
  final int? count;

  const SubTab({required this.label, required this.builder, this.count});
}

/// Раздел с горизонтальной лентой вкладок — тот же приём, что в шапке сайта.
///
/// Открытые вкладки сохраняются в IndexedStack: вернувшись, видишь ту же
/// прокрутку и те же введённые фильтры.
class SubTabView extends StatefulWidget {
  final List<SubTab> tabs;
  final int initialIndex;

  /// Строка над лентой вкладок: заголовок раздела, переключатели, поиск.
  final Widget? header;

  const SubTabView({
    super.key,
    required this.tabs,
    this.initialIndex = 0,
    this.header,
  });

  @override
  State<SubTabView> createState() => _SubTabViewState();
}

class _SubTabViewState extends State<SubTabView> {
  late int _index = widget.initialIndex.clamp(0, widget.tabs.length - 1);

  /// Какие вкладки уже открывали — только они и строятся.
  late final Set<int> _visited = {_index};

  @override
  void didUpdateWidget(SubTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Число вкладок может измениться (например, у гостя их меньше) —
    // не даём индексу уехать за границу списка.
    if (_index >= widget.tabs.length) {
      _index = widget.tabs.length - 1;
      _visited.add(_index);
    }
  }

  void _select(int i) {
    if (i == _index) return;
    setState(() {
      _index = i;
      _visited.add(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.header != null) widget.header!,
        _TabStrip(tabs: widget.tabs, index: _index, onSelect: _select),
        const Divider(height: 1),
        Expanded(
          child: IndexedStack(
            index: _index,
            children: [
              for (var i = 0; i < widget.tabs.length; i++)
                _visited.contains(i)
                    ? widget.tabs[i].builder(context)
                    : const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }
}

class _TabStrip extends StatelessWidget {
  final List<SubTab> tabs;
  final int index;
  final ValueChanged<int> onSelect;

  const _TabStrip({required this.tabs, required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final tab = tabs[i];
          final active = i == index;
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => onSelect(i),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  gradient: active ? AppColors.goldGradient : null,
                  color: active ? null : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                    color: active ? Colors.transparent : AppColors.border,
                  ),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: AppColors.gold.withValues(alpha: 0.22),
                            blurRadius: 16,
                            offset: const Offset(0, 5),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tab.label,
                      style: TextStyle(
                        color: active ? AppColors.bg : AppColors.textDim,
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    if (tab.count != null && tab.count! > 0) ...[
                      const SizedBox(width: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: active ? const Color(0x33000000) : AppColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          '${tab.count}',
                          style: TextStyle(
                            color: active ? AppColors.bg : AppColors.textDim,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Фильтр-«таблетка» с состоянием вкл/выкл — из них собраны панели жанров,
/// стран и студий.
class FilterChipPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const FilterChipPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.gold : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: selected ? AppColors.gold : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.bg : AppColors.textDim,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
