import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'games_common.dart';
import 'logic_sports.dart';

// ═════════════════════════════════════════════════════════════════════════
//  Дартс
// ═════════════════════════════════════════════════════════════════════════

class DartsScreen extends StatefulWidget {
  final int players;
  final DartsMode mode;

  const DartsScreen({super.key, required this.players, required this.mode});

  @override
  State<DartsScreen> createState() => _DartsScreenState();
}

class _DartsScreenState extends State<DartsScreen> with SingleTickerProviderStateMixin {
  late var _match = DartsMatch(players: widget.players, mode: widget.mode);
  late final Ticker _ticker;
  final _rng = math.Random();
  double _t = 0;

  /// Где палец (в координатах доски), null — не прицеливаемся.
  Offset? _finger;

  /// Дротики текущего хода: точка на мишени (-1..1) и подпись.
  final List<(Offset, String)> _darts = [];
  bool _turnDone = false;
  double _radius = 1;
  Offset _center = Offset.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) {
      _t = d.inMicroseconds / 1e6;
      if (_finger != null) setState(() {});
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _restart() => setState(() {
        _match = DartsMatch(players: widget.players, mode: widget.mode);
        _darts.clear();
        _turnDone = false;
      });

  /// Прицел — чуть выше пальца, чтобы палец его не закрывал, и «гуляет»,
  /// как рука: попасть в утроение 20 — уже умение.
  Offset get _aim {
    final f = _finger ?? Offset.zero;
    final wobble = Offset(math.sin(_t * 3.1) + 0.5 * math.sin(_t * 7.3), math.cos(_t * 2.6) + 0.5 * math.sin(_t * 5.9)) * 0.045;
    return Offset(f.dx, f.dy - 0.32) + wobble;
  }

  Offset _toBoard(Offset local) => (local - _center) / _radius;

  void _release() {
    if (_finger == null || _turnDone || _match.isOver) return;
    // Небольшой разброс при броске.
    final spread = Offset(_gauss(), _gauss()) * 0.025;
    final hit = _aim + spread;
    _finger = null;
    final s = Darts.score(hit);
    HapticFeedback.mediumImpact();
    final ended = _match.throwDart(s.points);
    setState(() {
      _darts.add((hit, s.label));
      _turnDone = ended;
    });
    if (_match.winner >= 0) {
      final w = _match.winner;
      Future.delayed(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        showResult(
          context,
          title: widget.players == 1 ? 'Готово!' : 'Победил ${playerNames[w]}!',
          subtitle: _summary(),
          color: playerColors[w],
          onAgain: _restart,
        );
      });
    }
  }

  double _gauss() {
    final u = 1 - _rng.nextDouble(), v = _rng.nextDouble();
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
  }

  void _next() {
    setState(() {
      _match.nextTurn();
      _darts.clear();
      _turnDone = false;
    });
    if (_match.isOver && _match.winner >= 0) {
      final w = _match.winner;
      showResult(
        context,
        title: widget.players == 1 ? 'Итог: ${_match.totals[0]}' : 'Победил ${playerNames[w]}!',
        subtitle: _summary(),
        color: playerColors[w],
        onAgain: _restart,
      );
    }
  }

  String _summary() => [
        for (var p = 0; p < widget.players; p++) '${playerNames[p]}: ${_match.totals[p]}',
      ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final m = _match;
    final turnSum = m.thisTurn.fold(0, (a, b) => a + b);
    final status = m.bust
        ? 'Перебор! Ход сгорел'
        : _turnDone
            ? 'Ход: $turnSum очков'
            : 'Дротик ${m.thisTurn.length + 1} из 3 · держи палец и отпусти';
    return GameScaffold(
      title: widget.mode == DartsMode.x301 ? 'Дартс · 301' : 'Дартс · на очки',
      onRestart: _restart,
      body: Column(
        children: [
          ScoreRow(scores: m.totals, active: m.turn),
          if (widget.mode == DartsMode.rounds)
            Text('Раунд ${math.min(m.round, DartsMatch.rounds)} из ${DartsMatch.rounds}',
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
          TurnBanner(player: m.turn, text: '${playerNames[m.turn]}: $status'),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                _radius = math.min(box.maxWidth, box.maxHeight) / 2 * 0.86;
                _center = Offset(box.maxWidth / 2, box.maxHeight / 2 + _radius * 0.05);
                return Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) {
                    if (_turnDone || m.isOver) return;
                    setState(() => _finger = _toBoard(e.localPosition));
                  },
                  onPointerMove: (e) {
                    if (_finger != null) _finger = _toBoard(e.localPosition);
                  },
                  onPointerUp: (_) => _release(),
                  onPointerCancel: (_) => setState(() => _finger = null),
                  child: CustomPaint(
                    size: Size(box.maxWidth, box.maxHeight),
                    painter: _BoardPainter(
                      center: _center,
                      radius: _radius,
                      aim: _finger == null ? null : _aim,
                      darts: _darts,
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: _turnDone && !m.isOver
                  ? FilledButton(
                      onPressed: _next,
                      style: FilledButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: AppColors.bg),
                      child: Text(widget.players == 1 ? 'Следующий ход' : 'Передать: ${playerNames[(m.turn + 1) % widget.players]}'),
                    )
                  : Center(
                      child: Text(
                        _darts.map((d) => d.$2).join('  ·  '),
                        style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  final Offset center;
  final double radius;
  final Offset? aim;
  final List<(Offset, String)> darts;

  _BoardPainter({required this.center, required this.radius, required this.aim, required this.darts});

  @override
  void paint(Canvas canvas, Size size) {
    final r = radius;
    canvas.drawCircle(center, r * 1.18, Paint()..color = const Color(0xFF1A1A1A));
    const dark = Color(0xFF1E1E1E), light = Color(0xFFF2E6C9);
    const red = Color(0xFFD32F2F), green = Color(0xFF2E7D32);

    for (var i = 0; i < 20; i++) {
      // Сектор i занимает от (i*18 - 9)° до (i*18 + 9)° от вертикали по часовой.
      final start = (-90 + i * 18 - 9) * math.pi / 180;
      const sweep = 18 * math.pi / 180;
      final even = i.isEven;
      void ring(double outer, double inner, Color c) {
        final path = Path()
          ..arcTo(Rect.fromCircle(center: center, radius: outer * r), start, sweep, true)
          ..arcTo(Rect.fromCircle(center: center, radius: inner * r), start + sweep, -sweep, false)
          ..close();
        canvas.drawPath(path, Paint()..color = c);
      }

      ring(1, Darts.doubleIn, even ? red : green);
      ring(Darts.doubleIn, Darts.tripleOut, even ? dark : light);
      ring(Darts.tripleOut, Darts.tripleIn, even ? red : green);
      ring(Darts.tripleIn, Darts.outerBull, even ? dark : light);

      // Числа секторов по кругу.
      final mid = (i * 18) * math.pi / 180;
      final tp = TextPainter(
        text: TextSpan(
          text: '${Darts.sectors[i]}',
          style: TextStyle(color: Colors.white, fontSize: r * 0.09, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final p = center + Offset(math.sin(mid), -math.cos(mid)) * r * 1.09;
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
    canvas.drawCircle(center, Darts.outerBull * r, Paint()..color = green);
    canvas.drawCircle(center, Darts.bull * r, Paint()..color = red);

    for (final (d, _) in darts) {
      final p = center + d * r;
      canvas.drawCircle(p, 6, Paint()..color = Colors.black);
      canvas.drawCircle(p, 4, Paint()..color = const Color(0xFFFFD54F));
    }

    final a = aim;
    if (a != null) {
      final p = center + a * r;
      final paint = Paint()
        ..color = Colors.white
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(p, 12, paint);
      canvas.drawLine(p - const Offset(18, 0), p + const Offset(18, 0), paint);
      canvas.drawLine(p - const Offset(0, 18), p + const Offset(0, 18), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ═════════════════════════════════════════════════════════════════════════
//  Боулинг
// ═════════════════════════════════════════════════════════════════════════

class BowlingScreen extends StatefulWidget {
  final int players;

  const BowlingScreen({super.key, required this.players});

  @override
  State<BowlingScreen> createState() => _BowlingScreenState();
}

class _BowlingScreenState extends State<BowlingScreen> with SingleTickerProviderStateMixin {
  late List<BowlingCard> _cards = List.generate(widget.players, (_) => BowlingCard());
  var _lane = BowlingLane();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  int _turn = 0;
  int _standingBefore = 10;
  String? _flash;

  /// Точки свайпа: по ним считаем силу, направление и подкрутку.
  final List<(Offset, Duration)> _swipe = [];
  Size _size = Size.zero;

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

  void _restart() => setState(() {
        _cards = List.generate(widget.players, (_) => BowlingCard());
        _lane = BowlingLane();
        _turn = 0;
        _standingBefore = 10;
        _flash = null;
      });

  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 0.0 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    if (!_lane.rolling || dt <= 0 || dt > 0.1) return;
    if (_lane.step(dt)) _afterRoll();
    setState(() {});
  }

  void _afterRoll() {
    final card = _cards[_turn];
    final (frameBefore, _) = card.position;
    final knocked = _standingBefore - _lane.standing;
    card.add(knocked);
    HapticFeedback.mediumImpact();
    final (frameAfter, rollAfter) = card.position;
    _flash = knocked == 10 && _standingBefore == 10
        ? 'СТРАЙК!'
        : _lane.standing == 0
            ? 'Спэр!'
            : knocked == 0
                ? 'Мимо'
                : 'Сбито: $knocked';

    final frameDone = card.isComplete || frameAfter != frameBefore || (frameAfter == 9 && rollAfter == 0);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() {
        _flash = null;
        if (frameDone) {
          _turn = (_turn + 1) % widget.players;
          _lane.resetRack();
        } else if (_cards[_turn].freshRack) {
          _lane.resetRack();
        } else {
          _lane.clearFallen();
        }
        _standingBefore = _lane.standing;
        _lane.ball = Offset(0.5, BowlingLane.length - 0.3);
      });
      if (_cards.every((c) => c.isComplete)) {
        final totals = [for (final c in _cards) c.total];
        final best = totals.reduce(math.max);
        final w = totals.indexOf(best);
        showResult(
          context,
          title: widget.players == 1 ? 'Итог: $best' : 'Победил ${playerNames[w]}!',
          subtitle: [for (var p = 0; p < widget.players; p++) '${playerNames[p]}: ${totals[p]}'].join(' · '),
          color: playerColors[w],
          onAgain: _restart,
        );
      }
    });
  }

  Offset _toLane(Offset local) => Offset(local.dx / _size.width, local.dy / _size.height * BowlingLane.length);

  void _throw() {
    if (_swipe.length < 3 || _lane.rolling || _flash != null) {
      _swipe.clear();
      return;
    }
    final (p0, t0) = _swipe.first;
    final (p1, t1) = _swipe.last;
    final secs = math.max(0.05, (t1 - t0).inMicroseconds / 1e6);
    final a = _toLane(p0), b = _toLane(p1);
    var v = (b - a) / secs;
    if (v.dy > -0.8) {
      _swipe.clear();
      return; // свайп не вперёд — не бросок
    }
    final speed = v.distance.clamp(2.5, 6.5);
    v = v / v.distance * speed;
    // Подкрутка — по изгибу свайпа: насколько конец ушёл вбок от прямой.
    final mid = _toLane(_swipe[_swipe.length ~/ 2].$1);
    final straightMid = Offset.lerp(a, b, 0.5)!;
    final spin = ((straightMid.dx - mid.dx) * 6).clamp(-1.2, 1.2);
    _swipe.clear();
    setState(() => _lane.launch(aimX: a.dx, velocity: v, spin: spin));
  }

  @override
  Widget build(BuildContext context) {
    final (frame, roll) = _cards[_turn].position;
    return GameScaffold(
      title: 'Боулинг',
      onRestart: _restart,
      body: Column(
        children: [
          _ScoreSheet(cards: _cards, turn: _turn),
          TurnBanner(
            player: _turn,
            text: _flash ?? '${playerNames[_turn]} · фрейм ${frame + 1}, бросок ${roll + 1} · свайп вверх',
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 6),
              child: LayoutBuilder(
                builder: (context, box) {
                  _size = Size(box.maxWidth, box.maxHeight);
                  return Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (e) => _swipe
                      ..clear()
                      ..add((e.localPosition, e.timeStamp)),
                    onPointerMove: (e) => _swipe.add((e.localPosition, e.timeStamp)),
                    onPointerUp: (_) => _throw(),
                    child: CustomPaint(size: _size, painter: _LanePainter(_lane)),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _ScoreSheet extends StatelessWidget {
  final List<BowlingCard> cards;
  final int turn;

  const _ScoreSheet({required this.cards, required this.turn});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Column(
        children: [
          for (var p = 0; p < cards.length; p++)
            Container(
              margin: const EdgeInsets.only(bottom: 3),
              decoration: BoxDecoration(
                color: playerColors[p].withValues(alpha: p == turn ? 0.22 : 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Container(width: 6, height: 26, color: playerColors[p]),
                  for (final t in cards[p].frameTotals)
                    Expanded(
                      child: Text(
                        t == null ? '·' : '$t',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.text, fontSize: 11.5),
                      ),
                    ),
                  SizedBox(
                    width: 40,
                    child: Text('${cards[p].total}',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LanePainter extends CustomPainter {
  final BowlingLane lane;

  _LanePainter(this.lane);

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width, sy = size.height / BowlingLane.length;
    Offset at(Offset p) => Offset(p.dx * sx, p.dy * sy);

    // Желоба и дорожка «под дерево».
    canvas.drawRect(Rect.fromLTWH(-14, 0, size.width + 28, size.height), Paint()..color = const Color(0xFF2B2B33));
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(colors: [Color(0xFFD9A867), Color(0xFFE8C08A), Color(0xFFD9A867)])
            .createShader(Offset.zero & size),
    );
    final arrow = Paint()..color = const Color(0x55693C12);
    for (var i = 1; i < 6; i++) {
      final x = size.width * i / 6;
      final y = size.height * 0.62;
      canvas.drawPath(
        Path()
          ..moveTo(x, y - 10)
          ..lineTo(x - 5, y + 4)
          ..lineTo(x + 5, y + 4)
          ..close(),
        arrow,
      );
    }
    canvas.drawLine(Offset(0, size.height * 0.82), Offset(size.width, size.height * 0.82),
        Paint()..color = const Color(0x88693C12)..strokeWidth = 2);

    for (final p in lane.pins) {
      final c = at(p.pos);
      final r = BowlingLane.pinR * sx;
      if (p.down) {
        canvas.drawOval(Rect.fromCenter(center: c, width: r * 2.6, height: r * 1.2), Paint()..color = const Color(0xAAFFFFFF));
      } else {
        canvas.drawCircle(c, r, Paint()..color = Colors.white);
        canvas.drawCircle(c, r * 0.45, Paint()..color = const Color(0xFFD32F2F));
      }
    }

    final b = at(lane.ball);
    canvas.drawCircle(b, BowlingLane.ballR * sx, Paint()..color = const Color(0xFF283593));
    canvas.drawCircle(b + Offset(-3, -3), BowlingLane.ballR * sx * 0.25, Paint()..color = const Color(0x55FFFFFF));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ═════════════════════════════════════════════════════════════════════════
//  Мини-гольф
// ═════════════════════════════════════════════════════════════════════════

class MiniGolfScreen extends StatefulWidget {
  final int players;

  const MiniGolfScreen({super.key, required this.players});

  @override
  State<MiniGolfScreen> createState() => _MiniGolfScreenState();
}

class _MiniGolfScreenState extends State<MiniGolfScreen> with SingleTickerProviderStateMixin {
  late var _match = GolfMatch(players: widget.players);
  late GolfBall _ball = GolfBall(_match.holes[0]);
  int _strokes = 0;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  Offset? _drag;
  double _scale = 1;
  Offset _origin = Offset.zero;
  bool _waiting = false;

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

  void _restart() => setState(() {
        _match = GolfMatch(players: widget.players);
        _ball = GolfBall(_match.holes[0]);
        _strokes = 0;
        _waiting = false;
      });

  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 0.0 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    if (dt <= 0 || dt > 0.1 || !_ball.moving) return;
    if (_ball.step(dt)) _stopped();
    setState(() {});
  }

  void _stopped() {
    if (!_ball.sunk && _strokes < GolfMatch.maxStrokes) return;
    HapticFeedback.mediumImpact();
    _waiting = true;
    final strokes = _strokes;
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() {
        _match.finish(strokes);
        _strokes = 0;
        _waiting = false;
        if (!_match.isOver) _ball = GolfBall(_match.holes[_match.hole]);
      });
      if (_match.isOver) {
        final leaders = _match.leaders;
        showResult(
          context,
          title: widget.players == 1
              ? 'Ударов: ${_match.total(0)}'
              : leaders.length == 1
                  ? 'Победил ${playerNames[leaders.first]}!'
                  : 'Ничья',
          subtitle: [for (var p = 0; p < widget.players; p++) '${playerNames[p]}: ${_match.total(p)}'].join(' · '),
          color: leaders.length == 1 ? playerColors[leaders.first] : null,
          onAgain: _restart,
        );
      }
    });
  }

  Offset _toCourse(Offset local) => (local - _origin) / _scale;

  @override
  Widget build(BuildContext context) {
    final hole = _match.holes[math.min(_match.hole, _match.holes.length - 1)];
    return GameScaffold(
      title: 'Мини-гольф',
      onRestart: _restart,
      body: Column(
        children: [
          ScoreRow(
            scores: [for (var p = 0; p < widget.players; p++) _match.total(p)],
            active: _match.isOver ? -1 : _match.turn,
          ),
          TurnBanner(
            player: _match.isOver ? -1 : _match.turn,
            text: _ball.sunk
                ? 'В лунке! Ударов: $_strokes'
                : 'Лунка ${_match.hole + 1}/${_match.holes.length} «${hole.name}», пар ${hole.par} · '
                    '${playerNames[_match.turn]}, удар ${_strokes + 1}',
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                _scale = math.min(box.maxWidth - 24, (box.maxHeight - 16) / hole.length);
                _origin = Offset((box.maxWidth - _scale) / 2, (box.maxHeight - _scale * hole.length) / 2);
                return Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) {
                    if (_ball.moving || _waiting || _ball.sunk) return;
                    setState(() => _drag = _toCourse(e.localPosition));
                  },
                  onPointerMove: (e) {
                    if (_drag != null) setState(() => _drag = _toCourse(e.localPosition));
                  },
                  onPointerUp: (_) {
                    final d = _drag;
                    _drag = null;
                    if (d == null) return;
                    // Рогатка: тянешь назад — мяч летит вперёд.
                    final pull = _ball.pos - d;
                    if (pull.distance < 0.03) return setState(() {});
                    _strokes++;
                    _ball.hit(pull * 4.5);
                    HapticFeedback.lightImpact();
                    setState(() {});
                  },
                  child: CustomPaint(
                    size: Size(box.maxWidth, box.maxHeight),
                    painter: _CoursePainter(hole, _ball, _origin, _scale, _drag),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('Тяни назад от мяча и отпусти — как рогатку',
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

class _CoursePainter extends CustomPainter {
  final GolfHole hole;
  final GolfBall ball;
  final Offset origin;
  final double s;
  final Offset? drag;

  _CoursePainter(this.hole, this.ball, this.origin, this.s, this.drag);

  @override
  void paint(Canvas canvas, Size size) {
    Offset at(Offset p) => origin + p * s;
    Rect rect(Rect r) => Rect.fromPoints(at(r.topLeft), at(r.bottomRight));

    final field = Rect.fromLTWH(origin.dx, origin.dy, s, s * hole.length);
    canvas.drawRRect(RRect.fromRectAndRadius(field.inflate(8), const Radius.circular(14)),
        Paint()..color = const Color(0xFF5D3A1A));
    canvas.drawRect(field, Paint()..color = const Color(0xFF2E9E4F));
    for (final sand in hole.sand) {
      canvas.drawRRect(RRect.fromRectAndRadius(rect(sand), const Radius.circular(10)), Paint()..color = const Color(0xFFE8D29A));
    }
    for (final w in hole.walls) {
      canvas.drawRect(rect(w), Paint()..color = const Color(0xFF5D3A1A));
    }
    canvas.drawCircle(at(hole.cup), GolfBall.cupR * s, Paint()..color = const Color(0xFF0B0B0B));
    // Флажок.
    final cup = at(hole.cup);
    canvas.drawLine(cup, cup - Offset(0, s * 0.12), Paint()..color = Colors.white..strokeWidth = 2);
    canvas.drawPath(
      Path()
        ..moveTo(cup.dx, cup.dy - s * 0.12)
        ..lineTo(cup.dx + s * 0.07, cup.dy - s * 0.1)
        ..lineTo(cup.dx, cup.dy - s * 0.08)
        ..close(),
      Paint()..color = const Color(0xFFE5484D),
    );

    final b = at(ball.pos);
    final d = drag;
    if (d != null) {
      final pull = ball.pos - d;
      final power = (pull.distance * 4.5 / GolfBall.maxSpeed).clamp(0.0, 1.0);
      final aim = Paint()
        ..color = Color.lerp(Colors.white, const Color(0xFFE5484D), power)!
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      final dir = pull.distance == 0 ? Offset.zero : pull / pull.distance;
      canvas.drawLine(b, b + dir * (s * 0.12 + power * s * 0.35), aim);
    }
    if (!ball.sunk) {
      canvas.drawCircle(b + const Offset(1.5, 2), GolfBall.r * s, Paint()..color = const Color(0x55000000));
      canvas.drawCircle(b, GolfBall.r * s, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ═════════════════════════════════════════════════════════════════════════
//  Пенальти
// ═════════════════════════════════════════════════════════════════════════

enum _KickStage { keeper, shooter, flight }

class PenaltyScreen extends StatefulWidget {
  const PenaltyScreen({super.key});

  @override
  State<PenaltyScreen> createState() => _PenaltyScreenState();
}

class _PenaltyScreenState extends State<PenaltyScreen> {
  var _series = PenaltyShootout();
  var _stage = _KickStage.keeper;
  int _keeperZone = 4;

  /// Куда летит мяч: x -1..1 по ширине ворот, y 0..1 по высоте.
  Offset? _target;
  String? _result;
  Offset? _swipeStart;
  Size _size = Size.zero;

  int get _shooter => _series.shooter;
  int get _keeper => 1 - _shooter;

  void _restart() => setState(() {
        _series = PenaltyShootout();
        _stage = _KickStage.keeper;
        _target = null;
        _result = null;
      });

  void _pickZone(int z) => setState(() {
        _keeperZone = z;
        _stage = _KickStage.shooter;
      });

  /// Свайп от мяча к воротам: направление — куда, длина — высота удара.
  void _shoot(Offset end) {
    final start = _swipeStart;
    _swipeStart = null;
    if (start == null || _stage != _KickStage.shooter) return;
    final d = end - start;
    if (d.dy > -30) return;
    final x = d.dx / (_size.width * 0.32);
    final y = (-d.dy - _size.height * 0.18) / (_size.height * 0.32);
    final result = Penalty.resolve(x: x, y: y, keeperZone: _keeperZone);
    HapticFeedback.mediumImpact();
    setState(() {
      _target = Offset(x, y);
      _stage = _KickStage.flight;
      _result = result.label;
    });
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() {
        _series.record(result.goal);
        _stage = _KickStage.keeper;
        _target = null;
        _result = null;
      });
      final w = _series.winner;
      if (w >= 0) {
        showResult(
          context,
          title: 'Победил ${playerNames[w]}!',
          subtitle: 'Голов: ${_series.goals(0)} : ${_series.goals(1)}',
          color: playerColors[w],
          onAgain: _restart,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'Пенальти',
      onRestart: _restart,
      body: Column(
        children: [
          _Kicks(series: _series),
          TurnBanner(
            player: _stage == _KickStage.keeper ? _keeper : _shooter,
            text: switch (_stage) {
              _KickStage.keeper => 'Вратарь ${playerNames[_keeper]}: выбери угол. ${playerNames[_shooter]}, не смотри!',
              _KickStage.shooter => 'Бьёт ${playerNames[_shooter]}: свайп от мяча в ворота',
              _KickStage.flight => _result ?? '',
            },
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                _size = Size(box.maxWidth, box.maxHeight);
                return Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) => _swipeStart = e.localPosition,
                  onPointerUp: (e) => _shoot(e.localPosition),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _PitchPainter(
                            keeperZone: _stage == _KickStage.flight ? _keeperZone : null,
                            target: _target,
                            keeperColor: playerColors[_keeper],
                          ),
                        ),
                      ),
                      if (_stage == _KickStage.keeper) Positioned.fill(child: _ZonePicker(onPick: _pickZone, size: _size)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Геометрия ворот на экране — общая для рисования и выбора зоны.
Rect _goalRect(Size s) => Rect.fromLTWH(s.width * 0.1, s.height * 0.12, s.width * 0.8, s.height * 0.32);

class _ZonePicker extends StatelessWidget {
  final ValueChanged<int> onPick;
  final Size size;

  const _ZonePicker({required this.onPick, required this.size});

  @override
  Widget build(BuildContext context) {
    final g = _goalRect(size);
    return Stack(
      children: [
        for (var z = 0; z < 6; z++)
          Positioned(
            left: g.left + (z % 3) * g.width / 3,
            top: g.top + (z ~/ 3) * g.height / 2,
            width: g.width / 3,
            height: g.height / 2,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Material(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onPick(z),
                  child: const Center(child: Text('🧤', style: TextStyle(fontSize: 26))),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PitchPainter extends CustomPainter {
  final int? keeperZone;
  final Offset? target;
  final Color keeperColor;

  _PitchPainter({required this.keeperZone, required this.target, required this.keeperColor});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
        ).createShader(Offset.zero & size),
    );
    final g = _goalRect(size);
    // Сетка.
    final net = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    for (var i = 1; i < 12; i++) {
      final x = g.left + g.width * i / 12;
      canvas.drawLine(Offset(x, g.top), Offset(x, g.bottom), net);
    }
    for (var i = 1; i < 5; i++) {
      final y = g.top + g.height * i / 5;
      canvas.drawLine(Offset(g.left, y), Offset(g.right, y), net);
    }
    final post = Paint()
      ..color = Colors.white
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      Path()
        ..moveTo(g.left, g.bottom)
        ..lineTo(g.left, g.top)
        ..lineTo(g.right, g.top)
        ..lineTo(g.right, g.bottom),
      post,
    );
    // Вратарь: в центре или в прыжке в выбранную зону.
    final z = keeperZone;
    final keeper = z == null
        ? Offset(g.center.dx, g.bottom - g.height * 0.3)
        : Offset(g.left + (z % 3 + 0.5) * g.width / 3, g.top + (z ~/ 3 + 0.5) * g.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: keeper, width: g.width / 3.4, height: g.height / 2.4),
          const Radius.circular(12)),
      Paint()..color = keeperColor.withValues(alpha: 0.9),
    );
    canvas.drawCircle(keeper - Offset(0, g.height / 3.6), g.height * 0.09, Paint()..color = const Color(0xFFFFCC80));

    // Мяч: на точке или в воротах.
    final t = target;
    final ball = t == null
        ? Offset(size.width / 2, size.height * 0.82)
        : Offset(g.center.dx + t.dx * g.width / 2, g.bottom - t.dy * g.height);
    canvas.drawCircle(ball, 16, Paint()..color = Colors.white);
    canvas.drawCircle(ball, 6, Paint()..color = Colors.black87);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Серия ударов: ● гол, ✕ мимо, ○ ещё не бил.
class _Kicks extends StatelessWidget {
  final PenaltyShootout series;

  const _Kicks({required this.series});

  @override
  Widget build(BuildContext context) {
    Widget row(int p) {
      final r = series.results[p];
      final n = math.max(PenaltyShootout.kicks, r.length);
      return Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(playerNames[p], style: TextStyle(color: playerColors[p], fontWeight: FontWeight.w800)),
          ),
          for (var i = 0; i < n; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Text(
                i >= r.length ? '○' : (r[i] ? '●' : '✕'),
                style: TextStyle(
                  fontSize: 18,
                  color: i >= r.length ? AppColors.textDim : (r[i] ? const Color(0xFF30A46C) : AppColors.red),
                ),
              ),
            ),
          const Spacer(),
          Text('${series.goals(p)}', style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w900)),
        ],
      );
    }

    return Padding(padding: const EdgeInsets.fromLTRB(18, 10, 18, 2), child: Column(children: [row(0), row(1)]));
  }
}

/// Перед дартсом: режим игры.
Future<DartsMode?> pickDartsMode(BuildContext context) {
  return showModalBottomSheet<DartsMode>(
    context: context,
    backgroundColor: AppColors.sheet,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Text('🎯', style: TextStyle(fontSize: 26)),
            title: const Text('301'),
            subtitle: const Text('Сбей 301 очко ровно до нуля. Перебор — ход сгорает'),
            onTap: () => Navigator.pop(sheetContext, DartsMode.x301),
          ),
          ListTile(
            leading: const Text('🏅', style: TextStyle(fontSize: 26)),
            title: const Text('На очки'),
            subtitle: const Text('5 ходов по 3 дротика — у кого больше'),
            onTap: () => Navigator.pop(sheetContext, DartsMode.rounds),
          ),
        ],
      ),
    ),
  );
}
