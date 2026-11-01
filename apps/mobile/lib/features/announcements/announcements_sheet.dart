/// Duyuru alanı: liste, yazma ve yetki yönetimi (host).
///
/// Duyuruları yalnız host ve modlar yazabilir (istemci + Firestore kuralları).
/// Host, yetkiler ekranından mod ekler/çıkarır ve hostluğu devreder —
/// "kendi hesabımı açınca hostluğu ona veririm" akışı buradan yürür.
library;

import 'package:flutter/material.dart';

import '../../core/accounts/account_service.dart';
import '../../ui/format.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Duyurular bottom sheet'i — akıştaki 📣 kartından açılır.
Future<void> showAnnouncements(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _AnnouncementsSheet(),
  );
}

class _AnnouncementsSheet extends StatelessWidget {
  const _AnnouncementsSheet();

  @override
  Widget build(BuildContext context) {
    final me = AccountService.instance.account;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: AppColors.lineStrong, borderRadius: Radii.pill),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
            child: Row(
              children: [
                const Icon(Icons.campaign_outlined,
                    color: AppColors.accent, size: 20),
                const SizedBox(width: 8),
                Text('Duyurular',
                    style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                if (me?.canAnnounce ?? false)
                  CircleIconButton(
                    icon: Icons.edit_note,
                    tooltip: 'Duyuru yaz',
                    onTap: () => _compose(context),
                  ),
                if (me?.isHost ?? false)
                  CircleIconButton(
                    icon: Icons.shield_outlined,
                    tooltip: 'Yetki yönetimi',
                    onTap: () => showRoleAdmin(context),
                  ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Announcement>>(
              stream: AnnouncementService.instance.watch(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  );
                }
                final items = snap.data!;
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.campaign_outlined,
                    title: 'Duyuru yok',
                    message: 'Host ve modlar yazdıkça burada listelenir.',
                  );
                }
                return ListView.separated(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _AnnouncementCard(
                    item: items[i],
                    canDelete: me?.isHost ?? false,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _compose(BuildContext context) async {
    final title = TextEditingController();
    final body = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: const Text('Duyuru yaz'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Başlık'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: body,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Metin'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yayınla')),
        ],
      ),
    );
    if (send != true && context.mounted) return;
    try {
      await AnnouncementService.instance
          .post(title: title.text, body: body.text);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Duyuru yayınlandı 📣')),
        );
      }
    } on AccountException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.item, required this.canDelete});

  final Announcement item;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    return Surface(
      padding: const EdgeInsets.all(14),
      borderColor: AppColors.accent.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              if (canDelete)
                InkWell(
                  borderRadius: Radii.pill,
                  onTap: () => AnnouncementService.instance.delete(item.id),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.delete_outline,
                        size: 18, color: AppColors.textFaint),
                  ),
                )
              else
                const Icon(Icons.lock_outline,
                    size: 14, color: AppColors.textFaint),
            ],
          ),
          if (item.body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(item.body,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 8),
          Text(
            '${item.authorName} · ${relativeTime(item.createdAtMs ~/ 1000)}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------- yetki yönetimi

/// Host: hesap listesi + rol değiştirme + hostluk devri.
Future<void> showRoleAdmin(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _RoleAdminSheet(),
  );
}

class _RoleAdminSheet extends StatefulWidget {
  const _RoleAdminSheet();

  @override
  State<_RoleAdminSheet> createState() => _RoleAdminSheetState();
}

class _RoleAdminSheetState extends State<_RoleAdminSheet> {
  List<Account>? _users;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final users = await AccountService.instance.listUsers();
      if (mounted) setState(() => _users = users);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _setRole(Account a, AccountRole role) async {
    try {
      await AccountService.instance.setRole(a.uid, role);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Yetki verilemedi: $e')));
      }
    }
  }

  Future<void> _transfer(Account a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: const Text('Hostluğu devret'),
        content: Text(
          'Hostluk "${a.username}" hesabına devredilsin mi?\n\n'
          'Sen normal üyeye düşersin; yetki geri alınamaz hâle gelir '
          '(yeni host isterse sana mod verebilir).',
          style: Theme.of(ctx).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Devret')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AccountService.instance.transferHost(a.uid);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hostluk ${a.username} hesabına devredildi')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Devir başarısız: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = AccountService.instance.account;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: AppColors.lineStrong, borderRadius: Radii.pill),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined,
                    color: AppColors.accent, size: 20),
                const SizedBox(width: 8),
                Text('Yetki yönetimi',
                    style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Modlar duyuru yazabilir. Host her şeyi yönetir ve tek kişidir.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _error != null
                ? Center(child: Text(_error!))
                : _users == null
                    ? const Center(
                        child: SizedBox(
                            width: 24,
                            height: 24,
                            child:
                                CircularProgressIndicator(strokeWidth: 2.5)))
                    : ListView.builder(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                        itemCount: _users!.length,
                        itemBuilder: (_, i) {
                          final u = _users![i];
                          final isMe = u.uid == me?.uid;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Surface(
                              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                              child: Row(
                                children: [
                                  Avatar(seed: u.username, size: 36),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isMe
                                              ? '${u.username} (sen)'
                                              : u.username,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600),
                                        ),
                                        Text(u.role.labelTR,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall),
                                      ],
                                    ),
                                  ),
                                  if (!isMe && u.role != AccountRole.host)
                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons.tune, size: 20),
                                      onSelected: (v) => switch (v) {
                                        'mod' => _setRole(
                                            u, AccountRole.mod),
                                        'user' => _setRole(
                                            u, AccountRole.user),
                                        'host' => _transfer(u),
                                        _ => null,
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                            value: 'mod',
                                            child: Text('Mod yap / Modu bırak')),
                                        PopupMenuItem(
                                            value: 'user',
                                            child: Text('Üyeye indir')),
                                        PopupMenuItem(
                                            value: 'host',
                                            child: Text('Hostluğu devret…')),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
