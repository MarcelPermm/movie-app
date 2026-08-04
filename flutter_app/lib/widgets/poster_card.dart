import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Карточка с обложкой — общая для фильмов и книг.
///
/// Изображения кэшируются на устройстве, поэтому при повторном открытии
/// список появляется мгновенно, без единой загрузки.
class PosterCard extends StatelessWidget {
  final String? imageUrl;
  final String title;
  final String? subtitle;

  /// Оценка в углу обложки, если она есть.
  final int? badge;

  /// Заглушка, когда обложки нет.
  final String fallbackEmoji;

  final VoidCallback? onTap;

  const PosterCard({
    super.key,
    required this.title,
    this.imageUrl,
    this.subtitle,
    this.badge,
    this.fallbackEmoji = '🎬',
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Image(url: imageUrl, fallbackEmoji: fallbackEmoji),
                  if (badge != null)
                    Positioned(top: 6, right: 6, child: _Badge(value: badge!)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textDim, fontSize: 11),
              ),
            ),
        ],
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
    return CachedNetworkImage(
      imageUrl: url!,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (_, _) => Container(color: AppColors.surface),
      errorWidget: (_, _, _) => _Fallback(emoji: fallbackEmoji),
    );
  }
}

class _Fallback extends StatelessWidget {
  final String emoji;
  const _Fallback({required this.emoji});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      alignment: Alignment.center,
      child: Text(emoji, style: const TextStyle(fontSize: 28)),
    );
  }
}

class _Badge extends StatelessWidget {
  final int value;
  const _Badge({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.gold,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$value',
        style: const TextStyle(
          color: AppColors.bg,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Сетка обложек, подстраивающаяся под ширину окна.
class PosterGrid extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;

  const PosterGrid({super.key, required this.itemCount, required this.itemBuilder});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 160).floor().clamp(2, 10);
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: 0.52,
            crossAxisSpacing: 14,
            mainAxisSpacing: 18,
          ),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        );
      },
    );
  }
}
