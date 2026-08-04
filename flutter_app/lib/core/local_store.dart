import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Локальное хранилище — «маленькая база на устройстве».
///
/// Хранит JSON-снимки серверных данных и время их последнего обновления.
/// Чтение синхронное и мгновенное: экраны рисуются из кэша до того,
/// как уйдёт хоть один сетевой запрос.
///
/// Сейчас под капотом shared_preferences (localStorage в вебе,
/// нативное key-value на Android/Windows). Интерфейс намеренно узкий,
/// чтобы позже подменить его на SQLite без правок в остальном коде.
class LocalStore {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static SharedPreferences get _p {
    final p = _prefs;
    if (p == null) {
      throw StateError('LocalStore.init() должен быть вызван до использования');
    }
    return p;
  }

  // ─── Списки объектов ────────────────────────────────────────────────

  /// Мгновенное чтение закэшированного списка. null — кэша ещё нет.
  static List<Map<String, dynamic>>? readList(String key) {
    final raw = _p.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      // Повреждённый кэш не должен ронять приложение — просто считаем, что его нет.
      return null;
    }
  }

  /// [fromServer] — данные только что пришли с сервера, значит это и есть
  /// момент последней синхронизации. Локальные правки отметку не двигают:
  /// иначе своя же оценка «продлевала» бы свежесть кэша и откладывала
  /// следующий поход за чужими изменениями.
  static Future<void> writeList(
    String key,
    List<dynamic> value, {
    bool fromServer = false,
  }) async {
    await _p.setString(key, jsonEncode(value));
    if (fromServer) await _touch(key);
  }

  // ─── Отдельные объекты ──────────────────────────────────────────────

  static Map<String, dynamic>? readMap(String key) {
    final raw = _p.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeMap(
    String key,
    Map<String, dynamic> value, {
    bool fromServer = false,
  }) async {
    await _p.setString(key, jsonEncode(value));
    if (fromServer) await _touch(key);
  }

  static Future<void> remove(String key) async {
    await _p.remove(key);
    await _p.remove(_syncKey(key));
  }

  /// Стереть всё локальное состояние (выход из аккаунта).
  static Future<void> clear() => _p.clear();

  // ─── Время последнего ответа сервера ────────────────────────────────

  static String _syncKey(String key) => '$key::synced_at';

  static Future<void> _touch(String key) =>
      _p.setInt(_syncKey(key), DateTime.now().millisecondsSinceEpoch);

  static DateTime? syncedAt(String key) {
    final ms = _p.getInt(_syncKey(key));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Свежесть считается от последнего ответа сервера, а не от последней
  /// правки на устройстве. На этом строится «раз в 30 минут»: чаще в сеть
  /// не ходим, но и реже — тоже, сколько бы своих правок ни сделали.
  static bool isFresh(String key, Duration maxAge) {
    final at = syncedAt(key);
    if (at == null) return false;
    return DateTime.now().difference(at) < maxAge;
  }
}
