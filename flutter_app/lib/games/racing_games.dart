import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'games_common.dart';
import 'logic_action.dart';

/// Обратный отсчёт «3, 2, 1, Старт!» перед заездом.
mixin _Countdown<T extends StatefulWidget> on State<T> {
  int countdown = 0;
  Timer? _countdownTimer;

  void startCountdown(VoidCallback onGo) {
    _countdownTimer?.cancel();
    setState(() => countdown = 3);
    _countdownTimer = Timer.periodic(const Duration(milliseconds: 700), (t) {
      if (!mounted) return;
      setState(() => countdown--);
      HapticFeedback.selectionClick();
      if (countdown <= 0) {
        t.cancel();
        onGo();
      }
    });
  }

  void stopCountdown() => _countdownTimer?.cancel();
}

/// Раскладка зон игроков: верхние повёрнуты к сидящим напротив.
Widget playerZones(int n, Widget Function(int player) zone) {
  Widget z(int p, {bool flipped = false}) => Expanded(
        child: RotatedBox(quarterTurns: flipped ? 2 : 0, child: zone(p)),
      );
  return switch (n) {
    2 => Column(children: [z(0, flipped: true), z(1)]),
    3 => Column(children: [z(0, flipped: true), Expanded(child: Row(children: [z(1), z(2)]))]),
    _ => Column(children: [
        Expanded(child: Row(children: [z(0, flipped: true), z(1, flipped: true)])),
        Expanded(child: Row(children: [z(2), z(3)])),
      ]),
  };
}

// ─── Тап-гонка ───────────────────────────────────────────────────────────

class TapRaceScreen extends StatefulWidget {
  final int players;

  const TapRaceScreen({super.key, required this.players});

  @override
  State<TapRaceScreen> createState() => _TapRaceScreenState();
}

class _TapRaceScreenState extends State<TapRaceScreen> with _Countdown {
  late var _race = TapRace(players: widget.players);
  bool _running = false;

  @override
  void dispose() {
    stopCountdown();
    super.dispose();
  }

  void _start() {
    setState(() {
      _race = TapRace(players: widget.players);
      _running = false;
    });
    startCountdown(() => setState(() => _running = true));
  }

  void _tap(int p) {
    if (!_running || !_race.tap(p)) return;
    setState(() {});
    if (_race.winner < 0) return;
    _running = false;
    HapticFeedback.heavyImpact();
    final w = _race.winner;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      showResult(context, title: 'Первым финишировал ${playerNames[w]}!', color: playerColors[w], onAgain: _start);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Stack(
          children: [
            playerZones(widget.players, (p) => _Lane(
                  player: p,
                  share: _race.share(p),
                  running: _running,
                  onTap: () => _tap(p),
                )),
            Center(child: _overlay()),
            _ExitButton(),
          ],
        ),
      ),
    );
  }

  Widget _overlay() {
    if (countdown > 0) return _Big('$countdown');
    if (!_running && _race.winner < 0) {
      return FilledButton(
        onPressed: _start,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: AppColors.bg,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          shape: const StadiumBorder(),
        ),
        child: Text('Старт · ${_race.taps} нажатий до финиша',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );
    }
    return const SizedBox.shrink();
  }
}

class _Lane extends StatelessWidget {
  final int player;
  final double share;
  final bool running;
  final VoidCallback onTap;

