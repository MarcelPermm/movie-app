import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

/// Спортивные игры: дартс, боулинг, мини-гольф, пенальти. Без виджетов.

// ─── Дартс ───────────────────────────────────────────────────────────────

class Darts {
  /// Сектора по часовой стрелке, начиная с верхнего.
  static const sectors = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5];

  /// Радиусы колец в долях радиуса внешнего края удвоения (как у настоящей
  /// мишени: 6,35 / 15,9 / 99 / 107 / 162 / 170 мм).
  static const bull = 6.35 / 170;
  static const outerBull = 15.9 / 170;
  static const tripleIn = 99 / 170;
  static const tripleOut = 107 / 170;
  static const doubleIn = 162 / 170;

  /// Очки за попадание в точку [p] (центр мишени — 0,0, край удвоения — 1).
  /// Ось y — вниз, как на экране.
  static ({int points, String label}) score(Offset p) {
    final r = p.distance;
    if (r > 1) return (points: 0, label: 'мимо');
    if (r <= bull) return (points: 50, label: 'яблочко');
    if (r <= outerBull) return (points: 25, label: '25');
    // Угол от вертикали вверх, по часовой; сектор 20 занимает ±9°.
    var deg = math.atan2(p.dx, -p.dy) * 180 / math.pi;
    if (deg < 0) deg += 360;
    final base = sectors[((deg + 9) ~/ 18) % 20];
    if (r >= tripleIn && r <= tripleOut) return (points: base * 3, label: 'T$base');
    if (r >= doubleIn) return (points: base * 2, label: 'D$base');
    return (points: base, label: '$base');
  }
}

enum DartsMode { x301, rounds }

/// Партия: каждый бросает по 3 дротика за ход.
///
/// «301»: очки вычитаются; перебор (ниже нуля) сгорает — счёт возвращается к
/// началу хода. Кто первым дошёл ровно до нуля — победил.
/// «На очки»: 5 ходов, у кого сумма больше.
class DartsMatch {
  final int players;
  final DartsMode mode;
  static const rounds = 5;

  late final List<int> totals = List.filled(players, mode == DartsMode.x301 ? 301 : 0);
  int turn = 0;
  int round = 1;
  final List<int> thisTurn = [];
  int _turnStart = 0;
  bool bust = false;
  int winner = -1;

  DartsMatch({this.players = 2, this.mode = DartsMode.x301}) {
    _turnStart = totals[0];
  }

  bool get isOver => winner >= 0 || (mode == DartsMode.rounds && round > rounds);

  /// Засчитать дротик. Возвращает true, если ход закончился.
  bool throwDart(int points) {
    if (isOver) return true;
    thisTurn.add(points);
    if (mode == DartsMode.x301) {
      final left = totals[turn] - points;
      if (left < 0) {
        bust = true;
        totals[turn] = _turnStart;
        return true;
      }
      totals[turn] = left;
      if (left == 0) {
        winner = turn;
        return true;
      }
    } else {
      totals[turn] += points;
    }
    return thisTurn.length >= 3;
  }

  void nextTurn() {
    thisTurn.clear();
    bust = false;
    if (winner >= 0) return;
    turn = (turn + 1) % players;
    if (turn == 0) round++;
    _turnStart = totals[turn];
    if (mode == DartsMode.rounds && round > rounds) {
      final best = totals.reduce(math.max);
      winner = totals.indexOf(best);
    }
  }
}

// ─── Боулинг: счёт ───────────────────────────────────────────────────────

/// Счёт по правилам: 10 фреймов, страйк — +2 следующих броска, спэр — +1,
/// в десятом фрейме до трёх бросков.
class BowlingCard {
  final List<int> rolls = [];

