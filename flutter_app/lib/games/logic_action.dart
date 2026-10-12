import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Логика игр «с движением» и морского боя — без виджетов, под тесты.

// ─── Аэрохокей ───────────────────────────────────────────────────────────

/// Стол в собственных единицах: ширина 1, высота [length]. Игрок 0 —
/// сверху (его ворота у y=0), игрок 1 — снизу (ворота у y=length).
class AirHockey {
  static const puckR = 0.04;
  static const malletR = 0.075;
  static const goalWidth = 0.38;
  static const maxSpeed = 3.2; // столов в секунду
  static const friction = 0.55; // доля скорости, теряемая за секунду
  static const wallBounce = 0.9;

  final double length;
  final int target;

  Offset puck;
  Offset puckVel = Offset.zero;
  final List<Offset> mallets;
  final List<Offset> _malletVel = [Offset.zero, Offset.zero];
  final List<int> scores = [0, 0];

  /// Кто забил последним (-1 — никто): к нему шайба подаётся после гола.
  int lastGoal = -1;

  AirHockey({this.length = 1.6, this.target = 7})
      : puck = Offset(0.5, length / 2),
        mallets = [Offset(0.5, length * 0.15), Offset(0.5, length * 0.85)];

  int get winner {
    for (var i = 0; i < 2; i++) {
      if (scores[i] >= target) return i;
    }
    return -1;
  }

  /// Бита игрока следует за пальцем, но не выходит из своей половины.
  void moveMallet(int player, Offset to, double dt) {
    final half = length / 2;
    final minY = player == 0 ? malletR : half + malletR;
    final maxY = player == 0 ? half - malletR : length - malletR;
    final clamped = Offset(
      to.dx.clamp(malletR, 1 - malletR),
      to.dy.clamp(minY, maxY),
    );
    if (dt > 0) _malletVel[player] = (clamped - mallets[player]) / dt;
    mallets[player] = clamped;
  }

  /// Шаг физики. Возвращает номер забившего или -1.
  int step(double dt) {
    // Мелкие подшаги: быстрая шайба не должна проскакивать сквозь биту.
    const sub = 4;
    final h = dt / sub;
    for (var i = 0; i < sub; i++) {
      final goal = _substep(h);
      if (goal >= 0) return goal;
    }
    for (var p = 0; p < 2; p++) {
      _malletVel[p] = _malletVel[p] * math.pow(0.02, dt).toDouble();
    }
    return -1;
  }

  int _substep(double dt) {
    puck += puckVel * dt;
    puckVel = puckVel * math.pow(1 - friction, dt).toDouble();

    // Боковые борта.
    if (puck.dx < puckR) {
      puck = Offset(puckR, puck.dy);
      puckVel = Offset(-puckVel.dx * wallBounce, puckVel.dy);
    } else if (puck.dx > 1 - puckR) {
      puck = Offset(1 - puckR, puck.dy);
      puckVel = Offset(-puckVel.dx * wallBounce, puckVel.dy);
    }

    // Торцы: в створе ворот — гол, иначе отскок.
    final inMouth = (puck.dx - 0.5).abs() < goalWidth / 2;
    if (puck.dy < puckR) {
      if (inMouth && puck.dy < -puckR) return _goal(1);
      if (!inMouth) {
        puck = Offset(puck.dx, puckR);
        puckVel = Offset(puckVel.dx, -puckVel.dy * wallBounce);
      }
    } else if (puck.dy > length - puckR) {
      if (inMouth && puck.dy > length + puckR) return _goal(0);
      if (!inMouth) {
        puck = Offset(puck.dx, length - puckR);
        puckVel = Offset(puckVel.dx, -puckVel.dy * wallBounce);
      }
    }

    // Удар битой: шайбу выталкиваем из биты и отражаем относительную
    // скорость — так сильный замах даёт сильный удар.
    for (var p = 0; p < 2; p++) {
      final d = puck - mallets[p];
      final dist = d.distance;
      const minDist = puckR + malletR;
      if (dist < minDist && dist > 0) {
        final n = d / dist;
        puck = mallets[p] + n * minDist;
        final rel = puckVel - _malletVel[p];
        final along = rel.dx * n.dx + rel.dy * n.dy;
        if (along < 0) {
          puckVel = puckVel - n * (2 * along) + _malletVel[p] * 0.15;
        }
      }
    }

    final speed = puckVel.distance;
    if (speed > maxSpeed) puckVel = puckVel / speed * maxSpeed;
    return -1;
  }

