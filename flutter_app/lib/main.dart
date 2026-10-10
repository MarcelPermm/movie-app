import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/http_factory.dart';
import 'core/local_store.dart';
import 'core/session.dart';
import 'core/sync_queue.dart';
import 'data/actor_repository.dart';
import 'data/book_repository.dart';
import 'data/budget_repository.dart';
import 'data/discover_repository.dart';
import 'data/goal_repository.dart';
import 'data/movie_repository.dart';
import 'data/notebook_repository.dart';
import 'data/profile_repository.dart';
import 'data/task_repository.dart';
import 'data/trip_repository.dart';
import 'data/wishlist_repository.dart';
import 'screens/app_shell.dart';
import 'screens/login_screen.dart';
import 'theme.dart';
import 'widgets/app_scroll.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Реализация WebView для Windows не подключается сама — в отличие от
  // Android, iOS и веба, где это делает федерация плагинов.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    InAppWebViewPlatform.instance = WindowsInAppWebViewPlatform();
  }

  // Настройки прокси читаются до создания клиента: иначе первые запросы
  // уйдут напрямую, а там может стоять блокировка.
  await initNetwork();

  // Локальное хранилище поднимается до первого кадра — дальше все чтения
  // синхронные, и первый экран рисуется без единого сетевого запроса.
  await LocalStore.init();
  AppTheme.restore();

  final session = Session()..restore();
  final api = ApiClient(session);

  // Если в прошлый раз что-то не доехало до сервера — досылаем на старте.
  if (session.isLoggedIn) {
    SyncQueue.flush(api);
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<Session>.value(value: session),
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider(create: (_) => DiscoverRepository(api: api, session: session)),
        ChangeNotifierProvider(create: (_) => MovieRepository(api: api, session: session)),
        ChangeNotifierProvider(create: (_) => BookRepository(api: api, session: session)),
        ChangeNotifierProvider(create: (_) => TaskRepository(api: api, session: session)),
        ChangeNotifierProvider(create: (_) => NotebookRepository(api: api, session: session)),
        ChangeNotifierProvider(create: (_) => GoalRepository(api: api, session: session)),
        ChangeNotifierProvider(create: (_) => BudgetRepository(api: api, session: session)),
        ChangeNotifierProvider(create: (_) => WishlistRepository(api: api, session: session)),
        ChangeNotifierProvider(create: (_) => ActorRepository(api: api, session: session)),
        ChangeNotifierProvider(create: (_) => ProfileRepository(api: api, session: session)),
        ChangeNotifierProvider(create: (_) => TripRepository(api: api, session: session)),
      ],
      child: const MonkeyApp(),
    ),
  );
}

class MonkeyApp extends StatefulWidget {
  const MonkeyApp({super.key});

  @override
  State<MonkeyApp> createState() => _MonkeyAppState();
}

class _MonkeyAppState extends State<MonkeyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppTheme.notifier.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    AppTheme.notifier.removeListener(_onThemeChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Смена темы. Цвета экраны читают из AppColors при каждой отрисовке,
  /// поэтому достаточно перерисовать всё дерево — состояние экранов
  /// (прокрутка, открытые вкладки) при этом сохраняется.
  void _onThemeChanged() {
    setState(() {});
    void markDirty(Element element) {
      element.markNeedsBuild();
      element.visitChildren(markDirty);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(markDirty);
  }

  /// Возврат из фона — момент, когда данные могли устареть.
  /// Каждый репозиторий сам решает, идти ли в сеть: если его кэш свежий,
  /// запроса не будет.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!context.read<Session>().isLoggedIn) return;

    context.read<DiscoverRepository>().load();
    context.read<MovieRepository>().load();
    context.read<BookRepository>().load();
    context.read<TaskRepository>().load();
    context.read<NotebookRepository>().load();
    context.read<GoalRepository>().load();
    context.read<BudgetRepository>().load();
    context.read<WishlistRepository>().load();
    context.read<ProfileRepository>().load();
    context.read<TripRepository>().load();
    // ActorRepository здесь намеренно нет: топ актёров пересчитывается по
    // всему просмотренному и стоит дорого. Он обновляется при открытии
    // своей вкладки, когда результат действительно кому-то нужен.
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Monkey App',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // Тема меняется мгновенно: плавный переход цвета смотрелся бы
      // рассинхронно с экранами, которые перерисовываются сразу.
      themeAnimationDuration: Duration.zero,
      // Общий фон под всеми экранами (у «Стекла» — размытые пятна).
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(child: AppBackdrop()),
          if (child != null) child,
        ],
      ),
      // Без этого горизонтальные ленты нельзя тянуть мышью на десктопе.
      scrollBehavior: const AppScrollBehavior(),
      home: Consumer<Session>(
        builder: (context, session, _) => session.isLoggedIn
            // Ключ по пользователю: смена аккаунта поднимает раздел заново,
            // и он читает уже свой кэш, а не остатки предыдущего.
            ? AppShell(key: ValueKey('shell-${session.userId}'))
            : const LoginScreen(),
      ),
    );
  }
}
