import 'package:flutter/material.dart';

import '../../core/nostr/event.dart';
import '../../core/nostr/nip17_nip44.dart';
import '../../core/session/app_session.dart';
import '../../ui/format.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Birebir sohbet.
///
/// Mesajlar `kind:1059` (gift wrap) olarak taşınır; içerik `NIP-44`
/// uyumlu şifreleme katmanından geçer. Karşı taraf `pubkey` (hex) ile tanımlanır.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.recipientPubkey});

  final String recipientPubkey;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: ListenableBuilder(
          listenable: session,
          builder: (context, _) {
            final profile = session.profiles[widget.recipientPubkey];
            return Row(
              children: [
                Avatar(
                  seed: widget.recipientPubkey,
                  label: profile?.displayName,
                  size: 32,
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile?.displayName ??
                            '${widget.recipientPubkey.substring(0, 10)}…',
                        style: theme.textTheme.titleMedium,
                      ),
                      Text('uçtan uca şifreli',
                          style: theme.textTheme.labelMedium
                              ?.copyWith(fontSize: 10.5)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          CircleIconButton(
            icon: Icons.more_horiz,
            onTap: () => _showInfo(context),
          ),
          const SizedBox(width: Insets.md),
        ],
      ),
      body: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final messages = session.giftWraps
              .where((e) => _belongsTo(e, widget.recipientPubkey))
              .toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

          return Column(
            children: [
              Expanded(
                child: messages.isEmpty
                    ? const EmptyState(
                        icon: Icons.lock_outline,
                        title: 'Sohbet boş',
                        message:
                            'Gönderdiğin mesajlar yalnızca sen ve karşı taraf tarafından okunabilir.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                        itemCount: messages.length,
                        itemBuilder: (context, i) {
                          final message = messages[i];
                          final isMe =
                              message.pubkey == session.keys?.publicKeyHex;
                          final showTime = i == 0 ||
                              message.createdAt -
                                      messages[i - 1].createdAt >
                                  300;
                          return Column(
                            children: [
                              if (showTime)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    clockTime(message.createdAt),
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ),
                              _Bubble(
                                text: _decrypt(message),
                                mine: isMe,
                                time: clockTime(message.createdAt),
                              ),
                            ],
                          );
                        },
                      ),
              ),
              _Composer(
                controller: _controller,
                focus: _focus,
                sending: _sending,
                onSend: _send,
              ),
            ],
          );
        },
      ),
    );
  }

  bool _belongsTo(NostrEvent event, String counterpart) {
    final me = AppSession.instance.keys?.publicKeyHex;
    if (event.pubkey == counterpart) return true;
    for (final tag in event.tags) {
      if (tag.length >= 2 && tag[0] == 'p' && tag[1] == counterpart) return true;
    }
    return event.pubkey == me &&
        event.tags.any((t) => t.length >= 2 && t[0] == 'p' && t[1] == counterpart);
  }

  String _decrypt(NostrEvent event) {
    final session = AppSession.instance;
    try {
      return decryptMessage(
          event.content, session.keys?.privateKeyHex ?? '', widget.recipientPubkey);
    } catch (_) {
      return 'Şifreli mesaj';
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final ok = await AppSession.instance.sendDm(widget.recipientPubkey, text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      _controller.clear();
      _focus.requestFocus();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mesaj gönderilemedi')),
      );
    }
  }

  void _showInfo(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sohbet bilgisi',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: Insets.md),
              const Text(
                'Mesajlar `kind:1059` zarfı içinde gönderilir. Sunucu yalnızca '
                'şifreli içeriği görür; anahtarlar cihazda kalır.',
              ),
              const SizedBox(height: Insets.lg),
              SelectableText(
                widget.recipientPubkey,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.mine, required this.time});

  final String text;
  final bool mine;
  final String time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.74,
        ),
        decoration: BoxDecoration(
          color: mine ? AppColors.accent : AppColors.surfaceAlt,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: mine ? null : Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: mine ? AppColors.accentInk : AppColors.text,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              time,
              style: TextStyle(
                fontSize: 10,
                color: mine
                    ? AppColors.accentInk.withValues(alpha: 0.55)
                    : AppColors.textFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focus,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        MediaQuery.of(context).viewInsets.bottom > 0
            ? 10
            : MediaQuery.of(context).padding.bottom + 10,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(
                hintText: 'Mesaj yaz…',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: Insets.sm),
          Material(
            color: AppColors.accent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: sending ? null : onSend,
              child: SizedBox(
                width: 44,
                height: 44,
                child: sending
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.accentInk),
                      )
                    : const Icon(Icons.arrow_upward,
                        size: 20, color: AppColors.accentInk),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