  /// Сбитые за каждый бросок → счёт по фреймам (null — ещё не известен).
  List<int?> get frameTotals {
    final out = <int?>[];
    var i = 0;
    var total = 0;
    for (var f = 0; f < 10; f++) {
      if (i >= rolls.length) {
        out.add(null);
        continue;
      }
      int? frame;
      if (rolls[i] == 10) {
        if (i + 2 < rolls.length) frame = 10 + rolls[i + 1] + rolls[i + 2];
        i += 1;
      } else if (i + 1 < rolls.length && rolls[i] + rolls[i + 1] == 10) {
        if (i + 2 < rolls.length) frame = 10 + rolls[i + 2];
        i += 2;
      } else if (i + 1 < rolls.length) {
        frame = rolls[i] + rolls[i + 1];
        i += 2;
      } else {
        i += 2;
      }
      if (frame == null) {
        out.add(null);
        // Дальше без бонуса не посчитать.
        while (out.length < 10) {
          out.add(null);
        }
        break;
      }
      total += frame;
      out.add(total);
    }
    return out;
  }

  int get total => frameTotals.whereType<int>().fold(0, math.max);

  /// Текущий фрейм (0..9) и бросок в нём (0..2).
  (int, int) get position {
    var i = 0;
    for (var f = 0; f < 9; f++) {
      if (i >= rolls.length) return (f, 0);
      if (rolls[i] == 10) {
        i += 1;
      } else {
        if (i + 1 >= rolls.length) return (f, 1);
        i += 2;
      }
    }
    return (9, rolls.length - i);
  }

  bool get isComplete {
    final (frame, roll) = position;
    if (frame < 9) return false;
    final tenth = rolls.sublist(rolls.length - roll);
    if (roll < 2) return false;
    if (roll == 2) return tenth[0] + tenth[1] < 10; // без страйка и спэра — 2 броска
    return true; // три броска
  }

  /// Нужно ли перед следующим броском поставить все кегли заново.
  bool get freshRack {
    final (frame, roll) = position;
    if (roll == 0) return true;
    if (frame < 9) return false;
    final tenth = rolls.sublist(rolls.length - roll);
    if (roll == 1) return tenth[0] == 10;
    return tenth[0] == 10 ? tenth[1] == 10 : tenth[0] + tenth[1] == 10;
  }

  void add(int pins) => rolls.add(pins);
}

// ─── Боулинг: дорожка ────────────────────────────────────────────────────

class Pin {
  Offset pos;
  Offset vel = Offset.zero;
  bool down = false;
  final Offset home;

  Pin(this.home) : pos = home;
}

/// Дорожка сверху: шар катится снизу вверх. Ширина 1, длина [length].
class BowlingLane {
  static const length = 6.0;
  static const ballR = 0.085;
  static const pinR = 0.045;

  late List<Pin> pins;
  Offset ball = const Offset(0.5, length - 0.3);
  Offset ballVel = Offset.zero;

  /// Подкрутка: поперечное ускорение, пока шар катится.
  double spin = 0;
  bool rolling = false;
  double _time = 0;

  BowlingLane() {
    pins = _rack();
  }

  /// Треугольник из 10 кеглей, первая — ближе всех к игроку.
  static List<Pin> _rack() {
    const gap = 0.16;
    const headY = 0.95;
    return [
      for (var row = 0; row < 4; row++)
        for (var k = 0; k <= row; k++)
          Pin(Offset(0.5 + (k - row / 2) * gap, headY - row * gap * 0.87)),
    ];
  }

  void resetRack() => pins = _rack();

  /// Убрать сбитые (между бросками фрейма) и вернуть шар.
  void clearFallen() {
    pins = pins.where((p) => !p.down).map((p) => Pin(p.home)).toList();
  }

  int get standing => pins.where((p) => !p.down).length;

  void launch({required double aimX, required Offset velocity, double spin = 0}) {
    ball = Offset(aimX.clamp(ballR, 1 - ballR), length - 0.3);
    ballVel = velocity;
    this.spin = spin;
    rolling = true;
    _time = 0;
  }

