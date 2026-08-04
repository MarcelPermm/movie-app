import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/movie.dart';
import '../theme.dart';

/// Постер с названием. Изображения кэшируются на устройстве,
/// поэтому при повторном открытии список появляется без единой загрузки.
class MovieCard extends StatelessWidget {
  final Movie movie;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const MovieCard({
    super.key,
    required this.movie,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
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
                  _Poster(url: movie.posterUrl),
                  if (movie.rating != null)
                    Positioned(top: 6, right: 6, child: _RatingBadge(rating: movie.rating!)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            movie.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          if (movie.releaseYear != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${movie.releaseYear}',
                style: const TextStyle(color: AppColors.textDim, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  final String? url;
  const _Poster({this.url});

  @override
  Widget build(BuildContext context) {
    if (url == null) return const _PosterFallback();
    return CachedNetworkImage(
      imageUrl: url!,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (_, _) => Container(color: AppColors.surface),
      errorWidget: (_, _, _) => const _PosterFallback(),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      alignment: Alignment.center,
      child: const Text('🎬', style: TextStyle(fontSize: 28)),
    );
  }
}

class _RatingBadge extends StatelessWidget {
  final int rating;
  const _RatingBadge({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.gold,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$rating',
        style: const TextStyle(
          color: AppColors.bg,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
