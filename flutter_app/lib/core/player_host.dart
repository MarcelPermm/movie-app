/// Где взять страницу-обёртку для встроенного плеера.
///
/// На Windows, Android и других платформах её отдаёт маленький сервер внутри
/// самого приложения (player_host_io.dart). В вебе приложение и так живёт
/// в браузере, и WebView там сам по себе iframe — обёртка не нужна.
library;

export 'player_host_io.dart' if (dart.library.js_interop) 'player_host_web.dart';
