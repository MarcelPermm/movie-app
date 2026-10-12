import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/games/games_screen.dart';
import 'package:movie_app/games/logic.dart';
import 'package:movie_app/games/words_ru.dart';

void main() {
  group('Крестики-нолики', () {
    test('три в ряд — победа, ход больше не принимается', () {
      final g = TicTacToe();
      for (final i in [0, 3, 1, 4, 2]) {
        g.play(i);
      }
      expect(g.winner, 0);
      expect(g.winLine, [0, 1, 2]);
      expect(g.play(8), isFalse);
    });

    test('занятая клетка не принимается, ничья распознаётся', () {
      final g = TicTacToe();
      expect(g.play(4), isTrue);
      expect(g.play(4), isFalse);
      final d = TicTacToe();
      for (final i in [0, 1, 2, 4, 3, 5, 7, 6, 8]) {
        d.play(i);
      }
      expect(d.winner, -1);
      expect(d.isDraw, isTrue);
    });
  });

  group('Четыре в ряд', () {
    test('фишка падает вниз, столбец заполняется', () {
      final g = ConnectFour();
      expect(g.drop(3), ConnectFour.rows - 1);
      expect(g.drop(3), ConnectFour.rows - 2);
      for (var i = 0; i < 4; i++) {
        g.drop(3);
      }
      expect(g.canDrop(3), isFalse);
      expect(g.drop(3), isNull);
    });

    test('горизонталь и диагональ', () {
      final h = ConnectFour();
      for (final c in [0, 0, 1, 1, 2, 2, 3]) {
        h.drop(c);
      }
      expect(h.winner, 0);
      expect(h.winCells.length, 4);

      // Диагональ снизу-слева вверх-направо для игрока 0.
      final d = ConnectFour();
      for (final c in [0, 1, 1, 2, 2, 3, 2, 3, 3, 6, 3]) {
        d.drop(c);
      }
      expect(d.winner, 0);
    });
  });

  group('Точки и квадраты', () {
    test('замкнул квадрат — очко и ещё ход', () {
      final g = DotsAndBoxes(size: 2, players: 3);
      g.draw(isHorizontal: true, r: 0, c: 0); // игрок 0
      g.draw(isHorizontal: true, r: 1, c: 0); // игрок 1
      g.draw(isHorizontal: false, r: 0, c: 0); // игрок 2
      expect(g.turn, 0);
      final closed = g.draw(isHorizontal: false, r: 0, c: 1); // игрок 0 замыкает
      expect(closed, 1);
      expect(g.scores, [1, 0, 0]);
      expect(g.turn, 0, reason: 'замкнувший ходит снова');
      expect(g.boxes[0][0], 0);
    });

    test('одна линия может замкнуть два квадрата, повтор линии запрещён', () {
      final g = DotsAndBoxes(size: 2, players: 2);
      for (final (h, r, c) in [
        (true, 0, 0), (true, 1, 0), (false, 0, 0),
        (true, 0, 1), (true, 1, 1), (false, 0, 2),
      ]) {
        g.draw(isHorizontal: h, r: r, c: c);
      }
      final before = g.turn;
      expect(g.draw(isHorizontal: false, r: 0, c: 1), 2);
      expect(g.scores[before], 2);
      expect(g.draw(isHorizontal: false, r: 0, c: 1), -1);
    });

    test('игра заканчивается, когда заняты все квадраты', () {
      final g = DotsAndBoxes(size: 2, players: 2);
      for (var r = 0; r <= 2; r++) {
        for (var c = 0; c < 2; c++) {
          g.draw(isHorizontal: true, r: r, c: c);
        }
      }
      for (var r = 0; r < 2; r++) {
        for (var c = 0; c <= 2; c++) {
          g.draw(isHorizontal: false, r: r, c: c);
        }
      }
      expect(g.isOver, isTrue);
      expect(g.claimed, 4);
      expect(g.leaders, isNotEmpty);
    });
  });

  group('Реакция', () {
    test('раньше сигнала — минус очко, не ниже нуля', () {
      final m = ReactionMatch(players: 3);
      m.startRound();
      expect(m.tap(1), isTrue);
      expect(m.falseStart, 1);
      expect(m.scores[1], 0);
    });

    test('после сигнала первый берёт очко, до цели — победа', () {
      final m = ReactionMatch(players: 2, target: 2);
      for (var i = 0; i < 2; i++) {
        m.startRound();
        m.signal();
        expect(m.tap(1), isTrue);
        expect(m.tap(0), isFalse, reason: 'второй в том же раунде не считается');
      }
      expect(m.phase, ReactionPhase.matchOver);
      expect(m.champion, 1);
    });

    test('задержка сигнала — от 1,5 до 5 секунд', () {
      final rng = math.Random(1);
      for (var i = 0; i < 200; i++) {
        final d = ReactionMatch.randomDelay(rng).inMilliseconds;
        expect(d, inInclusiveRange(1500, 5000));
      }
    });
  });

  group('Объясни слово', () {
    test('очки раунда: угадано плюс, пропуск минус, исправление отметки', () {
      final m = WordsMatch(words: const ['а', 'б', 'в', 'г'], teams: 2, rng: math.Random(0));
      m.guessed();
      m.guessed();
      m.skipped();
      expect(m.roundScore, 1);
      m.toggle(2); // пропуск оказался угаданным
      expect(m.roundScore, 3);
      m.finishRound();
      expect(m.scores, [3, 0]);
      expect(m.team, 1);
    });

    test('победа — только когда все команды сыграли поровну', () {
      final m = WordsMatch(words: const ['а', 'б'], teams: 2, target: 2, rng: math.Random(0));
      m.guessed();
      m.guessed();
      m.finishRound();
      expect(m.winner, -1, reason: 'вторая команда ещё не ходила');
      m.finishRound();
      expect(m.winner, 0);
    });

    test('словарь без повторов в колоде', () {
      final m = WordsMatch(words: wordsRu, rng: math.Random(3));
      final seen = <String>{};
      for (var i = 0; i < wordsRu.toSet().length; i++) {
        expect(seen.add(m.current), isTrue);
        m.skipped();
      }
    });
  });

  testWidgets('каталог игр открывается и предлагает выбрать число игроков', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: GamesScreen())));
    expect(find.text('Аэрохокей'), findsOneWidget);
    // Каталог длинный: последняя игра — за краем, до неё прокручиваем.
    await tester.scrollUntilVisible(find.text('Крестики-нолики'), 300);
    expect(find.text('Крестики-нолики'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Реакция'), -300);
    await tester.tap(find.text('Реакция'));
    await tester.pumpAndSettle();
    expect(find.text('Сколько играет?'), findsOneWidget);
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Старт'), findsOneWidget);
  });
}
