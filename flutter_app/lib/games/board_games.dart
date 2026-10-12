import 'package:flutter/material.dart';

import '../theme.dart';
import 'games_common.dart';
import 'logic.dart';

// ─── Крестики-нолики ─────────────────────────────────────────────────────

class TicTacToeScreen extends StatefulWidget {
  const TicTacToeScreen({super.key});

  @override
  State<TicTacToeScreen> createState() => _TicTacToeScreenState();
}

class _TicTacToeScreenState extends State<TicTacToeScreen> {
  var _game = TicTacToe();

  /// Счёт серии: кто сколько партий выиграл. Первым ходит проигравший.
  final _wins = [0, 0];
  int _starter = 0;

  void _restart() => setState(() {
        _game = TicTacToe()..turn = _starter;
      });

  void _play(int i) {
    if (!_game.play(i)) return;
    setState(() {});
    if (!_game.isOver) return;
    if (_game.winner >= 0) {
      _wins[_game.winner]++;
      _starter = 1 - _game.winner;
    } else {
      _starter = 1 - _starter;
    }
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      showResult(
        context,
        title: _game.winner >= 0 ? 'Победили ${_mark(_game.winner)}!' : 'Ничья',
        color: _game.winner >= 0 ? playerColors[_game.winner] : null,
        subtitle: 'Счёт серии: ${_wins[0]} : ${_wins[1]}',
        onAgain: _restart,
      );
    });
  }

  static String _mark(int p) => p == 0 ? 'крестики' : 'нолики';

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'Крестики-нолики',
      onRestart: _restart,
      body: Column(
        children: [
          ScoreRow(scores: _wins, active: _game.isOver ? -1 : _game.turn, names: const ['✕', '◯']),
          TurnBanner(
            player: _game.isOver ? -1 : _game.turn,
            text: _game.isOver ? 'Партия окончена' : 'Ходят ${_mark(_game.turn)}',
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: GridView.count(
                    crossAxisCount: 3,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    children: [
                      for (var i = 0; i < 9; i++)
                        Material(
                          color: _game.winLine.contains(i)
                              ? playerColors[_game.winner].withValues(alpha: 0.25)
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.medium),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(AppRadius.medium),
                            onTap: () => _play(i),
                            child: Center(
                              child: AnimatedScale(
                                scale: _game.cells[i] == -1 ? 0 : 1,
                                duration: const Duration(milliseconds: 180),
                                child: Text(
                                  _game.cells[i] == 1 ? '◯' : '✕',
                                  style: TextStyle(
                                    fontSize: 64,
                                    fontWeight: FontWeight.w300,
                                    color: playerColors[_game.cells[i] == 1 ? 1 : 0],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Четыре в ряд ────────────────────────────────────────────────────────

class ConnectFourScreen extends StatefulWidget {
  const ConnectFourScreen({super.key});

  @override
  State<ConnectFourScreen> createState() => _ConnectFourScreenState();
}

class _ConnectFourScreenState extends State<ConnectFourScreen> {
  var _game = ConnectFour();
  final _wins = [0, 0];
  int _starter = 0;

  void _restart() => setState(() => _game = ConnectFour()..turn = _starter);

  void _drop(int col) {
    if (_game.drop(col) == null) return;
    setState(() {});
    if (!_game.isOver) return;
    if (_game.winner >= 0) {
      _wins[_game.winner]++;
      _starter = 1 - _game.winner;
    } else {
      _starter = 1 - _starter;
    }
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      showResult(
        context,
        title: _game.winner >= 0 ? 'Победил ${playerNames[_game.winner]}!' : 'Ничья — поле заполнено',
        color: _game.winner >= 0 ? playerColors[_game.winner] : null,
        subtitle: 'Счёт серии: ${_wins[0]} : ${_wins[1]}',
        onAgain: _restart,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'Четыре в ряд',
      onRestart: _restart,
      body: Column(
        children: [
          ScoreRow(scores: _wins, active: _game.isOver ? -1 : _game.turn),
          TurnBanner(
            player: _game.isOver ? -1 : _game.turn,
            text: _game.isOver ? 'Партия окончена' : 'Ходит ${playerNames[_game.turn]} — нажми на столбец',
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: ConnectFour.cols / ConnectFour.rows,
                child: Container(
                  margin: const EdgeInsets.all(14),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F3A8A),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      for (var c = 0; c < ConnectFour.cols; c++)
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _drop(c),
                            child: Column(
                              children: [
                                for (var r = 0; r < ConnectFour.rows; r++)
                                  Expanded(child: _Disc(owner: _game.grid[r][c], win: _game.winCells.contains((r, c)))),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Disc extends StatelessWidget {
  final int owner;
  final bool win;

  const _Disc({required this.owner, required this.win});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: AspectRatio(
        aspectRatio: 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: owner == -1 ? AppColors.bg : playerColors[owner],
            border: win ? Border.all(color: Colors.white, width: 3) : null,
          ),
        ),
      ),
    );
  }
}

// ─── Точки и квадраты ────────────────────────────────────────────────────

class DotsAndBoxesScreen extends StatefulWidget {
  final int players;

  const DotsAndBoxesScreen({super.key, required this.players});

  @override
  State<DotsAndBoxesScreen> createState() => _DotsAndBoxesScreenState();
}

class _DotsAndBoxesScreenState extends State<DotsAndBoxesScreen> {
  /// Поле побольше для компании: квадратов должно хватить на всех.
  int get _size => widget.players <= 2 ? 4 : 5;

  late var _game = DotsAndBoxes(size: _size, players: widget.players);

  void _restart() => setState(() => _game = DotsAndBoxes(size: _size, players: widget.players));

  void _draw({required bool isHorizontal, required int r, required int c}) {
    if (_game.draw(isHorizontal: isHorizontal, r: r, c: c) < 0) return;
    setState(() {});
    if (!_game.isOver) return;
    final leaders = _game.leaders;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      showResult(
        context,
        title: leaders.length == 1
            ? 'Победил ${playerNames[leaders.first]}!'
            : 'Ничья: ${leaders.map((p) => playerNames[p]).join(' и ')}',
        color: leaders.length == 1 ? playerColors[leaders.first] : null,
        subtitle: 'Квадратов: ${_game.scores.join(' : ')}',
        onAgain: _restart,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'Точки и квадраты',
      onRestart: _restart,
      body: Column(
        children: [
          ScoreRow(scores: _game.scores, active: _game.isOver ? -1 : _game.turn),
          TurnBanner(
            player: _game.isOver ? -1 : _game.turn,
            text: _game.isOver
                ? 'Все квадраты заняты'
                : 'Ходит ${playerNames[_game.turn]}. Замкнул квадрат — ходи ещё',
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: LayoutBuilder(
                    builder: (context, box) => _DotsBoard(
                      game: _game,
                      side: box.maxWidth,
                      onDraw: _draw,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DotsBoard extends StatelessWidget {
  final DotsAndBoxes game;
  final double side;
  final void Function({required bool isHorizontal, required int r, required int c}) onDraw;

  const _DotsBoard({required this.game, required this.side, required this.onDraw});

  @override
  Widget build(BuildContext context) {
    final n = game.size;
    final cell = side / n;
    // Зона нажатия у линии — с запасом, чтобы попадать пальцем.
    final hit = cell * 0.36;
    const dot = 12.0;

    final children = <Widget>[];

    // Захваченные квадраты.
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final owner = game.boxes[r][c];
        if (owner == -1) continue;
        children.add(Positioned(
          left: c * cell + 4,
          top: r * cell + 4,
          width: cell - 8,
          height: cell - 8,
          child: Container(
            decoration: BoxDecoration(
              color: playerColors[owner].withValues(alpha: 0.32),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ));
      }
    }

    Widget line({required bool isHorizontal, required int r, required int c}) {
      final owner = (isHorizontal ? game.horizontal : game.vertical)[r][c];
      final drawn = owner != -1;
      final barColor = drawn ? playerColors[owner] : AppColors.border.withValues(alpha: 0.5);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: drawn ? null : () => onDraw(isHorizontal: isHorizontal, r: r, c: c),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: isHorizontal ? cell - dot : (drawn ? 6 : 3),
            height: isHorizontal ? (drawn ? 6 : 3) : cell - dot,
            decoration: BoxDecoration(color: barColor, borderRadius: BorderRadius.circular(3)),
          ),
        ),
      );
    }

    for (var r = 0; r <= n; r++) {
      for (var c = 0; c < n; c++) {
        children.add(Positioned(
          left: c * cell + dot / 2,
          top: r * cell - hit / 2,
          width: cell - dot,
          height: hit,
          child: line(isHorizontal: true, r: r, c: c),
        ));
      }
    }
    for (var r = 0; r < n; r++) {
      for (var c = 0; c <= n; c++) {
        children.add(Positioned(
          left: c * cell - hit / 2,
          top: r * cell + dot / 2,
          width: hit,
          height: cell - dot,
          child: line(isHorizontal: false, r: r, c: c),
        ));
      }
    }

    for (var r = 0; r <= n; r++) {
      for (var c = 0; c <= n; c++) {
        children.add(Positioned(
          left: c * cell - dot / 2,
          top: r * cell - dot / 2,
          width: dot,
          height: dot,
          child: IgnorePointer(
            child: Container(decoration: BoxDecoration(color: AppColors.text, shape: BoxShape.circle)),
          ),
        ));
      }
    }

    return Stack(clipBehavior: Clip.none, children: children);
  }
}
