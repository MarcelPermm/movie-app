import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'games_common.dart';
import 'logic_action.dart';

/// Аэрохокей на одном телефоне: игроки сидят друг напротив друга,
/// каждый водит свою биту пальцем по своей половине.
class AirHockeyScreen extends StatefulWidget {
  const AirHockeyScreen({super.key});

  @override
  State<AirHockeyScreen> createState() => _AirHockeyScreenState();
}

class _AirHockeyScreenState extends State<AirHockeyScreen> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  var _game = AirHockey();
  Duration _last = Duration.zero;

  /// Палец → игрок. Палец «принадлежит» той половине, где коснулся.
  final Map<int, int> _fingers = {};

  /// Куда тянуть биту (в координатах стола) — применяется на тике физики,
  /// чтобы скорость биты считалась по честному dt.
  final List<Offset?> _targets = [null, null];

  /// Пауза после гола, чтобы все увидели счёт.
  double _pause = 0;
  bool _over = false;

  Rect _table = Rect.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _restart() {
    setState(() {
      _game = AirHockey();
      _over = false;
      _pause = 0;
    });
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 0.0 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    if (dt <= 0 || dt > 0.1 || _over) return;

    for (var p = 0; p < 2; p++) {
      final t = _targets[p];
      if (t != null) _game.moveMallet(p, t, dt);
    }
    if (_pause > 0) {
      _pause -= dt;
      setState(() {});
      return;
    }
    final goal = _game.step(dt);
    if (goal >= 0) {
      HapticFeedback.heavyImpact();
      _pause = 1.0;
      if (_game.winner >= 0) {
        _over = true;
        final w = _game.winner;
        Future.delayed(const Duration(milliseconds: 600), () {
          if (!mounted) return;
          showResult(
            context,
            title: 'Победил ${playerNames[w]}!',
            color: playerColors[w],
            subtitle: 'Счёт ${_game.scores[0]} : ${_game.scores[1]}',
            onAgain: _restart,
          );
        });
      }
    }
    setState(() {});
  }

  Offset _toTable(Offset local) => Offset(
        (local.dx - _table.left) / _table.width,
        (local.dy - _table.top) / _table.width,
      );

  void _down(PointerDownEvent e) {
    final pos = _toTable(e.localPosition);
    final player = pos.dy < _game.length / 2 ? 0 : 1;
    // Одна бита — один палец: второй палец того же игрока игнорируем.
    if (_fingers.containsValue(player)) return;
    _fingers[e.pointer] = player;
    _targets[player] = pos;
  }

  void _move(PointerMoveEvent e) {
    final p = _fingers[e.pointer];
    if (p != null) _targets[p] = _toTable(e.localPosition);
  }

  void _up(PointerEvent e) {
    final p = _fingers.remove(e.pointer);
    if (p != null) _targets[p] = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      body: SafeArea(
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, box) {
                // Стол вписываем в экран с сохранением пропорций.
                final w = math.min(box.maxWidth, box.maxHeight / _game.length) - 16;
                final h = w * _game.length;
                _table = Rect.fromLTWH((box.maxWidth - w) / 2, (box.maxHeight - h) / 2, w, h);
                return Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _down,
                  onPointerMove: _move,
                  onPointerUp: _up,
                  onPointerCancel: _up,
                  child: CustomPaint(
                    size: Size(box.maxWidth, box.maxHeight),
                    painter: _TablePainter(_game, _table, _pause > 0),
                  ),
                );
              },
            ),
            Positioned(
              left: 4,
              top: 4,
              child: IconButton(
                tooltip: 'Выйти',
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TablePainter extends CustomPainter {
  final AirHockey g;
  final Rect t;
  final bool paused;

  _TablePainter(this.g, this.t, this.paused);

  @override
  void paint(Canvas canvas, Size size) {
    final s = t.width;
    Offset at(Offset p) => Offset(t.left + p.dx * s, t.top + p.dy * s);

    final table = RRect.fromRectAndRadius(t, const Radius.circular(24));
    canvas.drawRRect(table, Paint()..color = const Color(0xFF13203F));
    canvas.drawRRect(
      table,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Colors.white24,
    );

    final line = Paint()
      ..color = Colors.white24
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(t.left, t.center.dy), Offset(t.right, t.center.dy), line);
    canvas.drawCircle(t.center, s * 0.14, line);

    // Ворота — цветом игрока, которому они принадлежат.
    final gw = AirHockey.goalWidth * s;
    for (final (p, y) in [(0, t.top), (1, t.bottom)]) {
      canvas.drawLine(
        Offset(t.center.dx - gw / 2, y),
        Offset(t.center.dx + gw / 2, y),
        Paint()
          ..color = playerColors[p]
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round,
      );
    }

    // Счёт: у каждого — на его половине, повёрнут к нему.
    for (final p in [0, 1]) {
      final tp = TextPainter(
        text: TextSpan(
          text: '${g.scores[p]}',
          style: TextStyle(
            color: playerColors[p].withValues(alpha: paused ? 0.95 : 0.35),
            fontSize: s * 0.18,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      final cy = p == 0 ? t.top + t.height * 0.25 : t.top + t.height * 0.75;
      canvas.translate(t.center.dx, cy);
      if (p == 0) canvas.rotate(math.pi);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    // Биты.
    for (final p in [0, 1]) {
      final c = at(g.mallets[p]);
      final r = AirHockey.malletR * s;
      canvas.drawCircle(c, r, Paint()..color = playerColors[p]);
      canvas.drawCircle(c, r * 0.45, Paint()..color = Colors.white.withValues(alpha: 0.35));
    }

    // Шайба.
    canvas.drawCircle(at(g.puck), AirHockey.puckR * s, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
