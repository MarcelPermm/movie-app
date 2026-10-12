import 'dart:math' as math;

/// Логика одиночных игр — без виджетов, под тесты.

enum Dir { up, down, left, right }

// ─── 2048 ────────────────────────────────────────────────────────────────

class Game2048 {
  static const n = 4;
  final math.Random _rng;

  /// 0 — пусто, иначе значение плитки.
  List<List<int>> grid = List.generate(n, (_) => List.filled(n, 0));
  int score = 0;
  bool won = false;

  /// Где появилась новая плитка — для анимации.
  (int, int)? spawned;

  Game2048([math.Random? rng]) : _rng = rng ?? math.Random() {
    _spawn();
    _spawn();
  }

  void _spawn() {
    final empty = [
      for (var r = 0; r < n; r++)
        for (var c = 0; c < n; c++)
          if (grid[r][c] == 0) (r, c),
    ];
    if (empty.isEmpty) return;
    final (r, c) = empty[_rng.nextInt(empty.length)];
    grid[r][c] = _rng.nextInt(10) == 0 ? 4 : 2;
    spawned = (r, c);
  }

  /// Сдвиг одной строки влево по правилам 2048: каждая плитка сливается
  /// не больше одного раза за ход. Возвращает (новая строка, очки).
  static (List<int>, int) slideRow(List<int> row) {
    final tiles = row.where((v) => v != 0).toList();
    final out = <int>[];
    var gained = 0;
    for (var i = 0; i < tiles.length; i++) {
      if (i + 1 < tiles.length && tiles[i] == tiles[i + 1]) {
        out.add(tiles[i] * 2);
        gained += tiles[i] * 2;
        i++;
      } else {
        out.add(tiles[i]);
      }
    }
    while (out.length < n) {
      out.add(0);
    }
    return (out, gained);
  }

  /// Ход. Возвращает false, если ничего не сдвинулось (тогда плитка не
  /// появляется — как в оригинале).
  bool move(Dir d) {
    var moved = false;
    for (var i = 0; i < n; i++) {
      // Линию читаем в сторону сдвига, сдвигаем «влево», кладём обратно.
      final cells = [
        for (var j = 0; j < n; j++)
          switch (d) {
            Dir.left => (i, j),
            Dir.right => (i, n - 1 - j),
            Dir.up => (j, i),
            Dir.down => (n - 1 - j, i),
          },
      ];
      final line = [for (final (r, c) in cells) grid[r][c]];
      final (slid, gained) = slideRow(line);
      score += gained;
      for (var j = 0; j < n; j++) {
        final (r, c) = cells[j];
        if (grid[r][c] != slid[j]) moved = true;
        grid[r][c] = slid[j];
        if (slid[j] == 2048) won = true;
      }
    }
    if (moved) _spawn();
    return moved;
  }

  bool get isOver {
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final v = grid[r][c];
        if (v == 0) return false;
        if (c + 1 < n && grid[r][c + 1] == v) return false;
        if (r + 1 < n && grid[r + 1][c] == v) return false;
      }
    }
    return true;
  }
}

// ─── Змейка ──────────────────────────────────────────────────────────────

class Snake {
  final int width;
  final int height;
  final math.Random _rng;

  /// Голова — первый элемент.
  late List<(int, int)> body;
  Dir dir = Dir.right;
  Dir? _queued;
  late (int, int) food;
  bool dead = false;
  int eaten = 0;

  Snake({this.width = 16, this.height = 22, math.Random? rng}) : _rng = rng ?? math.Random() {
    final y = height ~/ 2;
    body = [(4, y), (3, y), (2, y)];
    _placeFood();
  }

  int get score => eaten * 10;

  /// Скорость растёт с каждым яблоком, но не бесконечно.
  Duration get tick => Duration(milliseconds: math.max(70, 170 - eaten * 4));

