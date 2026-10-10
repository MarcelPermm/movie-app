import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/ad_block.dart';
import '../core/config.dart';
import '../theme.dart';

/// Встроенный плеер.
///
/// Раньше «Смотреть» уводило во внешний браузер — там ты оставался один на
/// один с рекламой источника. Здесь страница открывается внутри приложения,
/// а всё лишнее отсекается на трёх уровнях (см. [AdBlock]).
class PlayerScreen extends StatefulWidget {
  final int tmdbId;
  final String mediaType;
  final String title;

  /// Для сериала: какую серию открыть.
  final int season;
  final int episode;

  /// С какого источника начать (см. [Config.watchSources]).
  final String? source;

  /// Готовый адрес — на случай, если понадобится открыть чужую страницу.
  final String? directUrl;

  /// Идентификатор ролика на YouTube. Трейлеры открываются так, а не через
  /// [directUrl]: YouTube отказывается проигрывать ролик, если открыть
  /// адрес /embed напрямую — отвечает ошибкой 153, «ошибка настройки
  /// видеопроигрывателя». Ему нужна страница-источник, и мы её собираем.
  final String? youtubeId;

  const PlayerScreen({
    super.key,
    required this.title,
    this.tmdbId = 0,
    this.mediaType = 'movie',
    this.season = 1,
    this.episode = 1,
    this.source,
    this.directUrl,
    this.youtubeId,
  });

  /// Одна страница — значит переключать источники нечего.
  bool get isSingleSource => directUrl != null || youtubeId != null;

  /// Где встроенный WebView вообще доступен.
  ///
  /// Linux-сборки плагина нет, поэтому там остаётся внешний браузер.
  static bool get isSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  InAppWebViewController? _controller;
  late String _source = Config.watchSources.containsKey(widget.source)
      ? widget.source!
      : Config.defaultWatchSource;
  bool _loading = true;
  int _blocked = 0;

  /// Адрес, который открывает WebView: плеер источника напрямую, как в
  /// Streambert, — без промежуточных страниц на сайте или сервере.
  String get _url {
    // Трейлер — обычной страницей ролика: /embed верхним уровнем YouTube
    // не играет (ошибка 153), а своей страницы-обёртки на Windows нет.
    if (widget.youtubeId != null) return Config.youtubeUrl(widget.youtubeId!);
    return widget.directUrl ??
        Config.embedUrl(
          _source,
          widget.mediaType,
          widget.tmdbId,
          season: widget.season,
          episode: widget.episode,
        );
  }

  /// Отсекаем по списку рекламных доменов, а не по списку разрешённых:
  /// источники ходят на свои CDN, адреса которых меняются.
  bool _isAdHost(WebUri? uri) {
    final host = uri?.host.toLowerCase();
    if (host == null || host.isEmpty) return false;
    return AdBlock.blockedDomains.any((d) => host == d || host.endsWith('.$d'));
  }

  /// Тот же ли это сайт, что открытый плеер: сравниваем по «корню» домена,
  /// потому что плеер живёт на поддоменах.
  bool _isSameSite(String? host) {
    if (host == null || host.isEmpty) return true;
    return _rootDomain(host.toLowerCase()) == _rootDomain(Uri.parse(_url).host.toLowerCase());
  }

  /// «player.videasy.to» → «videasy.to»
  static String _rootDomain(String host) {
    final parts = host.split('.');
    if (parts.length <= 2) return host;
    return parts.sublist(parts.length - 2).join('.');
  }

  /// Сколько раз уже возвращали плеер на место.
  ///
  /// Ограничение нужно на случай, если источник сам уводит верхний кадр
  /// на свой другой домен: без счётчика мы бы вечно возвращали его назад,
  /// а он — снова вперёд.
  int _recoveries = 0;