  /// Шаг. Возвращает true, когда всё остановилось.
  bool step(double dt) {
    if (!rolling) return true;
    _time += dt;
    const sub = 4;
    final h = dt / sub;
    for (var s = 0; s < sub; s++) {
      _sub(h);
    }
    final moving = ballVel.distance > 0.05 && ball.dy > -0.5 ||
        pins.any((p) => p.vel.distance > 0.05);
    if (!moving || _time > 8) {
      rolling = false;
      return true;
    }
    return false;
  }

  void _sub(double dt) {
    // Шар: подкрутка заворачивает его, пока он не дошёл до кеглей.
    if (ball.dy > 1.2) ballVel += Offset(spin * dt, 0);
    ball += ballVel * dt;

    // Желоб: шар, ушедший за край, катится по нему мимо кеглей.
    if (ball.dx < ballR * 0.5 || ball.dx > 1 - ballR * 0.5) {
      ballVel = Offset(0, ballVel.dy);
      ball = Offset(ball.dx.clamp(-0.2, 1.2), ball.dy);
    }

    for (final p in pins) {
      p.pos += p.vel * dt;
      p.vel = p.vel * math.pow(0.08, dt).toDouble();
    }

    void collide(Offset aPos, Offset aVel, double aR, double aMass, Pin pin, void Function(Offset) setA) {
      final d = pin.pos - aPos;
      final dist = d.distance;
      final minDist = aR + pinR;
      if (dist >= minDist || dist == 0) return;
      final n = d / dist;
      final rel = aVel - pin.vel;
      final along = rel.dx * n.dx + rel.dy * n.dy;
      if (along <= 0) return;
      // Упругий удар: шар тяжелее кегли, поэтому почти не тормозит.
      const pinMass = 1.0;
      final impulse = 2 * along / (1 / aMass + 1 / pinMass);
      setA(aVel - n * (impulse / aMass));
      pin.vel += n * (impulse / pinMass);
      pin.pos = aPos + n * minDist;
      pin.down = true;
    }

    // Шар сбивает кегли (шар игнорирует сбитые, они уже летят в сторону).
    if (ball.dx > 0 && ball.dx < 1) {
      for (final p in pins) {
        collide(ball, ballVel, ballR, 6, p, (v) => ballVel = v);
      }
    }
    // Летящие кегли сбивают соседние.
    for (final a in pins) {
      if (a.vel.distance < 0.15) continue;
      for (final b in pins) {
        if (identical(a, b)) continue;
        final d = b.pos - a.pos;
        if (d.distance < pinR * 2 && d.distance > 0) {
          final n = d / d.distance;
          final along = (a.vel - b.vel).dx * n.dx + (a.vel - b.vel).dy * n.dy;
          if (along > 0) {
            a.vel -= n * along;
            b.vel += n * along;
            b.pos = a.pos + n * pinR * 2;
            b.down = true;
          }
        }
      }
    }
    // Кегля, вылетевшая за дорожку, — тоже сбита.
    for (final p in pins) {
      if (p.pos.dx < 0 || p.pos.dx > 1 || p.pos.dy < 0) p.down = true;
    }
  }
}

// ─── Мини-гольф ──────────────────────────────────────────────────────────

class GolfHole {
  final String name;
  final double length;
  final Offset start;
  final Offset cup;

  /// Стены-препятствия (прямоугольники) и песок, где мяч вязнет.
  final List<Rect> walls;
  final List<Rect> sand;
  final int par;

  const GolfHole({
    required this.name,
    required this.start,
    required this.cup,
    this.length = 1.6,
    this.walls = const [],
    this.sand = const [],
    this.par = 3,
  });

