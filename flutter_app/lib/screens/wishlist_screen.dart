import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../data/wishlist_repository.dart';
import '../models/wishlist.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'friend_wishlist_screen.dart';

class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  bool _showItems = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WishlistRepository>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<WishlistRepository>();
    final pendingRequests = repo.incoming.length;

    return Column(
      children: [
        SectionHeader(
          title: 'Желания',
          actions: [
            AddButton(
              onPressed: _showItems ? _addItem : _addFriend,
              tooltip: _showItems ? 'Новое желание' : 'Добавить друга',
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedToggle<bool>(
              value: _showItems,
              options: {
                true: 'Мой список · ${repo.items.length}',
                false: pendingRequests > 0
                    ? 'Друзья · ${repo.friends.length} (+$pendingRequests)'
                    : 'Друзья · ${repo.friends.length}',
              },
              onChanged: (v) => setState(() => _showItems = v),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.gold,
            backgroundColor: AppColors.surface,
            onRefresh: () => context.read<WishlistRepository>().refresh(),
            child: _showItems ? _buildItems(repo) : _buildFriends(repo),
          ),
        ),
      ],
    );
  }

  // ─── Свой список ────────────────────────────────────────────────────

  Widget _buildItems(WishlistRepository repo) {
    if (repo.items.isEmpty) {
      return const EmptyHint(emoji: '🎁', text: 'Пока ничего не загадано');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: repo.items.map(_buildItemCard).toList(),
    );
  }

  Widget _buildItemCard(WishItem item) {
    return Dismissible(
      key: ValueKey('wish-${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.red.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: AppColors.red),
      ),
      onDismissed: (_) => context.read<WishlistRepository>().removeItem(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: () => _editItem(item),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WishImage(url: item.image),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _PriorityChip(priority: item.priority),
                          if (item.price != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              formatMoney(item.price!),
                              style: const TextStyle(color: AppColors.gold, fontSize: 13),
                            ),
                          ],
                        ],
                      ),
                      if (item.note != null && item.note!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          item.note!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textDim, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addItem() async {
    final result = await showDialog<_WishDraft>(
      context: context,
      builder: (_) => const _WishDialog(),
    );
    if (result == null || !mounted) return;
    await context.read<WishlistRepository>().addItem(
          title: result.title,
          url: result.url,
          image: result.image,
          price: result.price,
          note: result.note,
          priority: result.priority,
        );
  }

  Future<void> _editItem(WishItem item) async {
    final result = await showDialog<_WishDraft>(
      context: context,
      builder: (_) => _WishDialog(item: item),
    );
    if (result == null || !mounted) return;
    await context.read<WishlistRepository>().updateItem(
          item,
          title: result.title,
          url: result.url,
          image: result.image,
          price: result.price,
          note: result.note,
          priority: result.priority,
        );
  }

  // ─── Друзья ─────────────────────────────────────────────────────────

  Widget _buildFriends(WishlistRepository repo) {
    if (repo.friends.isEmpty && repo.incoming.isEmpty && repo.outgoing.isEmpty) {
      return const EmptyHint(emoji: '👋', text: 'Друзей пока нет.\nДобавь по логину — и увидишь их списки');
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (repo.incoming.isNotEmpty) ...[
          const _GroupLabel('Заявки к тебе'),
          ...repo.incoming.map((r) => _buildRequestTile(r, incoming: true)),
          const SizedBox(height: 12),
        ],
        if (repo.outgoing.isNotEmpty) ...[
          const _GroupLabel('Отправленные'),
          ...repo.outgoing.map((r) => _buildRequestTile(r, incoming: false)),
          const SizedBox(height: 12),
        ],
        if (repo.friends.isNotEmpty) const _GroupLabel('Друзья'),
        ...repo.friends.map(_buildFriendTile),
      ],
    );
  }

  Widget _buildRequestTile(FriendRequest request, {required bool incoming}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: _Avatar(name: request.displayName),
        title: Text(request.displayName, style: const TextStyle(color: AppColors.text, fontSize: 15)),
        subtitle: Text('@${request.username}',
            style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (incoming)
              IconButton(
                tooltip: 'Принять',
                icon: const Icon(Icons.check, color: AppColors.green),
                onPressed: () => context.read<WishlistRepository>().acceptRequest(request),
              ),
            IconButton(
              tooltip: incoming ? 'Отклонить' : 'Отменить',
              icon: const Icon(Icons.close, color: AppColors.textDim),
              onPressed: () => context.read<WishlistRepository>().declineRequest(request),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendTile(Friend friend) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => FriendWishlistScreen(friend: friend),
        )),
        onLongPress: () => _removeFriend(friend),
        leading: _Avatar(name: friend.displayName),
        title: Text(friend.displayName, style: const TextStyle(color: AppColors.text, fontSize: 15)),
        subtitle: Text('@${friend.username}',
            style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textDim),
      ),
    );
  }

  Future<void> _addFriend() async {
    final username = await promptText(
      context,
      title: 'Добавить друга',
      hint: 'Логин пользователя',
      confirmLabel: 'Отправить',
    );
    if (username == null || username.isEmpty || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await context.read<WishlistRepository>().sendFriendRequest(username);
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _removeFriend(Friend friend) async {
    final ok = await confirmDelete(context, '${friend.displayName} — убрать из друзей?');
    if (!ok || !mounted) return;
    await context.read<WishlistRepository>().removeFriend(friend);
  }
}

// ─── Мелкие части ─────────────────────────────────────────────────────

class _GroupLabel extends StatelessWidget {
  final String text;
  const _GroupLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Text(text, style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
      );
}

class _Avatar extends StatelessWidget {
  final String name;
  const _Avatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: 18,
      backgroundColor: AppColors.goldDim.withValues(alpha: 0.25),
      child: Text(letter, style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700)),
    );
  }
}

