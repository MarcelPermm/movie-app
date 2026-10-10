import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../data/profile_repository.dart';
import '../theme.dart';
import '../widgets/ai_panel.dart';
import '../widgets/poster_card.dart';
import 'movie_detail_screen.dart';

/// «Что посмотреть вечером»: три вопроса — и подборка, которая влезает
/// в свободное время. Длительность проверяет сервер по TMDB, а не модель.
class TonightScreen extends StatefulWidget {
  const TonightScreen({super.key});

  @override
  State<TonightScreen> createState() => _TonightScreenState();
}

class _Option {
  final String emoji;
  final String label;

  /// Что уходит на сервер. У настроения — описание для модели.
  final String value;

  const _Option(this.emoji, this.label, this.value);
}

class _TimeOption {
  final String label;
  final int minutes;
  final String kind;

  const _TimeOption(this.label, this.minutes, {this.kind = 'any'});
}

class _TonightScreenState extends State<TonightScreen> {
  static const _moods = [
    _Option('😂', 'Посмеяться', 'лёгкое и смешное, чтобы расслабиться'),
    _Option('🛋️', 'Уютно', 'уютное, тёплое и спокойное'),
    _Option('😱', 'Пощекотать нервы', 'напряжённое: триллер или хоррор'),
    _Option('🧩', 'Подумать', 'умное, с загадкой или неожиданным поворотом'),
    _Option('💔', 'На эмоции', 'трогательное, чтобы пережить сильные эмоции'),
    _Option('🔥', 'Драйв', 'динамичный экшен или приключение'),
    _Option('❤️', 'Романтика', 'романтичное'),
    _Option('🌌', 'Удивиться', 'необычное, визуально красивое, чтобы удивиться'),
  ];

  static const _times = [
    _TimeOption('До 1,5 часа', 90, kind: 'movie'),
    _TimeOption('До 2 часов', 120, kind: 'movie'),
    _TimeOption('Пара серий', 50, kind: 'tv'),
    _TimeOption('Не важно', 0),
  ];

  static const _company = [
    _Option('🙋', 'Один', 'один'),
    _Option('💑', 'Вдвоём', 'вдвоём с девушкой или парнем'),
    _Option('🍕', 'С друзьями', 'с друзьями'),
    _Option('👨‍👩‍👧', 'С семьёй', 'с семьёй, подойдёт для всех возрастов'),
  ];

  _Option? _mood;
  _TimeOption _time = _times.first;
  _Option _with = _company.first;
  final _extra = TextEditingController();

  bool _busy = false;
  String? _error;
  List<TonightPick>? _picks;

  @override
  void dispose() {
    _extra.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final mood = [
      if (_mood != null) _mood!.value,
      if (_extra.text.trim().isNotEmpty) _extra.text.trim(),
    ].join('; ');
    try {
      final picks = await context.read<ProfileRepository>().suggestTonight(
            mood: mood,
            maxMinutes: _time.minutes,
            company: _with.value,
            kind: _time.kind,
          );
      if (!mounted) return;
      setState(() => _picks = picks);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Что посмотреть вечером'),
        actions: [
          if (_picks != null && !_busy)
            TextButton(
              onPressed: () => setState(() => _picks = null),
              child: const Text('Изменить'),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: _busy
          ? const AiThinking()
          : _picks == null
              ? _buildForm()
              : _buildResults(_picks!),
    );
  }

  // ─── Вопросы ────────────────────────────────────────────────────────

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      children: [
        const Text('КАКОЕ НАСТРОЕНИЕ', style: kEyebrowStyle),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _moods
              .map((o) => _Chip(
                    text: '${o.emoji} ${o.label}',
                    selected: _mood == o,
                    onTap: () => setState(() => _mood = _mood == o ? null : o),
                  ))
              .toList(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _extra,
          decoration: const InputDecoration(
            hintText: 'Или своими словами: «как Интерстеллар, но короче»',
            prefixIcon: Icon(Icons.edit_note, size: 20),
          ),
          style: const TextStyle(color: AppColors.text),
        ),
        const SizedBox(height: 24),
        const Text('СКОЛЬКО ВРЕМЕНИ', style: kEyebrowStyle),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _times
              .map((t) => _Chip(
                    text: t.label,
                    selected: _time == t,
                    onTap: () => setState(() => _time = t),
                  ))
              .toList(),
        ),
        const SizedBox(height: 24),
        const Text('С КЕМ СМОТРИШЬ', style: kEyebrowStyle),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _company
              .map((o) => _Chip(
                    text: '${o.emoji} ${o.label}',
                    selected: _with == o,
                    onTap: () => setState(() => _with = o),
                  ))
              .toList(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 20),
          Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
        ],
        const SizedBox(height: 28),
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            onPressed: _run,
            icon: const Text('✦', style: TextStyle(fontSize: 16)),
            label: const Text('Подобрать', style: TextStyle(fontSize: 16)),
          ),
        ),
      ],
    );
  }

  // ─── Подборка ───────────────────────────────────────────────────────

  Widget _buildResults(List<TonightPick> picks) {
    if (picks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🍿', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              const Text(
                'Ничего не подошло под эти условия.\nПопробуй другое настроение или время.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textDim, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _run, child: const Text('Ещё раз')),
            ],
          ),
        ),
      );
    }

    final summary = [
      if (_mood != null) '${_mood!.emoji} ${_mood!.label}',
      _time.label,
      '${_with.emoji} ${_with.label}',
    ].join('  ·  ');

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 170).floor().clamp(2, 6);
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        summary,
                        style: const TextStyle(color: AppColors.textDim, fontSize: 12.5),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _run,
                      icon: const Icon(Icons.refresh, size: 17),
                      label: const Text('Другие'),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  childAspectRatio: 0.42,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 18,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _PickCard(pick: picks[i]),
                  childCount: picks.length,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PickCard extends StatelessWidget {
  final TonightPick pick;

  const _PickCard({required this.pick});

  @override
  Widget build(BuildContext context) {
    final movie = pick.movie;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: PosterCard(
            title: movie.title,
            subtitle: [
              if (pick.runtimeLabel != null) '⏱ ${pick.runtimeLabel}',
              if (movie.shortMeta.isNotEmpty) movie.shortMeta,
            ].join('  ·  '),
            imageUrl: movie.posterUrl,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: movie)),
            ),
          ),
        ),
        if (movie.aiReason != null) AiReasonNote(movie.aiReason!),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({required this.text, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.goldGradient : null,
          color: selected ? null : AppColors.surface,
          border: Border.all(color: selected ? Colors.transparent : AppColors.border),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: selected ? AppColors.bg : AppColors.text,
            fontSize: 13.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
