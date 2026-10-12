import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/games/logic_action.dart';

void main() {
  group('Аэрохокей', () {
    test('шайба, летящая в створ, — гол и подача пропустившему', () {
      final g = AirHockey();
      g.mallets[0] = const Offset(0.1, 0.3); // бита в стороне от линии полёта
      g.puck = const Offset(0.5, 0.5);
      g.puckVel = const Offset(0, -3);
      var goal = -1;
      for (var i = 0; i < 120 && goal < 0; i++) {
        goal = g.step(1 / 60);
      }
      expect(goal, 1, reason: 'забил нижний игрок в верхние ворота');
      expect(g.scores, [0, 1]);
      expect(g.puckVel, Offset.zero);
      expect(g.puck.dy, lessThan(g.length / 2), reason: 'подача на половину пропустившего');
    });

    test('мимо ворот — отскок от борта, не гол', () {
      final g = AirHockey();
      g.mallets[0] = const Offset(0.9, 0.3);
      g.puck = const Offset(0.08, 0.6);
      g.puckVel = const Offset(0, -2.5);
      for (var i = 0; i < 60; i++) {
        expect(g.step(1 / 60), -1);
      }
      expect(g.puck.dy, greaterThanOrEqualTo(AirHockey.puckR - 1e-9));
    });

    test('удар битой отправляет шайбу от биты, скорость ограничена', () {
      final g = AirHockey();
      g.puck = Offset(0.5, g.length * 0.75);
      g.mallets[1] = Offset(0.5, g.length * 0.75 + AirHockey.puckR + AirHockey.malletR + 0.01);
      // Резкий замах вверх.
      g.moveMallet(1, Offset(0.5, g.length * 0.75 + 0.05), 1 / 60);
      g.step(1 / 60);
      expect(g.puckVel.dy, lessThan(0), reason: 'шайба полетела вверх');
      expect(g.puckVel.distance, lessThanOrEqualTo(AirHockey.maxSpeed + 1e-9));
    });

    test('бита не заходит на чужую половину', () {
      final g = AirHockey();
      g.moveMallet(1, const Offset(0.5, 0.1), 1 / 60);
      expect(g.mallets[1].dy, greaterThan(g.length / 2));
      g.moveMallet(0, Offset(0.5, g.length), 1 / 60);
      expect(g.mallets[0].dy, lessThan(g.length / 2));
    });
  });

  group('Световые мотоциклы', () {
    test('врезался в стену — выбыл, второй берёт раунд', () {
      final g = LightCycles(players: 2, width: 10, height: 20);
      // Игрок 0 сворачивает к левой стене.
      g.turn(0, clockwise: true); // вниз → влево
      var over = false;
      for (var i = 0; i < 30 && !over; i++) {
        over = g.step();
      }
      expect(over, isTrue);
      expect(g.cycles[0].alive, isFalse);
      expect(g.roundWinner, 1);
      expect(g.scores, [0, 1]);
    });

    test('лобовое столкновение — оба выбывают, ничья', () {
      final g = LightCycles(players: 2, width: 9, height: 9);
      // Старты сверху и снизу по центру, едут навстречу.
      var over = false;
      for (var i = 0; i < 20 && !over; i++) {
        over = g.step();
      }
      expect(g.cycles.every((c) => !c.alive), isTrue);
      expect(g.roundWinner, -1);
    });

    test('разворот на 180° игнорируется', () {
      final g = LightCycles(players: 2);
      g.turn(0, clockwise: true);
      g.turn(0, clockwise: true); // два поворота подряд = разворот
      final before = g.cycles[0].heading;
      g.step();
      expect(g.cycles[0].heading, before);
      expect(g.cycles[0].alive, isTrue);
    });
  });

  test('Тап-гонка: первый, кто набрал нужное число, побеждает', () {
    final r = TapRace(players: 3, taps: 3);
    r.tap(2);
    r.tap(0);
    r.tap(2);
    r.tap(2);
    expect(r.winner, 2);
    expect(r.tap(0), isFalse);
  });

  group('Морской бой', () {
    test('расстановка: 10 кораблей, внутри поля, не касаются', () {
      for (var seed = 0; seed < 30; seed++) {
        final f = Fleet.random(math.Random(seed));
        expect(f.ships.map((s) => s.cells.length).toList()..sort(), [1, 1, 1, 1, 2, 2, 2, 3, 3, 4]);
        final all = <(int, int), int>{};
        for (var i = 0; i < f.ships.length; i++) {
          for (final c in f.ships[i].cells) {
            expect(c.$1, inInclusiveRange(0, 9));
            expect(c.$2, inInclusiveRange(0, 9));
            all[c] = i;
          }
        }
        for (final e in all.entries) {
          for (var dx = -1; dx <= 1; dx++) {
            for (var dy = -1; dy <= 1; dy++) {
              final other = all[(e.key.$1 + dx, e.key.$2 + dy)];
              if (other != null) expect(other, e.value, reason: 'корабли касаются (seed $seed)');
            }
          }
        }
      }
    });

    test('попал — ход остаётся, промах — переходит; потоплен — обводка', () {
      final b = Battleship(math.Random(7));
      final ship = b.fleets[1].ships.firstWhere((s) => s.cells.length == 1);
      final (x, y) = ship.cells.first;
      expect(b.fire(x, y), Shot.sunk);
      expect(b.turn, 0, reason: 'после попадания стреляет снова');
      // Клетки вокруг потопленного уже отмечены.
      if (x + 1 < Fleet.size) expect(b.fleets[1].shots.contains((x + 1, y)), isTrue);
      expect(b.fire(x, y), Shot.repeat);

      // Ищем пустую клетку для промаха.
      for (var i = 0; i < 100; i++) {
        final cx = i % 10, cy = i ~/ 10;
        if (b.fleets[1].shipAt(cx, cy) == null && !b.fleets[1].shots.contains((cx, cy))) {
          expect(b.fire(cx, cy), Shot.miss);
          break;
        }
      }
      expect(b.turn, 1);
    });

    test('все корабли потоплены — победа', () {
      final b = Battleship(math.Random(3));
      for (final s in b.fleets[1].ships) {
        for (final (x, y) in s.cells) {
          b.fleets[1].fire(x, y);
        }
      }
      expect(b.winner, 0);
    });
  });
}
