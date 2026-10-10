import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/screens/hub_screens.dart';
import 'package:movie_app/theme.dart';

/// Контраст по WCAG: 1 — одинаковые цвета, 21 — чёрное на белом.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Полупрозрачный цвет поверх фона — то, что реально видит глаз.
Color over(Color top, Color bottom) => Color.alphaBlend(top, bottom);

void main() {
  tearDown(() => AppTheme.notifier.value = AppThemeId.glass);

  for (final spec in AppTheme.specs.values) {
    group('Тема «${spec.name}»', () {
      setUp(() => AppTheme.notifier.value = spec.id);

      test('токены берутся из текущей темы', () {
        expect(AppColors.bg, spec.bg);
        expect(AppColors.gold, spec.accent);
        expect(AppRadius.medium, spec.radiusMedium);
      });

      test('основной текст читается на фоне и на карточке', () {
        final card = over(spec.surface, spec.bg);
        expect(contrast(over(spec.text, card), card), greaterThan(7));
        expect(contrast(over(spec.textDim, card), card), greaterThan(3));
      });

      test('текст на главной кнопке читается', () {
        expect(contrast(spec.buttonFg, spec.buttonBg), greaterThan(4.5));
        expect(contrast(spec.onAccent, spec.accent), greaterThan(4.5));
      });

      test('карточка не нарушает правила BoxDecoration', () {
        final deco = cardDecoration(highlighted: true);
        // Неравномерная рамка (линейка сверху) несовместима со скруглением.
        if (deco.border is Border && !(deco.border as Border).isUniform) {
          expect(deco.borderRadius, isNull);
        }
      });

      test('тема Material собирается', () {
        final theme = buildAppTheme();
        expect(theme.brightness, spec.brightness);
        // У «Классики» свой шрифт не задан — Flutter берёт системный.
        if (spec.displayFont != null) {
          expect(theme.textTheme.headlineMedium?.fontFamily, spec.displayFont);
        }
      });

      test('надписи на ярких карточках читаются', () {
        for (final tone in FeatureTone.values) {
          final colors = featureColors(tone);
          final base = over(colors.first, spec.bg);
          expect(contrast(featureForeground(colors), base), greaterThan(4.5), reason: tone.name);
        }
      });
    });
  }

  test('у каждой темы свои название и описание', () {
    final names = AppTheme.specs.values.map((s) => s.name).toSet();
    expect(names, hasLength(AppTheme.specs.length));
    expect(AppTheme.specs.values.every((s) => s.hint.isNotEmpty), isTrue);
  });
}
