import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Поведение прокрутки для всего приложения.
///
/// По умолчанию Flutter разрешает тянуть списки только пальцем и стилусом:
/// считается, что на десктопе для этого есть полоса прокрутки. Для наших
/// горизонтальных лент это означало «прокрутки нет» — мышью схватить ряд
/// было нельзя. Здесь мы добавляем мышь и трекпад.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  /// Отдача при перелистывании за край — без неё лента выглядит «мёртвой».
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) =>
      child;
}

/// Горизонтальная лента, которая слушается колеса мыши.
///
/// Колесо шлёт вертикальную дельту, а ряд прокручивается по горизонтали —
/// сама по себе такая пара не работает. Здесь вертикальный сдвиг колеса
/// переводится в горизонтальный, как в любом современном каталоге.
class HorizontalWheelScroll extends StatelessWidget {
  final ScrollController controller;
  final Widget child;

  const HorizontalWheelScroll({
    super.key,
    required this.controller,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (signal) {
        if (signal is! PointerScrollEvent) return;
        if (!controller.hasClients) return;

        // Трекпад умеет горизонтальный жест сам — берём ту ось, где
        // движение больше, иначе диагональный свайп дёргал бы ленту.
        final delta = signal.scrollDelta.dx.abs() > signal.scrollDelta.dy.abs()
            ? signal.scrollDelta.dx
            : signal.scrollDelta.dy;

        final target = (controller.offset + delta).clamp(
          controller.position.minScrollExtent,
          controller.position.maxScrollExtent,
        );
        controller.jumpTo(target);
      },
      child: child,
    );
  }
}

/// Круглая стрелка у края ленты. Появляется только когда есть куда листать.
class ScrollArrow extends StatelessWidget {
  final bool forward;
  final VoidCallback onTap;
  final bool visible;

  const ScrollArrow({
    super.key,
    required this.forward,
    required this.onTap,
    this.visible = true,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: IgnorePointer(
        ignoring: !visible,
        child: Material(
          color: const Color(0xE6141420),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 40,
              width: 40,
              child: Icon(
                forward ? Icons.chevron_right : Icons.chevron_left,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
