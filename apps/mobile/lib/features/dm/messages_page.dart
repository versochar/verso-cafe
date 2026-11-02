import 'package:flutter/material.dart';
import 'dart:convert';

import '../../core/nostr/bech32.dart';
import '../../core/nostr/event.dart';
import '../../core/nostr/nip17_nip44.dart';
import '../../core/session/app_session.dart';
import '../../ui/format.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../identity/scan_page.dart';
import 'dm_page.dart';

/// Mesajlar: sohbet listesi ve yeni sohbet başlatma.
class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;

    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final threads = _threads(session);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Mesajlar',
                subtitle: threads.isEmpty
                    ? 'Uçtan uca şifreli'
                    : '${threads.length} sohbet',
                actions: [
                  CircleIconButton(
                    icon: Icons.qr_code_scanner,
                    tooltip: 'Davet QR’ı tara',
                    onTap: () => showScanQr(context),
                  ),
                  const SizedBox(width: Insets.sm),
                  CircleIconButton(
                    icon: Icons.edit_square,
                    tooltip: 'Yeni mesaj',
                    filled: true,
                    onTap: () => _newMessage(context),
                  ),
                  const SizedBox(width: Insets.sm),
                ],
              ),
              const SizedBox(height: Insets.sm),
              Expanded(
                child: threads.isEmpty
                    ? ListView(
                        children: [
                          EmptyState(
                            icon: Icons.mark_email_unread_outlined,
                            title: 'Gelen kutusu boş',
                            message:
                                'Yeni bir sohbet başlatmak için sağ üstteki simgeye dokun.',
                            action: OutlinedButton(
                              onPressed: () => _newMessage(context),
                              child: const Text('Yeni mesaj'),
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(
                            left: 20, right: 20, bottom: 96, top: 4),
                        itemCount: threads.length,
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder: (context, i) {
                          final thread = threads[i];
                          final profile =
                              session.profiles[thread.pubkey];
                          return InkWell(
                            borderRadius: BorderRadius.circular(Radii.sm),
                            onTap: () => _openChat(context, thread.pubkey),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              child: Row(
                                children: [
                                  Avatar(
                                    seed: thread.pubkey,
                                    label: profile?.displayName,
                                    size: 42,
                                  ),
                                  const SizedBox(width: Insets.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                profile?.displayName ??
                                                    '${thread.pubkey.substring(0, 10)}…',
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium,
                                              ),
                                            ),
                                            Text(
                                              relativeTime(
                                                  thread.last.createdAt),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: AppColors.textFaint,
                                                  ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          _preview(session, thread),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _preview(AppSession session, _Thread thread) {
    try {
      final decrypted = decryptMessage(thread.last.content,
          session.keys?.privateKeyHex ?? '', thread.pubkey);
      // JSON formatından text'i çıkar
      try {
        final data = jsonDecode(decrypted);
        if (data is Map && data['text'] is String) {
          return data['text'] as String;
        }
      } catch (_) {}
      return decrypted;
    } catch (_) {
      return 'Şifreli mesaj';
    }
  }

  static List<_Thread> _threads(AppSession session) {
    final me = session.keys?.publicKeyHex ?? '';
    final map = <String, _Thread>{};
    for (final event in session.giftWraps) {
      final counterpart = event.pubkey == me ? _pTag(event) : event.pubkey;
      if (counterpart == null || counterpart.isEmpty || counterpart == me) {
        continue;
      }
      final existing = map[counterpart];
      if (existing == null || event.createdAt > existing.last.createdAt) {
        map[counterpart] = _Thread(counterpart, event);
      }
    }
    final list = map.values.toList()
      ..sort((a, b) => b.last.createdAt.compareTo(a.last.createdAt));
    return list;
  }

  static String? _pTag(NostrEvent event) {
    for (final tag in event.tags) {
      if (tag.length >= 2 && tag[0] == 'p') return tag[1];
    }
    return null;
  }

  static void _openChat(BuildContext context, String pubkey) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ChatPage(recipientPubkey: pubkey)),
    );
  }

  void _newMessage(BuildContext context) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yeni sohbet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Karşı tarafın `npub` ya da genel anahtarını gir.'),
            const SizedBox(height: Insets.lg),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'npub1… veya hex'),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              showScanQr(context);
            },
            icon: const Icon(Icons.qr_code_scanner, size: 18),
            label: const Text('QR tara'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () {
              final input = controller.text.trim();
              final pubkey = _resolve(input);
              if (pubkey == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Geçerli bir npub gir')),
                );
                return;
              }
              Navigator.pop(ctx);
              _openChat(context, pubkey);
            },
            child: const Text('Başlat'),
          ),
        ],
      ),
    );
  }

  static String? _resolve(String input) {
    if (input.isEmpty) return null;
    if (input.startsWith('npub1')) {
      try {
        final decoded = bech32Decode(input);
        if (decoded.hrp != 'npub' || decoded.data.length != 32) return null;
        return bytesToHex(decoded.data);
      } catch (_) {
        return null;
      }
    }
    final hex = input.toLowerCase();
    if (hex.length == 64 && RegExp(r'^[0-9a-f]+$').hasMatch(hex)) return hex;
    return null;
  }
}

class _Thread {
  const _Thread(this.pubkey, this.last);

  final String pubkey;
  final NostrEvent last;
}
