import '../core/api_client.dart';
import '../models/book.dart';
import '../models/json.dart';
import '../models/movie.dart';
import '../models/profile_stats.dart';
import '../models/wrapped.dart';
import 'local_first_repository.dart';

/// Профиль: числовая статистика по просмотренному и разбор вкуса от AI.
///
/// Разделены намеренно. Статистика считается из своей же базы, её не жалко
/// показывать из кэша и обновлять при каждом заходе. Анализ — платный вызов
/// к внешней модели, поэтому он запускается только по кнопке и живёт в кэше
/// до тех пор, пока пользователь не попросит новый.
class ProfileRepository extends LocalFirstRepository {
  ProfileRepository({required super.api, required super.session});

  ProfileStats? _stats;
  ProfileStats? get stats => _stats;

  String? _analysis;
  String? get analysis => _analysis;

  bool _analyzing = false;
  bool get analyzing => _analyzing;

  String? _analysisError;
  String? get analysisError => _analysisError;

  DateTime? get analyzedAt => syncedAt(_analysisKey);

  String get _statsKey => cacheKey('profile::stats');
  String get _analysisKey => cacheKey('profile::analysis');

  Future<void> load({bool forceRefresh = false}) async {
    _readFromCache();
    notifyListeners();
    if (forceRefresh || isStale(_statsKey)) await refresh();
  }

  void _readFromCache() {
    final cachedStats = readCache(_statsKey);
    _stats = cachedStats.isEmpty ? null : ProfileStats.fromJson(cachedStats.first);

    final cachedAnalysis = readCache(_analysisKey);
    _analysis = cachedAnalysis.isEmpty ? null : cachedAnalysis.first['analysis'] as String?;
  }

  Future<void> refresh() => runSync(() async {
        final data = await api.get('/profile/stats');
        final map = Map<String, dynamic>.from(data as Map);
        await writeCache(_statsKey, [map], fromServer: true);
        _stats = ProfileStats.fromJson(map);
      });

  /// Разбор вкуса. Требует минимум трёх отмеченных фильмов — иначе бэкенд
  /// отвечает 400 с понятным текстом, который мы и показываем.
  Future<void> analyze() async {
    if (_analyzing) return;
    _analyzing = true;
    _analysisError = null;
    notifyListeners();

    try {
      final data = await api.get('/profile/analyze');
      final text = data is Map ? '${data['analysis'] ?? ''}' : '';
      if (text.isEmpty) {
        _analysisError = 'AI вернул пустой ответ — попробуй ещё раз';
      } else {
        _analysis = text;
        await writeCache(_analysisKey, [
          {'analysis': text}
        ], fromServer: true);
      }
    } on ApiException catch (e) {
      _analysisError = e.message;
    } finally {
      _analyzing = false;
      notifyListeners();
    }
  }

  // ─── ✦ Посоветуй ────────────────────────────────────────────────────

  /// Подборка от AI под свободный запрос («что-нибудь медленное и осеннее»).
  /// Пустой запрос — «на своё усмотрение», как и на сайте.
  ///
  /// Каждая карточка несёт `ai_reason` — объяснение, почему это предложено.
  Future<List<Movie>> suggestMovies({String query = ''}) async {
    final data = await api.get('/ai/suggest', query: {
      if (query.trim().isNotEmpty) 'query': query.trim(),
    });
    final list = data is Map ? (data['movies'] as List? ?? const []) : const [];
    return list
        .whereType<Map>()
        .map((e) => Movie.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// «Что посмотреть вечером»: настроение, свободное время и компания.
  ///
  /// [maxMinutes] = 0 — без ограничения по времени. [kind] — any | movie | tv.
  Future<List<TonightPick>> suggestTonight({
    String mood = '',
    int maxMinutes = 0,
    String company = '',
    String kind = 'any',
  }) async {
    final data = await api.get('/ai/tonight', query: {
      if (mood.trim().isNotEmpty) 'mood': mood.trim(),
      if (maxMinutes > 0) 'max_minutes': '$maxMinutes',
      if (company.trim().isNotEmpty) 'company': company.trim(),
      'kind': kind,
    });
    final list = data is Map ? (data['movies'] as List? ?? const []) : const [];
    return list.whereType<Map>().map((e) {
      final map = Map<String, dynamic>.from(e);
      return TonightPick(movie: Movie.fromJson(map), runtime: asIntOrNull(map['runtime']));
    }).toList();
  }

  // ─── Итоги года ─────────────────────────────────────────────────────

  String _wrappedKey(int year) => cacheKey('wrapped::$year');

  /// Итоги из кэша — чтобы экран открывался сразу, а свежие подтягивались.
  Wrapped? cachedWrapped(int year) {
    final cached = readCache(_wrappedKey(year));
    return cached.isEmpty ? null : Wrapped.fromJson(cached.first);
  }

  /// Итоги с сервера. Ошибку сети пробрасываем: экран покажет кэш и текст.
  Future<Wrapped> fetchWrapped(int year) async {
    final data = await api.get('/wrapped', query: {'year': '$year'});
    final map = Map<String, dynamic>.from(data as Map);
    await writeCache(_wrappedKey(year), [map], fromServer: true);
    return Wrapped.fromJson(map);
  }

  /// То же самое для книг — отдельный эндпоинт, отдельная модель ответа.
  Future<List<Book>> suggestBooks({String query = ''}) async {
    final data = await api.get('/books/suggest', query: {'query': query.trim()});
    final list = data is Map ? (data['books'] as List? ?? const []) : const [];
    return list
        .whereType<Map>()
        .map((e) => Book.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}

/// Фильм на вечер и его длительность (минуты, у сериала — серия).
class TonightPick {
  final Movie movie;
  final int? runtime;

  const TonightPick({required this.movie, this.runtime});

  /// «1 ч 28 мин» или «42 мин».
  String? get runtimeLabel {
    final m = runtime;
    if (m == null || m <= 0) return null;
    if (m < 60) return '$m мин';
    final rest = m % 60;
    return rest == 0 ? '${m ~/ 60} ч' : '${m ~/ 60} ч $rest мин';
  }
}
