import 'package:flutter/material.dart';

import '../theme.dart';

/// Ожидание ответа AI. На сайте здесь думает обезьянка — сохраняем и её,
/// и интонацию: запрос идёт секунд десять, и пустой экран всё это время
/// выглядел бы как зависание.
class AiThinking extends StatefulWidget {
  final String text;

  const AiThinking({super.key, this.text = 'ОБЕЗЬЯНКА ДУМАЕТ'});

  @override
  State<AiThinking> createState() => _AiThinkingState();
}

class _AiThinkingState extends State<AiThinking> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, -8 * _controller.value),
              child: child,
            ),
            child: const Text('🙊', style: TextStyle(fontSize: 44)),
          ),
          const SizedBox(height: 6),
          FadeTransition(
            opacity: Tween<double>(begin: 0.35, end: 1).animate(_controller),
            child: Text('✦', style: TextStyle(color: AppColors.gold, fontSize: 18)),
          ),
          const SizedBox(height: 14),
          Text(
            widget.text,
            style: TextStyle(
              color: AppColors.textDim,
              fontSize: 11,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Объяснение AI под карточкой — почему он это предложил.
class AiReasonNote extends StatelessWidget {
  final String reason;

  const AiReasonNote(this.reason, {super.key});

  @override
  Widget build(BuildContext context) {
    if (reason.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
      decoration: BoxDecoration(
        color: AppColors.goldWash(0.07),
        borderRadius: BorderRadius.circular(AppRadius.small),
        border: Border.all(color: AppColors.goldWash(0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('✦', style: TextStyle(color: AppColors.gold, fontSize: 11)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              reason,
              style: TextStyle(color: AppColors.textDim, fontSize: 11, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Строка запроса к AI с кнопкой запуска.
class AiQueryBar extends StatefulWidget {
  final String hint;
  final String buttonLabel;
  final bool busy;
  final ValueChanged<String> onSubmit;

  /// Готовые формулировки — по ним запускается тот же запрос.
  final List<String> examples;

  const AiQueryBar({
    super.key,
    required this.onSubmit,
    this.hint = 'Например: что-нибудь медленное и осеннее',
    this.buttonLabel = 'Подобрать',
    this.busy = false,
    this.examples = const [],
  });

  @override
  State<AiQueryBar> createState() => _AiQueryBarState();
}

class _AiQueryBarState extends State<AiQueryBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit([String? preset]) {
    if (widget.busy) return;
    if (preset != null) _controller.text = preset;
    widget.onSubmit(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  enabled: !widget.busy,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(hintText: widget.hint),
                  style: TextStyle(color: AppColors.text, fontSize: 14),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: widget.busy ? null : () => _submit(),
                child: Text(widget.busy ? '…' : widget.buttonLabel),
              ),
            ],
          ),
          if (widget.examples.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: widget.examples
                  .map((e) => GestureDetector(
                        onTap: () => _submit(e),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            e,
                            style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Оставь поле пустым — обезьянка выберет на своё усмотрение.',
            style: TextStyle(color: AppColors.textDim, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
