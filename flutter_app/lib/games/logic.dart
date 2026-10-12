import 'dart:math' as math;

/// Логика игр — без виджетов, чтобы её можно было проверить тестами.
///
/// Все игры локальные: на одном экране, без сети. Игроки нумеруются с нуля.

// ─── Крестики-нолики ─────────────────────────────────────────────────────

class TicTacToe {
  /// -1 — пусто, 0 — крестик, 1 — нолик.
  final List<int> cells = List.filled(9, -1);
  int turn = 0;

  /// Победитель: 0/1, -1 — пока нет.
  int winner = -1;
  List<int> winLine = const [];

  bool get isDraw => winner == -1 && !cells.contains(-1);
  bool get isOver => winner != -1 || isDraw;

  static const _lines = [
    [0, 1, 2], [3, 4, 5], [6, 7, 8],
    [0, 3, 6], [1, 4, 7], [2, 5, 8],
    [0, 4, 8], [2, 4, 6],
  ];

  bool play(int index) {
    if (isOver || cells[index] != -1) return false;
    cells[index] = turn;
    for (final line in _lines) {
      if (line.every((i) => cells[i] == turn)) {
        winner = turn;
        winLine = line;
        return true;
      }
    }
    turn = 1 - turn;
    return true;
  }
}

// ─── Четыре в ряд ────────────────────────────────────────────────────────

class ConnectFour {
  static const cols = 7;
  static const rows = 6;

  /// [row][col], строка 0 — верхняя. -1 — пусто.
  final List<List<int>> grid = List.generate(rows, (_) => List.filled(cols, -1));
  int turn = 0;
  int winner = -1;
  List<(int, int)> winCells = const [];
  int moves = 0;

  bool get isDraw => winner == -1 && moves == rows * cols;
  bool get isOver => winner != -1 || isDraw;

  bool canDrop(int col) => !isOver && grid[0][col] == -1;

  /// Бросить фишку в столбец. Возвращает строку, куда она упала, или null.
  int? drop(int col) {
    if (!canDrop(col)) return null;
    var row = rows - 1;
    while (grid[row][col] != -1) {
      row--;
    }
    grid[row][col] = turn;
    moves++;
    final line = _lineThrough(row, col);
    if (line != null) {
      winner = turn;
      winCells = line;
    } else {
      turn = 1 - turn;
    }
    return row;
  }

  List<(int, int)>? _lineThrough(int row, int col) {
    final who = grid[row][col];
    for (final (dr, dc) in const [(0, 1), (1, 0), (1, 1), (1, -1)]) {
      final cells = <(int, int)>[(row, col)];
      for (final sign in const [1, -1]) {
        var r = row + dr * sign, c = col + dc * sign;
        while (r >= 0 && r < rows && c >= 0 && c < cols && grid[r][c] == who) {
          cells.add((r, c));
          r += dr * sign;
          c += dc * sign;
        }
      }
      if (cells.length >= 4) return cells;
    }
    return null;
  }
}

// ─── Точки и квадраты ────────────────────────────────────────────────────

/// Поле из [size]×[size] квадратов. Ход — провести одну линию; кто замкнул
/// квадрат, забирает его и ходит ещё раз.
class DotsAndBoxes {
  final int size;
  final int players;

  /// Горизонтальные линии: (size+1) рядов по size отрезков.
  late final List<List<int>> horizontal =
      List.generate(size + 1, (_) => List.filled(size, -1));

  /// Вертикальные линии: size рядов по (size+1) отрезков.
  late final List<List<int>> vertical =
      List.generate(size, (_) => List.filled(size + 1, -1));

  /// Владелец квадрата или -1.
  late final List<List<int>> boxes = List.generate(size, (_) => List.filled(size, -1));

  late final List<int> scores = List.filled(players, 0);
  int turn = 0;

  DotsAndBoxes({this.size = 4, this.players = 2});

  int get totalBoxes => size * size;
  int get claimed => scores.fold(0, (a, b) => a + b);
  bool get isOver => claimed == totalBoxes;

  /// Лидеры (может быть ничья между несколькими).
  List<int> get leaders {
    final best = scores.reduce(math.max);
    return [for (var i = 0; i < players; i++) if (scores[i] == best) i];
  }

  bool _complete(int r, int c) =>
      horizontal[r][c] != -1 &&
      horizontal[r + 1][c] != -1 &&
      vertical[r][c] != -1 &&
      vertical[r][c + 1] != -1;

