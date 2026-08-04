import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/config.dart';
import '../core/local_store.dart';
import '../core/session.dart';
import '../core/sync_queue.dart';

/// Общая механика local-first для всех разделов.
///
/// Каждый репозиторий поверх неё описывает только свои данные, а правила
/// одни на всех:
///   1. читаем из кэша синхронно, до любых запросов;
///   2. в сеть идём, только если кэш устарел;
///   3. пишем сначала локально, запрос уходит следом.
abstract class LocalFirstRepository extends ChangeNotifier {
  final ApiClient api;
  final Session session;

  LocalFirstRepository({required this.api, required this.session});

  bool _syncing = false;
  String? _lastError;

  bool get syncing => _syncing;
  String? get lastError => _lastError;
  int get pendingWrites => SyncQueue.pendingCount;

  /// Ключи разделены по пользователям, чтобы чужие данные не смешивались.
  String cacheKey(String name) => 'cache::$name::u${session.userId}';

  List<Map<String, dynamic>> readCache(String key) => LocalStore.readList(key) ?? const [];

  Future<void> writeCache(String key, List<dynamic> value, {bool fromServer = false}) =>
      LocalStore.writeList(key, value, fromServer: fromServer);

  bool isStale(String key) => !LocalStore.isFresh(key, Config.syncInterval);

  DateTime? syncedAt(String key) => LocalStore.syncedAt(key);

  /// Обёртка вокруг похода в сеть: не даёт запускать два обновления разом,
  /// сперва досылает очередь, а обрыв связи не роняет экран — на нём
  /// остаются данные из кэша.
  Future<void> runSync(Future<void> Function() body) async {
    if (_syncing) return;
    _syncing = true;
    _lastError = null;
    notifyListeners();
    try {
      await SyncQueue.flush(api);
      await body();
    } on ApiException catch (e) {
      _lastError = e.message;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Отправка одного изменения. Отсутствие сети уже обработано в ApiClient
  /// (запрос лёг в очередь), поэтому здесь ловим только отказы сервера.
  Future<dynamic> push(
    Future<dynamic> Function() call, {
    VoidCallback? rollback,
    bool ignoreConflict = true,
  }) async {
    try {
      return await call();
    } on ApiException catch (e) {
      // 409 — рассинхрон вроде «уже в списке», лечится следующим обновлением.
      if (ignoreConflict && e.statusCode == 409) return null;
      _lastError = e.message;
      if (rollback != null) {
        rollback();
      }
      notifyListeners();
      return null;
    }
  }

  /// Временный отрицательный id для только что созданной записи.
  ///
  /// Настоящий id генерирует сервер, но UI не должен его ждать: элемент
  /// появляется сразу, а при следующем обновлении заменяется серверным.
  static int nextTempId() => -DateTime.now().millisecondsSinceEpoch;

  static bool isTemp(int id) => id < 0;
}