  Future<void> _backToPlayer() async {
    if (_recoveries >= 3) return;
    _recoveries++;
    setState(() => _loading = true);
    await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(_url)));
  }

  Future<void> _switchSource(String source) async {
    if (source == _source) return;
    setState(() {
      _source = source;
      _loading = true;
      _blocked = 0;
      _recoveries = 0;
    });
    await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(_url)));
  }

  Future<void> _openExternally() async {
    await launchUrl(Uri.parse(_url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            if (widget.mediaType == 'tv' && !widget.isSingleSource)
              Text(
                'Сезон ${widget.season} · Серия ${widget.episode}',
                style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
              ),
          ],
        ),
        actions: [
          if (_blocked > 0)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Center(child: _BlockedCounter(count: _blocked)),
            ),
          // У трейлера источник один — переключать нечего.
          if (!widget.isSingleSource)
            PopupMenuButton<String>(
              initialValue: _source,
              tooltip: 'Источник',
              icon: Icon(Icons.swap_horiz, color: AppColors.textDim),
              onSelected: _switchSource,
              itemBuilder: (_) => Config.watchSources.entries
                  .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
            ),
          // Ручной возврат: если реклама всё-таки увела страницу, а
          // автоматический откат исчерпал попытки, это лечится одним нажатием.
          IconButton(
            tooltip: 'Вернуться к плееру',
            icon: Icon(Icons.refresh, color: AppColors.textDim),
            onPressed: () {
              _recoveries = 0;
              _backToPlayer();
            },
          ),
          IconButton(
            tooltip: 'Открыть в браузере',
            icon: Icon(Icons.open_in_new, color: AppColors.textDim),
            onPressed: _openExternally,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _buildWebView()),
          if (_loading)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black,
                child: Center(child: CircularProgressIndicator(color: AppColors.gold)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWebView() {
    // Windows-реализация плагина заметно моложе остальных: часть настроек
    // и обратных вызовов там не поддержана, и попытка их применить роняет
    // экран ошибкой разбора («type 'Null' is not a subtype of type String»).
    // Поэтому на Windows включаем только то, что там точно работает —
    // блокировка окон и переходов плюс скрипт на странице.
    final limited = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

    return InAppWebView(
      // Только обычная загрузка по адресу: initialData на Windows не поддержан.
      initialUrlRequest: URLRequest(url: WebUri(_url)),
      initialSettings: InAppWebViewSettings(
        // Реклама сначала не загружается…
        contentBlockers: limited ? const [] : AdBlock.rules,

        // …потом ей запрещают открывать окна…
        javaScriptCanOpenWindowsAutomatically: false,
        supportMultipleWindows: false,

        // Видео должно стартовать по кнопке в самом плеере, а не требовать
        // отдельного касания по WebView.
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        iframeAllow: 'autoplay; fullscreen; encrypted-media; picture-in-picture',
        iframeAllowFullscreen: true,

        // Прозрачный фон на Windows давал белое полотно вместо чёрного,
        // пока страница грузится. Плееру прозрачность и не нужна.
        transparentBackground: false,
        useShouldOverrideUrlLoading: true,
        useOnDownloadStart: !limited,
      ),
      onWebViewCreated: (controller) => _controller = controller,

      // …и наконец то, что осталось, глушится на самой странице.
      onLoadStop: (controller, _) async {
        try {
          await controller.evaluateJavascript(source: AdBlock.tamerScript);
        } catch (_) {
          // Скрипт мог не выполниться на чужой странице — не повод
          // оставлять пользователя перед вечной крутилкой.
        }
        if (mounted) setState(() => _loading = false);
      },
      onReceivedError: (_, _, _) {
        if (mounted) setState(() => _loading = false);
      },

      // Попытка открыть новое окно — почти всегда реклама.
      onCreateWindow: (_, _) async {
        if (mounted) setState(() => _blocked++);
        return false;
      },

      shouldOverrideUrlLoading: (controller, action) async {
        final uri = action.request.url;

        // Известная рекламная сеть — отсекаем сразу.
        if (_isAdHost(uri)) {
          if (mounted) setState(() => _blocked++);
          return NavigationActionPolicy.CANCEL;
        }

        // Клик, который уводит всё окно на посторонний сайт, — реклама.
        // Переходы без клика (редиректы плеера на свои домены) и переходы
        // внутри iframe не трогаем: на этом плеер и ломался.
        final byClick = action.hasGesture ?? false;
        if (byClick && action.isForMainFrame && !_isSameSite(uri?.host)) {
          if (mounted) setState(() => _blocked++);
          return NavigationActionPolicy.CANCEL;
        }

        return NavigationActionPolicy.ALLOW;
      },

      // Источники иногда подсовывают «скачать плеер» — не наш случай.
      onDownloadStartRequest: limited
          ? null
          : (_, _) async {
              if (mounted) setState(() => _blocked++);
            },
    );
  }
}

/// Счётчик заблокированного — видно, что защита работает.
class _BlockedCounter extends StatelessWidget {
  final int count;

  const _BlockedCounter({required this.count});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Заблокировано попыток открыть рекламу: $count',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.green.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.green.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined, size: 13, color: AppColors.green),
            const SizedBox(width: 5),
            Text(
              '$count',
              style: TextStyle(
                color: AppColors.green,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
