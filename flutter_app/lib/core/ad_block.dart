import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Блокировка рекламы во встроенном плеере.
///
/// Источники видео живут на чужой рекламе: баннеры поверх кадра, окна,
/// открывающиеся по первому клику, и переходы на сторонние сайты вместо
/// воспроизведения. Защита строится в три слоя, потому что ни один из них
/// сам по себе не закрывает всё:
///
///   1. запросы к рекламным доменам не уходят вовсе (contentBlockers);
///   2. открытие новых окон запрещено на уровне WebView;
///   3. на странице глушится то, что осталось, — window.open, ссылки-подложки
///      поверх плеера и попытки увести вкладку.
///
/// Идеальной блокировки не бывает: сети меняют домены. Список стоит
/// пополнять по мере того, как что-то пролезает.
class AdBlock {
  /// Домены рекламных и трекинговых сетей, которые чаще всего попадаются
  /// на страницах видео-источников.
  static const blockedDomains = <String>[
    'doubleclick.net',
    'googlesyndication.com',
    'googleadservices.com',
    'google-analytics.com',
    'googletagmanager.com',
    'googletagservices.com',
    'adservice.google.com',
    'amazon-adsystem.com',
    'adnxs.com',
    'rubiconproject.com',
    'pubmatic.com',
    'openx.net',
    'criteo.com',
    'criteo.net',
    'taboola.com',
    'outbrain.com',
    'popads.net',
    'popcash.net',
    'popmyads.com',
    'propellerads.com',
    'propellerclick.com',
    'onclickalgo.com',
    'onclickmega.com',
    'onclicksuper.com',
    'hilltopads.net',
    'exoclick.com',
    'exdynsrv.com',
    'juicyads.com',
    'adsterra.com',
    'adskeeper.com',
    'mgid.com',
    'revcontent.com',
    'zedo.com',
    'bidvertiser.com',
    'clicksgear.com',
    'trafficjunky.net',
    'clickadu.com',
    'adcash.com',
    'admaven.com',
    'mediafire-ads.com',
    'histats.com',
    'statcounter.com',
    'hotjar.com',
    'yandex.ru/metrika',
    'mc.yandex.ru',
    'scorecardresearch.com',
    'quantserve.com',
    'moatads.com',
    'sekindo.com',
    'vidoomy.com',
    'aniview.com',
    'springserve.com',
    'contentabc.com',
    'luckyforbet.com',
    'bestadbid.com',
    'ad-maven.com',
    // Сети, замеченные на страницах источников вживую.
    'pwrgamerz.com',
    'gamezop.com',
    'clickiocdn.com',
    'ad-delivery.net',
    'smartadserver.com',
    'doubleverify.com',
    'teads.tv',
    'rtmark.net',
    'stpd.cloud',
    'bidgear.com',
    'monetag.com',
    'zeydoo.com',
    'onclickperformance.com',
    'highperformanceformat.com',
    'profitableratecpm.com',
    'effectivegatecpm.com',
    // Из списка Streambert (github.com/truelockmc/streambert, index.js):
    // то, что всплывает на страницах Videasy, VidSrc и Vidking.
    'analytics.google.com',
    'adservice.google.de',
    'cdn.adx1.com',
    'intelligenceadx.com',
    'adsco.re',
    'mc.yandex.com',
    'bvtpk.com',
    'b7510.com',
    'gt.unbrownunflat.com',
    'im.malocacomals.com',
    'users.videasy.net',
    'nf.sixmossin.com',
    'realizationnewestfangs.com',
    'acscdn.com',
    'lt.taloseempest.com',
    'preferencenail.com',
    'protrafficinspector.com',
    'weirdopt.com',
    'static.cloudflareinsights.com',
    'kettledroopingcontinuation.com',
    'wayfarerorthodox.com',
    'woxaglasuy.net',
    'adeptspiritual.com',
    'calculating-laugh.com',
    'amavhxdlofklxjg.xyz',
    '7jtjubf8p5kq7x3z2.u3qleufcm6vure326ktfpbj.cfd',
    '5mq.get64t9vqg8pnbex1y463o.rest',
    'usrpubtrk.com',
    'adexchangeclear.com',
    'rzjzjnavztycv.online',
    'tmstr4.cloudnestra.com',
    'tmstr4.neonhorizonworkshops.com',
  ];

  /// Правила для WebView: любой запрос к домену из списка отбрасывается.
  ///
  /// `.*` в фильтре с `ifDomain` работает надёжнее, чем регулярка по URL:
  /// поддомены рекламных сетей меняются каждую неделю, а корневой домен —
  /// почти никогда.
  static List<ContentBlocker> get rules => [
        for (final domain in blockedDomains)
          ContentBlocker(
            trigger: ContentBlockerTrigger(
              urlFilter: '.*',
              ifDomain: ['*$domain'],
            ),
            action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
          ),

        // Типовые рекламные пути внутри самого источника — они не на чужом
        // домене, поэтому доменный список их не ловит.
        ContentBlocker(
          trigger: ContentBlockerTrigger(
            urlFilter: r'.*(\/ads?\/|\/adserve|\/popunder|\/banner|prebid|adsbygoogle).*',
          ),
          action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
        ),
      ];

  /// Скрипт, который выполняется после загрузки страницы.
  ///
  /// Всё, что не удалось отсечь на уровне запросов, ловится здесь:
  /// подменяем window.open, снимаем ссылки-подложки, растянутые поверх
  /// видео, и не даём странице увести вкладку без нашего ведома.
  static const tamerScript = '''
(function () {
  if (window.__monkeyTamed) return;
  window.__monkeyTamed = true;

  // 1. Всплывающие окна. Многие плееры вешают window.open на первый клик
  //    по любому месту страницы — включая саму кнопку воспроизведения.
  window.open = function () { return null; };

  // 2. Уход со страницы. Реклама часто меняет location вместо открытия окна.
  window.addEventListener('beforeunload', function (e) {
    e.stopImmediatePropagation();
  }, true);

  // 3. Прозрачные ссылки-подложки поверх кадра: клик «по видео» на самом деле
  //    попадает в них. Убираем всё, что растянуто почти на весь экран.
  function stripOverlays() {
    var w = window.innerWidth, h = window.innerHeight;
    document.querySelectorAll('a, ins, iframe').forEach(function (el) {
      var r = el.getBoundingClientRect();
      var coversScreen = r.width > w * 0.7 && r.height > h * 0.7;
      var isVideo = el.tagName === 'IFRAME' && /player|embed|stream|video/i.test(el.src || '');
      if (coversScreen && !isVideo) el.remove();
      if (el.tagName === 'A' && el.target === '_blank') el.removeAttribute('target');
    });
  }

  stripOverlays();
  // Подложки подставляются повторно, поэтому чистим и по мере изменений.
  new MutationObserver(stripOverlays).observe(document.documentElement, {
    childList: true,
    subtree: true,
  });
  setInterval(stripOverlays, 1500);
})();
''';
}
