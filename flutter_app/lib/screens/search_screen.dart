import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../data/movie_repository.dart';
import '../models/movie.dart';
import '../theme.dart';
import '../widgets/movie_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  List<Movie> _results = const [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Ждём паузу в наборе, чтобы не слать запрос на каждую букву.
  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = const [];
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _run(value));
  }

  Future<void> _run(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final found = await context.read<MovieRepository>().search(query);
      if (!mounted) return;
      setState(() => _results = found);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          decoration: const InputDecoration(
            hintText: 'Название фильма или сериала',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
          style: const TextStyle(color: AppColors.text, fontSize: 16),
        ),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 18),
              child: Center(
                child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.goldDim),
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.red, fontSize: 14),
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Text(
          _controller.text.trim().isEmpty
              ? 'Начни вводить название'
              : (_loading ? '' : 'Ничего не нашлось'),
          style: const TextStyle(color: AppColors.textDim, fontSize: 14),
        ),
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
          itemCount: _results.length,
          itemBuilder: (context, i) {
            final movie = _results[i];
            return MovieCard(
              movie: movie,
              onTap: () => _add(movie),
            );
          },
        );
      },
    );
  }

  /// Добавление мгновенное: список обновляется локально, запрос уходит фоном.
  void _add(Movie movie) {
    context.read<MovieRepository>().addToWatchlist(movie);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('«${movie.title}» добавлен к просмотру'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
