import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../theme.dart';
import '../widgets/poster_card.dart';

/// Одна найденная строка. `payload` хранит исходный объект (фильм или книгу),
/// чтобы обработчик выбора получил его целиком.
class SearchResult {
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final String fallbackEmoji;
  final Object payload;

  const SearchResult({
    required this.title,
    required this.payload,
    this.subtitle,
    this.imageUrl,
    this.fallbackEmoji = '🎬',
  });
}

/// Экран поиска, общий для кино и книг.
///
/// Результаты не кэшируются: запрос всегда живой, кэшировать тут нечего.
class SearchScreen extends StatefulWidget {
  final String hint;
  final Future<List<SearchResult>> Function(String query) onSearch;

  /// Что делать с выбранным результатом — открыть карточку или добавить
  /// в список. Решает вызывающий экран.
  final void Function(BuildContext context, SearchResult result) onPick;

  const SearchScreen({
    super.key,
    required this.hint,
    required this.onSearch,
    required this.onPick,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  List<SearchResult> _results = const [];
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
      final found = await widget.onSearch(query);
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
          decoration: InputDecoration(
            hintText: widget.hint,
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

    return PosterGrid(
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final result = _results[i];
        return PosterCard(
          title: result.title,
          subtitle: result.subtitle,
          imageUrl: result.imageUrl,
          fallbackEmoji: result.fallbackEmoji,
          onTap: () => widget.onPick(context, result),
        );
      },
    );
  }
}
