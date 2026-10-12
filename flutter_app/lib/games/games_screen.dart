import 'package:flutter/material.dart';

import '../theme.dart';
import 'air_hockey.dart';
import 'battleship_game.dart';
import 'board_games.dart';
import 'games_common.dart';
import 'racing_games.dart';
import 'reaction_game.dart';
import 'solo_games.dart';
import 'sports_games.dart';
import 'logic_sports.dart' show DartsMode;
import 'words_game.dart';

class _GameInfo {
  final String emoji;
  final String title;
  final String players;
  final String about;
  final Color color;

  /// Сколько игроков спросить перед стартом (null — фиксированное число).
  final (int, int, String)? ask;
  final Widget Function(int players) build;

  /// Дополнительный выбор перед стартом (режим дартса).
  final Future<Widget?> Function(BuildContext context, int players)? setup;

  const _GameInfo({
    required this.emoji,
    required this.title,
    required this.players,
    required this.about,
    required this.color,
    required this.build,
    this.ask,
    this.setup,
  });
}

/// «Игры»: всё на одном телефоне и без интернета — в дороге, в очереди,
/// за столом. Никаких аккаунтов и комнат: выбрал игру и играете.
class GamesScreen extends StatelessWidget {
  const GamesScreen({super.key});

  static final _games = <_GameInfo>[
    _GameInfo(
      emoji: '🏒',
      title: 'Аэрохокей',
      players: '2 игрока',
      about: 'Телефон между вами, каждый водит свою биту пальцем. До 7 голов.',
      color: const Color(0xFF22C3E6),
      build: (_) => const AirHockeyScreen(),
    ),
    _GameInfo(
      emoji: '🏍️',
      title: 'Световые мотоциклы',
      players: '2–4 игрока',
      about: 'Мотоциклы оставляют стену. Поворачивай вовремя — врезался, выбыл.',
      color: const Color(0xFFFF7A1A),
      ask: (2, 4, 'игрока'),
      build: (n) => LightCyclesScreen(players: n),
    ),
    _GameInfo(
      emoji: '🏎️',
      title: 'Тап-гонка',
      players: '2–4 игрока',
      about: 'Каждый тапает по своей дорожке. Кто быстрее — тот первым на финише.',
      color: const Color(0xFFE5484D),
      ask: (2, 4, 'игрока'),
      build: (n) => TapRaceScreen(players: n),
    ),
    _GameInfo(
      emoji: '🚢',
      title: 'Морской бой',
      players: '2 игрока',
      about: 'Передаёте телефон друг другу — экран закрывается, корабли не подсмотреть.',
      color: const Color(0xFF3E8BFF),
      build: (_) => const BattleshipScreen(),
    ),
    _GameInfo(
      emoji: '🎯',
      title: 'Дартс',
      players: '1–4 игрока',
      about: 'Прицел дрожит, как рука. Режимы «301» и «на очки».',
      color: const Color(0xFF30A46C),
      ask: (1, 4, 'игрока'),
      build: (n) => DartsScreen(players: n, mode: DartsMode.x301),
      setup: (context, n) async {
        final mode = await pickDartsMode(context);
        return mode == null ? null : DartsScreen(players: n, mode: mode);
      },
    ),
    _GameInfo(
      emoji: '🎳',
      title: 'Боулинг',
      players: '1–4 игрока',
      about: 'Свайп — бросок, изгиб свайпа — подкрутка. Честный счёт на 10 фреймов.',
      color: const Color(0xFF8E7CFF),
      ask: (1, 4, 'игрока'),
      build: (n) => BowlingScreen(players: n),
    ),
    _GameInfo(
      emoji: '⛳',
      title: 'Мини-гольф',
      players: '1–4 игрока',
      about: '6 лунок со стенками и песком. Тяни мяч назад, как рогатку.',
      color: const Color(0xFF2E9E4F),
      ask: (1, 4, 'игрока'),
      build: (n) => MiniGolfScreen(players: n),
    ),
    _GameInfo(
      emoji: '⚽',
      title: 'Пенальти',
      players: '2 игрока',
      about: 'Вратарь тайно выбирает угол, бьющий — свайп в ворота. По 5 ударов.',
      color: const Color(0xFFF5B83D),
      build: (_) => const PenaltyScreen(),
    ),
    _GameInfo(
      emoji: '⚡',
      title: 'Реакция',
      players: '2–4 игрока',
      about: 'Телефон посередине, у каждого свой угол. Загорелся зелёный — жми первым.',
      color: playerColors[3],
      ask: (2, 4, 'игрока'),
      build: (n) => ReactionScreen(players: n),
    ),
    _GameInfo(
      emoji: '🗣️',
      title: 'Объясни слово',
      players: '2–4 команды',
      about: 'Как «Шляпа»: объясняй слова своей команде, пока идёт минута.',
      color: playerColors[2],
      ask: (2, 4, 'команды'),
      build: (n) => WordsScreen(teams: n),
    ),
    _GameInfo(
      emoji: '🔲',
      title: 'Точки и квадраты',
      players: '2–4 игрока',
      about: 'Проводите линии по очереди. Замкнул квадрат — он твой, и ходишь ещё.',
      color: playerColors[1],
      ask: (2, 4, 'игрока'),
      build: (n) => DotsAndBoxesScreen(players: n),
    ),
    _GameInfo(
      emoji: '🔴',
      title: 'Четыре в ряд',
      players: '2 игрока',
      about: 'Бросай фишки в столбцы. Четыре своих подряд — победа.',
      color: playerColors[0],
      build: (_) => const ConnectFourScreen(),
    ),
    _GameInfo(
      emoji: '✕',
      title: 'Крестики-нолики',
      players: '2 игрока',
      about: 'Классика на одном экране, со счётом серии.',
      color: const Color(0xFF8E7CFF),
      build: (_) => const TicTacToeScreen(),
    ),
  ];

