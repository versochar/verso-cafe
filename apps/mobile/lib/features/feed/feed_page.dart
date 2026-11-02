import 'package:flutter/material.dart';

import '../../core/accounts/account_service.dart';
import '../../core/config/app_config.dart';
import '../../core/session/app_session.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../announcements/announcements_sheet.dart';
import '../notifications/notifications_sheet.dart';
import '../stories/story_row.dart';
import 'compose_sheet.dart';
import 'post_tile.dart';

/// Akış: üstte hikâye sırası, altta relay'den gelen `kind:1` notları.
class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;

    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final feed = session.feedItems;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                child: Row(
                  children: [
                    Text(
                      AppConfig.name,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.6,
                          ),
                    ),
                    const Spacer(),
                    _NotificationsBell(unread: session.unreadActivity),
                    const SizedBox(width: 4),
                    ConnectionBadge(connected: session.connected),
                  ],
                ),
              ),
              const StoryRow(),
              const Divider(height: 1),
              const _AnnouncementBanner(),
              Expanded(
                child: feed.isEmpty
                    ? ListView(
                        children: [
                          EmptyState(
                            icon: Icons.auto_stories_outlined,
                            title: 'Akış henüz sessiz',
                            message:
                                'İlk gönderiyi sen paylaş; takip ettiklerinin '
                                'paylaşımları burada görünecek.',
                            action: OutlinedButton(
                              onPressed: () => showComposer(context),
                              child: const Text('İlk gönderiyi yaz'),
                            ),
                          ),
                        ],
                      )
                    : RefreshIndicator(
                        color: AppColors.accent,
                        backgroundColor: AppColors.surface,
                        onRefresh: () async {
                          // Relay aboneliği canlı; kısa bir bekleme yeterli.
                          await Future<void>.delayed(
                              const Duration(milliseconds: 400));
                        },
                        child: ListView.separated(
                          padding: const EdgeInsets.only(bottom: 96),
                          itemCount: feed.length,
                          separatorBuilder: (_, _) => const Divider(
                              height: 1, thickness: 1, color: AppColors.line),
                          itemBuilder: (context, i) => PostTile(
                            event: feed[i].note,
                            repostedBy: feed[i].repostedBy,
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Akışın üstündeki duyuru şeridi: en son duyuruyu gösterir, dokununca
/// listeyi açar. Hesabı olmayan (yerel anahtar) oturumlarda ve
/// duyuru yoksa görünmez.
class _AnnouncementBanner extends StatefulWidget {
  const _AnnouncementBanner();

  @override
  State<_AnnouncementBanner> createState() => _AnnouncementBannerState();
}

class _AnnouncementBannerState extends State<_AnnouncementBanner> {
  /// Tek kez üretilir; akış her kurulduğunda yeni bir yoklama zamanlayıcısı
  /// açılmasın diye stream örneği sabit tutulur.
  late final Stream<List<Announcement>> _stream =
      AccountService.instance.signedIn
          ? AnnouncementService.instance.watch(limit: 1)
          : const Stream.empty();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Announcement>>(
      stream: _stream,
      builder: (context, snap) {
        final items = snap.data;
        if (items == null || items.isEmpty) return const SizedBox.shrink();
        final a = items.first;
        return InkWell(
          onTap: () => showAnnouncements(context),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.line)),
              color: AppColors.accentWash,
            ),
            child: Row(
              children: [
                const Icon(Icons.campaign,
                    size: 18, color: AppColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    a.body.isEmpty ? a.title : '${a.title} — ${a.body}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13.5),
                  ),
                ),
                const Icon(Icons.chevron_right,
                    size: 18, color: AppColors.textMuted),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Başlıktaki zil; okunmamış bildirim varsa turuncu nokta rozeti gösterir.
class _NotificationsBell extends StatelessWidget {
  const _NotificationsBell({required this.unread});

  final int unread;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 34,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            splashRadius: 17,
            icon: const Icon(Icons.notifications_none_rounded, size: 22),
            color: AppColors.text,
            tooltip: 'Bildirimler',
            onPressed: () => showNotificationsSheet(context),
          ),
          if (unread > 0)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.surface, width: 1.5),
                ),
                child: Text(
                  unread > 9 ? '9+' : '$unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
