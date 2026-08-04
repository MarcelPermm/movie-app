import 'package:flutter/foundation.dart';

import 'local_store.dart';

/// Текущий пользователь. Хранится локально, переживает перезапуск приложения.
///
/// Бэкенд принимает user_id как обычный параметр (как и веб-версия),
/// поэтому сессия — это просто запомненный id.
class Session extends ChangeNotifier {
  static const _key = 'session::user';

  int? _userId;
  String? _username;
  String? _displayName;

  int? get userId => _userId;
  String? get username => _username;
  String? get displayName => _displayName;
  bool get isLoggedIn => _userId != null;

  /// Восстановить сессию из локального хранилища при старте.
  void restore() {
    final saved = LocalStore.readMap(_key);
    if (saved == null) return;
    _userId = saved['id'] as int?;
    _username = saved['username'] as String?;
    _displayName = saved['display_name'] as String?;
    notifyListeners();
  }

  Future<void> signIn(Map<String, dynamic> user) async {
    _userId = user['id'] as int?;
    _username = user['username'] as String?;
    _displayName = user['display_name'] as String?;
    await LocalStore.writeMap(_key, {
      'id': _userId,
      'username': _username,
      'display_name': _displayName,
    });
    notifyListeners();
  }

  /// Выход стирает и сессию, и весь локальный кэш —
  /// иначе следующий пользователь увидит чужие фильмы.
  Future<void> signOut() async {
    _userId = null;
    _username = null;
    _displayName = null;
    await LocalStore.clear();
    notifyListeners();
  }
}
