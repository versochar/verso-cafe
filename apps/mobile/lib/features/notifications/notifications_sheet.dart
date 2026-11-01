import 'package:flutter/material.dart';

import '../../core/session/app_session.dart';
import '../../ui/format.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../feed/post_tile.dart';
import '../feed/user_sheet.dart';

/// Bildirim merkezi: gönderilerine gelen beğeni/yorum/yeniden gönderimler.
/// Açıldığında okundu zamanını kalıcı olarak günceller.
Future<void> showNotificationsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const NotificationsSheet(),
  );
}

class NotificationsSheet extends StatefulWidget {
  const NotificationsSheet({super.key});

  @override
  State<NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<NotificationsSheet> {
  /// Sheet açıldığı andeki okundu zamanı; bu andan sonrası "okunmamış" noktası.
  int _openedAfter = 0;

  @override
  void initState() {
    super.initState();
    _openedAfter = AppSession.instance.activityReadAt;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppSession.instance.markActivityRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scrollController) => ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final items = session.activity;
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
              Row(
                children: [
                  Text('Bildirimler',
                      style: theme.textTheme.titleLarge),
                  const Spacer(),
                  if (items.isNotEmpty)
                    Text('${items.length} kayıt',
                        style: theme.textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: Insets.lg),
              if (items.isEmpty)
                const EmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: 'Henüz bildirim yok',
                  message:
                      'Gönderilerini beğenen, yorum yapan ya da yeniden '
                      'gönderen kişiler burada görünecek.',
                )
              else
                RowsGroup(
                  children: [
                    for (final item in items)
                      _ActivityRow(
                          item: item, unread: item.createdAt > _openedAfter),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item, required this.unread});

  final ActivityItem item;
  final bool unread;

  static const _verbs = {
    'like': 'gönderini beğendi',
    'comment': 'gönderine yorum yaptı',
    'repost': 'gönderini yeniden gönderdi',
  };
  static const _icons = {
    'like': Icons.favorite,
    'comment': Icons.mode_comment_outlined,
    'repost': Icons.repeat,
  };

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;
    final theme = Theme.of(context);
    final actor = session.profiles[item.actor];
    final name = actor?.displayName ?? '${item.actor.substring(0, 8)}…';
    final note = session.noteById(item.targetId);

    return InkWell(
      onTap: () {
        if (note != null) {
          showPostSheet(context, note);
        } else {
          showUserSheet(context, item.actor);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: Insets.lg, vertical: Insets.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Avatar(
                  seed: item.actor,
                  label: name,
                  imageUrl: actor?.picture,
                  size: 38,
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Icon(
                      _icons[item.action] ?? Icons.notifications_none,
                      size: 10,
                      color: item.action == 'like'
                          ? AppColors.accent
                          : AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: theme.textTheme.bodyMedium,
                      children: [
                        TextSpan(
                          text: name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                        TextSpan(text: ' ${_verbs[item.action] ?? item.action}'),
                      ],
                    ),
                  ),
                  if ((item.commentText ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '“${item.commentText!}”',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppColors.textMuted),
                      ),
                    )
                  else if (note != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        note.content,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.textFaint),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: Insets.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  relativeTime(item.createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
                ),
                if (unread) ...[
                  const SizedBox(height: 4),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
