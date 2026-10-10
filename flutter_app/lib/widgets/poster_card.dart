import 'package:flutter/material.dart';

import '../theme.dart';
import 'net_image.dart';

/// Карточка с обложкой — общая для фильмов и книг.
///
/// Изображения кэшируются на устройстве, поэтому при повторном открытии
/// список появляется мгновенно, без единой загрузки.
///
/// При наведении карточка чуть поднимается и подсвечивается: без реакции
/// на курсор интерфейс кажется картинкой, а не приложением.
class PosterCard extends StatefulWidget {
  final String? imageUrl;
  final String title;
  final String? subtitle;

  /// Оценка в углу обложки, если она есть.
  final int? badge;

  /// Заглушка, когда обложки нет.
  final String fallbackEmoji;

  /// Отметка «уже смотрел / читал» — галочка поверх обложки.
  final bool seen;

  /// Кнопка, всплывающая по центру обложки при наведении.
  final IconData? hoverAction;
  final VoidCallback? onHoverAction;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const PosterCard({
    super.key,
    required this.title,
    this.imageUrl,
    this.subtitle,
    this.badge,
    this.fallbackEmoji = '🎬',
    this.seen = false,
    this.hoverAction,
    this.onHoverAction,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          offset: Offset(0, _hover ? -0.012 : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.medium),
                    boxShadow: _hover ? AppShadow.raised : AppShadow.card,
                    border: Border.all(
                      color: _hover ? AppColors.goldWash(0.55) : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.medium - 1.5),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _Image(url: widget.imageUrl, fallbackEmoji: widget.fallbackEmoji),

                        // Лёгкое затемнение по низу: постеры бывают светлыми,
                        // и на них тонут значки поверх обложки.
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.center,
                              colors: [Color(0x77000000), Colors.transparent],
                            ),
                          ),
                        ),

                        // Затемнение под кнопку — только при наведении.
                        AnimatedOpacity(
                          opacity: _hover && widget.hoverAction != null ? 1 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: const DecoratedBox(
                            decoration: BoxDecoration(color: Color(0x66000000)),
                          ),
                        ),

                        if (widget.badge != null)
                          Positioned(top: 8, right: 8, child: _Badge(value: widget.badge!)),

                        if (widget.seen)
                          const Positioned(top: 8, left: 8, child: _SeenMark()),

                        if (widget.hoverAction != null)
                          Center(
                            child: AnimatedScale(
                              scale: _hover ? 1 : 0.6,
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOutBack,
                              child: AnimatedOpacity(
                                opacity: _hover ? 1 : 0,
                                duration: const Duration(milliseconds: 160),
                                child: _HoverButton(
                                  icon: widget.hoverAction!,
                                  onTap: widget.onHoverAction ?? widget.onTap,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: TextStyle(
                  color: _hover ? AppColors.gold : AppColors.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  letterSpacing: -0.2,
                ),
                child: Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    widget.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HoverButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _HoverButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46,
        width: 46,
        decoration: BoxDecoration(
          gradient: AppColors.goldGradient,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Color(0x88000000), blurRadius: 14, offset: Offset(0, 5))],
        ),
        child: Icon(icon, color: AppColors.bg, size: 24),
      ),
    );
  }
}

class _Image extends StatelessWidget {
  final String? url;
  final String fallbackEmoji;

  const _Image({this.url, required this.fallbackEmoji});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return _Fallback(emoji: fallbackEmoji);
    return NetImage(
      imageUrl: url!,
      placeholder: (_, _) => const _Skeleton(),
      errorWidget: (_, _, _) => _Fallback(emoji: fallbackEmoji),
    );
  }
}

/// Пульсирующая заглушка вместо серого прямоугольника: пока грузится обложка,
/// сетка выглядит живой, а не поломанной.
class _Skeleton extends StatefulWidget {
  const _Skeleton();

  @override
  State<_Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<_Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => DecoratedBox(
        decoration: BoxDecoration(
          color: Color.lerp(AppColors.surface, AppColors.surfaceTop, _controller.value),
        ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  final String emoji;
  const _Fallback({required this.emoji});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surfaceHigh, AppColors.surface],
        ),
      ),
      alignment: Alignment.center,
      child: Text(emoji, style: const TextStyle(fontSize: 30)),
    );
  }
}

class _Badge extends StatelessWidget {
  final int value;
  const _Badge({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: AppColors.goldGradient,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: const [
          BoxShadow(color: Color(0x77000000), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Text(
        '$value',
        style: TextStyle(
          color: AppColors.bg,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SeenMark extends StatelessWidget {
  const _SeenMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      width: 24,
      decoration: BoxDecoration(
        color: AppColors.green,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(color: Color(0x77000000), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Icon(Icons.check, size: 15, color: AppColors.bg),
    );
  }
}

/// Сетка обложек, подстраивающаяся под ширину окна.
class PosterGrid extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;

  /// Минимальная ширина карточки. Крупнее — меньше колонок, но каждая
  /// обложка читается; так каталог выглядит дороже плотной мозаики.
  final double minTileWidth;

  final double aspectRatio;

  const PosterGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.minTileWidth = 190,
    this.aspectRatio = 0.54,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / minTileWidth).floor().clamp(2, 10);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: aspectRatio,
            crossAxisSpacing: 18,
            mainAxisSpacing: 24,
          ),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        );
      },
    );
  }
}
