import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/widgets/net_image.dart';

void main() {
  const poster = NetImage(imageUrl: 'x');
  const still = NetImage(imageUrl: 'x', aspect: 16 / 9);

  test('постер декодируется под ширину карточки с учётом плотности экрана', () {
    // 120 × 2 = 240 → вверх до шага 64 = 256
    expect(poster.decodeWidth(const BoxConstraints(maxWidth: 120, maxHeight: 180), 2), 256);
  });

  test('кадр в узкой высокой плитке берёт ширину по высоте', () {
    // 300 × 16/9 ≈ 533 > 200 → 533 × 1 → 576
    expect(still.decodeWidth(const BoxConstraints(maxWidth: 200, maxHeight: 300), 1), 576);
  });

  test('без размеров — как есть, с потолком — не больше потолка', () {
    expect(poster.decodeWidth(const BoxConstraints(), 2), isNull);
    const blurred = NetImage(imageUrl: 'x', aspect: 16 / 9, maxDecodeWidth: 640);
    expect(blurred.decodeWidth(const BoxConstraints(maxWidth: 1920, maxHeight: 1080), 1.5), 640);
  });
}