  const _Lane({required this.player, required this.share, required this.running, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = playerColors[player];
    return Listener(
      onPointerDown: (_) => onTap(),
      child: Container(
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: running ? 0.22 : 0.12),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: color, width: 2),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            const car = 44.0;
            final track = box.maxWidth - car - 32;
            return Stack(
              children: [
                // Дорога с финишной клеткой.
                Positioned(
                  left: 16,
                  right: 16,
                  top: box.maxHeight / 2 - 2,
                  height: 4,
                  child: Container(color: Colors.white24),
                ),
                Positioned(
                  right: 12,
                  top: box.maxHeight / 2 - 22,
                  child: const Text('🏁', style: TextStyle(fontSize: 30)),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 90),
                  left: 16 + track * share.clamp(0.0, 1.0),
                  top: box.maxHeight / 2 - car / 2 - 6,
                  child: const Text('🏎️', style: TextStyle(fontSize: car)),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 12,
                  child: Text(
                    running ? 'ТАПАЙ!' : playerNames[player],
                    textAlign: TextAlign.center,
                    style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─── Световые мотоциклы ──────────────────────────────────────────────────

class LightCyclesScreen extends StatefulWidget {
  final int players;

  const LightCyclesScreen({super.key, required this.players});

  @override
  State<LightCyclesScreen> createState() => _LightCyclesScreenState();
}

class _LightCyclesScreenState extends State<LightCyclesScreen> with _Countdown {
  /// Для двоих поле вытянуто по экрану; для компании — квадратное, чтобы
  /// старты со всех четырёх сторон были честными.
  late var _game = _newGame();
  Timer? _loop;
  bool _running = false;

  LightCycles _newGame() => widget.players <= 2
      ? LightCycles(players: widget.players, width: 36, height: 56)
      : LightCycles(players: widget.players, width: 44, height: 44);

  @override
  void dispose() {
    _loop?.cancel();
    stopCountdown();
    super.dispose();
  }

  void _restart() {
    _loop?.cancel();
    setState(() {
      _game = _newGame();
      _running = false;
    });
  }

  void _startRound() {
    _loop?.cancel();
    setState(() {
      if (_game.roundOver) _game.newRound();
      _running = false;
    });
    startCountdown(() {
      setState(() => _running = true);
      _loop = Timer.periodic(const Duration(milliseconds: 85), (_) => _step());
    });
  }

  void _step() {
    if (!mounted) return;
    final over = _game.step();
    setState(() {});
    if (!over) return;
    _loop?.cancel();
    _running = false;
    HapticFeedback.heavyImpact();
    final champ = _game.champion;
    if (champ >= 0) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        showResult(
          context,
          title: 'Победил ${playerNames[champ]}!',
          color: playerColors[champ],
          subtitle: 'Раунды: ${_game.scores.join(' : ')}',
          onAgain: () {
            _restart();
            _startRound();
          },
        );
      });
    }
  }

  void _turn(int p, bool clockwise) {
    if (!_running) return;
    HapticFeedback.selectionClick();
    _game.turn(p, clockwise: clockwise);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.players;
    final board = AspectRatio(
      aspectRatio: _game.width / _game.height,
      child: CustomPaint(painter: _TrailPainter(_game)),
    );

    // Кнопки по сторонам экрана: 0 — сверху, 1 — снизу, 2 — слева, 3 — справа.
    Widget pad(int p) => _TurnPad(player: p, alive: _game.cycles[p].alive, onTurn: (cw) => _turn(p, cw));

    Widget middle = Center(child: board);
    if (n >= 3) {
      middle = Row(
        children: [
          RotatedBox(quarterTurns: 1, child: pad(2)),
          Expanded(child: middle),
          if (n >= 4) RotatedBox(quarterTurns: 3, child: pad(3)),
        ],
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF05070D),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                RotatedBox(quarterTurns: 2, child: pad(0)),
                Expanded(child: Padding(padding: const EdgeInsets.all(6), child: middle)),
                pad(1),
              ],
            ),
            Center(child: _overlay()),
            _ExitButton(),
          ],
        ),
      ),
    );
  }

  Widget _overlay() {
    if (countdown > 0) return _Big('$countdown');
    if (_running) return const SizedBox.shrink();
    if (_game.champion >= 0) return const SizedBox.shrink();
    final label = _game.roundOver
        ? (_game.roundWinner >= 0 ? 'Раунд — ${playerNames[_game.roundWinner]}. Дальше' : 'Все разбились. Ещё раунд')
        : 'Старт · до ${_game.target} побед';
    return FilledButton(
      onPressed: _startRound,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.bg,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: const StadiumBorder(),
      ),
      child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
    );
  }
}

/// Две кнопки поворота: ↺ налево, ↻ направо — относительно мотоцикла.
class _TurnPad extends StatelessWidget {
  final int player;
  final bool alive;
  final ValueChanged<bool> onTurn;

  const _TurnPad({required this.player, required this.alive, required this.onTurn});

  @override
  Widget build(BuildContext context) {
    final color = playerColors[player].withValues(alpha: alive ? 1 : 0.3);
    Widget button(bool clockwise) => Expanded(
          child: Listener(
            onPointerDown: (_) => onTurn(clockwise),
            child: Container(
              height: 64,
              margin: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color, width: 2),
              ),
              child: Icon(clockwise ? Icons.rotate_right : Icons.rotate_left, color: color, size: 34),
            ),
          ),
        );
    return SizedBox(
      width: 300,
      child: Row(children: [button(false), button(true)]),
    );
  }
}

class _TrailPainter extends CustomPainter {
  final LightCycles g;

  _TrailPainter(this.g);

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / g.width;
    final ch = size.height / g.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0C1222));
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white24,
    );
    final paints = [for (final c in playerColors) Paint()..color = c.withValues(alpha: 0.75)];
    for (var y = 0; y < g.height; y++) {
      for (var x = 0; x < g.width; x++) {
        final o = g.trail[y][x];
        if (o >= 0) canvas.drawRect(Rect.fromLTWH(x * cw, y * ch, cw + 0.5, ch + 0.5), paints[o]);
      }
    }
    for (var i = 0; i < g.players; i++) {
      final c = g.cycles[i];
      final rect = Rect.fromLTWH(c.x * cw - cw * 0.4, c.y * ch - ch * 0.4, cw * 1.8, ch * 1.8);
      canvas.drawOval(rect, Paint()..color = c.alive ? Colors.white : Colors.white24);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _Big extends StatelessWidget {
  final String text;

  const _Big(this.text);

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Text(text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 96,
              fontWeight: FontWeight.w900,
              shadows: [Shadow(blurRadius: 18, color: Colors.black)],
            )),
      );
}

class _ExitButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Positioned(
        left: 4,
        top: 4,
        child: IconButton(
          tooltip: 'Выйти',
          icon: Icon(Icons.close, color: AppColors.textDim),
          onPressed: () => Navigator.pop(context),
        ),
      );
}