  static bool _opposite(Dir a, Dir b) =>
      (a == Dir.up && b == Dir.down) ||
      (a == Dir.down && b == Dir.up) ||
      (a == Dir.left && b == Dir.right) ||
      (a == Dir.right && b == Dir.left);

  /// Поворот применяется на следующем шаге; развернуться в себя нельзя.
  void steer(Dir d) {
    if (_opposite(d, dir)) return;
    _queued = d;
  }

  void _placeFood() {
    final free = [
      for (var y = 0; y < height; y++)
        for (var x = 0; x < width; x++)
          if (!body.contains((x, y))) (x, y),
    ];
    food = free[_rng.nextInt(free.length)];
  }

  /// Шаг. Возвращает true, если съели яблоко.
  bool step() {
    if (dead) return false;
    if (_queued != null) {
      dir = _queued!;
      _queued = null;
    }
    final (hx, hy) = body.first;
    final next = switch (dir) {
      Dir.up => (hx, hy - 1),
      Dir.down => (hx, hy + 1),
      Dir.left => (hx - 1, hy),
      Dir.right => (hx + 1, hy),
    };
    final ate = next == food;
    // Хвост уходит в этот же шаг, поэтому в его клетку въехать можно.
    final blocking = ate ? body : body.sublist(0, body.length - 1);
    if (next.$1 < 0 || next.$2 < 0 || next.$1 >= width || next.$2 >= height || blocking.contains(next)) {
      dead = true;
      return false;
    }
    body = [next, ...blocking];
    if (ate) {
      eaten++;
      if (body.length < width * height) _placeFood();
    }
    return ate;
  }
}

// ─── Сапёр ───────────────────────────────────────────────────────────────

class Minesweeper {
  final int width;
  final int height;
  final int mines;
  final math.Random _rng;

  late List<List<bool>> mine;
  late List<List<int>> around;
  late List<List<bool>> open;
  late List<List<bool>> flag;
  bool _planted = false;
  bool lost = false;
  (int, int)? boom;

  Minesweeper({this.width = 9, this.height = 9, this.mines = 10, math.Random? rng})
      : _rng = rng ?? math.Random() {
    mine = List.generate(height, (_) => List.filled(width, false));
    around = List.generate(height, (_) => List.filled(width, 0));
    open = List.generate(height, (_) => List.filled(width, false));
    flag = List.generate(height, (_) => List.filled(width, false));
  }

  bool get won {
    if (lost) return false;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (!mine[y][x] && !open[y][x]) return false;
      }
    }
    return true;
  }

  bool get isOver => lost || won;

  int get flagsLeft => mines - flag.fold(0, (s, row) => s + row.where((f) => f).length);

  Iterable<(int, int)> _neighbours(int x, int y) sync* {
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx, ny = y + dy;
        if (nx >= 0 && ny >= 0 && nx < width && ny < height) yield (nx, ny);
      }
    }
  }

  /// Мины ставятся после первого нажатия — и не рядом с ним: первый ход
  /// всегда открывает кусок поля, а не взрывается.
  void _plant(int sx, int sy) {
    final safe = {(sx, sy), ..._neighbours(sx, sy)};
    final cells = [
      for (var y = 0; y < height; y++)
        for (var x = 0; x < width; x++)
          if (!safe.contains((x, y))) (x, y),
    ]..shuffle(_rng);
    for (final (x, y) in cells.take(mines)) {
      mine[y][x] = true;
    }
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        around[y][x] = _neighbours(x, y).where((p) => mine[p.$2][p.$1]).length;
      }
    }
    _planted = true;
  }

  void reveal(int x, int y) {
    if (isOver || flag[y][x] || open[y][x]) return;
    if (!_planted) _plant(x, y);
    if (mine[y][x]) {
      lost = true;
      boom = (x, y);
      return;
    }
    // Пустые клетки раскрываются волной.
    final queue = [(x, y)];
    while (queue.isNotEmpty) {
      final (cx, cy) = queue.removeLast();
      if (open[cy][cx] || flag[cy][cx]) continue;
      open[cy][cx] = true;
      if (around[cy][cx] == 0) queue.addAll(_neighbours(cx, cy));
    }
  }

  void toggleFlag(int x, int y) {
    if (isOver || open[y][x]) return;
    flag[y][x] = !flag[y][x];
  }

  /// Нажатие на открытую цифру, вокруг которой стоит столько же флажков, —
  /// открыть остальных соседей разом (как в классическом сапёре).
  void chord(int x, int y) {
    if (!open[y][x] || around[y][x] == 0) return;
    final ns = _neighbours(x, y).toList();
    if (ns.where((p) => flag[p.$2][p.$1]).length != around[y][x]) return;
    for (final (nx, ny) in ns) {
      reveal(nx, ny);
    }
  }
}

