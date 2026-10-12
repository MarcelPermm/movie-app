import 'dart:convert';

/// Страница-обёртка встроенного плеера: один iframe на весь экран.
///
/// Источники видео рассчитаны на то, что их вставят в iframe на чьей-то
/// странице, — так работает сайт. Открытые сами по себе, верхним уровнем,
/// они отвечают 403 («У вас нет прав для просмотра этой страницы») или
/// «We couldn't find that». Поэтому приложение показывает их так же, как
/// сайт, — внутри iframe, но страницу отдаёт само (см. player_host_io.dart),
/// ни от сайта, ни от сервера не завися.

/// Только известные источники: страница не должна встраивать что угодно.
bool embedAllowed(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;
  final host = uri.host.toLowerCase();
  final parts = host.split('.');
  final site = parts.length <= 2 ? host : parts.sublist(parts.length - 2).join('.');
  // VidSrc часто переезжает: vidsrc.to, vidsrc.xyz, vidsrc-embed.ru…
  if (site.startsWith('vidsrc')) return true;
  const roots = [
    'videasy.net',
    'videasy.to',
    'vsembed.su',
    'vidking.net',
    '2embed.cc',
    'youtube.com',
    'youtube-nocookie.com',
  ];
  return roots.any((r) => host == r || host.endsWith('.$r'));
}

String playerPageHtml(String embedUrl) {
  final src = const HtmlEscape(HtmlEscapeMode.attribute).convert(embedUrl);
  return '''<!doctype html>
<html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Monkey App</title>
<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}
iframe{position:fixed;inset:0;width:100%;height:100%;border:0}</style>
</head><body>
<iframe src="$src" allowfullscreen
 allow="accelerometer; autoplay; clipboard-write; encrypted-media; fullscreen; gyroscope; picture-in-picture"></iframe>
</body></html>''';
}