  static final _solo = <_GameInfo>[
    _GameInfo(
      emoji: '🔢',
      title: '2048',
      players: 'Для одного',
      about: 'Свайпами сливай одинаковые плитки. Дойдёшь до 2048?',
      color: const Color(0xFFEDC22E),
      build: (_) => const Game2048Screen(),
    ),
    _GameInfo(
      emoji: '🐍',
      title: 'Змейка',
      players: 'Для одного',
      about: 'Собирай яблоки — змейка растёт и ускоряется.',
      color: const Color(0xFF30A46C),
      build: (_) => const SnakeScreen(),
    ),
    _GameInfo(
      emoji: '💣',
      title: 'Сапёр',
      players: 'Для одного',
      about: 'Три размера поля, первый ход всегда безопасен. Рекорд по времени.',
      color: const Color(0xFF8A94A6),
      build: (_) => const MinesweeperScreen(),
    ),
    _GameInfo(
      emoji: '🧩',
      title: 'Судоку',
      players: 'Для одного',
      about: 'Три уровня, заметки карандашом, ошибки подсвечиваются.',
      color: const Color(0xFF3E8BFF),
      build: (_) => const SudokuScreen(),
    ),
  ];

  Future<void> _open(BuildContext context, _GameInfo g) async {
    var players = 2;
    final ask = g.ask;
    if (ask != null) {
      final picked = await pickPlayers(context, title: g.title, min: ask.$1, max: ask.$2, unit: ask.$3);
      if (picked == null || !context.mounted) return;
      players = picked;
    }
    var screen = g.build(players);
    final setup = g.setup;
    if (setup != null) {
      if (!context.mounted) return;
      final chosen = await setup(context, players);
      if (chosen == null) return;
      screen = chosen;
    }
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final columns = (box.maxWidth / 360).floor().clamp(1, 3);
        SliverGrid grid(List<_GameInfo> games) => SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisExtent: 136,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: games.length,
              itemBuilder: (context, i) => _GameCard(game: games[i], onTap: () => _open(context, games[i])),
            );
        Widget heading(String text) => Padding(
              padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
              child: Text(text.toUpperCase(), style: kEyebrowStyle),
            );
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverToBoxAdapter(child: const _Intro()),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(child: heading('Компанией · на одном телефоне')),
            ),
            SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 16), sliver: grid(_games)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(child: heading('Для одного')),
            ),
            SliverPadding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), sliver: grid(_solo)),
          ],
        );
      },
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Игры', style: AppText.display(28)),
          const SizedBox(height: 6),
          Text(
            'На одном телефоне, вдвоём или компанией. Работают без интернета — '
            'в дороге самое то.',
            style: TextStyle(color: AppColors.textDim, fontSize: 13.5, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final _GameInfo game;
  final VoidCallback onTap;

  const _GameCard({required this.game, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.medium),
            border: Border.all(color: game.color.withValues(alpha: 0.45)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [game.color.withValues(alpha: 0.16), Colors.transparent],
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: game.color.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(game.emoji, style: TextStyle(fontSize: 28, color: game.color)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(game.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.text, fontSize: 16.5, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(game.players,
                        style: TextStyle(color: game.color, fontSize: 12.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      game.about,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