// ─── Судоку ──────────────────────────────────────────────────────────────

class Sudoku {
  /// Решение и стартовая расстановка: 0 — пустая клетка.
  final List<int> solution;
  final List<int> puzzle;

  Sudoku._(this.solution, this.puzzle);

  /// Сколько подсказок оставить на каждом уровне.
  static const clues = {0: 40, 1: 32, 2: 26};

  factory Sudoku.generate({int level = 0, math.Random? rng}) {
    final r = rng ?? math.Random();
    final solution = List.filled(81, 0);
    _fill(solution, r);
    final puzzle = [...solution];
    final target = clues[level] ?? 32;
    final order = List.generate(81, (i) => i)..shuffle(r);
    var filled = 81;
    for (final i in order) {
      if (filled <= target) break;
      final keep = puzzle[i];
      puzzle[i] = 0;
      // Убираем цифру, только если решение остаётся единственным.
      if (countSolutions([...puzzle], limit: 2) != 1) {
        puzzle[i] = keep;
      } else {
        filled--;
      }
    }
    return Sudoku._(solution, puzzle);
  }

  static bool canPlace(List<int> g, int i, int v) {
    final row = i ~/ 9, col = i % 9;
    for (var k = 0; k < 9; k++) {
      if (g[row * 9 + k] == v || g[k * 9 + col] == v) return false;
    }
    final br = row - row % 3, bc = col - col % 3;
    for (var r = br; r < br + 3; r++) {
      for (var c = bc; c < bc + 3; c++) {
        if (g[r * 9 + c] == v) return false;
      }
    }
    return true;
  }

  static bool _fill(List<int> g, math.Random rng) {
    final i = g.indexOf(0);
    if (i < 0) return true;
    final digits = List.generate(9, (k) => k + 1)..shuffle(rng);
    for (final v in digits) {
      if (canPlace(g, i, v)) {
        g[i] = v;
        if (_fill(g, rng)) return true;
        g[i] = 0;
      }
    }
    return false;
  }

  /// Сколько решений (до [limit]) — проверка единственности.
  static int countSolutions(List<int> g, {int limit = 2}) {
    // Клетка с наименьшим числом вариантов — перебор сильно короче.
    var best = -1;
    var bestOptions = <int>[];
    for (var i = 0; i < 81; i++) {
      if (g[i] != 0) continue;
      final options = [for (var v = 1; v <= 9; v++) if (canPlace(g, i, v)) v];
      if (options.isEmpty) return 0;
      if (best < 0 || options.length < bestOptions.length) {
        best = i;
        bestOptions = options;
        if (options.length == 1) break;
      }
    }
    if (best < 0) return 1;
    var count = 0;
    for (final v in bestOptions) {
      g[best] = v;
      count += countSolutions(g, limit: limit - count);
      g[best] = 0;
      if (count >= limit) break;
    }
    return count;
  }

  /// Конфликт с другой цифрой в строке, столбце или квадрате.
  static bool conflicts(List<int> g, int i) {
    final v = g[i];
    if (v == 0) return false;
    g[i] = 0;
    final ok = canPlace(g, i, v);
    g[i] = v;
    return !ok;
  }
}
