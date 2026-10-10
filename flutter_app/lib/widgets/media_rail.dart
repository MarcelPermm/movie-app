import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/movie.dart';
import '../theme.dart';
import 'app_scroll.dart';
import 'poster_card.dart';

/// Блок главной: рубрика, заголовок и лента кадров.
///
/// Лента устроена как карусель: тот кадр, что оказался посередине, крупнее
/// остальных и показывает подробности, соседние ужаты по краям. Прокрутка
/// сдвигает выбор — «главный» фильм блока меняется на ходу.
///
/// Ряд одинаковых прямоугольников не даёт глазу зацепиться. Здесь взгляд
/// всегда знает, куда смотреть, а страница при этом не растёт вверх, как
/// было бы с отдельным баннером над каждым блоком.
class MediaRail extends StatefulWidget {
  final String title;

  /// Мелкая надпись над заголовком — «подобрано для тебя», «на этой неделе».
  final String? eyebrow;

  final List<Movie> movies;
  final void Function(Movie) onOpen;

  /// Быстрое действие с карточки — обычно «в список к просмотру».
  final void Function(Movie)? onQuickAdd;

  /// Ссылка «все» справа от заголовка.
  final VoidCallback? onShowAll;

  /// false — обычная лента постеров без крупного кадра. Нужна там, где блок
  /// замыкает страницу и второй акцент подряд её перегружает.
  final bool showBanner;

  const MediaRail({
    super.key,
    required this.title,
    required this.movies,
    required this.onOpen,
    this.eyebrow,
    this.onQuickAdd,
    this.onShowAll,
    this.showBanner = true,
  });

  @override
  State<MediaRail> createState() => _MediaRailState();
}

class _MediaRailState extends State<MediaRail> {
  final _controller = ScrollController();

  static const _railHeight = 250.0;

  /// Насколько низкими становятся боковые кадры относительно центрального.
  /// Разница только по высоте: если ужимать и по ширине, между карточками
  /// появляются провалы, и лента рассыпается на отдельные картинки.
  static const _sideHeightFactor = 0.62;

  static const _gap = 10.0;

  /// Отступ ленты от края экрана. Раньше он равнялся половине окна — так
  /// первый кадр вставал ровно по центру, но слева зияла пустота в пол-экрана.
  /// Обычного отступа достаточно: «центральным» становится тот кадр, что
  /// оказался посередине окна, и ряд выглядит заполненным с первого взгляда.
  static const _sidePad = 22.0;

  double _offset = 0;
  double _viewport = 0;
  double _itemWidth = 320;

