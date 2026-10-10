import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/book_repository.dart';
import '../data/profile_repository.dart';
import '../models/book.dart';
import '../theme.dart';
import '../widgets/ai_panel.dart';
import '../widgets/common.dart';
import '../widgets/poster_card.dart';
import '../widgets/rating_sheet.dart';
import '../widgets/sub_tabs.dart';
import 'ai_suggest_screen.dart';
import 'book_detail_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

/// Раздел «Книги»: те же пять вкладок, что в книжном режиме сайта.
class BooksScreen extends StatefulWidget {
  const BooksScreen({super.key});

  @override
  State<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends State<BooksScreen> {
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

    return SubTabView(
      header: SectionHeader(
        title: 'Книги',
        actions: [
          IconButton(
            tooltip: 'Поиск',
            icon: Icon(Icons.search, color: AppColors.textDim),
            onPressed: _openSearch,
          ),
        ],
      ),
      tabs: [
        SubTab(label: 'Открытие', builder: (_) => const BooksDiscoverTab()),
        SubTab(
          label: 'Дневник',
          count: repo.read.length,
          builder: (_) => const BookListTab(showRead: true),
        ),
        SubTab(
          label: 'Хочу прочесть',
          count: repo.wishlist.length,
          builder: (_) => const BookListTab(showRead: false),
        ),
        SubTab(
          label: '✦ Посоветуй',
          builder: (_) => AiSuggestTab<Book>(
            hint: 'Например: нон-фикшн про космос, но не сухо',
            examples: const [
              'что-то короткое и лёгкое',
              'научпоп про мозг',
              'как «Дюна», но не фантастика',
              'русская проза XX века',
            ],
            emptyEmoji: '📚',
            fetch: (query) => context.read<ProfileRepository>().suggestBooks(query: query),
            cardBuilder: (context, book) => _SuggestedBookCard(book: book),
          ),
        ),
        SubTab(label: 'Профиль', builder: (_) => const BookProfileTab()),
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
        // Открываем карточку — как в кино. Раньше поиск молча добавлял книгу
        // в список, и посмотреть описание перед этим было негде.
        onPick: (searchContext, result) => Navigator.of(searchContext).push(
          MaterialPageRoute(
            builder: (_) => BookDetailScreen(book: result.payload as Book),
          ),
        ),
      ),
    ));
  }
}

/// Вкладка «Открытие» — подборка популярного из Google Books.
class BooksDiscoverTab extends StatefulWidget {
  const BooksDiscoverTab({super.key});

  @override
  State<BooksDiscoverTab> createState() => _BooksDiscoverTabState();
}

class _BooksDiscoverTabState extends State<BooksDiscoverTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BookRepository>().loadPopular();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<BookRepository>();
    final books = repo.popular;

    if (books.isEmpty) {
      return repo.loadingPopular
          ? Center(child: CircularProgressIndicator(color: AppColors.gold))
          : RefreshIndicator(
              color: AppColors.gold,
              backgroundColor: AppColors.sheet,
              onRefresh: () => context.read<BookRepository>().loadPopular(forceRefresh: true),
              child: const EmptyHint(
                emoji: '📚',
                text: 'Подборка не загрузилась.\nПотяни вниз, чтобы повторить',
              ),
            );
    }

    return RefreshIndicator(
      color: AppColors.gold,
      backgroundColor: AppColors.sheet,
      onRefresh: () => context.read<BookRepository>().loadPopular(forceRefresh: true),
      child: PosterGrid(
        itemCount: books.length,
        itemBuilder: (context, i) {
          final book = books[i];
          return PosterCard(
            title: book.title,
            subtitle: book.author,
            imageUrl: book.coverUrl,
            fallbackEmoji: '📖',
            // Отметка «уже читал» приходит с сервера вместе с подборкой,
            // но локальные списки свежее — сверяемся с ними.
            badge: repo.ratingOf(book.bookId),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => BookDetailScreen(book: book)),
            ),
          );
        },
      ),
    );
  }
}

/// Дневник и список «хочу прочесть» — отличаются только источником.
class BookListTab extends StatelessWidget {
  final bool showRead;

  const BookListTab({super.key, required this.showRead});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<BookRepository>();
    final books = showRead ? repo.read : repo.wishlist;

    return RefreshIndicator(
      color: AppColors.gold,
      backgroundColor: AppColors.sheet,
      onRefresh: () => context.read<BookRepository>().refresh(),
      child: books.isEmpty
          ? EmptyHint(
              emoji: '📚',
              text: showRead
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
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => BookDetailScreen(book: books[i])),
                ),
                onLongPress: () => _showActions(context, books[i]),
              ),
            ),
    );
  }

  void _showActions(BuildContext context, Book book) {
    final repo = context.read<BookRepository>();

    showActionSheet(
      context,
      title: book.title,
      actions: (sheetContext) => [
        if (!showRead)
          ListTile(
            leading: Icon(Icons.check_circle_outline, color: AppColors.green),
            title: const Text('Отметить прочитанной'),
            onTap: () {
              Navigator.pop(sheetContext);
              repo.markRead(book);
            },
          ),
        ListTile(
          leading: Icon(Icons.star_outline, color: AppColors.gold),
          title: Text(book.rating == null ? 'Поставить оценку' : 'Изменить оценку'),
          onTap: () async {
            Navigator.pop(sheetContext);
            final rating = await pickRating(context, title: book.title, current: book.rating);
            if (rating != null && context.mounted) await repo.rate(book, rating);
          },
        ),
        ListTile(
          leading: Icon(Icons.delete_outline, color: AppColors.red),
          title: const Text('Удалить'),
          onTap: () {
            Navigator.pop(sheetContext);
            showRead
                ? repo.removeFromRead(book.bookId)
                : repo.removeFromWishlist(book.bookId);
          },
        ),
      ],
    );
  }
}

/// Карточка из подборки AI: обложка плюс объяснение, почему это предложено.
class _SuggestedBookCard extends StatelessWidget {
  final Book book;

  const _SuggestedBookCard({required this.book});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: PosterCard(
            title: book.title,
            subtitle: book.author,
            imageUrl: book.coverUrl,
            fallbackEmoji: '📖',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => BookDetailScreen(book: book)),
            ),
          ),
        ),
        if (book.aiReason != null) AiReasonNote(book.aiReason!),
      ],
    );
  }
}
