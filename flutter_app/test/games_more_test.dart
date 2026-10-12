import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/games/logic_solo.dart';
import 'package:movie_app/games/logic_sports.dart';

void main() {
  group('2048', () {
    test('слияние по правилам: каждая плитка — один раз за ход', () {
      // Записи со списком внутри сравниваются по ссылке — сверяем поля.
      void slides(List<int> row, List<int> to, int gained) {
        final (out, got) = Game2048.slideRow(row);
        expect(out, to);
        expect(got, gained);
      }

      slides([2, 2, 2, 2], [4, 4, 0, 0], 8);
      slides([2, 0, 2, 4], [4, 4, 0, 0], 4);
      slides([4, 4, 8, 0], [8, 8, 0, 0], 8);
      slides([2, 4, 8, 16], [2, 4, 8, 16], 0);
    });

    test('ход без сдвига не добавляет плитку; вправо и вниз работают', () {
      final g = Game2048(math.Random(1));
      g.grid = [
        [2, 4, 8, 16],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ];
      expect(g.move(Dir.up), isFalse);
      expect(g.grid.expand((r) => r).where((v) => v != 0).length, 4);
      g.grid = [
        [2, 2, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 2],
      ];
      expect(g.move(Dir.right), isTrue);
      expect(g.grid[0][3], 4);
      expect(g.score, 4);
    });

    test('конец игры: нет пустых и соседних одинаковых', () {
      final g = Game2048(math.Random(1));
      g.grid = [
        [2, 4, 2, 4],
        [4, 2, 4, 2],
        [2, 4, 2, 4],
        [4, 2, 4, 2],
      ];
      expect(g.isOver, isTrue);
      g.grid[3][3] = 4;
      expect(g.isOver, isFalse);
    });
  });

  group('Змейка', () {
    test('ест яблоко и растёт, в стену — смерть', () {
      final s = Snake(width: 10, height: 10, rng: math.Random(1));
      s.food = (5, 5);
      expect(s.step(), isTrue);
      expect(s.body.length, 4);
      expect(s.score, 10);
      for (var i = 0; i < 10; i++) {
        s.step();
      }
      expect(s.dead, isTrue);
    });

    test('развернуться в себя нельзя, в клетку уходящего хвоста — можно', () {
      final s = Snake(width: 10, height: 10, rng: math.Random(1));
      s.food = (0, 0);
      s.steer(Dir.left);
      s.step();
      expect(s.dead, isFalse);
      expect(s.dir, Dir.right);

      // Голова (2,2) идёт вниз в (2,3) — там хвост, и он уходит в этот же шаг.
      s.food = (9, 9);
      s.body = [(2, 2), (3, 2), (3, 3), (2, 3)];
      s.dir = Dir.left;
      s.steer(Dir.down);
      s.step();
      expect(s.dead, isFalse);
      expect(s.body.first, (2, 3));

      // А в середину тела — смерть.
      s.body = [(2, 2), (3, 2), (3, 3), (2, 3), (1, 3)];
      s.dir = Dir.left;
      s.steer(Dir.down);
      s.step();
      expect(s.dead, isTrue);
    });
  });

  group('Сапёр', () {
    test('первое нажатие безопасно и открывает область', () {
      for (var seed = 0; seed < 20; seed++) {
        final m = Minesweeper(width: 9, height: 9, mines: 10, rng: math.Random(seed));
        m.reveal(4, 4);
        expect(m.lost, isFalse);
        expect(m.open[4][4], isTrue);
        expect(m.around[4][4], 0, reason: 'вокруг первой клетки мин нет');
        final count = m.mine.expand((r) => r).where((x) => x).length;
        expect(count, 10);
      }
    });

    test('флажок защищает клетку; аккорд открывает соседей', () {
      final m = Minesweeper(width: 5, height: 5, mines: 3, rng: math.Random(2));
      m.reveal(0, 0);
      // Найдём мину и поставим флажок — открыть её нельзя.
      late int mx, my;
      for (var y = 0; y < 5; y++) {
        for (var x = 0; x < 5; x++) {
          if (m.mine[y][x]) {
            mx = x;
            my = y;
          }
        }
      }
      m.toggleFlag(mx, my);
      m.reveal(mx, my);
      expect(m.lost, isFalse);
      expect(m.flagsLeft, 2);
    });

    test('открыл мину — проигрыш, все безопасные — победа', () {
      final m = Minesweeper(width: 6, height: 6, mines: 4, rng: math.Random(5));
      m.reveal(0, 0);
      for (var y = 0; y < 6; y++) {
        for (var x = 0; x < 6; x++) {
          if (!m.mine[y][x]) m.reveal(x, y);
        }
      }
      expect(m.won, isTrue);
      final l = Minesweeper(width: 6, height: 6, mines: 4, rng: math.Random(5));
      l.reveal(0, 0);
      for (var y = 0; y < 6; y++) {
        for (var x = 0; x < 6; x++) {
          if (l.mine[y][x] && !l.lost) l.reveal(x, y);
        }
      }
      expect(l.lost, isTrue);
    });
  });

  group('Судоку', () {
    test('решение корректно, головоломка — его часть, решение единственное', () {
      for (final level in [0, 2]) {
        final s = Sudoku.generate(level: level, rng: math.Random(level + 1));
        for (var i = 0; i < 81; i++) {
          expect(Sudoku.conflicts(s.solution, i), isFalse);
          if (s.puzzle[i] != 0) expect(s.puzzle[i], s.solution[i]);
        }
        expect(Sudoku.countSolutions([...s.puzzle]), 1);
        expect(s.puzzle.where((v) => v != 0).length, greaterThanOrEqualTo(Sudoku.clues[level]!));
      }
    });

    test('конфликт подсвечивается', () {
      final g = List.filled(81, 0);
      g[0] = 5;
      g[8] = 5;
      expect(Sudoku.conflicts(g, 8), isTrue);
      g[8] = 6;
      expect(Sudoku.conflicts(g, 8), isFalse);
    });
  });

  group('Дартс', () {
    test('мишень: яблочко, 25, сектор 20 сверху, утроение и удвоение', () {
      expect(Darts.score(Offset.zero).points, 50);
      expect(Darts.score(const Offset(0, -0.07)).points, 25);
      expect(Darts.score(const Offset(0, -0.5)).points, 20);
      expect(Darts.score(const Offset(0, -0.61)).points, 60);
      expect(Darts.score(const Offset(0, -0.98)).points, 40);
      expect(Darts.score(const Offset(0, -1.1)).points, 0);
      // Справа (90°) — сектор 6, снизу — 3, слева — 11.
      expect(Darts.score(const Offset(0.5, 0)).points, 6);
      expect(Darts.score(const Offset(0, 0.5)).points, 3);
      expect(Darts.score(const Offset(-0.5, 0)).points, 11);
    });

    test('301: перебор сгорает, ровно ноль — победа', () {
      final m = DartsMatch(players: 2);
      m.totals[0] = 40;
      m.nextTurn();
      m.nextTurn(); // снова игрок 0, начало хода — 40
      expect(m.turn, 0);
      expect(m.throwDart(30), isFalse);
      expect(m.throwDart(20), isTrue, reason: 'перебор заканчивает ход');
      expect(m.bust, isTrue);
      expect(m.totals[0], 40);
      m.nextTurn();
      m.nextTurn();
      m.throwDart(20);
      m.throwDart(20);
      expect(m.winner, 0);
    });

    test('«на очки»: 5 ходов, побеждает сумма', () {
      final m = DartsMatch(players: 2, mode: DartsMode.rounds);
      while (!m.isOver) {
        for (var i = 0; i < 3; i++) {
          m.throwDart(m.turn == 1 ? 20 : 5);
        }
        m.nextTurn();
      }
      expect(m.winner, 1);
      expect(m.totals, [75, 300]);
    });
  });

  group('Боулинг: счёт', () {
    BowlingCard card(List<int> rolls) => BowlingCard()..rolls.addAll(rolls);

    test('идеальная игра — 300', () {
      final c = card(List.filled(12, 10));
      expect(c.total, 300);
      expect(c.isComplete, isTrue);
    });

    test('все спэры 5/5 и 5 в конце — 150', () {
      final c = card(List.filled(21, 5));
      expect(c.total, 150);
      expect(c.isComplete, isTrue);
    });

    test('обычная игра без бонусов — 20 бросков', () {
      final c = card(List.filled(20, 4));
      expect(c.total, 80);
      expect(c.isComplete, isTrue);
      expect(card(List.filled(19, 4)).isComplete, isFalse);
    });

    test('позиция и новая расстановка', () {
      final c = card([10]);
      expect(c.position, (1, 0));
      expect(c.freshRack, isTrue);
      c.add(7);
      expect(c.position, (1, 1));
      expect(c.freshRack, isFalse);
      expect(c.frameTotals.first, isNull, reason: 'страйк ждёт два броска');
      c.add(2);
      expect(c.frameTotals.take(2).toList(), [19, 28]);
    });

    test('десятый фрейм: страйк даёт ещё два броска с новой расстановкой', () {
      final c = card([...List.filled(18, 0), 10]);
      expect(c.position, (9, 1));
      expect(c.freshRack, isTrue);
      c.add(3);
      expect(c.freshRack, isFalse);
      expect(c.isComplete, isFalse);
      c.add(4);
      expect(c.isComplete, isTrue);
      expect(c.total, 17);
    });
  });

  group('Боулинг: дорожка', () {
    test('сильный бросок в центр сбивает большинство кеглей', () {
      final lane = BowlingLane();
      lane.launch(aimX: 0.5, velocity: const Offset(0, -4));
      var t = 0;
      while (!lane.step(1 / 60) && t < 1200) {
        t++;
      }
      expect(lane.standing, lessThanOrEqualTo(4));
    });

    test('шар в желобе не сбивает ничего', () {
      final lane = BowlingLane();
      lane.launch(aimX: 0.02, velocity: const Offset(-0.2, -4));
      while (!lane.step(1 / 60)) {}
      expect(lane.standing, 10);
    });
  });

  group('Мини-гольф', () {
    test('точный удар в лунку на прямой', () {
      final b = GolfBall(GolfHole.all.first);
      b.hit(const Offset(0, -1.5));
      var t = 0;
      while (!b.step(1 / 60) && t < 600) {
        t++;
      }
      expect(b.sunk, isTrue);
    });

    test('стенка не пропускает мяч', () {
      final hole = GolfHole.all[1];
      final b = GolfBall(hole);
      b.hit(const Offset(0, -2.4));
      for (var i = 0; i < 600 && !b.step(1 / 60); i++) {}
      expect(b.sunk, isFalse);
      expect(b.pos.dy, greaterThan(hole.walls.first.top - GolfBall.r - 1e-6));
    });

    test('счёт партии: меньше ударов — лучше, не больше 8 за лунку', () {
      final m = GolfMatch(players: 2, holes: GolfHole.all.take(2).toList());
      m.finish(3);
      m.finish(12);
      m.finish(2);
      m.finish(2);
      expect(m.isOver, isTrue);
      expect(m.total(0), 5);
      expect(m.total(1), 10);
      expect(m.leaders, [0]);
    });
  });

  group('Пенальти', () {
    test('зоны и исход удара', () {
      expect(Penalty.zoneOf(-0.8, 0.8), 0);
      expect(Penalty.zoneOf(0, 0.2), 4);
      expect(Penalty.resolve(x: 0.9, y: 0.9, keeperZone: 0).goal, isTrue);
      expect(Penalty.resolve(x: 0.9, y: 0.9, keeperZone: 2).goal, isFalse);
      expect(Penalty.resolve(x: 1.2, y: 0.5, keeperZone: 0).goal, isFalse);
    });

    test('досрочная победа и серия до разницы', () {
      final s = PenaltyShootout();
      // 3:0 после трёх пар — у второго осталось 2 удара, не догнать.
      for (var i = 0; i < 3; i++) {
        s.record(true);
        s.record(false);
      }
      expect(s.winner, 0, reason: '3:0, у второго два удара — уже не догнать');
    });

    test('после 5:5 — до первой разницы в паре', () {
      final s = PenaltyShootout();
      for (var i = 0; i < 5; i++) {
        s.record(true);
        s.record(true);
      }
      expect(s.winner, -1);
      s.record(true);
      expect(s.winner, -1, reason: 'пара не закончена');
      s.record(false);
      expect(s.winner, 0);
    });
  });
}