  int _goal(int scorer) {
    scores[scorer]++;
    lastGoal = scorer;
    // Подача — на половину пропустившего: ему отыгрываться.
    final loser = 1 - scorer;
    puck = Offset(0.5, loser == 0 ? length * 0.3 : length * 0.7);
    puckVel = Offset.zero;
    return scorer;
  }
}

// ─── Световые мотоциклы ──────────────────────────────────────────────────

enum Heading { up, right, down, left }

extension on Heading {
  (int, int) get delta => switch (this) {
        Heading.up => (0, -1),
        Heading.right => (1, 0),
        Heading.down => (0, 1),
        Heading.left => (-1, 0),
      };

  Heading turned(bool clockwise) =>
      Heading.values[(index + (clockwise ? 1 : 3)) % 4];
}

class Cycle {
  int x, y;
  Heading heading;
  bool alive = true;

  /// Поворот, который применится на следующем шаге (одно нажатие — один
  /// поворот, даже если тапнули между шагами дважды по-разному).
  Heading? _pending;

  Cycle(this.x, this.y, this.heading);
}

/// Мотоциклы едут сами и оставляют стену. Врезался в стену, чужой или
/// свой след — выбыл. Последний оставшийся берёт раунд.
class LightCycles {
  final int width;
  final int height;
  final int players;
  final int target;

  /// Владелец клетки (след) или -1.
  late List<List<int>> trail;
  late List<Cycle> cycles;
  late final List<int> scores = List.filled(players, 0);
  int roundWinner = -1;
  bool roundOver = false;

  LightCycles({this.width = 40, this.height = 64, this.players = 2, this.target = 3}) {
    newRound();
  }

  void newRound() {
    trail = List.generate(height, (_) => List.filled(width, -1));
    // Стартуют с середин сторон, носом к центру.
    final starts = [
      Cycle(width ~/ 2, 2, Heading.down),
      Cycle(width ~/ 2, height - 3, Heading.up),
      Cycle(2, height ~/ 2, Heading.right),
      Cycle(width - 3, height ~/ 2, Heading.left),
    ];
    cycles = starts.take(players).toList();
    for (var i = 0; i < players; i++) {
      trail[cycles[i].y][cycles[i].x] = i;
    }
    roundWinner = -1;
    roundOver = false;
  }

  void turn(int player, {required bool clockwise}) {
    final c = cycles[player];
    if (!c.alive || roundOver) return;
    c._pending = (c._pending ?? c.heading).turned(clockwise);
  }

  int get champion {
    for (var i = 0; i < players; i++) {
      if (scores[i] >= target) return i;
    }
    return -1;
  }

  /// Один шаг всех. Возвращает true, если раунд закончился.
  bool step() {
    if (roundOver) return true;
    final next = <int, (int, int)>{};
    for (var i = 0; i < players; i++) {
      final c = cycles[i];
      if (!c.alive) continue;
      if (c._pending != null) {
        // Разворот на 180° запрещён — это мгновенное самоубийство.
        if ((c._pending!.index - c.heading.index).abs() != 2) c.heading = c._pending!;
        c._pending = null;
      }
      final (dx, dy) = c.heading.delta;
      next[i] = (c.x + dx, c.y + dy);
    }

    // Лобовые: двое в одну клетку — выбывают оба.
    final crowd = <(int, int), int>{};
    for (final p in next.values) {
      crowd[p] = (crowd[p] ?? 0) + 1;
    }

    for (final e in next.entries) {
      final (x, y) = e.value;
      final c = cycles[e.key];
      final out = x < 0 || y < 0 || x >= width || y >= height;
      if (out || trail[y][x] != -1 || crowd[e.value]! > 1) {
        c.alive = false;
      }
    }
    for (final e in next.entries) {
      final c = cycles[e.key];
      if (!c.alive) continue;
      c.x = e.value.$1;
      c.y = e.value.$2;
      trail[c.y][c.x] = e.key;
    }

    final alive = [for (var i = 0; i < players; i++) if (cycles[i].alive) i];
    if (alive.length <= 1) {
      roundOver = true;
      roundWinner = alive.length == 1 ? alive.first : -1;
      if (roundWinner >= 0) scores[roundWinner]++;
    }
    return roundOver;
  }
}

