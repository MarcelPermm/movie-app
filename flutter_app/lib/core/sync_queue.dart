import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'local_store.dart';

/// Одна отложенная запись на сервер.
class PendingOp {
  final String method; // POST / PATCH / PUT / DELETE
  final String path;
  final Map<String, dynamic>? body;
  final Map<String, String>? query;
  final int createdAt;

  PendingOp({
    required this.method,
    required this.path,
    this.body,
    this.query,
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'method': method,
        'path': path,
        'body': body,
        'query': query,
        'createdAt': createdAt,
      };

  static PendingOp fromJson(Map<String, dynamic> j) => PendingOp(
        method: j['method'] as String,
        path: j['path'] as String,
        body: (j['body'] as Map?)?.cast<String, dynamic>(),
        query: (j['query'] as Map?)?.cast<String, String>(),
        createdAt: j['createdAt'] as int?,
      );
}

/// Очередь исходящих изменений — то, что делает приложение по-настоящему
/// быстрым и работающим офлайн.
///
/// Экран меняет данные локально и мгновенно перерисовывается, а сам запрос
/// кладётся сюда. Очередь разгребается в фоне: при старте, после каждого
/// удачного запроса и при следующей синхронизации. Пользователь не ждёт сеть.
class SyncQueue {
  static const _key = 'sync::outbox';
  static bool _flushing = false;

  static List<PendingOp> _read() {
    final raw = LocalStore.readList(_key) ?? const [];
    return raw.map(PendingOp.fromJson).toList();
  }

  static Future<void> _write(List<PendingOp> ops) =>
      LocalStore.writeList(_key, ops.map((o) => o.toJson()).toList());

  static int get pendingCount => _read().length;

  static Future<void> enqueue(PendingOp op) async {
    final ops = _read()..add(op);
    await _write(ops);
  }

  /// Отправить всё накопившееся по порядку.
  ///
  /// Порядок важен: «добавил в список» должно уйти раньше, чем «удалил из списка».
  /// Поэтому при сетевой ошибке останавливаемся и ждём следующей попытки,
  /// а на ошибке сервера (4xx) операцию выбрасываем — она не станет валидной.
  static Future<void> flush(ApiClient api) async {
    if (_flushing) return;
    _flushing = true;
    try {
      var ops = _read();
      while (ops.isNotEmpty) {
        final op = ops.first;
        try {
          await api.send(
            op.method,
            op.path,
            body: op.body,
            query: op.query,
            queueOnFailure: false,
          );
        } on ApiException catch (e) {
          if (e.isNetworkError) break; // сети нет — попробуем позже
          debugPrint('SyncQueue: операция отброшена (${e.statusCode}) ${op.method} ${op.path}');
        } catch (e) {
          debugPrint('SyncQueue: неожиданная ошибка, операция отброшена: $e');
        }
        ops = ops.sublist(1);
        await _write(ops);
      }
    } finally {
      _flushing = false;
    }
  }

  static Future<void> clear() => LocalStore.remove(_key);
}
