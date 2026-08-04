import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/local_store.dart';
import 'core/session.dart';
import 'core/sync_queue.dart';
import 'data/book_repository.dart';
import 'data/budget_repository.dart';
import 'data/discover_repository.dart';
import 'data/goal_repository.dart';
import 'data/movie_repository.dart';
import 'data/notebook_repository.dart';
import 'data/task_repository.dart';
import 'data/wishlist_repository.dart';
import 'screens/app_shell.dart';
import 'screens/login_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Локальное хранилище поднимается до первого кадра — дальше все чтения
  // синхронные, и первый экран рисуется без единого сетевого запроса.
  await LocalStore.init();

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Monkey App',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
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
