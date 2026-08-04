import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/book_repository.dart';
import '../models/book.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/poster_card.dart';
import '../widgets/rating_sheet.dart';
import 'search_screen.dart';

class BooksScreen extends StatefulWidget {
  const BooksScreen({super.key});

  @override
  State<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends State<BooksScreen> {
  bool _showRead = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BookRepository>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<BookRepository>();
    final books = _showRead ? repo.read : repo.wishlist;

    return Column(
      children: [
        SectionHeader(
          title: 'Книги',
          actions: [
            IconButton(
              tooltip: 'Поиск',
              icon: const Icon(Icons.search, color: AppColors.textDim),
              onPressed: _openSearch,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedToggle<bool>(
              value: _showRead,
              options: {
                true: 'Прочитано · ${repo.read.length}',
                false: 'Хочу прочесть · ${repo.wishlist.length}',
              },
              onChanged: (v) => setState(() => _showRead = v),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.gold,
            backgroundColor: AppColors.surface,
            onRefresh: () => context.read<BookRepository>().refresh(),
            child: books.isEmpty
                ? EmptyHint(
                    emoji: '📚',
                    text: _showRead
                        ? 'Здесь появятся прочитанные книги'
                        : 'Список «хочу прочесть» пуст',
                  )
                : PosterGrid(
                    itemCount: books.length,
                    itemBuilder: (context, i) => PosterCard(
                      title: books[i].title,
                      subtitle: books[i].author,
                      imageUrl: books[i].coverUrl,
                      badge: books[i].rating,
                      fallbackEmoji: '📖',
                      onTap: () => _showActions(books[i]),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  void _openSearch() {
    final repo = context.read<BookRepository>();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SearchScreen(
        hint: 'Название книги или автор',
        onSearch: (query) async {
          final found = await repo.search(query);
          return found
              .map((b) => SearchResult(
                    title: b.title,
                    subtitle: b.author,
                    imageUrl: b.coverUrl,
                    fallbackEmoji: '📖',
                    payload: b,
                  ))
              .toList();
        },
        onPick: (searchContext, result) {
          final book = result.payload as Book;
          repo.addToWishlist(book);
          ScaffoldMessenger.of(searchContext).showSnackBar(
            SnackBar(
              content: Text('«${book.title}» добавлена в список'),
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
    ));
  }

  void _showActions(Book book) {
    final read = _showRead;
    showActionSheet(
      context,
      title: book.title,
      actions: (sheetContext) => [
        if (!read)
          ListTile(
            leading: const Icon(Icons.check_circle_outline, color: AppColors.green),
            title: const Text('Отметить прочитанной'),
            onTap: () {
              Navigator.pop(sheetContext);
              context.read<BookRepository>().markRead(book);
            },
          ),
        ListTile(
          leading: const Icon(Icons.star_outline, color: AppColors.gold),
          title: Text(book.rating == null ? 'Поставить оценку' : 'Изменить оценку'),
          onTap: () async {
            Navigator.pop(sheetContext);
            final rating = await pickRating(context, title: book.title, current: book.rating);
            if (rating != null && mounted) {
              await context.read<BookRepository>().rate(book, rating);
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline, color: AppColors.red),
          title: const Text('Удалить'),
          onTap: () {
            Navigator.pop(sheetContext);
            final repo = context.read<BookRepository>();
            read ? repo.removeFromRead(book.bookId) : repo.removeFromWishlist(book.bookId);
          },
        ),
      ],
    );
  }
}
