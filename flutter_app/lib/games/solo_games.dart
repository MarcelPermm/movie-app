import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'games_common.dart';
import 'logic_solo.dart';

Dir _dirOf(AxisDirection a) => switch (a) {
      AxisDirection.up => Dir.up,
      AxisDirection.down => Dir.down,
      AxisDirection.left => Dir.left,
      AxisDirection.right => Dir.right,
    };

/// Плашка «Счёт / Рекорд» над полем.
class _Scores extends StatelessWidget {
  final List<(String, String)> items;

  const _Scores(this.items);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          for (final (label, value) in items)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Text(label.toUpperCase(), style: TextStyle(color: AppColors.textDim, fontSize: 10.5)),
                    Text(value, style: TextStyle(color: AppColors.text, fontSize: 19, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── 2048 ────────────────────────────────────────────────────────────────

class Game2048Screen extends StatefulWidget {
  const Game2048Screen({super.key});

  @override
  State<Game2048Screen> createState() => _Game2048ScreenState();
}

class _Game2048ScreenState extends State<Game2048Screen> {
  var _game = Game2048();
  int _best = BestScore.get('2048');
  bool _wonShown = false;

  void _restart() => setState(() {
        _game = Game2048();
        _wonShown = false;
      });

  void _swipe(AxisDirection a) {
    if (_game.isOver || !_game.move(_dirOf(a))) return;
    HapticFeedback.selectionClick();
    if (BestScore.submit('2048', _game.score)) _best = _game.score;
    setState(() {});
    if (_game.won && !_wonShown) {
      _wonShown = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('2048! Можно играть дальше — до 4096')),
      );
    }
    if (_game.isOver) {
      showResult(context, title: 'Ходов больше нет', subtitle: 'Счёт: ${_game.score}', onAgain: _restart);
    }
  }

  static Color _tileColor(int v) => switch (v) {
        0 => const Color(0x22FFFFFF),
        2 => const Color(0xFFEEE4DA),
        4 => const Color(0xFFEDE0C8),
        8 => const Color(0xFFF2B179),
        16 => const Color(0xFFF59563),
        32 => const Color(0xFFF67C5F),
        64 => const Color(0xFFF65E3B),
        128 => const Color(0xFFEDCF72),
        256 => const Color(0xFFEDCC61),
        512 => const Color(0xFFEDC850),
        1024 => const Color(0xFFEDC53F),
        2048 => const Color(0xFFEDC22E),
        _ => const Color(0xFF3C3A32),
      };

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: '2048',
      onRestart: _restart,
      body: SwipeArea(
        onSwipe: _swipe,
        child: Column(
          children: [
            _Scores([('Счёт', '${_game.score}'), ('Рекорд', '${math.max(_best, _game.score)}')]),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Свайпай в любую сторону — одинаковые плитки сливаются',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
            ),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFF3B3530), borderRadius: BorderRadius.circular(12)),
                    child: GridView.count(
                      crossAxisCount: Game2048.n,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      children: [
                        for (var r = 0; r < Game2048.n; r++)
                          for (var c = 0; c < Game2048.n; c++) _tile(_game.grid[r][c], _game.spawned == (r, c)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(int v, bool fresh) {
    final dark = v <= 4;
    return TweenAnimationBuilder<double>(
      key: ValueKey('$v-$fresh-${_game.score}'),
      tween: Tween(begin: fresh ? 0.4 : 1, end: 1),
      duration: const Duration(milliseconds: 140),
      builder: (context, s, child) => Transform.scale(scale: s, child: child),
      child: Container(
        decoration: BoxDecoration(color: _tileColor(v), borderRadius: BorderRadius.circular(8)),
        alignment: Alignment.center,
        child: v == 0
            ? null
            : FittedBox(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text('$v',
                      style: TextStyle(
                        color: dark ? const Color(0xFF776E65) : Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                      )),
                ),
              ),
      ),
    );
  }
}

// ─── Змейка ──────────────────────────────────────────────────────────────

class SnakeScreen extends StatefulWidget {
  const SnakeScreen({super.key});

  @override
  State<SnakeScreen> createState() => _SnakeScreenState();
}

class _SnakeScreenState extends State<SnakeScreen> {
  var _snake = Snake();
  Timer? _timer;
  bool _started = false;
  int _best = BestScore.get('snake');

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    setState(() {
      _snake = Snake();
      _started = true;
    });
    _schedule();
  }

  /// Таймер перезаводится после каждого яблока: змейка ускоряется.
  void _schedule() {
    _timer = Timer(_snake.tick, () {
      if (!mounted) return;
      final ate = _snake.step();
      if (ate) HapticFeedback.lightImpact();
      setState(() {});
      if (_snake.dead) {
        HapticFeedback.heavyImpact();
        if (BestScore.submit('snake', _snake.score)) _best = _snake.score;
        showResult(context, title: 'Врезалась!', subtitle: 'Счёт: ${_snake.score}', onAgain: _start);
        return;
      }
      _schedule();
    });
  }

  void _steer(Dir d) {
    if (!_started) return;
    _snake.steer(d);
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'Змейка',
      onRestart: _start,
      body: SwipeArea(
        onSwipe: (a) => _steer(_dirOf(a)),
        child: Column(
          children: [
            _Scores([('Счёт', '${_snake.score}'), ('Рекорд', '${math.max(_best, _snake.score)}')]),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: AspectRatio(
                    aspectRatio: _snake.width / _snake.height,
                    child: Stack(
                      children: [
                        Positioned.fill(child: CustomPaint(painter: _SnakePainter(_snake))),
                        if (!_started)
                          Center(
                            child: FilledButton(
                              onPressed: _start,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.gold,
                                foregroundColor: AppColors.bg,
                                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                              ),
                              child: const Text('Старт · свайпай, чтобы рулить'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _Arrows(onTap: _steer),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

/// Стрелки под полем — для тех, кому удобнее кнопками.
class _Arrows extends StatelessWidget {
  final ValueChanged<Dir> onTap;

  const _Arrows({required this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget b(Dir d, IconData icon) => Listener(
          onPointerDown: (_) => onTap(d),
          child: Container(
            width: 64,
            height: 48,
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(icon, color: AppColors.text),
          ),
        );
    return Column(
      children: [
        b(Dir.up, Icons.keyboard_arrow_up),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            b(Dir.left, Icons.keyboard_arrow_left),
            b(Dir.down, Icons.keyboard_arrow_down),
            b(Dir.right, Icons.keyboard_arrow_right),
          ],
        ),
      ],
    );
  }
}

class _SnakePainter extends CustomPainter {
  final Snake s;

  _SnakePainter(this.s);

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / s.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)),
      Paint()..color = const Color(0xFF14261A),
    );
    final (fx, fy) = s.food;
    canvas.drawCircle(Offset((fx + 0.5) * cw, (fy + 0.5) * cw), cw * 0.38, Paint()..color = const Color(0xFFE5484D));
    for (var i = 0; i < s.body.length; i++) {
      final (x, y) = s.body[i];
      final t = i / math.max(1, s.body.length - 1);
      final color = Color.lerp(const Color(0xFF7CE38B), const Color(0xFF2E8B57), t)!;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x * cw + 1, y * cw + 1, cw - 2, cw - 2), Radius.circular(cw * 0.3)),
        Paint()..color = s.dead && i == 0 ? const Color(0xFFE5484D) : color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ─── Сапёр ───────────────────────────────────────────────────────────────

class MinesweeperScreen extends StatefulWidget {
  const MinesweeperScreen({super.key});

  @override
  State<MinesweeperScreen> createState() => _MinesweeperScreenState();
}

class _MinesweeperScreenState extends State<MinesweeperScreen> {
  static const _levels = [
    ('Новичок', 9, 9, 10),
    ('Любитель', 10, 14, 24),
    ('Профи', 12, 18, 40),
  ];
  int _level = 0;
  late var _game = _make();
  bool _flagMode = false;
  int _seconds = 0;
  Timer? _clock;

  Minesweeper _make() {
    final (_, w, h, m) = _levels[_level];
    return Minesweeper(width: w, height: h, mines: m);
  }

  String get _bestKey => 'mines$_level';

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  void _restart() {
    _clock?.cancel();
    setState(() {
      _game = _make();
      _seconds = 0;
    });
  }

  void _tap(int x, int y, {bool long = false}) {
    if (_game.isOver) return;
    _clock ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_game.isOver) setState(() => _seconds++);
    });
    setState(() {
      if (_game.open[y][x]) {
        _game.chord(x, y);
      } else if (long || _flagMode) {
        _game.toggleFlag(x, y);
        HapticFeedback.selectionClick();
      } else {
        _game.reveal(x, y);
      }
    });
    if (_game.isOver) {
      _clock?.cancel();
      _clock = null;
      HapticFeedback.heavyImpact();
      final record = _game.won && BestScore.submit(_bestKey, _seconds, lowerIsBetter: true);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        showResult(
          context,
          title: _game.won ? 'Поле разминировано!' : 'Бабах 💥',
          subtitle: _game.won ? 'Время ${formatSeconds(_seconds)}${record ? ' — новый рекорд!' : ''}' : null,
          onAgain: _restart,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final best = BestScore.get(_bestKey);
    return GameScaffold(
      title: 'Сапёр',
      onRestart: _restart,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SegmentedButton<int>(
              segments: [
                for (var i = 0; i < _levels.length; i++) ButtonSegment(value: i, label: Text(_levels[i].$1)),
              ],
              selected: {_level},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                _level = s.first;
                _restart();
              },
            ),
          ),
          _Scores([
            ('Мины', '${_game.flagsLeft}'),
            ('Время', formatSeconds(_seconds)),
            ('Рекорд', best == 0 ? '—' : formatSeconds(best)),
          ]),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: AspectRatio(
                  aspectRatio: _game.width / _game.height,
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: _game.width),
                    itemCount: _game.width * _game.height,
                    itemBuilder: (context, i) => _cell(i % _game.width, i ~/ _game.width),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text('Долгое нажатие — флажок',
                      style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                ),
                FilterChip(
                  label: const Text('🚩 Режим флажков'),
                  selected: _flagMode,
                  onSelected: (v) => setState(() => _flagMode = v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _numberColors = [
    Colors.transparent,
    Color(0xFF3E8BFF),
    Color(0xFF30A46C),
    Color(0xFFE5484D),
    Color(0xFF8E7CFF),
    Color(0xFFB45309),
    Color(0xFF0891B2),
    Color(0xFFDDDDDD),
    Color(0xFF999999),
  ];

  Widget _cell(int x, int y) {
    final open = _game.open[y][x];
    final mine = _game.mine[y][x];
    final showMine = _game.lost && mine;
    final n = _game.around[y][x];
    Widget? content;
    if (showMine) {
      content = Text(_game.boom == (x, y) ? '💥' : '💣');
    } else if (_game.flag[y][x]) {
      content = const Text('🚩');
    } else if (open && n > 0) {
      content = Text('$n', style: TextStyle(color: _numberColors[n], fontWeight: FontWeight.w900, fontSize: 18));
    }
    return GestureDetector(
      onTap: () => _tap(x, y),
      onLongPress: () => _tap(x, y, long: true),
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: open ? AppColors.bg : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.border.withValues(alpha: open ? 0.4 : 1)),
        ),
        alignment: Alignment.center,
        child: content == null ? null : FittedBox(child: Padding(padding: const EdgeInsets.all(2), child: content)),
      ),
    );
  }
}

// ─── Судоку ──────────────────────────────────────────────────────────────

class SudokuScreen extends StatefulWidget {
  const SudokuScreen({super.key});

  @override
  State<SudokuScreen> createState() => _SudokuScreenState();
}

class _SudokuScreenState extends State<SudokuScreen> {
  static const _levelNames = ['Лёгкий', 'Средний', 'Сложный'];
  int _level = 0;
  Sudoku? _puzzle;
  List<int> _grid = List.filled(81, 0);
  final List<Set<int>> _notes = List.generate(81, (_) => <int>{});
  int? _selected;
  bool _notesMode = false;
  int _seconds = 0;
  Timer? _clock;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _newGame();
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _newGame() async {
    _clock?.cancel();
    setState(() => _puzzle = null);
    // Генерация занимает доли секунды — даём кадру отрисовать «Готовлю…».
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final p = Sudoku.generate(level: _level);
    if (!mounted) return;
    setState(() {
      _puzzle = p;
      _grid = [...p.puzzle];
      for (final n in _notes) {
        n.clear();
      }
      _selected = null;
      _seconds = 0;
      _done = false;
    });
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_done) setState(() => _seconds++);
    });
  }

  bool _given(int i) => _puzzle!.puzzle[i] != 0;

  void _input(int v) {
    final i = _selected;
    if (i == null || _given(i) || _done) return;
    setState(() {
      if (_notesMode && v != 0) {
        _notes[i].contains(v) ? _notes[i].remove(v) : _notes[i].add(v);
        _grid[i] = 0;
      } else {
        _grid[i] = _grid[i] == v ? 0 : v;
        _notes[i].clear();
      }
    });
    if (!_grid.contains(0) && _grid.indexed.every((e) => !Sudoku.conflicts(_grid, e.$1))) {
      _done = true;
      _clock?.cancel();
      HapticFeedback.heavyImpact();
      final record = BestScore.submit('sudoku$_level', _seconds, lowerIsBetter: true);
      showResult(
        context,
        title: 'Решено!',
        subtitle: 'Время ${formatSeconds(_seconds)}${record ? ' — новый рекорд!' : ''}',
        onAgain: _newGame,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final best = BestScore.get('sudoku$_level');
    return GameScaffold(
      title: 'Судоку',
      onRestart: _newGame,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SegmentedButton<int>(
              segments: [for (var i = 0; i < 3; i++) ButtonSegment(value: i, label: Text(_levelNames[i]))],
              selected: {_level},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                _level = s.first;
                _newGame();
              },
            ),
          ),
          _Scores([('Время', formatSeconds(_seconds)), ('Рекорд', best == 0 ? '—' : formatSeconds(best))]),
          Expanded(
            child: Center(
              child: _puzzle == null
                  ? Text('Готовлю поле…', style: TextStyle(color: AppColors.textDim))
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: AspectRatio(aspectRatio: 1, child: _board()),
                    ),
            ),
          ),
          _pad(),
        ],
      ),
    );
  }