class _PriorityChip extends StatelessWidget {
  final int priority;
  const _PriorityChip({required this.priority});

  static const _colors = {
    1: AppColors.red,
    2: AppColors.gold,
    3: AppColors.blue,
    4: AppColors.textDim,
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[priority] ?? AppColors.textDim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        WishItem.priorityLabels[priority] ?? '',
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _WishImage extends StatelessWidget {
  final String? url;
  const _WishImage({this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(
        height: 64,
        width: 64,
        child: url == null || url!.isEmpty
            ? Container(
                color: AppColors.bg,
                alignment: Alignment.center,
                child: const Text('🎁', style: TextStyle(fontSize: 22)),
              )
            : CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(color: AppColors.bg),
                errorWidget: (_, _, _) => Container(
                  color: AppColors.bg,
                  alignment: Alignment.center,
                  child: const Text('🎁', style: TextStyle(fontSize: 22)),
                ),
              ),
      ),
    );
  }
}

/// Черновик желания, возвращаемый диалогом.
class _WishDraft {
  final String title;
  final String? url;
  final String? image;
  final double? price;
  final String? note;
  final int priority;

  const _WishDraft({
    required this.title,
    this.url,
    this.image,
    this.price,
    this.note,
    this.priority = 2,
  });
}

/// Форма желания. Ссылку можно вставить и попробовать подтянуть данные
/// автоматически, но многие магазины закрыты антиботом — тогда поля
/// заполняются руками, и это нормальный путь, а не запасной.
class _WishDialog extends StatefulWidget {
  final WishItem? item;
  const _WishDialog({this.item});

  @override
  State<_WishDialog> createState() => _WishDialogState();
}

class _WishDialogState extends State<_WishDialog> {
  late final _title = TextEditingController(text: widget.item?.title ?? '');
  late final _url = TextEditingController(text: widget.item?.url ?? '');
  late final _image = TextEditingController(text: widget.item?.image ?? '');
  late final _price = TextEditingController(
      text: widget.item?.price == null ? '' : widget.item!.price!.round().toString());
  late final _note = TextEditingController(text: widget.item?.note ?? '');

  late int _priority = widget.item?.priority ?? 2;
  bool _loadingPreview = false;

  @override
  void dispose() {
    _title.dispose();
    _url.dispose();
    _image.dispose();
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _fetchPreview() async {
    final url = _url.text.trim();
    if (url.isEmpty) return;

    setState(() => _loadingPreview = true);
    final data = await context.read<WishlistRepository>().preview(url);
    if (!mounted) return;
    setState(() => _loadingPreview = false);

    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Магазин не отдал данные — заполни поля вручную')),
      );
      return;
    }
    setState(() {
      if (_title.text.trim().isEmpty && data['title'] != null) _title.text = '${data['title']}';
      if (_image.text.trim().isEmpty && data['image'] != null) _image.text = '${data['image']}';
      if (_price.text.trim().isEmpty && data['price'] != null) {
        _price.text = '${(data['price'] as num).round()}';
      }
    });
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    Navigator.pop(
      context,
      _WishDraft(
        title: title,
        url: _url.text.trim().isEmpty ? null : _url.text.trim(),
        image: _image.text.trim().isEmpty ? null : _image.text.trim(),
        price: double.tryParse(_price.text.trim().replaceAll(',', '.')),
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        priority: _priority,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        widget.item == null ? 'Новое желание' : 'Желание',
        style: const TextStyle(color: AppColors.text, fontSize: 17),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _title,
                autofocus: widget.item == null,
                decoration: const InputDecoration(hintText: 'Что хочется'),
                style: const TextStyle(color: AppColors.text),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _url,
                      decoration: const InputDecoration(hintText: 'Ссылка на товар'),
                      style: const TextStyle(color: AppColors.text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _loadingPreview
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.goldDim),
                        )
                      : IconButton(
                          tooltip: 'Подтянуть название и фото',
                          icon: const Icon(Icons.download_outlined, color: AppColors.textDim),
                          onPressed: _fetchPreview,
                        ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _image,
                decoration: const InputDecoration(hintText: 'Ссылка на картинку'),
                style: const TextStyle(color: AppColors.text),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: 'Цена, ₽'),
                style: const TextStyle(color: AppColors.text),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _note,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(hintText: 'Комментарий: размер, цвет, ссылка на аналог'),
                style: const TextStyle(color: AppColors.text),
              ),
              const SizedBox(height: 14),
              const Text('Насколько хочется',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: WishItem.priorityLabels.entries.map((e) {
                  final selected = _priority == e.key;
                  return GestureDetector(
                    onTap: () => setState(() => _priority = e.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.gold : AppColors.bg,
                        border: Border.all(color: selected ? AppColors.gold : AppColors.border),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        e.value,
                        style: TextStyle(
                          color: selected ? AppColors.bg : AppColors.text,
                          fontSize: 12,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена', style: TextStyle(color: AppColors.textDim)),
        ),
        FilledButton(onPressed: _submit, child: const Text('Сохранить')),
      ],
    );
  }
}