// ─── Тап-гонка ───────────────────────────────────────────────────────────

/// Кто быстрее натапает [taps] нажатий, тот первым доехал.
class TapRace {
  final int players;
  final int taps;
  late final List<int> progress = List.filled(players, 0);
  int winner = -1;

  TapRace({this.players = 2, this.taps = 50});

  double share(int p) => progress[p] / taps;

  bool tap(int p) {
    if (winner >= 0) return false;
    progress[p]++;
    if (progress[p] >= taps) winner = p;
    return true;
  }
}

// ─── Морской бой ─────────────────────────────────────────────────────────

enum Shot { miss, hit, sunk, repeat }

class Ship {
  final List<(int, int)> cells;
  final Set<(int, int)> hits = {};

  Ship(this.cells);

  bool get sunk => hits.length == cells.length;
}

class Fleet {
  static const size = 10;

  /// Классический набор: 1×4, 2×3, 3×2, 4×1.
  static const lengths = [4, 3, 3, 2, 2, 2, 1, 1, 1, 1];

  final List<Ship> ships;

  /// Куда уже стреляли по этому флоту.
  final Set<(int, int)> shots = {};

  Fleet(this.ships);

  bool get defeated => ships.every((s) => s.sunk);

  Ship? shipAt(int x, int y) {
    for (final s in ships) {
      if (s.cells.contains((x, y))) return s;
    }
    return null;
  }

  /// Случайная расстановка по правилам: корабли не касаются даже углами.
  factory Fleet.random(math.Random rng) {
    while (true) {
      final taken = <(int, int)>{};
      final ships = <Ship>[];
      var ok = true;
      for (final len in lengths) {
        var placed = false;
        for (var attempt = 0; attempt < 200 && !placed; attempt++) {
          final horizontal = rng.nextBool();
          final x = rng.nextInt(horizontal ? size - len + 1 : size);
          final y = rng.nextInt(horizontal ? size : size - len + 1);
          final cells = [for (var i = 0; i < len; i++) horizontal ? (x + i, y) : (x, y + i)];
          if (cells.any((c) => _nearTaken(c, taken))) continue;
          taken.addAll(cells);
          ships.add(Ship(cells));
          placed = true;
        }
        if (!placed) {
          ok = false;
          break;
        }
      }
      if (ok) return Fleet(ships);
    }
  }

  static bool _nearTaken((int, int) c, Set<(int, int)> taken) {
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        if (taken.contains((c.$1 + dx, c.$2 + dy))) return true;
      }
    }
    return false;
  }

  /// Выстрел. Потопленный корабль обводится промахами — туда стрелять
  /// бессмысленно, и все так делают на бумаге.
  Shot fire(int x, int y) {
    if (shots.contains((x, y))) return Shot.repeat;
    shots.add((x, y));
    final ship = shipAt(x, y);
    if (ship == null) return Shot.miss;
    ship.hits.add((x, y));
    if (!ship.sunk) return Shot.hit;
    for (final (cx, cy) in ship.cells) {
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          final nx = cx + dx, ny = cy + dy;
          if (nx >= 0 && ny >= 0 && nx < size && ny < size) shots.add((nx, ny));
        }
      }
    }
    return Shot.sunk;
  }
}

class Battleship {
  final List<Fleet> fleets;
  int turn = 0;

  Battleship(math.Random rng) : fleets = [Fleet.random(rng), Fleet.random(rng)];

  /// Флот, по которому стреляет текущий игрок.
  Fleet get target => fleets[1 - turn];

  int get winner {
    if (fleets[1].defeated) return 0;
    if (fleets[0].defeated) return 1;
    return -1;
  }

  /// Попал — стреляешь ещё; промах — ход переходит.
  Shot fire(int x, int y) {
    final r = target.fire(x, y);
    if (r == Shot.miss) turn = 1 - turn;
    return r;
  }
}