  bool _canBack = false;
  bool _canForward = false;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final p = _controller.position;
    setState(() {
      _offset = p.pixels;
      _viewport = p.viewportDimension;
      _canBack = p.pixels > 4;
      _canForward = p.pixels < p.maxScrollExtent - 4;
    });
  }

  double get _step => _itemWidth + _gap;

  /// Середина элемента в координатах содержимого ленты.
  double _itemCenter(int index) => _sidePad + index * _step + _itemWidth / 2;

  /// Насколько элемент удалён от середины окна, в шагах ленты.
  /// 0 — ровно по центру, 1 — соседний.
  double _distanceFromCenter(int index) {
    if (_viewport == 0) return index == 0 ? 0 : 1;
    return (_itemCenter(index) - (_offset + _viewport / 2)).abs() / _step;
  }

  int get _featuredIndex {
    if (_viewport == 0) return 0;
    final index = ((_offset + _viewport / 2 - _sidePad - _itemWidth / 2) / _step).round();
    return index.clamp(0, widget.movies.length - 1);
  }

  /// Листаем ровно на один кадр: так выбор всегда встаёт по центру.
  void _scrollBy(bool forward) {
    if (!_controller.hasClients) return;
    _controller.animateTo(
      (_offset + (forward ? _step : -_step)).clamp(
        _controller.position.minScrollExtent,
        _controller.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.movies.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 8),
          widget.showBanner ? _buildCarousel() : _buildPosterStrip(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.eyebrow != null) ...[
                  Text(widget.eyebrow!.toUpperCase(), style: kEyebrowStyle),
                  const SizedBox(height: 5),
                ],
                Row(
                  children: [
                    // Тонкая золотая засечка у заголовка — деталь, которая
                    // собирает страницу в целое.
                    Container(
                      width: 3,
                      height: 20,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        gradient: AppColors.goldGradient,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (widget.onShowAll != null)
            TextButton(onPressed: widget.onShowAll, child: const Text('Все  →')),
        ],
      ),
    );
  }

  // ─── Карусель ───────────────────────────────────────────────────────

  Widget _buildCarousel() {
    return SizedBox(
      height: _railHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Кадр занимает около пятой части окна: в ряд помещается пять
          // штук, и лента читается лентой, а не парой афиш.
          _itemWidth = constraints.maxWidth < 700
              ? math.min(constraints.maxWidth - 90, 280.0)
              : (constraints.maxWidth * 0.19).clamp(220.0, 300.0);

          final featured = _featuredIndex;

          return MouseRegion(
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: Stack(
              children: [
                HorizontalWheelScroll(
                  controller: _controller,
                  child: ListView.separated(
                    controller: _controller,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: _sidePad),
                    itemCount: widget.movies.length,
                    separatorBuilder: (_, _) => const SizedBox(width: _gap),
                    itemBuilder: (context, i) {
                      final distance = _distanceFromCenter(i).clamp(0.0, 1.0);
                      return SizedBox(
                        width: _itemWidth,
                        child: _CarouselCard(
                          movie: widget.movies[i],
                          // Высота падает по мере удаления от центра —
                          // непрерывно, а не ступенькой, иначе при прокрутке
                          // соседние кадры «прыгают». Ширина у всех одна:
                          // так между ними нет провалов.
                          height: _railHeight *
                              (1 - (1 - _sideHeightFactor) * distance),
                          dim: 0.62 * distance,
                          expanded: i == featured,
                          onOpen: () => widget.onOpen(widget.movies[i]),
                          onQuickAdd: widget.onQuickAdd == null
                              ? null
                              : () => widget.onQuickAdd!(widget.movies[i]),
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  left: 10,
                  top: _railHeight / 2 - 20,
                  child: ScrollArrow(
                    forward: false,
                    visible: _hover && _canBack,
                    onTap: () => _scrollBy(false),
                  ),
                ),
                Positioned(
                  right: 10,
                  top: _railHeight / 2 - 20,
                  child: ScrollArrow(
                    forward: true,
                    visible: _hover && _canForward,
                    onTap: () => _scrollBy(true),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── Обычная лента постеров ─────────────────────────────────────────

  Widget _buildPosterStrip() {
    return SizedBox(
      height: 268,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Stack(
          children: [
            HorizontalWheelScroll(
              controller: _controller,
              child: ListView.separated(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                itemCount: widget.movies.length,
                separatorBuilder: (_, _) => const SizedBox(width: 16),
                itemBuilder: (context, i) {
                  final movie = widget.movies[i];
                  return SizedBox(
                    width: 158,
                    child: PosterCard(
                      title: movie.title,
                      subtitle: movie.shortMeta,
                      imageUrl: movie.posterUrl,
                      badge: movie.rating,
                      seen: movie.isWatched,
                      hoverAction: Icons.play_arrow_rounded,
                      onHoverAction: () => widget.onOpen(movie),
                      onTap: () => widget.onOpen(movie),
                      onLongPress: widget.onQuickAdd == null
                          ? null
                          : () => widget.onQuickAdd!(movie),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              left: 8,
              top: 88,
              child: ScrollArrow(
                forward: false,
                visible: _hover && _canBack,
                onTap: () => _scrollBy(false),
              ),
            ),
            Positioned(
              right: 8,
              top: 88,
              child: ScrollArrow(
                forward: true,
                visible: _hover && _canForward,
                onTap: () => _scrollBy(true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Кадр в карусели. Центральный крупнее, светлее и с кнопками;
/// боковые ужаты и притемнены.
class _CarouselCard extends StatefulWidget {
  final Movie movie;
  final double height;
  final double dim;
  final bool expanded;
  final VoidCallback onOpen;
  final VoidCallback? onQuickAdd;

  const _CarouselCard({
    required this.movie,
    required this.height,
    required this.dim,
    required this.expanded,
    required this.onOpen,
    this.onQuickAdd,
  });

  @override
  State<_CarouselCard> createState() => _CarouselCardState();
}

class _CarouselCardState extends State<_CarouselCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        // Все кадры стоят на одной линии, как на полке, и растут вверх.
        // Ширина у всех одинаковая — между ними нет провалов.
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.large),
              boxShadow: widget.expanded
                  ? (_hover ? AppShadow.glow(AppColors.gold) : AppShadow.raised)
                  : AppShadow.card,
              border: Border.all(
                color: widget.expanded && _hover
                    ? AppColors.goldWash(0.65)
                    : widget.expanded
                        ? AppColors.goldWash(0.28)
                        : AppColors.border,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.large - 1),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (movie.backdropUrl != null)
                    CachedNetworkImage(
                      imageUrl: movie.backdropUrl!,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 240),
                      placeholder: (_, _) => Container(color: AppColors.surface),
                      errorWidget: (_, _, _) => Container(color: AppColors.surface),
                    )
                  else
                    Container(color: AppColors.surface),

                  const DecoratedBox(decoration: BoxDecoration(gradient: AppColors.scrim)),

                  // Боковые кадры уходят в тень — центр читается сам собой.
                  if (widget.dim > 0)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.bg.withValues(alpha: widget.dim),
                      ),
                    ),

                  if (movie.isWatched)
                    const Positioned(
                      top: 12,
                      left: 12,
                      child: _SeenChip(),
                    ),

                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 13,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (movie.genres.isNotEmpty)
                          Text(
                            movie.genres.take(2).join('  ·  ').toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: kEyebrowStyle.copyWith(color: AppColors.gold),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          movie.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: widget.expanded ? 18 : 14,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                            letterSpacing: -0.4,
                            shadows: const [
                              Shadow(
                                color: Color(0xCC000000),
                                blurRadius: 14,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            if (movie.voteAverage > 0) ...[
                              _Chip('★ ${movie.voteAverage.toStringAsFixed(1)}', accent: true),
                              const SizedBox(width: 7),
                            ],
                            if (movie.releaseYear != null) _Chip('${movie.releaseYear}'),
                          ],
                        ),
                        // Кнопки только у центрального: на боковых они были бы
                        // мелкими и всё равно недоступными для попадания.
                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 220),
                          crossFadeState: widget.expanded
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                          firstChild: const SizedBox.shrink(),
                          secondChild: Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Row(
                              children: [
                                FilledButton.icon(
                                  onPressed: widget.onOpen,
                                  icon: const Icon(Icons.play_arrow_rounded, size: 17),
                                  label: const Text('Смотреть'),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 13,
                                      vertical: 8,
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (widget.onQuickAdd != null) ...[
                                  const SizedBox(width: 8),
                                  IconButton(
                                    onPressed: widget.onQuickAdd,
                                    tooltip: 'В список к просмотру',
                                    icon: const Icon(Icons.add, size: 17),
                                    style: IconButton.styleFrom(
                                      backgroundColor: const Color(0x66121218),
                                      foregroundColor: AppColors.text,
                                      side: const BorderSide(color: Color(0x44FFFFFF)),
                                      minimumSize: const Size(34, 34),
                                      padding: EdgeInsets.zero,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SeenChip extends StatelessWidget {
  const _SeenChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.green,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check, size: 13, color: AppColors.bg),
          SizedBox(width: 4),
          Text(
            'просмотрено',
            style: TextStyle(color: AppColors.bg, fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final bool accent;

  const _Chip(this.text, {this.accent = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent ? AppColors.goldWash(0.2) : const Color(0x55000000),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: accent ? AppColors.goldWash(0.5) : const Color(0x33FFFFFF),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: accent ? AppColors.gold : AppColors.text,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