  static const all = <GolfHole>[
    GolfHole(name: 'Прямая', start: Offset(0.5, 1.4), cup: Offset(0.5, 0.25), par: 2),
    GolfHole(
      name: 'Стенка',
      start: Offset(0.5, 1.4),
      cup: Offset(0.5, 0.25),
      walls: [Rect.fromLTWH(0.18, 0.75, 0.64, 0.06)],
    ),
    GolfHole(
      name: 'Зигзаг',
      start: Offset(0.2, 1.4),
      cup: Offset(0.8, 0.22),
      walls: [Rect.fromLTWH(0.0, 1.0, 0.65, 0.06), Rect.fromLTWH(0.35, 0.55, 0.65, 0.06)],
      par: 4,
    ),
    GolfHole(
      name: 'Песочница',
      start: Offset(0.5, 1.4),
      cup: Offset(0.5, 0.3),
      sand: [Rect.fromLTWH(0.15, 0.55, 0.7, 0.3)],
    ),
    GolfHole(
      name: 'Ворота',
      start: Offset(0.15, 1.4),
      cup: Offset(0.85, 0.25),
      walls: [
        Rect.fromLTWH(0.0, 0.8, 0.4, 0.06),
        Rect.fromLTWH(0.6, 0.8, 0.4, 0.06),
        Rect.fromLTWH(0.46, 0.35, 0.08, 0.3),
      ],
      sand: [Rect.fromLTWH(0.6, 0.1, 0.4, 0.12)],
      par: 4,
    ),
    GolfHole(
      name: 'Лабиринт',
      start: Offset(0.15, 1.45),
      cup: Offset(0.15, 0.2),
      walls: [
        Rect.fromLTWH(0.0, 1.15, 0.75, 0.05),
        Rect.fromLTWH(0.25, 0.85, 0.75, 0.05),
        Rect.fromLTWH(0.0, 0.55, 0.75, 0.05),
      ],
      par: 5,
    ),
  ];
}

class GolfBall {
  static const r = 0.025;
  static const cupR = 0.045;
  static const maxSpeed = 2.4;

  final GolfHole hole;
  Offset pos;
  Offset vel = Offset.zero;
  bool sunk = false;

  GolfBall(this.hole) : pos = hole.start;

  bool get moving => vel.distance > 0.01;

  void hit(Offset v) {
    final s = v.distance;
    vel = s > maxSpeed ? v / s * maxSpeed : v;
  }

  /// Шаг физики. Возвращает true, когда мяч остановился или в лунке.
  bool step(double dt) {
    if (sunk) return true;
    const sub = 6;
    for (var i = 0; i < sub; i++) {
      _sub(dt / sub);
      if (sunk) return true;
    }
    if (!moving) {
      vel = Offset.zero;
      return true;
    }
    return false;
  }

  void _sub(double dt) {
    final inSand = hole.sand.any((s) => s.contains(pos));
    final drag = inSand ? 0.02 : 0.35; // доля скорости, остающаяся за секунду
    vel = vel * math.pow(drag, dt).toDouble();
    pos += vel * dt;

    // Борта поля.
    if (pos.dx < r) {
      pos = Offset(r, pos.dy);
      vel = Offset(-vel.dx * 0.8, vel.dy);
    } else if (pos.dx > 1 - r) {
      pos = Offset(1 - r, pos.dy);
      vel = Offset(-vel.dx * 0.8, vel.dy);
    }
    if (pos.dy < r) {
      pos = Offset(pos.dx, r);
      vel = Offset(vel.dx, -vel.dy * 0.8);
    } else if (pos.dy > hole.length - r) {
      pos = Offset(pos.dx, hole.length - r);
      vel = Offset(vel.dx, -vel.dy * 0.8);
    }

    // Стенки: отражаем по оси наименьшего проникновения.
    for (final w in hole.walls) {
      final grown = w.inflate(r);
      if (!grown.contains(pos)) continue;
      final dl = pos.dx - grown.left, dr = grown.right - pos.dx;
      final dtp = pos.dy - grown.top, db = grown.bottom - pos.dy;
      final m = [dl, dr, dtp, db].reduce(math.min);
      if (m == dl) {
        pos = Offset(grown.left, pos.dy);
        vel = Offset(-vel.dx.abs() * 0.8, vel.dy);
      } else if (m == dr) {
        pos = Offset(grown.right, pos.dy);
        vel = Offset(vel.dx.abs() * 0.8, vel.dy);
      } else if (m == dtp) {
        pos = Offset(pos.dx, grown.top);
        vel = Offset(vel.dx, -vel.dy.abs() * 0.8);
      } else {
        pos = Offset(pos.dx, grown.bottom);
        vel = Offset(vel.dx, vel.dy.abs() * 0.8);
      }
    }

    // Лунка: мяч падает, если достаточно медленный; быстрый перескакивает.
    if ((pos - hole.cup).distance < cupR && vel.distance < 1.1) {
      sunk = true;
      pos = hole.cup;
      vel = Offset.zero;
    }
  }
}