  Widget _board() {
    final sel = _selected;
    final selValue = sel == null ? 0 : _grid[sel];
    return Container(
      decoration: BoxDecoration(border: Border.all(color: AppColors.text, width: 2)),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 9),
        itemCount: 81,
        itemBuilder: (context, i) {
          final r = i ~/ 9, c = i % 9;
          final v = _grid[i];
          final related = sel != null && (sel ~/ 9 == r || sel % 9 == c || (sel ~/ 27 == i ~/ 27 && (sel % 9) ~/ 3 == c ~/ 3));
          final same = v != 0 && v == selValue;
          final bad = v != 0 && Sudoku.conflicts(_grid, i);
          final thick = BorderSide(color: AppColors.text, width: 1.6);
          final thin = BorderSide(color: AppColors.border, width: 0.5);
          return GestureDetector(
            onTap: () => setState(() => _selected = i),
            child: Container(
              decoration: BoxDecoration(
                color: i == sel
                    ? AppColors.gold.withValues(alpha: 0.35)
                    : same
                        ? AppColors.gold.withValues(alpha: 0.18)
                        : related
                            ? AppColors.surfaceHigh
                            : AppColors.surface,
                border: Border(
                  right: c % 3 == 2 && c < 8 ? thick : thin,
                  bottom: r % 3 == 2 && r < 8 ? thick : thin,
                ),
              ),
              alignment: Alignment.center,
              child: v != 0
                  ? FittedBox(
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Text(
                          '$v',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: _given(i) ? FontWeight.w900 : FontWeight.w500,
                            color: bad ? AppColors.red : (_given(i) ? AppColors.text : AppColors.blue),
                          ),
                        ),
                      ),
                    )
                  : _notes[i].isEmpty
                      ? null
                      : FittedBox(
                          child: Padding(
                            padding: const EdgeInsets.all(1),
                            child: Text(
                              [for (var k = 1; k <= 9; k++) _notes[i].contains(k) ? '$k' : ' '].join(),
                              style: TextStyle(color: AppColors.textDim, fontSize: 8),
                            ),
                          ),
                        ),
            ),
          );
        },
      ),
    );
  }

  Widget _pad() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 14),
      child: Column(
        children: [
          Row(
            children: [
              for (var v = 1; v <= 9; v++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Material(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _input(v),
                        child: SizedBox(
                          height: 48,
                          child: Center(
                            child: Text('$v',
                                style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: FilterChip(
                  label: const Text('✏️ Заметки'),
                  selected: _notesMode,
                  onSelected: (v) => setState(() => _notesMode = v),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => _input(0),
                icon: const Icon(Icons.backspace_outlined, size: 18),
                label: const Text('Стереть'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
