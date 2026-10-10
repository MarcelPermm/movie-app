import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Адрес прокси вида «хост:порт» или null, если ходим напрямую.
/// Определяется один раз при старте — см. [initNetwork].
String? _proxy;

/// Прокси можно задать при сборке, минуя автоопределение:
///   flutter run --dart-define=HTTP_PROXY=127.0.0.1:10809
/// Пустая строка означает «ходить напрямую, ничего не искать».
const _proxyOverride = String.fromEnvironment('HTTP_PROXY', defaultValue: '__auto__');

/// Найденный прокси — для показа в интерфейсе и в отладке.
String? get activeProxy => _proxy;

/// Подготовка сети. Вызывается из main() до запуска приложения.
///
/// Зачем это вообще нужно. Windows хранит настройки прокси в реестре,
/// и браузеры с PowerShell берут их оттуда сами. Dart так не умеет: он
/// всегда идёт напрямую. Если между тобой и сервером стоит блокировка,
/// а обходится она локальным прокси, получается странная картина —
/// сайт в браузере открывается, а приложение говорит «нет соединения».
/// Именно это мы и ловили: системная ошибка 121, «превышен таймаут
/// семафора», то есть соединение открылось и умерло молча.
Future<void> initNetwork() async {
  if (_proxyOverride != '__auto__') {
    _proxy = _proxyOverride.trim().isEmpty ? null : _clean(_proxyOverride);
    return;
  }

  // Переменные окружения — их выставляют многие клиенты VPN и прокси.
  final env = Platform.environment;
  final fromEnv = env['HTTPS_PROXY'] ??
      env['https_proxy'] ??
      env['HTTP_PROXY'] ??
      env['http_proxy'];
  if (fromEnv != null && fromEnv.trim().isNotEmpty) {
    _proxy = _clean(fromEnv);
    return;
  }

  if (Platform.isWindows) _proxy = await _readWindowsProxy();

  // Картинки Flutter качает не нашим клиентом, а своим собственным —
  // отсюда и картина «текст пришёл, постеры пустые». HttpOverrides
  // подменяет фабрику клиентов для всего приложения разом, включая
  // загрузчик изображений и кэш обложек.
  HttpOverrides.global = _AppHttpOverrides();
}

class _AppHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context)
      ..connectionTimeout = const Duration(seconds: 20)
      ..idleTimeout = const Duration(seconds: 20)
      ..userAgent = 'MonkeyApp';
    client.findProxy = (uri) => _proxy == null ? 'DIRECT' : 'PROXY $_proxy; DIRECT';
    return client;
  }
}

/// Чтение настроек прокси из реестра Windows.
///
/// Через `reg query`, а не через пакет для работы с реестром: одна внешняя
/// команда против лишней зависимости и биндингов к WinAPI. Названия ключей
/// не переводятся, поэтому разбор не зависит от языка системы.
Future<String?> _readWindowsProxy() async {
  const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  try {
    final enabled = await Process.run('reg', ['query', key, '/v', 'ProxyEnable']);
    // Значение приходит как REG_DWORD 0x1 или 0x0.
    if (!'${enabled.stdout}'.contains('0x1')) return null;

    final server = await Process.run('reg', ['query', key, '/v', 'ProxyServer']);
    for (final line in '${server.stdout}'.split('\n')) {
      if (!line.contains('ProxyServer')) continue;
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 3) continue;
      return _pickHttpsProxy(parts.last);
    }
  } catch (_) {
    // Реестр недоступен — не повод падать, просто пойдём напрямую.
  }
  return null;
}

/// В реестре бывает как один адрес «127.0.0.1:10809», так и список по схемам:
/// «http=127.0.0.1:10809;https=127.0.0.1:10809;socks=...». Нам нужен тот,
/// через который ходит https, а socks дальше не поддерживается.
String? _pickHttpsProxy(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  if (!value.contains('=')) return _clean(value);

  String? http;
  for (final part in value.split(';')) {
    final pair = part.split('=');
    if (pair.length != 2) continue;
    final scheme = pair[0].trim().toLowerCase();
    if (scheme == 'https') return _clean(pair[1]);
    if (scheme == 'http') http = pair[1];
  }
  return http == null ? null : _clean(http);
}

/// Приводим к виду «хост:порт»: из переменных окружения адрес обычно
/// приходит полным URL, а findProxy ждёт голую пару.
String _clean(String value) {
  var v = value.trim();
  for (final prefix in ['http://', 'https://']) {
    if (v.startsWith(prefix)) v = v.substring(prefix.length);
  }
  if (v.endsWith('/')) v = v.substring(0, v.length - 1);
  return v;
}

/// HTTP-клиент для мобильных и десктопных сборок.
http.Client createHttpClient() {
  final inner = HttpClient()
    // Явный предел на установку соединения. По умолчанию его нет вовсе,
    // и неудачная попытка висела до системного таймаута — почти минуту.
    ..connectionTimeout = const Duration(seconds: 20)
    ..idleTimeout = const Duration(seconds: 20)
    ..userAgent = 'MonkeyApp';

  // DIRECT в конце списка — запасной путь: если прокси вдруг не отвечает,
  // клиент попробует пойти напрямую, а не сдастся сразу.
  inner.findProxy = (uri) => _proxy == null ? 'DIRECT' : 'PROXY $_proxy; DIRECT';

  return IOClient(inner);
}
