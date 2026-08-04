import '../core/api_client.dart';
import '../models/wishlist.dart';
import 'local_first_repository.dart';

/// Виш-лист и друзья.
///
/// Чужие списки не кэшируются надолго: резерв и складчина там меняются
/// чужими руками, и показывать устаревшее хуже, чем подождать.
class WishlistRepository extends LocalFirstRepository {
  WishlistRepository({required super.api, required super.session});

  List<WishItem> _items = [];
  List<Friend> _friends = [];
  List<FriendRequest> _incoming = [];
  List<FriendRequest> _outgoing = [];

  List<WishItem> get items => List.unmodifiable(_items);
  List<Friend> get friends => List.unmodifiable(_friends);
  List<FriendRequest> get incoming => List.unmodifiable(_incoming);
  List<FriendRequest> get outgoing => List.unmodifiable(_outgoing);

  String get _itemsKey => cacheKey('wishlist::items');
  String get _friendsKey => cacheKey('wishlist::friends');
  String get _reqKey => cacheKey('wishlist::requests');

  Future<void> load({bool forceRefresh = false}) async {
    _items = readCache(_itemsKey).map(WishItem.fromJson).toList();
    _friends = readCache(_friendsKey).map(Friend.fromJson).toList();

    final reqs = readCache(_reqKey);
    _incoming = reqs.where((r) => r['_dir'] == 'in').map(FriendRequest.fromJson).toList();
    _outgoing = reqs.where((r) => r['_dir'] == 'out').map(FriendRequest.fromJson).toList();

    notifyListeners();
    if (forceRefresh || isStale(_itemsKey)) await refresh();
  }

  Future<void> refresh() => runSync(() async {
        final uid = session.userId;
        if (uid == null) return;

        final results = await Future.wait([
          api.get('/wishlist/$uid'),
          api.get('/friends'),
          api.get('/friends/requests'),
        ]);

        await writeCache(_itemsKey, (results[0] as List?) ?? const [], fromServer: true);
        await writeCache(_friendsKey, (results[1] as List?) ?? const [], fromServer: true);

        // Входящие и исходящие приходят одним объектом — раскладываем в один
        // список с пометкой направления, чтобы кэш остался плоским.
        final requests = results[2];
        final incoming = (requests is Map ? requests['incoming'] as List? : null) ?? const [];
        final outgoing = (requests is Map ? requests['outgoing'] as List? : null) ?? const [];
        await writeCache(_reqKey, [
          ...incoming.whereType<Map>().map((r) => {...r, '_dir': 'in'}),
          ...outgoing.whereType<Map>().map((r) => {...r, '_dir': 'out'}),
        ], fromServer: true);

        _items = readCache(_itemsKey).map(WishItem.fromJson).toList();
        _friends = readCache(_friendsKey).map(Friend.fromJson).toList();
        final cached = readCache(_reqKey);
        _incoming = cached.where((r) => r['_dir'] == 'in').map(FriendRequest.fromJson).toList();
        _outgoing = cached.where((r) => r['_dir'] == 'out').map(FriendRequest.fromJson).toList();
      });

  Future<void> _saveItems() => writeCache(_itemsKey, _items.map((i) => i.toJson()).toList());

  // ─── Свои вещи ──────────────────────────────────────────────────────

  Future<void> addItem({
    required String title,
    String? url,
    String? image,
    double? price,
    String? note,
    int priority = 2,
  }) async {
    final title0 = title.trim();
    if (title0.isEmpty) return;

    final temp = WishItem(
      id: LocalFirstRepository.nextTempId(),
      title: title0,
      url: url,
      image: image,
      price: price,
      note: note,
      priority: priority,
    );
    _items = [..._items, temp]..sort((a, b) => a.priority.compareTo(b.priority));
    notifyListeners();
    await _saveItems();

    final created = await push(() => api.post('/wishlist/items', body: {
          'title': title0,
          'url': ?url,
          'image': ?image,
          'price': ?price,
          'note': ?note,
          'priority': priority,
        }));
    if (created is Map) {
      final real = WishItem.fromJson(Map<String, dynamic>.from(created));
      _items = _items.map((i) => i.id == temp.id ? real : i).toList();
      notifyListeners();
      await _saveItems();
    }
  }

