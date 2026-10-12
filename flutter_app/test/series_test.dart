import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/series.dart';

UpcomingEpisode episodeOn(DateTime air) => UpcomingEpisode(
      showId: 1,
      title: 'Сериал',
      season: 3,
      episode: 4,
      airDate: DateTime(air.year, air.month, air.day),
    );

void main() {
  final now = DateTime(2026, 10, 12, 21, 30);

  test('подпись даты выхода серии', () {
    expect(episodeOn(DateTime(2026, 10, 12)).whenLabel(now), 'Сегодня');
    expect(episodeOn(DateTime(2026, 10, 13)).whenLabel(now), 'Завтра');
    expect(episodeOn(DateTime(2026, 10, 17)).whenLabel(now), 'Через 5 дней');
    expect(episodeOn(DateTime(2026, 10, 14)).whenLabel(now), 'Через 2 дня');
    expect(episodeOn(DateTime(2026, 10, 11)).whenLabel(now), 'Вышла вчера');
    expect(episodeOn(DateTime(2026, 10, 9)).whenLabel(now), 'Вышла 3 дня назад');
  });

  test('переход через месяц считается по календарным дням', () {
    final late = DateTime(2026, 10, 31, 23, 59);
    expect(episodeOn(DateTime(2026, 11, 1)).whenLabel(late), 'Завтра');
  });

  test('склонение дней', () {
    expect(daysWord(1), 'день');
    expect(daysWord(3), 'дня');
    expect(daysWord(5), 'дней');
    expect(daysWord(11), 'дней');
    expect(daysWord(21), 'день');
    expect(daysWord(24), 'дня');
  });

  test('серия с сервера разбирается, без даты — пропускается', () {
    final ok = UpcomingEpisode.tryParse({
      'show_id': 42,
      'title': 'Сериал',
      'season': 2,
      'episode': 5,
      'air_date': '2026-10-13',
      'watching': true,
    });
    expect(ok, isNotNull);
    expect(ok!.code, 'S2E5');
    expect(ok.watching, isTrue);
    expect(UpcomingEpisode.tryParse({'show_id': 1, 'air_date': null}), isNull);
  });

  test('заглушки вроде «Эпизод 1» не показываются', () {
    UpcomingEpisode named(String n) =>
        UpcomingEpisode(showId: 1, title: 'С', season: 1, episode: 1, name: n, airDate: DateTime(2026));
    expect(named('Эпизод 1').realName, '');
    expect(named('Episode 12').realName, '');
    expect(named('Серия 3').realName, '');
    expect(named('Пилот').realName, 'Пилот');
    expect(named('Эпизод с котом').realName, 'Эпизод с котом');
  });

  test('прогресс переживает сохранение в кэш', () {
    const p = TvProgress(showId: 7, title: 'Сериал', season: 2, episode: 5, source: 'vidsrc');
    final back = TvProgress.fromJson(p.toJson());
    expect(back.showId, 7);
    expect(back.code, 'S2E5');
    expect(back.source, 'vidsrc');
    expect(back.copyWith(episode: 6).code, 'S2E6');
  });
}
