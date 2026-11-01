import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/media/media_uploader.dart';
import '../../core/nostr/event.dart';
import '../../core/session/app_session.dart';
import '../../ui/format.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'user_sheet.dart';

/// Akıştaki tek bir gönderi (tam genişlik kart).
///
/// Yorum ve beğeni işlemleri oturum üzerinden relay'e yazılır; iyimser
/// güncelleme yalnızca beğenide yapılır (tek tuşla geri alınabildiği için).
class PostTile extends StatelessWidget {
  const PostTile({
    super.key,
    required this.event,
    this.hideActions = false,
    this.repostedBy,
  });

  final NostrEvent event;
  final bool hideActions;

  /// Bu gönderi birileri tarafından yeniden gönderildiyse o `kind:6` olayı.
  final NostrEvent? repostedBy;

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;
    final theme = Theme.of(context);
    final author = session.profiles[event.pubkey];
    final name = author?.displayName ?? '${event.pubkey.substring(0, 8)}…';
    final mine = event.pubkey == session.keys?.publicKeyHex;
    final likes = session.reactionCount(event.id);
    final comments = session.commentsFor(event.id);
    final liked = session.reactedByMe(event.id);
    final saved = session.savedByMe(event.id);
    final reposts = session.repostCount(event.id);
    final reposted = session.repostedByMe(event.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (repostedBy != null)
          Builder(builder: (context) {
            final rpAuthor = session.profiles[repostedBy!.pubkey];
            final rpName = rpAuthor?.displayName ??
                '${repostedBy!.pubkey.substring(0, 6)}…';
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.repeat, size: 13, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$rpName yeniden gönderdi · '
                      '${feedTime(repostedBy!.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
            );
          }),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              InkWell(
                onTap: () => showUserSheet(context, event.pubkey),
                customBorder: const CircleBorder(),
                child: Avatar(
                  seed: event.pubkey,
                  label: name,
                  imageUrl: author?.picture,
                  size: 32,
                ),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: InkWell(
                  onTap: () => showUserSheet(context, event.pubkey),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ),
              ),
              if (mine)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Text(
                    'SEN',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              Text(
                feedTime(event.createdAt),
                style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
              ),
              SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  splashRadius: 16,
                  icon: const Icon(Icons.more_horiz, size: 20),
                  color: AppColors.text,
                  onPressed: () => _openMenu(context),
                ),
              ),
            ],
          ),
        ),
        if (event.content.isNotEmpty ||
            MediaRef.firstImageUrl(event) == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              event.content.isEmpty ? '(boş gönderi)' : event.content,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        if (MediaRef.firstImageUrl(event) case final imageUrl?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: PostImage(url: imageUrl),
          ),
        if (!hideActions) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
            child: Row(
              children: [
                _Action(
                  icon: liked ? Icons.favorite : Icons.favorite_border,
                  color: liked ? AppColors.accent : AppColors.text,
                  onTap: () => _toggleLike(context),
                  tooltip: 'Beğen',
                ),
                _Action(
                  icon: Icons.mode_comment_outlined,
                  onTap: () => _openReply(context),
                  tooltip: 'Yorum yap',
                ),
                _Action(
                  icon: Icons.repeat,
                  color: reposted ? AppColors.accent : AppColors.text,
                  onTap: () => _repost(context),
                  tooltip: reposted ? 'Yeniden gönderdin' : 'Yeniden gönder',
                ),
                const Spacer(),
                _Action(
                  icon: saved ? Icons.bookmark : Icons.bookmark_border,
                  color: saved ? AppColors.text : AppColors.text,
                  onTap: () => session.toggleSave(event.id),
                  tooltip: 'Kaydet',
                ),
              ],
            ),
          ),
          if (likes > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                '$likes beğeni'
                '${reposts > 0 ? ' · $reposts yeniden gönderim' : ''}',
                style: theme.textTheme.titleSmall,
              ),
            )
          else if (reposts > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('$reposts yeniden gönderim',
                  style: theme.textTheme.titleSmall),
            ),
          _ReplyLines(event: event, comments: comments),
          const SizedBox(height: Insets.sm),
        ],
      ],
    );
  }

  Future<void> _toggleLike(BuildContext context) async {
    final ok = await AppSession.instance.react(event);
    if (!ok && context.mounted) {
      _toast(context, 'Beğeni gönderilemedi — relay bağlantısını kontrol et');
    }
  }

  Future<void> _repost(BuildContext context) async {
    final session = AppSession.instance;
    if (session.repostedByMe(event.id)) {
      _toast(context, 'Bu gönderiyi zaten yeniden gönderdin');
      return;
    }
    final ok = await session.repostNote(event);
    if (!ok && context.mounted) {
      _toast(context, 'Yeniden gönderim iletilemedi — relay bağlantısını kontrol et');
    } else if (context.mounted) {
      _toast(context, 'Yeniden gönderildi');
    }
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: event.id));
    _toast(context, 'Etkinlik kimliği kopyalandı');
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openMenu(BuildContext context) {
    final session = AppSession.instance;
    final mine = event.pubkey == session.keys?.publicKeyHex;
    final muted = session.isMuted(event.pubkey);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            RowItem(
              icon: Icons.person_outline_rounded,
              title: 'Yazarın profili',
              onTap: () {
                Navigator.pop(ctx);
                showUserSheet(context, event.pubkey);
              },
            ),
            RowItem(
              icon: Icons.link,
              title: 'Etkinlik kimliğini kopyala',
              onTap: () {
                Navigator.pop(ctx);
                _copy(context);
              },
            ),
            if (mine)
              RowItem(
                icon: Icons.delete_outline,
                title: 'Gönderiyi sil',
                danger: true,
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await session.deleteNote(event);
                  if (!ok && context.mounted) {
                    _toast(context, 'Silme isteği gönderilemedi');
                  }
                },
              ),
            if (!mine)
              RowItem(
                icon: muted ? Icons.remove_circle_outline : Icons.block,
                title: muted ? 'Engeli kaldır' : 'Engelle',
                danger: !muted,
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await session.toggleMute(event.pubkey);
                  if (!ok && context.mounted) {
                    _toast(context, 'Engelleme yayınlanamadı');
                  } else if (context.mounted) {
                    _toast(context, muted ? 'Engel kaldırıldı' : 'Kullanıcı engellendi');
                  }
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _openReply(BuildContext context) {
    final controller = TextEditingController();
    final session = AppSession.instance;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Avatar(
                    seed: session.keys?.publicKeyHex ?? '',
                    label: session.me.name,
                    imageUrl: session.me.picture,
                    size: 32,
                  ),
                  const SizedBox(width: Insets.md),
                  Text('Yorum ekle',
                      style: Theme.of(ctx).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: Insets.lg),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 2,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(hintText: 'Yorumunu yaz…'),
              ),
              const SizedBox(height: Insets.md),
              FilledButton(
                onPressed: () async {
                  final text = controller.text;
                  Navigator.pop(ctx);
                  final ok = await session.comment(event, text);
                  if (!ok && context.mounted) {
                    _toast(context, 'Yorum gönderilemedi');
                  }
                },
                child: const Text('Yorumla'),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "N yanıttan tümünü gör" satırı ya da kısa yorumların kendisi.
class _ReplyLines extends StatelessWidget {
  const _ReplyLines({required this.event, required this.comments});

  final NostrEvent event;
  final List<NostrEvent> comments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = AppSession.instance;

    if (comments.isEmpty) return const SizedBox(height: 6);

    if (comments.length > 2) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: InkWell(
          onTap: () => showPostSheet(context, event),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              'Tüm ${comments.length} yorumu gör',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textMuted),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final c in comments)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: RichText(
                text: TextSpan(
                  style: theme.textTheme.bodyMedium,
                  children: [
                    TextSpan(
                      text:
                          '${session.profiles[c.pubkey]?.displayName ?? '${c.pubkey.substring(0, 6)}…'} ',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    TextSpan(text: c.content),
                  ],
                ),
              ),
            ),
          InkWell(
            onTap: () => showPostSheet(context, event),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                'Yanıtla',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gönderi detayı: kartın kendisi + tüm yorumlar.
Future<void> showPostSheet(BuildContext context, NostrEvent event) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) => ListenableBuilder(
        listenable: AppSession.instance,
        builder: (ctx, _) {
          final comments = AppSession.instance.commentsFor(event.id);
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: Insets.md),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.lineStrong, borderRadius: Radii.pill),
                ),
              ),
              PostTile(event: event),
              const Divider(indent: 16, endIndent: 16),
              if (comments.isEmpty)
                const EmptyState(
                  icon: Icons.mode_comment_outlined,
                  title: 'Henüz yorum yok',
                  message: 'İlk yorumu sen yaz.',
                )
              else
                for (final c in comments)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Avatar(
                          seed: c.pubkey,
                          label: AppSession
                              .instance.profiles[c.pubkey]?.displayName,
                          size: 28,
                        ),
                        const SizedBox(width: Insets.md),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: Theme.of(ctx).textTheme.bodyMedium,
                              children: [
                                TextSpan(
                                  text:
                                      '${AppSession.instance.profiles[c.pubkey]?.displayName ?? '${c.pubkey.substring(0, 6)}…'} ',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.text,
                                  ),
                                ),
                                TextSpan(text: c.content),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: Insets.sm),
                        Text(
                          relativeTime(c.createdAt),
                          style: Theme.of(ctx)
                              .textTheme
                              .labelSmall
                              ?.copyWith(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
            ],
          );
        },
      ),
    ),
  );
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.onTap,
    this.color,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      onTap: onTap,
      borderRadius: Radii.pill,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        child: Icon(icon, size: 22, color: color ?? AppColors.text),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
