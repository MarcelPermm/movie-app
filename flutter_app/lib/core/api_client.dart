import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import 'config.dart';
import 'session.dart';
import 'sync_queue.dart';

class ApiException implements Exception {
  final String message;

  /// null — до сервера не дошли (нет сети, таймаут). Такие запросы можно повторить.
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  bool get isNetworkError => statusCode == null;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// HTTP-клиент к тому же FastAPI, что обслуживает сайт.
///
/// Повторяет поведение apiFetch() из веб-версии: user_id всегда подмешивается
/// и в query-строку, и в тело изменяющих запросов.
class ApiClient {
  final Session session;
  final http.Client _http = http.Client();

  ApiClient(this.session);

  Uri _uri(String path, Map<String, String>? query) {
    final params = <String, String>{...?query};
    final uid = session.userId;
    if (uid != null) params['user_id'] = '$uid';
    return Uri.parse('${Config.apiBaseUrl}$path')
        .replace(queryParameters: params.isEmpty ? null : params);
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      send('GET', path, query: query);

  Future<dynamic> post(String path, {Map<String, dynamic>? body, Map<String, String>? query, bool queueOnFailure = true}) =>
      send('POST', path, body: body, query: query, queueOnFailure: queueOnFailure);

  Future<dynamic> patch(String path, {Map<String, dynamic>? body, Map<String, String>? query, bool queueOnFailure = true}) =>
      send('PATCH', path, body: body, query: query, queueOnFailure: queueOnFailure);

  Future<dynamic> put(String path, {Map<String, dynamic>? body, Map<String, String>? query, bool queueOnFailure = true}) =>
      send('PUT', path, body: body, query: query, queueOnFailure: queueOnFailure);

  Future<dynamic> delete(String path, {Map<String, dynamic>? body, Map<String, String>? query, bool queueOnFailure = true}) =>
      send('DELETE', path, body: body, query: query, queueOnFailure: queueOnFailure);

  /// Единственная точка выхода в сеть.
  ///
  /// [queueOnFailure] — если сети нет, положить запрос в очередь и вернуть
  /// управление сразу. Так изменения не теряются, а UI не блокируется.
  Future<dynamic> send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool queueOnFailure = false,
  }) async {
    final isWrite = method != 'GET';
    final payload = <String, dynamic>{...?body};
    // Тело изменяющих запросов тоже несёт user_id — как на сайте.
    if (isWrite && body != null && session.userId != null) {
      payload.putIfAbsent('user_id', () => session.userId);
    }

    final uri = _uri(path, query);
    final headers = {if (isWrite && body != null) 'Content-Type': 'application/json'};

    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (isWrite && body != null) request.body = jsonEncode(payload);

      final streamed = await _http.send(request).timeout(Config.requestTimeout);
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isEmpty) return null;
        return jsonDecode(utf8.decode(response.bodyBytes));
      }

      throw ApiException(
        _errorMessage(response),
        statusCode: response.statusCode,
      );
    } on ApiException {
      rethrow;
    } on TimeoutException {
      return _handleOffline(method, path, payload, query, queueOnFailure, 'Сервер не ответил вовремя');
    } on SocketException {
      return _handleOffline(method, path, payload, query, queueOnFailure, 'Нет соединения');
    } on http.ClientException {
      return _handleOffline(method, path, payload, query, queueOnFailure, 'Нет соединения');
    }
  }

  Future<dynamic> _handleOffline(
    String method,
    String path,
    Map<String, dynamic> body,
    Map<String, String>? query,
    bool queueOnFailure,
    String message,
  ) async {
    if (queueOnFailure && method != 'GET') {
      await SyncQueue.enqueue(PendingOp(
        method: method,
        path: path,
        body: body.isEmpty ? null : body,
        query: query,
      ));
      return null; // изменение сохранено локально, уйдёт позже
    }
    throw ApiException(message);
  }

  /// FastAPI отдаёт ошибки как {"detail": "..."} — достаём человеческий текст.
  String _errorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map && decoded['detail'] != null) return '${decoded['detail']}';
    } catch (_) {
      // тело не JSON — используем статус
    }
    return 'Ошибка ${response.statusCode}';
  }

  void dispose() => _http.close();
}
