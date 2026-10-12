import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/games/air_hockey.dart';
import 'package:movie_app/games/battleship_game.dart';
import 'package:movie_app/games/board_games.dart';
import 'package:movie_app/games/racing_games.dart';
import 'package:movie_app/games/reaction_game.dart';
import 'package:movie_app/games/words_game.dart';

/// Каждая игра открывается на экране телефона без ошибок и переполнений.
void main() {
  final screens = <String, Widget>{
    'аэрохокей': const AirHockeyScreen(),
    'мотоциклы ×2': const LightCyclesScreen(players: 2),
    'мотоциклы ×4': const LightCyclesScreen(players: 4),
    'тап-гонка ×3': const TapRaceScreen(players: 3),
    'морской бой': const BattleshipScreen(),
    'реакция ×4': const ReactionScreen(players: 4),
    'слова ×3': const WordsScreen(teams: 3),
    'точки ×4': const DotsAndBoxesScreen(players: 4),
    'четыре в ряд': const ConnectFourScreen(),
    'крестики': const TicTacToeScreen(),
  };

  for (final size in const [Size(390, 844), Size(360, 640)]) {
    for (final e in screens.entries) {
      testWidgets('${e.key} на ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(home: e.value));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox()); // гасим таймеры и тикеры
      });
    }
  }

  testWidgets('морской бой: расстановка → заставка → второй игрок', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: BattleshipScreen()));
    expect(find.textContaining('твои корабли'), findsOneWidget);
    await tester.tap(find.text('Готово'));
    await tester.pump();
    expect(find.text('Передай телефон'), findsOneWidget);
    expect(find.text('Синий'), findsOneWidget);
  });
}
