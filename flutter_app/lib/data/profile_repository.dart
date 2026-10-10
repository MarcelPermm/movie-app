import '../core/api_client.dart';
import '../models/book.dart';
import '../models/movie.dart';
import '../models/profile_stats.dart';
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
