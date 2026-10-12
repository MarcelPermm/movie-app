import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'games_common.dart';
import 'logic_action.dart';

enum _Stage { setup, cover, aim }

/// Морской бой вдвоём на одном телефоне. Между ходами экран закрывается
/// заставкой «передай телефон» — чтобы соперник не увидел твои корабли.
class BattleshipScreen extends StatefulWidget {
  const BattleshipScreen({super.key});

  @override
  State<BattleshipScreen> createState() => _BattleshipScreenState();
}

class _BattleshipScreenState extends State<BattleshipScreen> {
  final _rng = math.Random();
  late var _game = Battleship(_rng);

  /// Кто сейчас держит телефон.
  int _holder = 0;
  var _stage = _Stage.setup;

  /// Расстановку смотрят оба по очереди; потом — бой.
  bool _setupDone = false;
  String? _flash;
  bool _busy = false;

  void _restart() => setState(() {
        _game = Battleship(_rng);
        _holder = 0;
        _stage = _Stage.setup;
        _setupDone = false;
        _flash = null;
      });

  void _reshuffle() => setState(() => _game.fleets[_holder] = Fleet.random(_rng));

  void _setupReady() {
    setState(() {
      if (_holder == 0) {
        _holder = 1;
        _stage = _Stage.cover;
      } else {
        _setupDone = true;
        _holder = 0;
        _stage = _Stage.cover;
      }
    });
  }

  void _uncover() => setState(() => _stage = _setupDone ? _Stage.aim : _Stage.setup);

  Future<void> _fire(int x, int y) async {
    if (_busy) return;
    final shooter = _game.turn;
    final r = _game.fire(x, y);
    if (r == Shot.repeat) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _flash = switch (r) {
        Shot.miss => 'Мимо',
        Shot.hit => 'Ранил! Стреляй ещё',
        Shot.sunk => 'Убил! Стреляй ещё',
        Shot.repeat => null,
      };
    });

    final w = _game.winner;
    if (w >= 0) {
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      showResult(context, title: 'Победил ${playerNames[w]}!', color: playerColors[w], onAgain: _restart);
      return;
    }
    if (r == Shot.miss) {
      // Промах: показываем его секунду и закрываем экран для передачи.
      _busy = true;
      await Future.delayed(const Duration(milliseconds: 1100));
      if (!mounted) return;
      setState(() {
        _busy = false;
        _flash = null;
        _holder = 1 - shooter;
        _stage = _Stage.cover;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: 'Морской бой',
      onRestart: _restart,
      body: switch (_stage) {
        _Stage.cover => _cover(),
        _Stage.setup => _setup(),
        _Stage.aim => _aim(),
      },
    );
  }

  Widget _cover() {
    final color = playerColors[_holder];
    return InkWell(
      onTap: _uncover,
      child: Container(
        width: double.infinity,
        color: color.withValues(alpha: 0.12),
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🙈', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text('Передай телефон', style: TextStyle(color: AppColors.textDim, fontSize: 16)),
            const SizedBox(height: 6),
            Text(playerNames[_holder],
                style: TextStyle(color: color, fontSize: 34, fontWeight: FontWeight.w900)),
            const SizedBox(height: 18),
            Text(
              _setupDone ? 'Нажми, когда соперник отвернётся' : 'Посмотри свою расстановку — соперник не подглядывает',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textDim, fontSize: 14.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _setup() {
    return Column(
      children: [
        TurnBanner(player: _holder, text: '${playerNames[_holder]}: твои корабли'),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: _Grid(fleet: _game.fleets[_holder], showShips: true),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _reshuffle,
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Перемешать'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _setupReady,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.bg,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Готово', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _aim() {
    final me = _game.turn;
    final enemy = _game.fleets[1 - me];
    final left = enemy.ships.where((s) => !s.sunk).length;
    return Column(
      children: [
        TurnBanner(
          player: me,
          text: _flash ?? '${playerNames[me]} стреляет · у соперника кораблей: $left',
        ),
        Expanded(
          flex: 3,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _Grid(fleet: enemy, showShips: false, onTap: _busy ? null : _fire),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text('Твоё поле', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
        ),
        Expanded(
          flex: 1,
          child: Center(child: _Grid(fleet: _game.fleets[me], showShips: true)),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  final Fleet fleet;
  final bool showShips;
  final void Function(int x, int y)? onTap;

  const _Grid({required this.fleet, required this.showShips, this.onTap});

  @override
  Widget build(BuildContext context) {
    const n = Fleet.size;
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0E2A47),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(2),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: n),
          itemCount: n * n,
          itemBuilder: (context, i) {
            final x = i % n, y = i ~/ n;
            final ship = fleet.shipAt(x, y);
            final shot = fleet.shots.contains((x, y));
            final hit = ship != null && ship.hits.contains((x, y));
            final sunk = ship != null && ship.sunk;

            Color fill = const Color(0xFF14385E);
            Widget? mark;
            if (sunk) {
              fill = const Color(0xFF7A1F25);
              mark = const Icon(Icons.close, color: Colors.white, size: 14);
            } else if (hit) {
              fill = const Color(0xFFE5484D);
              mark = const Icon(Icons.local_fire_department, color: Colors.white, size: 14);
            } else if (showShips && ship != null) {
              fill = const Color(0xFF8A94A6);
            } else if (shot) {
              mark = Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(color: Colors.white54, shape: BoxShape.circle),
              );
            }

            return GestureDetector(
              onTap: onTap == null || shot ? null : () => onTap!(x, y),
              child: Container(
                margin: const EdgeInsets.all(1),
                decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(3)),
                child: Center(child: mark == null ? null : FittedBox(child: mark)),
              ),
            );
          },
        ),
      ),
    );
  }
}
