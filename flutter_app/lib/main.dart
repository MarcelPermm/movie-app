import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/local_store.dart';
import 'core/session.dart';
import 'core/sync_queue.dart';
import 'data/movie_repository.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Локальное хранилище поднимается до первого кадра — дальше все чтения
  // синхронные, и первый экран рисуется без единого сетевого запроса.
  await LocalStore.init();

  final session = Session()..restore();
  final api = ApiClient(session);
  final movies = MovieRepository(api: api, session: session);

  // Если в прошлый раз что-то не доехало до сервера — досылаем на старте.
  if (session.isLoggedIn) {
    SyncQueue.flush(api);
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<Session>.value(value: session),
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider<MovieRepository>.value(value: movies),
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
  /// load() сам решит, идти ли в сеть: если кэш свежее 30 минут, не пойдёт.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && context.read<Session>().isLoggedIn) {
      context.read<MovieRepository>().load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Monkey App',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Consumer<Session>(
        builder: (context, session, _) =>
            session.isLoggedIn ? const HomeScreen() : const LoginScreen(),
      ),
    );
  }
}
