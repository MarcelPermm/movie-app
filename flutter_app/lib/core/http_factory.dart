/// Создание HTTP-клиента под текущую платформу.
///
/// В вебе запросы идут через сам браузер, и настраивать там нечего.
/// На остальных платформах клиент нужно подкрутить — см. http_factory_io.dart.
export 'http_factory_io.dart' if (dart.library.js_interop) 'http_factory_web.dart';
