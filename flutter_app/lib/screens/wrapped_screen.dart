import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../data/profile_repository.dart';
import '../models/wrapped.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// «Итоги года» — истории в духе Spotify Wrapped: одна мысль на экран.
///
/// Листается свайпом или нажатием на правую/левую часть экрана. Слайды без
/// данных пропускаются: если книг в этом году не было, книжного слайда нет.
class WrappedScreen extends StatefulWidget {
  final int? year;

  const WrappedScreen({super.key, this.year});

  @override
  State<WrappedScreen> createState() => _WrappedScreenState();
}

class _WrappedScreenState extends State<WrappedScreen> {
  late int _year = widget.year ?? DateTime.now().year;
  Wrapped? _data;
  bool _loading = false;
  String? _error;

  final _pages = PageController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = context.read<ProfileRepository>();
    setState(() {
      _data = repo.cachedWrapped(_year);
      _loading = true;
      _error = null;
      _page = 0;
    });
    if (_pages.hasClients) _pages.jumpToPage(0);
    try {
      final fresh = await repo.fetchWrapped(_year);
      if (mounted) setState(() => _data = fresh);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changeYear(int delta) {
    final next = _year + delta;
    if (next > DateTime.now().year) return;
    _year = next;
    _load();
  }

  void _go(int delta, int count) {
    final target = (_page + delta).clamp(0, count - 1);
    if (target == _page) {
      if (delta > 0) Navigator.of(context).maybePop();
      return;
    }
    _pages.animateToPage(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final slides = _buildSlides(_data);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: slides.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => LayoutBuilder(
              builder: (context, box) => GestureDetector(
                behavior: HitTestBehavior.translucent,
                // Как в историях: левая треть — назад, остальное — вперёд.
                onTapUp: (d) =>
                    _go(d.localPosition.dx < box.maxWidth / 3 ? -1 : 1, slides.length),
                child: slides[i],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 0),
              child: Column(
                children: [
                  _ProgressBars(count: slides.length, index: _page),
                  Row(
                    children: [
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                          ),
                        ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Закрыть',
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSlides(Wrapped? d) {
    final intro = _IntroSlide(
      year: _year,
      title: d?.title,
      loading: d == null && _loading,
      error: d == null ? _error : null,
      onPrevYear: () => _changeYear(-1),
      onNextYear: _year < DateTime.now().year ? () => _changeYear(1) : null,
      empty: d != null && !d.hasData,
    );
    if (d == null || !d.hasData) return [intro];

    return [
      intro,
      if (d.cinema.total > 0) _CinemaSlide(d.cinema),
      if (d.cinema.topGenres.isNotEmpty) _GenresSlide(d.cinema),
      if (d.cinema.topRated.isNotEmpty) _TopRatedSlide(d.cinema),
      if (d.cinema.topActors.isNotEmpty) _ActorsSlide(d.cinema),
      if (d.reading.count > 0) _BooksSlide(d.reading),
      if (d.travel.count > 0) _TravelSlide(d.travel),
      if (d.money.total > 0) _MoneySlide(d.money),
      _SummarySlide(d),
    ];
  }
}

// ─── Каркас слайда ──────────────────────────────────────────────────────

/// Фон и отступы, одинаковые для всех слайдов; цвет у каждого свой.
class _Slide extends StatelessWidget {
  final List<Color> colors;
  final Widget child;

  const _Slide({required this.colors, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SizedBox.expand(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 64, 28, 36),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _kicker = TextStyle(
  color: Colors.white70,
  fontSize: 13,
  fontWeight: FontWeight.w700,
  letterSpacing: 1.6,
);

const _headline = TextStyle(
  color: Colors.white,
  fontSize: 30,
  fontWeight: FontWeight.w800,
  height: 1.15,
  letterSpacing: -0.6,
);

const _body = TextStyle(color: Colors.white, fontSize: 16, height: 1.45);

Widget _huge(String text, {Color color = Colors.white}) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 104,
          fontWeight: FontWeight.w900,
          height: 1,
          letterSpacing: -4,
        ),
      ),
    );

/// 12345 → «12 345».
String _thousands(int n) => formatMoney(n).replaceAll(' ₽', '');

String _plural(int n, String one, String few, String many) {
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 14) return many;
  switch (n % 10) {
    case 1:
      return one;
    case 2:
    case 3:
    case 4:
      return few;
    default:
      return many;
  }
}

/// Горизонтальная полоса «название — значение», ширина по доле от максимума.
class _Bar extends StatelessWidget {
  final String label;
  final String value;
  final double share;
  final Color color;

  const _Bar({required this.label, required this.value, required this.share, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              Text(value, style: const TextStyle(color: Colors.white70, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, box) => TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: share.clamp(0.04, 1.0)),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Container(
                height: 10,
                width: box.maxWidth * v,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Двенадцать столбиков по месяцам — подсвечен самый насыщенный.
class _MonthBars extends StatelessWidget {
  final List<int> values;
  final Color color;

  const _MonthBars({required this.values, required this.color});

  static const _letters = ['Я', 'Ф', 'М', 'А', 'М', 'И', 'И', 'А', 'С', 'О', 'Н', 'Д'];

  @override
  Widget build(BuildContext context) {
    final list = values.length == 12 ? values : List.filled(12, 0);
    final max = list.fold<int>(0, (a, b) => a > b ? a : b);
    return SizedBox(
      height: 96,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 12; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: max == 0 ? 2 : 2 + 70 * list[i] / max,
                      decoration: BoxDecoration(
                        color: list[i] == max && max > 0 ? color : color.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(_letters[i], style: const TextStyle(color: Colors.white60, fontSize: 11)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Слайды ─────────────────────────────────────────────────────────────

class _IntroSlide extends StatelessWidget {
  final int year;
  final String? title;
  final bool loading;
  final bool empty;
  final String? error;
  final VoidCallback onPrevYear;
  final VoidCallback? onNextYear;

  const _IntroSlide({
    required this.year,
    required this.title,
    required this.loading,
    required this.empty,
    required this.error,
    required this.onPrevYear,
    required this.onNextYear,
  });

  @override
  Widget build(BuildContext context) {
    return _Slide(
      colors: const [Color(0xFF2A1F05), Color(0xFF0B0B10), Color(0xFF1A1030)],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onPrevYear,
                icon: const Icon(Icons.chevron_left, color: Colors.white70),
              ),
              Text('$year', style: _kicker),
              IconButton(
                onPressed: onNextYear,
                icon: Icon(
                  Icons.chevron_right,
                  color: onNextYear == null ? Colors.white24 : Colors.white70,
                ),
              ),
            ],
          ),
          const Spacer(),
          const Text('🐒', style: TextStyle(fontSize: 54)),
          const SizedBox(height: 18),
          const Text('Твои итоги', style: _headline),
          _huge('$year', color: AppColors.gold),
          const SizedBox(height: 18),
          if (loading)
            const Text('Собираем твой год…', style: _body)
          else if (error != null)
            Text('Не получилось загрузить: $error', style: _body)
          else if (empty)
            const Text(
              'В этом году пока нечего подводить — отмечай фильмы, книги и траты, '
              'и здесь появится твой год.',
              style: _body,
            )
          else if (title != null) ...[
            const Text('Твоё звание года', style: _kicker),
            const SizedBox(height: 6),
            Text('«$title»', style: _headline.copyWith(color: AppColors.gold)),
          ],
          const Spacer(),
          if (!loading && !empty && error == null)
            const Row(
              children: [
                Text('Листай', style: TextStyle(color: Colors.white60, fontSize: 14)),
                SizedBox(width: 6),
                Icon(Icons.arrow_forward, color: Colors.white60, size: 18),
              ],
            ),
        ],
      ),
    );
  }
}

class _CinemaSlide extends StatelessWidget {
  final WrappedCinema c;

  const _CinemaSlide(this.c);

  @override
  Widget build(BuildContext context) {
    return _Slide(
      colors: const [Color(0xFF3A0D1E), Color(0xFF12060B)],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('КИНО', style: _kicker),
          const Spacer(),
          const Text('За год ты посмотрел', style: _headline),
          _huge('${c.total}', color: const Color(0xFFFF6B8B)),
          Text(
            '${c.movies} ${_plural(c.movies, 'фильм', 'фильма', 'фильмов')} и '
            '${c.shows} ${_plural(c.shows, 'сериал', 'сериала', 'сериалов')}',
            style: _body.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          if (c.avgRating != null) ...[
            const SizedBox(height: 8),
            Text('Средняя оценка — ${c.avgRating!.toStringAsFixed(1)}', style: _body),
          ],
          const Spacer(),
          if (c.busiestMonth != null) ...[
            Text(
              'Самый киношный месяц — ${c.busiestMonth!.name}: ${c.busiestMonth!.value}',
              style: _body,
            ),
            const SizedBox(height: 14),
          ],
          _MonthBars(values: c.monthly, color: const Color(0xFFFF6B8B)),
        ],
      ),
    );
  }
}

class _GenresSlide extends StatelessWidget {
  final WrappedCinema c;

  const _GenresSlide(this.c);

  @override
  Widget build(BuildContext context) {
    final top = c.topGenres;
    final max = top.first.count;
    return _Slide(
      colors: const [Color(0xFF0D2A3A), Color(0xFF060E14)],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ЖАНРЫ', style: _kicker),
          const Spacer(),
          const Text('Больше всего тебя тянуло на', style: _body),
          const SizedBox(height: 6),
          Text(top.first.name.toLowerCase(), style: _headline.copyWith(fontSize: 44)),
          const SizedBox(height: 28),
          for (final g in top)
            _Bar(
              label: g.name,
              value: '${g.count}',
              share: g.count / max,
              color: const Color(0xFF4FC3F7),
            ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _TopRatedSlide extends StatelessWidget {
  final WrappedCinema c;

  const _TopRatedSlide(this.c);

  @override
  Widget build(BuildContext context) {
    final best = c.topRated.first;
    final rest = c.topRated.skip(1).take(4).toList();
    return _Slide(
      colors: const [Color(0xFF2B2205), Color(0xFF0C0A04)],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ЛУЧШЕЕ', style: _kicker),
          const SizedBox(height: 18),
          const Text('Фильм года по твоей версии', style: _body),
          const SizedBox(height: 8),
          Text(best.title, style: _headline, maxLines: 2, overflow: TextOverflow.ellipsis),
          Text('${best.rating} / 10', style: _headline.copyWith(color: AppColors.gold)),
          const SizedBox(height: 18),
          Expanded(
            flex: 3,
            child: _Poster(url: best.posterUrl),
          ),
          if (rest.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text('А ещё', style: _kicker),
            const SizedBox(height: 10),
            Expanded(
              flex: 1,
              child: Row(
                children: [
                  for (final t in rest)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _Poster(url: t.posterUrl, badge: '${t.rating}'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  final String? url;
  final String? badge;

  const _Poster({required this.url, this.badge});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: url == null
                ? Container(
                    color: Colors.white10,
                    alignment: Alignment.center,
                    child: const Text('🎬', style: TextStyle(fontSize: 28)),
                  )
                : CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover),
          ),
          if (badge != null)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActorsSlide extends StatelessWidget {
  final WrappedCinema c;

  const _ActorsSlide(this.c);

  @override
  Widget build(BuildContext context) {
    final actors = c.topActors.take(3).toList();
    return _Slide(
      colors: const [Color(0xFF1E0D3A), Color(0xFF09060F)],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('АКТЁРЫ', style: _kicker),
          const Spacer(),
          const Text('Чаще всего на твоём экране', style: _body),
          const SizedBox(height: 6),
          Text(actors.first.name, style: _headline.copyWith(fontSize: 36)),
          const SizedBox(height: 28),
          for (var i = 0; i < actors.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Text('${i + 1}', style: _headline.copyWith(color: const Color(0xFFB39DFF))),
                  const SizedBox(width: 16),
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white10,
                    backgroundImage: actors[i].imageUrl == null
                        ? null
                        : CachedNetworkImageProvider(actors[i].imageUrl!),
                    child: actors[i].imageUrl == null
                        ? const Icon(Icons.person, color: Colors.white54)
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          actors[i].name,
                          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${actors[i].count} ${_plural(actors[i].count, 'фильм', 'фильма', 'фильмов')} с ним',
                          style: const TextStyle(color: Colors.white60, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (c.topDirectors.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Любимый режиссёр — ${c.topDirectors.first.name}',
              style: _body.copyWith(color: Colors.white70),
            ),
          ],
          const Spacer(),
        ],
      ),
    );
  }
}

class _BooksSlide extends StatelessWidget {
  final WrappedReading r;

  const _BooksSlide(this.r);

  @override
  Widget build(BuildContext context) {
    return _Slide(
      colors: const [Color(0xFF0D3A24), Color(0xFF05120B)],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('КНИГИ', style: _kicker),
          const Spacer(),
          const Text('Прочитано', style: _headline),
          _huge('${r.count}', color: const Color(0xFF6EE7A8)),
          Text(_plural(r.count, 'книга', 'книги', 'книг'), style: _body.copyWith(fontSize: 20)),
          if (r.pages > 0) ...[
            const SizedBox(height: 10),
            Text(
              'Это ${_thousands(r.pages)} страниц — '
              'примерно ${(r.pages / 30).round()} ${_plural((r.pages / 30).round(), 'вечер', 'вечера', 'вечеров')} за книгой',
              style: _body,
            ),
          ],
          const Spacer(),
          if (r.topAuthors.isNotEmpty)
            Text('Любимый автор — ${r.topAuthors.first.name}', style: _body),
          if (r.topRated.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Лучшая книга — «${r.topRated.first.title}» (${r.topRated.first.rating}/10)',
              style: _body,
            ),
          ],
        ],
      ),
    );
  }
}

class _TravelSlide extends StatelessWidget {
  final WrappedTravel t;

  const _TravelSlide(this.t);

  @override
  Widget build(BuildContext context) {
    return _Slide(
      colors: const [Color(0xFF0D2140), Color(0xFF050A14)],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ПУТЕШЕСТВИЯ', style: _kicker),
          const SizedBox(height: 20),
          Text(
            '${t.days} ${_plural(t.days, 'день', 'дня', 'дней')} в пути',
            style: _headline.copyWith(fontSize: 38),
          ),
          Text(
            '${t.count} ${_plural(t.count, 'место', 'места', 'мест')} на карте года',
            style: _body,
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: t.places.length,
              itemBuilder: (context, i) {
                final p = t.places[i];
                final last = i == t.places.length - 1;
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Линия маршрута с точками — как на карте метро.
                      SizedBox(
                        width: 22,
                        child: Column(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              margin: const EdgeInsets.only(top: 4),
                              decoration: const BoxDecoration(
                                color: Color(0xFF64B5F6),
                                shape: BoxShape.circle,
                              ),
                            ),
                            if (!last)
                              Expanded(child: Container(width: 2, color: Colors.white24)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.name,
                                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                              ),
                              Text(
                                [
                                  if (p.trip != null) p.trip!,
                                  _dates(p.startDate, p.endDate),
                                  if (p.spent > 0) formatMoney(p.spent),
                                ].where((s) => s.isNotEmpty).join('  ·  '),
                                style: const TextStyle(color: Colors.white60, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (t.spent > 0) Text('На поездки ушло ${formatMoney(t.spent)}', style: _body),
        ],
      ),
    );
  }

  static const _months = [
    'янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];

  static String _dates(String from, String to) {
    final a = DateTime.tryParse(from);
    final b = DateTime.tryParse(to);
    if (a == null) return '';
    String d(DateTime x) => '${x.day} ${_months[x.month - 1]}';
    if (b == null || b == a) return d(a);
    final lo = a.isBefore(b) ? a : b;
    final hi = a.isBefore(b) ? b : a;
    return '${d(lo)} – ${d(hi)}';
  }
}

class _MoneySlide extends StatelessWidget {
  final WrappedMoney m;

  const _MoneySlide(this.m);

  @override
  Widget build(BuildContext context) {
    final cats = m.byCategory.take(5).toList();
    final max = cats.isEmpty ? 1 : cats.first.amount;
    return _Slide(
      colors: const [Color(0xFF3A2A0D), Color(0xFF120D05)],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ДЕНЬГИ', style: _kicker),
          const SizedBox(height: 20),
          const Text('Через твои руки прошло', style: _body),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(formatMoney(m.total), style: _headline.copyWith(fontSize: 52, color: AppColors.gold)),
          ),
          const SizedBox(height: 26),
          for (final c in cats)
            _Bar(
              label: '${c.emoji} ${c.name}',
              value: formatMoney(c.amount),
              share: max == 0 ? 0 : c.amount / max,
              color: AppColors.gold,
            ),
          const Spacer(),
          if (m.topMerchant != null)
            Text(
              'Чаще всего — «${m.topMerchant}»: ${m.topMerchantCount} '
              '${_plural(m.topMerchantCount, 'раз', 'раза', 'раз')}',
              style: _body,
            ),
          if (m.biggestMonth != null) ...[
            const SizedBox(height: 6),
            Text(
              'Самый дорогой месяц — ${m.biggestMonth!.name} (${formatMoney(m.biggestMonth!.value)})',
              style: _body,
            ),
          ],
        ],
      ),
    );
  }
}

class _SummarySlide extends StatelessWidget {
  final Wrapped d;

  const _SummarySlide(this.d);

  @override
  Widget build(BuildContext context) {
    final tiles = <(String, String)>[
      if (d.cinema.total > 0) ('${d.cinema.total}', 'фильмов и сериалов'),
      if (d.reading.count > 0) ('${d.reading.count}', _plural(d.reading.count, 'книга', 'книги', 'книг')),
      if (d.travel.days > 0) ('${d.travel.days}', 'дней в пути'),
      if (d.cinema.topGenres.isNotEmpty) (d.cinema.topGenres.first.name, 'любимый жанр'),
      if (d.cinema.topActors.isNotEmpty) (d.cinema.topActors.first.name, 'актёр года'),
      if (d.money.byCategory.isNotEmpty) (d.money.byCategory.first.name, 'главная статья трат'),
    ];

    return _Slide(
      colors: const [Color(0xFF1A1405), Color(0xFF08080C), Color(0xFF14081E)],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${d.year} В ЦИФРАХ', style: _kicker),
          const SizedBox(height: 10),
          Text('«${d.title}»', style: _headline.copyWith(color: AppColors.gold)),
          const SizedBox(height: 24),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.45,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final t in tiles)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            t.$1,
                            style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(t.$2, style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: d.toShareText()));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Итоги скопированы — вставь в любой мессенджер'),
                ));
              },
              icon: const Icon(Icons.ios_share, size: 19),
              label: const Text('Поделиться итогами'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Полоски-индикаторы сверху, как в историях.
class _ProgressBars extends StatelessWidget {
  final int count;
  final int index;

  const _ProgressBars({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 3,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: i <= index ? Colors.white : Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ],
    );
  }
}
