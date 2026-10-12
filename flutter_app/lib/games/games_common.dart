import 'package:flutter/material.dart';

import '../theme.dart';

/// Цвета игроков — одни и те же во всех играх и темах: на общем экране
/// их нужно различать мгновенно, даже краем глаза.
const playerColors = <Color>[
  Color(0xFFE5484D), // красный
  Color(0xFF3E8BFF), // синий
  Color(0xFF30A46C), // зелёный
  Color(0xFFF5B83D), // жёлтый
];

const playerNames = ['Красный', 'Синий', 'Зелёный', 'Жёлтый'];

/// Те же цвета для команд: «Ходят Синие», «Победили Красные».
const teamNames = ['Красные', 'Синие', 'Зелёные', 'Жёлтые'];

/// Каркас игры: тёмный фон, «назад», название и кнопка «Заново».
class GameScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final VoidCallback? onRestart;

  const GameScaffold({super.key, required this.title, required this.body, this.onRestart});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (onRestart != null)
            IconButton(
              tooltip: 'Заново',
              icon: const Icon(Icons.refresh),
              onPressed: onRestart,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(child: body),
    );
  }
}

/// Чей ход: цветная плашка над полем.
class TurnBanner extends StatelessWidget {
  final int player;
  final String text;

  const TurnBanner({super.key, required this.player, required this.text});

  @override
  Widget build(BuildContext context) {
    final color = player >= 0 ? playerColors[player] : AppColors.textDim;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: color.withValues(alpha: 0.7), width: 1.5),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Выбор числа игроков перед стартом: «2 · 3 · 4».
Future<int?> pickPlayers(BuildContext context, {required String title, int min = 2, int max = 4, String unit = 'игрока'}) {
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: AppColors.sheet,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Сколько играет?', style: TextStyle(color: AppColors.textDim)),
          const SizedBox(height: 16),
          Row(
            children: [
              for (var n = min; n <= max; n++) ...[
                if (n > min) const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext, n),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.surface,
                      foregroundColor: AppColors.text,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      side: BorderSide(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        Text('$n', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                        Text(unit, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    ),
  );
}

/// Счёт игроков в строку: цветные кружки с числами.
class ScoreRow extends StatelessWidget {
  final List<int> scores;
  final int active;
  final List<String>? names;

  const ScoreRow({super.key, required this.scores, this.active = -1, this.names});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          for (var i = 0; i < scores.length; i++)
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: playerColors[i].withValues(alpha: i == active ? 0.28 : 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.small),
                  border: Border.all(
                    color: playerColors[i].withValues(alpha: i == active ? 1 : 0.35),
                    width: i == active ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      names?[i] ?? playerNames[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
                    ),
                    Text(
                      '${scores[i]}',
                      style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Окно итога: «Победил Синий!» и кнопка «Ещё раз».
Future<void> showResult(BuildContext context, {required String title, String? subtitle, Color? color, required VoidCallback onAgain}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.sheet,
      title: Row(
        children: [
          Text('🏆 ', style: TextStyle(fontSize: 26, color: color)),
          Expanded(child: Text(title, style: TextStyle(color: color ?? AppColors.text))),
        ],
      ),
      content: subtitle == null ? null : Text(subtitle, style: TextStyle(color: AppColors.textDim)),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(dialogContext);
            Navigator.pop(context);
          },
          child: const Text('К играм'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(dialogContext);
            onAgain();
          },
          style: FilledButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: AppColors.bg),
          child: const Text('Ещё раз'),
        ),
      ],
    ),
  );
}
