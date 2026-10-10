import 'json.dart';

/// Жанр из /genres или студия/сеть из /studios — у обоих одинаковая форма
/// «id + название», поэтому и модель одна.
class CatalogOption {
  final int id;
  final String name;

  const CatalogOption({required this.id, required this.name});

  factory CatalogOption.fromJson(Map<String, dynamic> j) =>
      CatalogOption(id: asInt(j['id']), name: asString(j['name']));

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  @override
  bool operator ==(Object other) =>
      other is CatalogOption && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// Страна производства. Список фиксированный — тот же, что в фильтрах на сайте
/// (COUNTRY_OPTIONS в frontend/app.js).
class CountryOption {
  final String code;
  final String flag;
  final String name;

  const CountryOption(this.code, this.flag, this.name);

  String get label => '$flag $name';

  static const all = <CountryOption>[
    CountryOption('US', '🇺🇸', 'США'),
    CountryOption('GB', '🇬🇧', 'Великобритания'),
    CountryOption('FR', '🇫🇷', 'Франция'),
    CountryOption('DE', '🇩🇪', 'Германия'),
    CountryOption('IT', '🇮🇹', 'Италия'),
    CountryOption('JP', '🇯🇵', 'Япония'),
    CountryOption('KR', '🇰🇷', 'Южная Корея'),
    CountryOption('RU', '🇷🇺', 'Россия'),
    CountryOption('IN', '🇮🇳', 'Индия'),
    CountryOption('ES', '🇪🇸', 'Испания'),
    CountryOption('CN', '🇨🇳', 'Китай'),
    CountryOption('SE', '🇸🇪', 'Швеция'),
    CountryOption('AU', '🇦🇺', 'Австралия'),
    CountryOption('TR', '🇹🇷', 'Турция'),
  ];

  static CountryOption? byCode(String code) {
    for (final c in all) {
      if (c.code == code) return c;
    }
    return null;
  }
}

/// Категории списка «к просмотру» — те же три, что на сайте.
class WatchlistCategory {
  final String value;
  final String label;
  final String emoji;

  const WatchlistCategory(this.value, this.emoji, this.label);

  static const mustSee = WatchlistCategory('must_see', '🔥', 'Обязательно');
  static const notSure = WatchlistCategory('not_sure', '🤔', 'Под вопросом');
  static const lastResort = WatchlistCategory('last_resort', '🥱', 'На безрыбье');

  static const all = [mustSee, notSure, lastResort];

  static WatchlistCategory? byValue(String? value) {
    if (value == null) return null;
    for (final c in all) {
      if (c.value == value) return c;
    }
    return null;
  }
}
