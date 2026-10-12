import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'games_common.dart';
import 'logic.dart';
import 'words_ru.dart';

enum _Stage { handOver, playing, review }

/// «Объясни слово» — как «Шляпа» или Alias: команды по очереди объясняют
/// слова, не называя однокоренных. Телефон — у объясняющего.
class WordsScreen extends StatefulWidget {
  final int teams;

  const WordsScreen({super.key, required this.teams});

  @override
  State<WordsScreen> createState() => _WordsScreenState();
}

class _WordsScreenState extends State<WordsScreen> {
  static const _roundSeconds = 60;

  late var _match = WordsMatch(words: wordsRu, teams: widget.teams);
  var _stage = _Stage.handOver;
  int _left = _roundSeconds;
  Timer? _timer;

  String _team(int i) => teamNames[i];

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    setState(() {
      _match = WordsMatch(words: wordsRu, teams: widget.teams);
      _stage = _Stage.handOver;
    });
  }

  void _startRound() {
    setState(() {
      _stage = _Stage.playing;
      _left = _roundSeconds;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 3 && _left > 0) HapticFeedback.selectionClick();
      if (_left <= 0) {
        t.cancel();
        HapticFeedback.heavyImpact();
        setState(() => _stage = _Stage.review);
      }
    });
  }

  void _finishRound() {
    final team = _match.team;
    final got = _match.roundScore;
    setState(() {
      _match.finishRound();
      _stage = _Stage.handOver;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('${_team(team)}: ${got >= 0 ? '+' : ''}$got за раунд')));
    final w = _match.winner;
    if (w >= 0) {
      showResult(
        context,
        title: 'Победили ${_team(w)}!',
        color: playerColors[w],
        subtitle: 'Счёт: ${_match.scores.join(' : ')}',
        onAgain: _restart,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'Объясни слово',
      onRestart: _stage == _Stage.playing ? null : _restart,
      body: Column(
        children: [
          ScoreRow(
            scores: _match.scores,
            active: _match.team,
            names: [for (var i = 0; i < widget.teams; i++) teamNames[i]],
          ),
          Expanded(
            child: switch (_stage) {
              _Stage.handOver => _handOver(),
              _Stage.playing => _playing(),
              _Stage.review => _review(),
            },
          ),
        ],
      ),
    );
  }

  Widget _handOver() {
    final color = playerColors[_match.team];
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Объясняют', style: TextStyle(color: AppColors.textDim, fontSize: 16)),
          const SizedBox(height: 6),
          Text(_team(_match.team),
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontSize: 30, fontWeight: FontWeight.w900)),
          const SizedBox(height: 18),
          Text(
            'Один объясняет, остальные из команды угадывают. '
            'Нельзя называть само слово и однокоренные. '
            '$_roundSeconds секунд, до ${_match.target} очков.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textDim, fontSize: 14.5, height: 1.45),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _startRound,
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18),
              shape: const StadiumBorder(),
            ),
            child: const Text('Поехали', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _playing() {
    final urgent = _left <= 10;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('⏱ $_left',
                  style: TextStyle(
                    color: urgent ? AppColors.red : AppColors.text,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  )),
              Text('за раунд: ${_match.roundScore}',
                  style: TextStyle(color: AppColors.textDim, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _left / _roundSeconds,
              minHeight: 6,
              backgroundColor: AppColors.surfaceHigh,
              valueColor: AlwaysStoppedAnimation(urgent ? AppColors.red : playerColors[_match.team]),
            ),
          ),
          Expanded(
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: FittedBox(
                  key: ValueKey(_match.current),
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _match.current,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.text, fontSize: 44, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _BigButton(
                  label: 'Пропустить',
                  icon: Icons.skip_next,
                  color: const Color(0xFF6B6B7A),
                  onTap: () => setState(_match.skipped),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BigButton(
                  label: 'Угадали',
                  icon: Icons.check,
                  color: const Color(0xFF30A46C),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(_match.guessed);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _review() {
    final log = _match.roundLog;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(
            'Время вышло! Проверьте отметки — нажмите на слово, чтобы исправить.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textDim),
          ),
        ),
        Expanded(
          child: log.isEmpty
              ? Center(child: Text('Ни одного слова за раунд', style: TextStyle(color: AppColors.textDim)))
              : ListView.builder(
                  itemCount: log.length,
                  itemBuilder: (context, i) {
                    final (word, ok) = log[i];
                    return ListTile(
                      onTap: () => setState(() => _match.toggle(i)),
                      leading: Icon(
                        ok ? Icons.check_circle : Icons.cancel,
                        color: ok ? const Color(0xFF30A46C) : AppColors.textDim,
                      ),
                      title: Text(word, style: TextStyle(color: AppColors.text, fontSize: 16)),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _finishRound,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.bg,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text('Засчитать ${_match.roundScore >= 0 ? '+' : ''}${_match.roundScore}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      ],
    );
  }
}

class _BigButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _BigButton({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: SizedBox(
          height: 96,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 30),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}
