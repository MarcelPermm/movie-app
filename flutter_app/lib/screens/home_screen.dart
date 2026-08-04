import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/movie_repository.dart';
import '../models/movie.dart';
import '../theme.dart';
import '../widgets/movie_card.dart';
import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Кэш поднимется синхронно внутри load(), сеть — уже в фоне.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MovieRepository>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<MovieRepository>();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            const Text('🐒', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            const Text(
              'Monkey App',
              style: TextStyle(
                color: AppColors.gold,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 12),
            const _SyncBadge(),
          ],
        ),
        actions: [
          _MediaTypeToggle(
            value: repo.mediaType,
            onChanged: (v) => context.read<MovieRepository>().setMediaType(v),
          ),
          IconButton(
            tooltip: 'Поиск',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.gold,
        backgroundColor: AppColors.surface,
        onRefresh: () => context.read<MovieRepository>().refresh(),
        child: IndexedStack(
          index: _tab,
          children: [
            _MovieGrid(
              movies: repo.watched,
              emptyText: 'Пока ничего не отмечено просмотренным',
              onLongPress: (m) => _showActions(m, watched: true),
            ),
            _MovieGrid(
              movies: repo.watchlist,
              emptyText: 'Список «к просмотру» пуст',
              onLongPress: (m) => _showActions(m, watched: false),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.gold.withValues(alpha: 0.16),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.check_circle_outline),
            selectedIcon: const Icon(Icons.check_circle, color: AppColors.gold),
            label: 'Просмотрено (${repo.watched.length})',
          ),
          NavigationDestination(
            icon: const Icon(Icons.bookmark_border),
            selectedIcon: const Icon(Icons.bookmark, color: AppColors.gold),
            label: 'К просмотру (${repo.watchlist.length})',
          ),
        ],
      ),
    );
  }

  void _showActions(Movie movie, {required bool watched}) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Text(
                movie.title,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (!watched)
              ListTile(
                leading: const Icon(Icons.check_circle_outline, color: AppColors.green),
                title: const Text('Отметить просмотренным'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.read<MovieRepository>().markWatched(movie);
                },
              ),
            if (watched)
              ListTile(
                leading: const Icon(Icons.star_outline, color: AppColors.gold),
                title: Text(movie.rating == null ? 'Поставить оценку' : 'Изменить оценку'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showRating(movie);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.red),
              title: const Text('Удалить'),
              onTap: () {
                Navigator.pop(sheetContext);
                final repo = context.read<MovieRepository>();
                watched ? repo.removeFromWatched(movie.id) : repo.removeFromWatchlist(movie.id);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showRating(Movie movie) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                movie.title,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(10, (i) {
                  final value = i + 1;
                  final selected = movie.rating == value;
                  return SizedBox(
                    width: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: selected ? AppColors.gold : AppColors.bg,
                        foregroundColor: selected ? AppColors.bg : AppColors.text,
                      ),
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        context.read<MovieRepository>().rate(movie, value);
                      },
                      child: Text('$value'),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Показывает, что происходит с синхронизацией, не мешая пользоваться списком.
class _SyncBadge extends StatelessWidget {
  const _SyncBadge();

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<MovieRepository>();

    if (repo.syncing) {
      return const SizedBox(
        height: 13,
        width: 13,
        child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.goldDim),
      );
    }
    if (repo.pendingWrites > 0) {
      return _pill('↑ ${repo.pendingWrites}', AppColors.blue);
    }
    if (repo.lastError != null) {
      return _pill('офлайн', AppColors.textDim);
    }
    return const SizedBox.shrink();
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 11)),
      );
}

class _MediaTypeToggle extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _MediaTypeToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button('Фильмы', 'movie'),
          _button('Сериалы', 'tv'),
        ],
      ),
    );
  }

  Widget _button(String label, String type) {
    final active = value == type;
    return GestureDetector(
      onTap: () => onChanged(type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.gold : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? AppColors.bg : AppColors.textDim,
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _MovieGrid extends StatelessWidget {
  final List<Movie> movies;
  final String emptyText;
  final void Function(Movie) onLongPress;

  const _MovieGrid({
    required this.movies,
    required this.emptyText,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (movies.isEmpty) {
      // ListView, а не Center — иначе RefreshIndicator некуда тянуть.
      return ListView(
        children: [
          const SizedBox(height: 120),
          Text(
            emptyText,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textDim, fontSize: 14),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 160).floor().clamp(2, 8);
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: 0.52,
            crossAxisSpacing: 14,
            mainAxisSpacing: 18,
          ),
          itemCount: movies.length,
          itemBuilder: (context, i) => MovieCard(
            movie: movies[i],
            onLongPress: () => onLongPress(movies[i]),
            onTap: () => onLongPress(movies[i]),
          ),
        );
      },
    );
  }
}
