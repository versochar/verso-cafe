import 'package:flutter/material.dart';

import '../../core/nostr/bech32.dart';
import '../../core/session/app_session.dart';
import '../../ui/format.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../dm/dm_page.dart';
import 'post_tile.dart';

/// Bir kişinin özet profili: takip/takipci, aksiyonlar ve gönderileri.
/// Akıştaki kullanıcı adindan ve kesfet izgarasindan acilir.
Future<void> showUserSheet(BuildContext context, String pubkey) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => UserSheet(pubkey: pubkey),
  );
}

class UserSheet extends StatelessWidget {
  const UserSheet({super.key, required this.pubkey});

  final String pubkey;

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;
    final isMe = pubkey == session.keys?.publicKeyHex;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.95,
      builder: (context, scrollController) => ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final profile = session.profiles[pubkey];
          final name = profile?.displayName ?? '${pubkey.substring(0, 8)}…';
          final posts = session.notesBy(pubkey);
          final following = session.isFollowing(pubkey);

          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.lineStrong, borderRadius: Radii.pill),
                ),
              ),
              const SizedBox(height: Insets.lg),
              Column(
                children: [
                  Avatar(
                    seed: pubkey,
                    label: name,
                    imageUrl: profile?.picture,
                    size: 72,
                  ),
                  const SizedBox(height: Insets.md),
                  Text(name, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 2),
                  Text(
                    shortNpub(bech32Encode('npub', hexToBytes(pubkey))),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                  ),
                ],
              ),
              if ((profile?.about ?? '').isNotEmpty) ...[
                const SizedBox(height: Insets.md),
                Text(
                  profile!.about!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: Insets.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _MiniStat(value: posts.length, label: 'gönderi'),
                  const _Dot(),
                  _MiniStat(
                      value: session.followingCount(pubkey), label: 'takip'),
                  const _Dot(),
                  _MiniStat(
                      value: session.followerCount(pubkey), label: 'takipçi'),
                ],
              ),
              const SizedBox(height: Insets.lg),
              if (!isMe)
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(42),
                          backgroundColor:
                              following ? AppColors.surfaceAlt : null,
                          foregroundColor:
                              following ? AppColors.text : null,
                          side: following
                              ? const BorderSide(color: AppColors.lineStrong)
                              : null,
                        ),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final ok =
                              await session.followPerson(pubkey);
                          messenger.showSnackBar(SnackBar(
                            content: Text(ok
                                ? (following
                                    ? 'Takipten çıkarılamadı'
                                    : 'Takip ediliyor')
                                : 'İşlem gönderilemedi'),
                          ));
                        },
                        child: Text(following ? 'Takip ediliyor' : 'Takip et'),
                      ),
                    ),
                    const SizedBox(width: Insets.sm),
                    SizedBox(
                      height: 42,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 42),
                          padding: const EdgeInsets.symmetric(
                              horizontal: Insets.lg),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ChatPage(recipientPubkey: pubkey),
                            ),
                          );
                        },
                        child: const Text('Mesaj'),
                      ),
                    ),
                  ],
                ),
              if (!isMe)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final ok = await session.toggleMute(pubkey);
                      messenger.showSnackBar(SnackBar(
                        content: Text(ok
                            ? (session.isMuted(pubkey)
                                ? 'Kullanıcı engellendi'
                                : 'Engel kaldırıldı')
                            : 'İşlem gönderilemedi'),
                      ));
                    },
                    icon: Icon(
                      session.isMuted(pubkey)
                          ? Icons.remove_circle_outline
                          : Icons.block,
                      size: 17,
                    ),
                    label: Text(session.isMuted(pubkey)
                        ? 'Engeli kaldır'
                        : 'Engelle'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textMuted,
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              const SizedBox(height: Insets.lg),
              const Divider(),
              SectionLabel('Gönderiler'),
              if (posts.isEmpty)
                const EmptyState(
                  icon: Icons.article_outlined,
                  title: 'Gönderi yok',
                  message: 'Bu kişinin henüz paylaşımı yok.',
                )
              else
                for (final p in posts) ...[
                  PostTile(event: p),
                  const Divider(),
                ],
            ],
          );
        },
      ),
    );
  }

}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$value',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Text('·', style: TextStyle(color: AppColors.textFaint)),
      );
}
