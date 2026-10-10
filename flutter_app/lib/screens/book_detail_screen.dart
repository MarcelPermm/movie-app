import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../data/book_repository.dart';
import '../models/book.dart';
import '../theme.dart';
import '../widgets/poster_card.dart';
import '../widgets/rating_sheet.dart';

/// Карточка книги: обложка, описание, действия и похожие.
///
/// На вход берётся уже известная книга (из списка или поиска) — она рисуется
/// сразу, а полные данные подгружаются следом. Так экран открывается без
/// пустого кадра, даже если сеть медленная.
class BookDetailScreen extends StatefulWidget {
  final Book book;

  const BookDetailScreen({super.key, required this.book});

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  late Book _book = widget.book;
  List<Book> _similar = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<BookRepository>();
    try {
      final details = await repo.details(_book.bookId);
      if (!mounted) return;
      setState(() => _book = details);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }

    try {
      final similar = await repo.similar(_book.bookId);
      if (!mounted) return;
      setState(() => _similar = similar);
    } on ApiException {
      // Похожие — приятное дополнение, без них карточка полноценна.
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<BookRepository>();
    final isRead = repo.isRead(_book.bookId);
    final inWishlist = repo.isInWishlist(_book.bookId);
    // Своя оценка живёт в списке прочитанного — она свежее, чем в деталях.
    final myRating = _ratingFromList(repo.read, _book.bookId) ?? _book.rating;

    return Scaffold(
      appBar: AppBar(title: Text(_book.title, style: const TextStyle(fontSize: 16))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _buildHeader(myRating),
          const SizedBox(height: 18),
          _buildActions(isRead, inWishlist, myRating),
          if (_book.description.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _Label('Описание'),
            const SizedBox(height: 8),
            Text(
              _book.description,
              style: const TextStyle(color: AppColors.text, fontSize: 13.5, height: 1.6),
            ),
          ],
          if (_book.genres.isNotEmpty) ...[
            const SizedBox(height: 18),
            const _Label('Жанры'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: _book.genres
                  .map((g) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          g,
                          style: const TextStyle(color: AppColors.textDim, fontSize: 11.5),
                        ),
                      ))
                  .toList(),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 12)),
          ],
          if (_similar.isNotEmpty) ...[
            const SizedBox(height: 24),
            const _Label('Похожие книги'),
            const SizedBox(height: 10),
            SizedBox(
              height: 210,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _similar.length,
                separatorBuilder: (_, _) => const SizedBox(width: 11),
                itemBuilder: (context, i) => SizedBox(
                  width: 105,
                  child: PosterCard(
                    title: _similar[i].title,
                    subtitle: _similar[i].author,
                    imageUrl: _similar[i].coverUrl,
                    fallbackEmoji: '📖',
                    onTap: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => BookDetailScreen(book: _similar[i]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(int? myRating) {
    final community = _book.communityRating;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          child: SizedBox(
            width: 118,
            height: 176,
            child: _book.coverUrl == null
                ? Container(
                    color: AppColors.surface,
                    alignment: Alignment.center,
                    child: const Text('📖', style: TextStyle(fontSize: 34)),
                  )
                : CachedNetworkImage(
                    imageUrl: _book.coverUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(color: AppColors.surface),
                    errorWidget: (_, _, _) => Container(color: AppColors.surface),
                  ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _book.title,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              if (_book.author != null) ...[
                const SizedBox(height: 5),
                Text(
                  _book.author!,
                  style: const TextStyle(color: AppColors.gold, fontSize: 13.5),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (_book.year.isNotEmpty) _meta('📅', _book.year),
                  if (_book.pageCount != null && _book.pageCount! > 0)
                    _meta('📄', '${_book.pageCount} с.'),
                  if (community != null)
                    _meta('★', '${community.toStringAsFixed(1)} на Google Books'),
                  if (myRating != null) _meta('🏅', 'моя оценка $myRating'),
                ],
              ),
              if (_book.publisher != null) ...[
                const SizedBox(height: 8),
                Text(
                  _book.publisher!,
                  style: const TextStyle(color: AppColors.textDim, fontSize: 11.5),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _meta(String icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
        ],
      );

  Widget _buildActions(bool isRead, bool inWishlist, int? myRating) {
    final repo = context.read<BookRepository>();

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          onPressed: () async {
            final rating = await pickRating(context, title: _book.title, current: myRating);
            if (rating != null && mounted) await repo.rate(_book, rating);
          },
          icon: const Icon(Icons.star_outline, size: 18),
          label: Text(myRating == null ? 'Оценить' : 'Оценка $myRating'),
        ),
        OutlinedButton.icon(
          onPressed: () =>
              isRead ? repo.removeFromRead(_book.bookId) : repo.markRead(_book),
          icon: Icon(
            isRead ? Icons.check_circle : Icons.check_circle_outline,
            size: 18,
            color: isRead ? AppColors.green : AppColors.textDim,
          ),
          label: Text(isRead ? 'Прочитана' : 'Отметить прочитанной'),
          style: OutlinedButton.styleFrom(
            foregroundColor: isRead ? AppColors.green : AppColors.text,
            side: BorderSide(color: isRead ? AppColors.green : AppColors.border),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => inWishlist
              ? repo.removeFromWishlist(_book.bookId)
              : repo.addToWishlist(_book),
          icon: Icon(
            inWishlist ? Icons.bookmark : Icons.bookmark_border,
            size: 18,
            color: inWishlist ? AppColors.gold : AppColors.textDim,
          ),
          label: Text(inWishlist ? 'В списке' : 'Хочу прочесть'),
          style: OutlinedButton.styleFrom(
            foregroundColor: inWishlist ? AppColors.gold : AppColors.text,
            side: BorderSide(color: inWishlist ? AppColors.goldDim : AppColors.border),
          ),
        ),
      ],
    );
  }
}

/// Оценка книги из локального списка, если она там есть.
int? _ratingFromList(List<Book> books, String bookId) {
  for (final b in books) {
    if (b.bookId == bookId) return b.rating;
  }
  return null;
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: AppColors.textDim,
          fontSize: 10,
          letterSpacing: 0.9,
          fontWeight: FontWeight.w700,
        ),
      );
}
