import 'package:flutter/material.dart';

import '../../core/media/media_uploader.dart';
import '../../core/nostr/bech32.dart';
import '../../core/nostr/event.dart';
import '../../core/session/app_session.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../feed/post_tile.dart';
import '../feed/user_sheet.dart';

/// Keşfet: kişi arama ve tüm gönderilerin ızgarası.
class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() => _query = _search.text.trim()));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;

    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final people = _matchPeople(session, _query);
          final posts = session.visibleNotes;

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Text(
                  'Keşfet',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    color: AppColors.text,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    hintText: 'İsim veya npub ara…',
                    prefixIcon: Icon(Icons.search,
                        size: 19, color: AppColors.textFaint),
                    prefixIconConstraints:
                        BoxConstraints(minWidth: 40, minHeight: 0),
                  ),
                ),
              ),
              if (people.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: SectionLabel(
                      _query.isEmpty ? 'İnsanlar' : 'Arama sonuçları'),
                ),
                SizedBox(
                  height: 92,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    children: [
                      for (final p in people)
                        SizedBox(
                          width: 76,
                          child: InkWell(
                            onTap: () => showUserSheet(context, p.pubkey),
                            customBorder: const CircleBorder(),
                            child: Column(
                              children: [
                                Avatar(
                                  seed: p.pubkey,
                                  label: p.displayName,
                                  imageUrl: p.picture,
                                  size: 56,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  p.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                        color: AppColors.textMuted,
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: SectionLabel('Gönderiler'),
              ),
              if (posts.isEmpty)
                const EmptyState(
                  icon: Icons.grid_view_outlined,
                  title: 'Henüz bir şey yok',
                  message:
                      'Relay üzerindeki tüm gönderiler burada toplanır.',
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                  ),
                  itemCount: posts.length,
                  itemBuilder: (context, i) =>
                      _PostThumb(event: posts[i]),
                ),
            ],
          );
        },
      ),
    );
  }

  static List<ProfileView> _matchPeople(AppSession session, String query) {
    final q = query.toLowerCase();
    final all = session.profiles.values
        .where((p) => !session.isMuted(p.pubkey))
        .toList()
      ..sort((a, b) {
        final an = session.notesBy(a.pubkey).length;
        final bn = session.notesBy(b.pubkey).length;
        return bn.compareTo(an);
      });
    if (q.isEmpty) return all.take(12).toList();

    String? hex;
    if (q.startsWith('npub1')) {
      try {
        hex = bytesToHex(bech32Decode(q).data);
      } catch (_) {
        hex = null;
      }
    }
    return all
        .where((p) =>
            p.displayName.toLowerCase().contains(q) ||
            p.pubkey.startsWith(q) ||
            (hex != null && p.pubkey == hex))
        .toList();
  }
}

/// Izgaradaki kare gönderi küçüğü.
class _PostThumb extends StatelessWidget {
  const _PostThumb({required this.event});

  final NostrEvent event;

  @override
  Widget build(BuildContext context) {
    final color = Avatar.colorFor(event.pubkey);

    // Foto gönderisi: kapak görseliyle kısa yol.
    if (MediaRef.firstImageUrl(event) case final url?) {
      return Material(
        color: AppColors.surface,
        child: InkWell(
          onTap: () => showPostSheet(context, event),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, _, _) => const ColoredBox(
              color: AppColors.surface,
              child: Icon(Icons.broken_image_outlined,
                  color: AppColors.textFaint),
            ),
          ),
        ),
      );
    }

    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: () => showPostSheet(context, event),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.14),
                AppColors.surface,
              ],
            ),
            border: Border.all(color: AppColors.line.withValues(alpha: 0.6)),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Avatar(
                seed: event.pubkey,
                label: AppSession.instance.profiles[event.pubkey]?.displayName,
                size: 20,
              ),
              const Spacer(),
              Text(
                event.content.isEmpty ? '·' : event.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  height: 1.3,
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
