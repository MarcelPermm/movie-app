import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'games_common.dart';
import 'logic.dart';

/// «Реакция»: телефон лежит между игроками, у каждого своя зона экрана.
/// Загорелся зелёный — жми. Раньше времени — минус очко.
class ReactionScreen extends StatefulWidget {
  final int players;

  const ReactionScreen({super.key, required this.players});

  @override
  State<ReactionScreen> createState() => _ReactionScreenState();
}

class _ReactionScreenState extends State<ReactionScreen> {
  late var _match = ReactionMatch(players: widget.players);
  final _rng = math.Random();
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    setState(() => _match = ReactionMatch(players: widget.players));
  }

  void _startRound() {
    _timer?.cancel();
    setState(_match.startRound);
    _timer = Timer(ReactionMatch.randomDelay(_rng), () {
      if (!mounted) return;
      setState(_match.signal);
      HapticFeedback.mediumImpact();
    });
  }

  void _tap(int player) {
    if (_match.phase == ReactionPhase.waiting || _match.phase == ReactionPhase.roundOver) return;
    if (!_match.tap(player)) return;
    _timer?.cancel();
    HapticFeedback.lightImpact();
    setState(() {});
    if (_match.phase == ReactionPhase.matchOver) {
      final w = _match.champion;
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        showResult(
          context,
          title: 'Победил ${playerNames[w]}!',
          color: playerColors[w],
          subtitle: 'Счёт: ${_match.scores.join(' : ')}',
          onAgain: _restart,
        );
      });
      return;
    }
    // Следующий раунд — сам, после короткой паузы на «кто взял».
    _timer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) _startRound();
    });
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.players;
    final go = _match.phase == ReactionPhase.go;

    Widget zone(int p, {bool flipped = false}) => Expanded(
          child: RotatedBox(
            quarterTurns: flipped ? 2 : 0,
            child: _Zone(player: p, match: _match, onTap: () => _tap(p)),
          ),
        );

    // Зоны раскладываем так, чтобы каждый тянулся к своей стороне экрана.
    final Widget field = switch (n) {
      2 => Column(children: [zone(0, flipped: true), zone(1)]),
      3 => Column(children: [
          zone(0, flipped: true),
          Expanded(child: Row(children: [zone(1), zone(2)])),
        ]),
      _ => Column(children: [
          Expanded(child: Row(children: [zone(0, flipped: true), zone(1, flipped: true)])),
          Expanded(child: Row(children: [zone(2), zone(3)])),
        ]),
    };

    return Scaffold(
      backgroundColor: go ? const Color(0xFF0E3B22) : AppColors.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: field),
            // Центр: старт и подсказка. Не мешает нажимать в зонах.
            Align(
              child: _Center(
                match: _match,
                onStart: _startRound,
              ),
            ),
            Positioned(
              left: 4,
              top: 4,
              child: IconButton(
                tooltip: 'Выйти',
                icon: Icon(Icons.close, color: AppColors.textDim),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Zone extends StatelessWidget {
  final int player;
  final ReactionMatch match;
  final VoidCallback onTap;

  const _Zone({required this.player, required this.match, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = playerColors[player];
    final go = match.phase == ReactionPhase.go;
    final won = match.roundWinner == player;
    final fouled = match.falseStart == player;

    final message = won
        ? 'Твоё очко!'
        : fouled
            ? 'Рано! −1'
            : go
                ? 'ЖМИ!'
                : '';

    return Listener(
      // Listener, а не onTap: срабатывает в момент касания, а не отпускания —
      // в игре на реакцию это десятки миллисекунд.
      onPointerDown: (_) => onTap(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: go ? 0.55 : (won ? 0.45 : 0.18)),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: fouled ? AppColors.red : color, width: fouled ? 4 : 2),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${match.scores[player]}',
                style: const TextStyle(color: Colors.white, fontSize: 54, fontWeight: FontWeight.w900),
              ),
              Text(
                playerNames[player],
                style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Center extends StatelessWidget {
  final ReactionMatch match;
  final VoidCallback onStart;

  const _Center({required this.match, required this.onStart});

  @override
  Widget build(BuildContext context) {
    switch (match.phase) {
      case ReactionPhase.waiting:
        return FilledButton(
          onPressed: onStart,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: AppColors.bg,
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
            shape: const StadiumBorder(),
          ),
          child: Text('Старт · до ${match.target} очков',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        );
      case ReactionPhase.ready:
        return const _Pill(text: 'Ждите зелёного…', color: Color(0xFF7A1F25));
      case ReactionPhase.go:
        return const _Pill(text: 'ЖМИ!', color: Color(0xFF1E9E55));
      case ReactionPhase.roundOver:
      case ReactionPhase.matchOver:
        return const SizedBox.shrink();
    }
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;

  const _Pill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(40)),
          child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
        ),
      );
}