  /// Провести линию. [isHorizontal] — какая; r, c — её место.
  /// Возвращает, сколько квадратов замкнулось (-1 — ход невозможен).
  int draw({required bool isHorizontal, required int r, required int c}) {
    final lines = isHorizontal ? horizontal : vertical;
    if (isOver || lines[r][c] != -1) return -1;
    lines[r][c] = turn;

    // Линия может замкнуть один или два соседних квадрата.
    final touched = isHorizontal
        ? [(r - 1, c), (r, c)]
        : [(r, c - 1), (r, c)];
    var closed = 0;
    for (final (br, bc) in touched) {
      if (br < 0 || bc < 0 || br >= size || bc >= size) continue;
      if (boxes[br][bc] == -1 && _complete(br, bc)) {
        boxes[br][bc] = turn;
        scores[turn]++;
        closed++;
      }
    }
    if (closed == 0) turn = (turn + 1) % players;
    return closed;
  }
}

// ─── Реакция ─────────────────────────────────────────────────────────────

enum ReactionPhase { waiting, ready, go, roundOver, matchOver }

/// Все держат палец у своей кнопки. Экран загорается через случайное
/// время — кто первым нажал, тот берёт очко. Нажал раньше — очко теряешь.
class ReactionMatch {
  final int players;
  final int target;
  late final List<int> scores = List.filled(players, 0);
  ReactionPhase phase = ReactionPhase.waiting;

  /// Кто взял раунд (или -1), кто сфальшивил (или -1).
  int roundWinner = -1;
  int falseStart = -1;

  ReactionMatch({this.players = 2, this.target = 5});

  /// Сколько ждать сигнала: от 1,5 до 5 секунд.
  static Duration randomDelay(math.Random rng) =>
      Duration(milliseconds: 1500 + rng.nextInt(3500));

  void startRound() {
    roundWinner = -1;
    falseStart = -1;
    phase = ReactionPhase.ready;
  }

  void signal() {
    if (phase == ReactionPhase.ready) phase = ReactionPhase.go;
  }

  /// Нажатие игрока. Возвращает true, если раунд закончился.
  bool tap(int player) {
    switch (phase) {
      case ReactionPhase.ready:
        // Фальстарт: минус очко (не ниже нуля), раунд переигрывается.
        falseStart = player;
        scores[player] = math.max(0, scores[player] - 1);
        phase = ReactionPhase.roundOver;
        return true;
      case ReactionPhase.go:
        roundWinner = player;
        scores[player]++;
        phase = scores[player] >= target ? ReactionPhase.matchOver : ReactionPhase.roundOver;
        return true;
      default:
        return false;
    }
  }

  int get champion => phase == ReactionPhase.matchOver ? roundWinner : -1;
}

// ─── Объясни слово ───────────────────────────────────────────────────────

/// Команды по очереди объясняют слова за ограниченное время.
/// Угадали — плюс очко, пропустили — минус (если включён штраф).
class WordsMatch {
  final int teams;
  final int target;
  final bool skipPenalty;
  final List<String> _deck;
  late final List<int> scores = List.filled(teams, 0);
  int team = 0;
  int _next = 0;

  /// Слова текущего раунда: слово → угадано ли.
  final List<(String, bool)> roundLog = [];

  WordsMatch({
    required List<String> words,
    this.teams = 2,
    this.target = 30,
    this.skipPenalty = true,
    math.Random? rng,
  }) : _deck = {...words}.toList()..shuffle(rng ?? math.Random()); // без повторов

  String get current => _deck[_next % _deck.length];

  int get roundScore =>
      roundLog.fold(0, (sum, e) => sum + (e.$2 ? 1 : (skipPenalty ? -1 : 0)));

  void guessed() {
    roundLog.add((current, true));
    _next++;
  }

  void skipped() {
    roundLog.add((current, false));
    _next++;
  }

  /// Конец раунда: очки команде (с поправками, если ведущий их сделал),
  /// ход следующей команде.
  void finishRound() {
    scores[team] += roundScore;
    roundLog.clear();
    team = (team + 1) % teams;
  }

  /// Исправить отметку слова после раунда (ошиблись кнопкой).
  void toggle(int index) {
    final (word, ok) = roundLog[index];
    roundLog[index] = (word, !ok);
  }

  /// Победитель — когда все команды сыграли поровну раундов и кто-то
  /// дошёл до цели. Так у последней команды есть шанс догнать.
  int get winner {
    if (team != 0) return -1;
    final best = scores.reduce(math.max);
    if (best < target) return -1;
    final leaders = [for (var i = 0; i < teams; i++) if (scores[i] == best) i];
    return leaders.length == 1 ? leaders.first : -1;
  }
}