/// Партия: лунки по очереди, на каждой все игроки бьют до попадания
/// (не больше [maxStrokes] — дальше ставится максимум).
class GolfMatch {
  static const maxStrokes = 8;
  final int players;
  final List<GolfHole> holes;
  late final List<List<int>> strokes = List.generate(players, (_) => []);
  int hole = 0;
  int turn = 0;

  GolfMatch({this.players = 2, this.holes = GolfHole.all});

  bool get isOver => hole >= holes.length;

  int total(int p) => strokes[p].fold(0, (a, b) => a + b);

  /// Игрок закончил лунку за [n] ударов.
  void finish(int n) {
    strokes[turn].add(math.min(n, maxStrokes));
    turn++;
    if (turn >= players) {
      turn = 0;
      hole++;
    }
  }

  List<int> get leaders {
    final best = [for (var p = 0; p < players; p++) total(p)].reduce(math.min);
    return [for (var p = 0; p < players; p++) if (total(p) == best) p];
  }
}

// ─── Пенальти ────────────────────────────────────────────────────────────

/// Ворота делятся на 6 зон: 3 по ширине × 2 по высоте.
/// Вратарь выбирает зону заранее, бьющий — точку удара.
class Penalty {
  /// Куда ударили: x от -1 до 1 (края ворот), y от 0 (низ) до 1 (перекладина).
  /// За пределами — мимо.
  static int zoneOf(double x, double y) {
    final col = x < -1 / 3 ? 0 : (x > 1 / 3 ? 2 : 1);
    final row = y < 0.5 ? 1 : 0; // 0 — верх, 1 — низ
    return row * 3 + col;
  }

  static ({bool goal, String label}) resolve({required double x, required double y, required int keeperZone}) {
    if (x.abs() > 1 || y > 1 || y < 0) return (goal: false, label: 'Мимо!');
    if (zoneOf(x, y) == keeperZone) return (goal: false, label: 'Вратарь взял!');
    return (goal: true, label: 'ГОЛ!');
  }
}

class PenaltyShootout {
  static const kicks = 5;
  final List<List<bool>> results = [[], []];

  /// Бьёт игрок [shooter], вратарь — другой.
  int get shooter => results[0].length > results[1].length ? 1 : 0;

  int goals(int p) => results[p].where((g) => g).length;

  void record(bool goal) => results[shooter].add(goal);

  /// Победитель или -1. После 5 ударов при равенстве — по удару до первой
  /// разницы (пара ударов).
  int get winner {
    final a = results[0], b = results[1];
    final left0 = math.max(0, kicks - a.length), left1 = math.max(0, kicks - b.length);
    final g0 = goals(0), g1 = goals(1);
    if (a.length <= kicks && b.length <= kicks) {
      if (g0 > g1 + left1) return 0;
      if (g1 > g0 + left0) return 1;
      if (a.length < kicks || b.length < kicks) return -1;
    }
    if (a.length == b.length && g0 != g1) return g0 > g1 ? 0 : 1;
    return -1;
  }
}
