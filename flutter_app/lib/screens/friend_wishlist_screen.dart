import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../data/wishlist_repository.dart';
import '../models/wishlist.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Виш-лист друга: можно забронировать подарок или скинуться на дорогой.
///
/// Данные всегда берутся с сервера, а не из кэша: бронь мог поставить
/// кто-то другой минуту назад, и показывать устаревшее здесь вреднее,
/// чем немного подождать.
class FriendWishlistScreen extends StatefulWidget {
  final Friend friend;
  const FriendWishlistScreen({super.key, required this.friend});

  @override
  State<FriendWishlistScreen> createState() => _FriendWishlistScreenState();
}

class _FriendWishlistScreenState extends State<FriendWishlistScreen> {
  List<WishItem> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await context.read<WishlistRepository>().friendWishlist(widget.friend.id);
      if (!mounted) return;
      setState(() => _items = items);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.friend.displayName,
          style: const TextStyle(color: AppColors.text, fontSize: 17),
        ),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 18),
              child: Center(
                child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.goldDim),
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.gold,
        backgroundColor: AppColors.surface,
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(28),
        children: [
          const SizedBox(height: 80),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.red, fontSize: 14),
          ),
        ],
      );
    }

    if (_items.isEmpty) {
      return EmptyHint(
        emoji: '🎁',
        text: _loading ? 'Загружаем список…' : 'У ${widget.friend.displayName} пока пусто',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: _items.map(_buildCard).toList(),
    );
  }

  Widget _buildCard(WishItem item) {
    // Занято кем-то другим — подсвечиваем приглушённо, чтобы не дарить дважды.
    final takenByOther = item.isReserved && !item.reservedByMe;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(
          color: item.reservedByMe ? AppColors.green : AppColors.border,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Opacity(
        opacity: takenByOther ? 0.55 : 1,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: SizedBox(
                      height: 64,
                      width: 64,
                      child: item.image == null || item.image!.isEmpty
                          ? Container(
                              color: AppColors.bg,
                              alignment: Alignment.center,
                              child: const Text('🎁', style: TextStyle(fontSize: 22)),
                            )
                          : CachedNetworkImage(
                              imageUrl: item.image!,
                              fit: BoxFit.cover,
                              placeholder: (_, _) => Container(color: AppColors.bg),
                              errorWidget: (_, _, _) => Container(
                                color: AppColors.bg,
                                alignment: Alignment.center,
                                child: const Text('🎁', style: TextStyle(fontSize: 22)),
                              ),
                            ),
                    ),
                  ),
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
                        Text(
                          [
                            item.priorityLabel,
                            if (item.price != null) formatMoney(item.price!),
                          ].join('  ·  '),
                          style: const TextStyle(color: AppColors.textDim, fontSize: 12),
                        ),
                        if (item.note != null && item.note!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            item.note!,
                            style: const TextStyle(color: AppColors.textDim, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (item.price != null && item.contributedTotal > 0) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (item.contributedTotal / item.price!).clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: AppColors.bg,
                    valueColor: const AlwaysStoppedAnimation(AppColors.green),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Собрано ${formatMoney(item.contributedTotal)} из ${formatMoney(item.price!)}',
                  style: const TextStyle(color: AppColors.textDim, fontSize: 11),
                ),
              ],
              const SizedBox(height: 10),
              _buildActions(item, takenByOther),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActions(WishItem item, bool takenByOther) {
    if (takenByOther) {
      return Text(
        'Уже дарит ${item.reserverName ?? 'кто-то'}',
        style: const TextStyle(color: AppColors.textDim, fontSize: 12),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            backgroundColor: item.reservedByMe ? AppColors.green : AppColors.bg,
            foregroundColor: item.reservedByMe ? AppColors.bg : AppColors.text,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          onPressed: () => _toggleReserve(item),
          child: Text(item.reservedByMe ? 'Дарю я' : 'Беру на себя'),
        ),
        if (item.price != null)
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.bg,
              foregroundColor: AppColors.text,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            onPressed: () => _contribute(item),
            child: Text(
              item.myContribution == null
                  ? 'Скинуться'
                  : 'Мой вклад ${formatMoney(item.myContribution!)}',
            ),
          ),
      ],
    );
  }

  Future<void> _toggleReserve(WishItem item) async {
    final repo = context.read<WishlistRepository>();
    await repo.reserve(item.id, reserve: !item.reservedByMe);
    await _load();
  }

  Future<void> _contribute(WishItem item) async {
    final amount = await promptText(
      context,
      title: 'Скинуться на «${item.title}»',
      hint: 'Сумма, ₽',
      initial: item.myContribution == null ? '' : item.myContribution!.round().toString(),
      keyboardType: TextInputType.number,
      confirmLabel: 'Готово',
    );
    if (amount == null || !mounted) return;

    final repo = context.read<WishlistRepository>();
    final value = double.tryParse(amount.replaceAll(',', '.'));
    if (value == null || value <= 0) {
      await repo.removeContribution(item.id);
    } else {
      await repo.contribute(item.id, value);
    }
    await _load();
  }
}
