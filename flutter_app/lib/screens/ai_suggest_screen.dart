import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../theme.dart';
import '../widgets/ai_panel.dart';

/// Вкладка «✦ Посоветуй» — одна и та же для кино и книг.
///
/// Отличаются только источник данных и вид карточки, поэтому оба передаются
/// параметрами, а вся механика (запрос, ожидание, ошибки, повтор) общая.
class AiSuggestTab<T> extends StatefulWidget {
  /// Запрос к AI. Пустая строка означает «на своё усмотрение».
  final Future<List<T>> Function(String query) fetch;

  final Widget Function(BuildContext context, T item) cardBuilder;

  /// Готовые формулировки под строкой ввода.
  final List<String> examples;

  final String hint;
  final String emptyEmoji;

  const AiSuggestTab({
    super.key,
    required this.fetch,
    required this.cardBuilder,
    this.examples = const [],
    this.hint = 'Например: что-нибудь медленное и осеннее',
    this.emptyEmoji = '✦',
  });

  @override
  State<AiSuggestTab<T>> createState() => _AiSuggestTabState<T>();
}

class _AiSuggestTabState<T> extends State<AiSuggestTab<T>> {
  List<T> _results = const [];
  bool _busy = false;
  String? _error;

  /// Успел ли пользователь хоть раз нажать кнопку — от этого зависит,
  /// что показывать вместо результатов: приглашение или «ничего не нашлось».
  bool _ran = false;

  Future<void> _run(String query) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final found = await widget.fetch(query);
      if (!mounted) return;
      setState(() {
        _results = found;
        _ran = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      // 429 от AI-провайдера — не поломка, а «подожди минуту».
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AiQueryBar(
          hint: widget.hint,
          busy: _busy,
          examples: widget.examples,
          onSubmit: _run,
        ),
        const Divider(height: 1),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_busy) return const AiThinking();

    if (_error != null) {
      return _Message(
        emoji: '⚠',
        text: _error!,
        color: AppColors.red,
        action: TextButton(onPressed: () => _run(''), child: const Text('Попробовать ещё раз')),
      );
    }

    if (_results.isEmpty) {
      return _Message(
        emoji: widget.emptyEmoji,
        text: _ran
            ? 'Ничего не подобралось. Попробуй сформулировать иначе —\nобезьянка каждый раз предлагает разное.'
            : 'Опиши настроение или жанр — и получишь подборку\nпод то, что ты уже смотрел.',
      );
    }

    // Пропорция выше обычной сетки: под обложкой ещё живёт объяснение AI.
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 170).floor().clamp(2, 8);
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: 0.42,
            crossAxisSpacing: 14,
            mainAxisSpacing: 18,
          ),
          itemCount: _results.length,
          itemBuilder: (context, i) => widget.cardBuilder(context, _results[i]),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  final String emoji;
  final String text;
  final Color? color;
  final Widget? action;

  const _Message({
    required this.emoji,
    required this.text,
    this.color,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 30)),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: color ?? AppColors.textDim, fontSize: 13.5, height: 1.5),
            ),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}
