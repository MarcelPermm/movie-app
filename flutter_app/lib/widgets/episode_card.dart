import 'package:flutter/material.dart';

import '../models/movie_details.dart';
import '../theme.dart';
import 'net_image.dart';

/// Карточка серии с превью — то же, что на сайте: обложка, номер,
/// название, описание и отметка «Идёт» у той, что открыта в плеере.
class EpisodeCard extends StatefulWidget {
  final Episode episode;
  final bool isPlaying;
  final VoidCallback onPlay;

  /// Серия отмечена просмотренной — галочка в углу кадра.
  final bool watched;
  final VoidCallback? onToggleWatched;

  const EpisodeCard({
    super.key,
    required this.episode,
    required this.isPlaying,
    required this.onPlay,
    this.watched = false,
    this.onToggleWatched,
  });

  @override
  State<EpisodeCard> createState() => _EpisodeCardState();
}

class _EpisodeCardState extends State<EpisodeCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ep = widget.episode;
    final long = ep.overview.length > 110;

    return InkWell(
      onTap: widget.onPlay,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(
            color: widget.isPlaying ? AppColors.gold : AppColors.border,
            width: widget.isPlaying ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (ep.stillUrl != null)
                    NetImage(
                      imageUrl: ep.stillUrl!,
                      aspect: 16 / 9,
                      placeholder: (_, _) => Container(color: AppColors.bg),
                      errorWidget: (_, _, _) => const _NoStill(),
                    )
                  else
                    const _NoStill(),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.bg.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        '${ep.episodeNumber}',
                        style: TextStyle(
                          color: AppColors.gold,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  if (widget.watched && !widget.isPlaying)
                    Container(color: AppColors.bg.withValues(alpha: 0.45)),
                  if (widget.onToggleWatched != null)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: _WatchedToggle(
                        watched: widget.watched,
                        onTap: widget.onToggleWatched!,
                      ),
                    ),
                  if (widget.isPlaying)
                    Container(
                      color: AppColors.bg.withValues(alpha: 0.55),
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.gold,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '▶  Идёт',
                          style: TextStyle(
                            color: AppColors.bg,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ep.name.isEmpty ? 'Серия ${ep.episodeNumber}' : ep.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.isPlaying ? AppColors.gold : AppColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  if (ep.meta.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      ep.meta,
                      style: TextStyle(color: AppColors.textDim, fontSize: 11),
                    ),
                  ],
                  if (ep.overview.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      ep.overview,
                      maxLines: _expanded ? null : 3,
                      overflow: _expanded ? null : TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textDim,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                    if (long)
                      GestureDetector(
                        // Разворачивание не должно запускать серию.
                        onTap: () => setState(() => _expanded = !_expanded),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _expanded ? 'свернуть' : 'ещё',
                            style: TextStyle(
                              color: AppColors.gold,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Кружок-галочка «просмотрено» в углу кадра. Отдельная кнопка, чтобы
/// отметка не запускала серию.
class _WatchedToggle extends StatelessWidget {
  final bool watched;
  final VoidCallback onTap;

  const _WatchedToggle({required this.watched, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: watched ? 'Снять отметку' : 'Отметить просмотренной',
      child: Material(
        color: watched ? AppColors.green : AppColors.bg.withValues(alpha: 0.72),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(
              Icons.check,
              size: 17,
              color: watched ? AppColors.bg : AppColors.textDim,
            ),
          ),
        ),
      ),
    );
  }
}

class _NoStill extends StatelessWidget {
  const _NoStill();

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.bg,
        alignment: Alignment.center,
        child: const Text('📺', style: TextStyle(fontSize: 26)),
      );
}
