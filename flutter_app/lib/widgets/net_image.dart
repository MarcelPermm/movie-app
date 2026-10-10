import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Картинка из сети, которая декодируется под реальный размер на экране.
///
/// Без этого постер w342 для карточки шириной 120 точек, а кадр w1280 для
/// плитки в ленте распаковываются в память целиком: десятки мегабайт на
/// экран и заметные подёргивания при прокрутке. Здесь ширину декодирования
/// считаем по месту — с учётом плотности экрана и того, что при BoxFit.cover
/// картинку может растягивать по высоте.
class NetImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;

  /// Соотношение сторон самой картинки (ширина / высота):
  /// 2/3 для постеров и фото, 16/9 для кадров.
  final double aspect;

  /// Верхняя граница ширины декодирования. Для размытого фона хватает
  /// маленькой картинки — размытие всё равно съест детали.
  final int? maxDecodeWidth;

  final Duration fadeInDuration;
  final PlaceholderWidgetBuilder? placeholder;
  final LoadingErrorWidgetBuilder? errorWidget;

  const NetImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.aspect = 2 / 3,
    this.maxDecodeWidth,
    this.fadeInDuration = const Duration(milliseconds: 240),
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => CachedNetworkImage(
        imageUrl: imageUrl,
        fit: fit,
        memCacheWidth: decodeWidth(box, MediaQuery.devicePixelRatioOf(context)),
        fadeInDuration: fadeInDuration,
        placeholder: placeholder,
        errorWidget: errorWidget,
      ),
    );
  }

  /// Сколько пикселей ширины реально нужно, или null — «как есть».
  int? decodeWidth(BoxConstraints box, double dpr) {
    final byWidth = box.maxWidth.isFinite ? box.maxWidth : 0.0;
    // При cover картинка заполняет и высоту: узкая высокая плитка с кадром
    // 16:9 требует ширины больше, чем у самой плитки.
    final byHeight = box.maxHeight.isFinite && fit == BoxFit.cover ? box.maxHeight * aspect : 0.0;
    final logical = byWidth > byHeight ? byWidth : byHeight;
    if (logical <= 0) return maxDecodeWidth;

    // Шаг 64: соседние размеры (окно потянули на пару точек) делят одну запись
    // в кэше и не декодируются заново.
    var px = ((logical * dpr / 64).ceil()) * 64;
    if (maxDecodeWidth != null && px > maxDecodeWidth!) px = maxDecodeWidth!;
    return px;
  }
}
