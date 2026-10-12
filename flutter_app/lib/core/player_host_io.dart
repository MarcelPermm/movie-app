import 'dart:async';
import 'dart:io';

import 'player_page.dart';

/// Крошечный HTTP-сервер внутри приложения, который отдаёт страницу-обёртку
/// плеера (см. player_page.dart).
///
/// Свою HTML-страницу WebView на Windows напрямую не принимает (initialData
/// там не поддержан), а держать её на сайте или сервере — значит зависеть от
/// них. Поэтому страницу отдаёт само приложение: сервер слушает только
/// 127.0.0.1 — снаружи к нему не подключиться, и брандмауэр Windows не
/// спрашивает разрешения. Порт выбирает система, сервер поднимается при
/// первом открытии плеера и живёт, пока открыто приложение.
class PlayerHost {
  static Future<HttpServer>? _server;

  static Future<String?> pageUrl(String embedUrl) async {
    try {
      final server = await (_server ??= _start());
      return 'http://127.0.0.1:${server.port}/player?u=${Uri.encodeComponent(embedUrl)}';
    } catch (_) {
      // Не поднялся сервер — откроем источник напрямую, это лучше, чем ничего.
      _server = null;
      return null;
    }
  }

  static Future<HttpServer> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      final response = request.response;
      final url = request.uri.queryParameters['u'] ?? '';
      if (request.uri.path != '/player' || !embedAllowed(url)) {
        response.statusCode = HttpStatus.notFound;
        response.close();
        return;
      }
      response.headers.contentType = ContentType.html;
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      response.write(playerPageHtml(url));
      response.close();
    });
    return server;
  }
}