  Future<void> updateItem(
    WishItem item, {
    String? title,
    String? url,
    String? image,
    double? price,
    String? note,
    int? priority,
  }) async {
    _items = _items
        .map((i) => i.id == item.id
            ? i.copyWith(
                title: title,
                url: url,
                image: image,
                price: price,
                note: note,
                priority: priority)
            : i)
        .toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
    notifyListeners();
    await _saveItems();

    if (LocalFirstRepository.isTemp(item.id)) return;
    await push(() => api.put('/wishlist/items/${item.id}', body: {
          'title': ?title,
          'url': ?url,
          'image': ?image,
          'price': ?price,
          'note': ?note,
          'priority': ?priority,
        }));
  }

  Future<void> removeItem(WishItem item) async {
    final backup = _items;
    _items = _items.where((i) => i.id != item.id).toList();
    notifyListeners();
    await _saveItems();

    if (LocalFirstRepository.isTemp(item.id)) return;
    await push(
      () => api.delete('/wishlist/items/${item.id}'),
      rollback: () => _items = backup,
    );
  }

  // ─── Чужой виш-лист ─────────────────────────────────────────────────

  /// Список друга. Всегда с сервера: резерв мог измениться минуту назад.
  Future<List<WishItem>> friendWishlist(int friendId) async {
    final data = await api.get('/wishlist/$friendId');
    return ((data as List?) ?? const [])
        .whereType<Map>()
        .map((e) => WishItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> reserve(int itemId, {required bool reserve}) async {
    await push(() => reserve
        ? api.post('/wishlist/items/$itemId/reserve')
        : api.post('/wishlist/items/$itemId/unreserve'));
  }

  Future<void> contribute(int itemId, double amount) async {
    await push(() => api.post('/wishlist/items/$itemId/contribute', body: {'amount': amount}));
  }

  Future<void> removeContribution(int itemId) async {
    await push(() => api.delete('/wishlist/items/$itemId/contribute'));
  }

  // ─── Друзья ─────────────────────────────────────────────────────────

  /// Возвращает сообщение сервера — оно объясняет, что произошло
  /// (заявка отправлена или встречная сразу принята).
  Future<String> sendFriendRequest(String username) async {
    final result = await api.post(
      '/friends/request',
      body: {'username': username.trim()},
      queueOnFailure: false,
    );
    await refresh();
    if (result is Map && result['message'] != null) return '${result['message']}';
    return 'Заявка отправлена';
  }

  Future<void> acceptRequest(FriendRequest request) async {
    _incoming = _incoming.where((r) => r.id != request.id).toList();
    notifyListeners();
    await push(() => api.post('/friends/accept/${request.id}'));
    await refresh();
  }

  Future<void> declineRequest(FriendRequest request) async {
    _incoming = _incoming.where((r) => r.id != request.id).toList();
    _outgoing = _outgoing.where((r) => r.id != request.id).toList();
    notifyListeners();
    await push(() => api.post('/friends/decline/${request.id}'));
  }

  Future<void> removeFriend(Friend friend) async {
    final backup = _friends;
    _friends = _friends.where((f) => f.id != friend.id).toList();
    notifyListeners();
    await push(
      () => api.delete('/friends/${friend.id}'),
      rollback: () => _friends = backup,
    );
  }

  /// Подтягивает название, картинку и цену со страницы товара.
  /// Многие магазины закрыты антиботом — тогда просто вернётся пусто.
  Future<Map<String, dynamic>?> preview(String url) async {
    try {
      final data = await api.get('/wishlist/preview', query: {'url': url});
      return data is Map ? Map<String, dynamic>.from(data) : null;
    } on ApiException {
      return null;
    }
  }
}
