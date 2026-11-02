/// Tam ekran hikâye görüntüleyici.
///
/// Bir yazarın hikâyeleri sırayla oynar (5 sn); dokunarak ilerlenir/geri
/// gidilir, basılı tutunca duraklar. Her gösterilen hikâye cihazda "görüldü"
/// olarak işaretlenir. Beğeni (kind:7) ve görüntüleyenler listesi desteklenir.
library;

import 'package:flutter/material.dart';

import '../../core/identity/key_storage.dart';
import '../../core/media/media_uploader.dart';
import '../../core/session/app_session.dart';
import '../../core/stories/story.dart';
import '../../ui/format.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

Future<void> showStoryViewer(
  BuildContext context, {
  required List<StoryGroup> groups,
  int initialGroup = 0,
}) {
  if (groups.isEmpty) return Future<void>.value();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Hikâye',
    barrierColor: Colors.black,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) =>
        StoryViewer(groups: groups, initialGroup: initialGroup),
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

class StoryViewer extends StatefulWidget {
  const StoryViewer({
    super.key,
    required this.groups,
    this.initialGroup = 0,
  });

  final List<StoryGroup> groups;
  final int initialGroup;

  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) _next();
    });

  late int _groupIndex =
      widget.initialGroup.clamp(0, widget.groups.length - 1).toInt();
  int _itemIndex = 0;
  Set<String> _seen = const {};
  bool _paused = false;
  bool _liked = false;
  int _likesCount = 0;
  Set<String> _likers = const {};
  Set<String> _viewers = const {};

  StoryGroup get _group => widget.groups[_groupIndex];
  int get _itemCount => _group.items.length;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final seen = await KeyStorage().loadSeenStories();
    if (!mounted) return;
    var index = 0;
    for (var i = 0; i < _itemCount; i++) {
      if (!seen.contains(_group.items[i].id)) {
        index = i;
        break;
      }
    }
    setState(() {
      _seen = seen;
      _itemIndex = index;
    });
    _loadReactions();
    _startProgress();
  }

  Future<void> _loadReactions() async {
    final session = AppSession.instance;
    final item = _group.items[_itemIndex];
    final reactions = session.reactions[item.id] ?? <String>{};
    final likers = reactions.toSet();
    // Viewers: those who have seen this story (from local seen + assumption)
    // For now, we only track local views. In a full implementation, this would
    // come from a separate NIP-10000 event or similar.
    setState(() {
      _likers = likers;
      _likesCount = likers.length;
      final myPk = session.keys?.publicKeyHex?.toLowerCase();
      _liked = myPk != null && likers.contains(myPk);
      // Local viewer tracking
      _viewers = _seen.intersection(session.contacts.keys.toSet());
      if (session.keys != null) {
        _viewers.add(session.keys!.publicKeyHex.toLowerCase());
      }
    });
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _startProgress() {
    _markSeen();
    _progress
      ..reset()
      ..forward();
  }

  void _markSeen() {
    final item = _group.items[_itemIndex];
    if (_seen.contains(item.id)) return;
    _seen = {..._seen, item.id};
    KeyStorage().markStorySeen([item.id]);
    // Add self to viewers
    final session = AppSession.instance;
    final myPk = session.keys?.publicKeyHex?.toLowerCase();
    if (myPk != null) {
      setState(() {
        _viewers = {..._viewers, myPk};
      });
    }
  }

  Future<void> _toggleLike() async {
    final session = AppSession.instance;
    final item = _group.items[_itemIndex];
    final myPk = session.keys!.publicKeyHex.toLowerCase();
    if (_liked) {
      // Unlike - send reaction with '-'
      final ok = await session.react(item);
      if (ok && mounted) {
        setState(() {
          _liked = false;
          _likesCount = (_likesCount - 1).clamp(0, 999);
          _likers = {..._likers}..remove(myPk);
        });
      }
    } else {
      // Like - send reaction with '+'
      final ok = await session.react(item);
      if (ok && mounted) {
        setState(() {
          _liked = true;
          _likesCount++;
          _likers = {..._likers, myPk};
        });
      }
    }
  }

  void _showViewersAndLikers() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (ctx) => _ViewersSheet(
        viewers: _viewers,
        likers: _likers,
        session: AppSession.instance,
      ),
    );
  }

  void _next() {
    if (_itemIndex + 1 < _itemCount) {
      setState(() => _itemIndex++);
      _loadReactions();
      _startProgress();
      return;
    }
    if (_groupIndex + 1 < widget.groups.length) {
      setState(() {
        _groupIndex++;
        _itemIndex = 0;
      });
      _loadReactions();
      _startProgress();
      return;
    }
    Navigator.of(context).maybePop();
  }

  void _prev() {
    if (_itemIndex > 0) {
      setState(() => _itemIndex--);
      _startProgress();
      return;
    }
    if (_groupIndex > 0) {
      setState(() {
        _groupIndex--;
        _itemIndex = widget.groups[_groupIndex].items.length - 1;
      });
      _startProgress();
      return;
    }
    _progress
      ..reset()
      ..forward();
  }

  void _pause() {
    _paused = true;
    _progress.stop();
  }

  void _resume() {
    if (!_paused) return;
    _paused = false;
    _progress.forward();
  }

  @override
  Widget build(BuildContext context) {
    final item = _group.items[_itemIndex];
    final profile = AppSession.instance.profiles[item.pubkey];
    final name = profile?.displayName ??
        '${item.pubkey.substring(0, 8)}…';
    final image = MediaRef.firstImageUrl(item);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onLongPressStart: (_) => _pause(),
        onLongPressEnd: (_) => _resume(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (image != null)
              Image.network(
                image,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : const _Loader(),
                errorBuilder: (_, _, _) => _TextStory(
                  text: item.content.isEmpty ? 'Fotoğraf yüklenemedi' : item.content,
                ),
              )
            else
              _TextStory(text: item.content),
            // Okuma alanları: sol geri, sağ ileri.
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _prev,
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _next,
                  ),
                ),
              ],
            ),
            // Üst bilgi çubuğu.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 12,
                  right: 8,
                  bottom: 12,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Column(
                  children: [
                    AnimatedBuilder(
                      animation: _progress,
                      builder: (context, _) => Row(
                        children: [
                          for (var i = 0; i < _itemCount; i++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 2),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value: i < _itemIndex
                                        ? 1
                                        : i == _itemIndex
                                            ? _progress.value
                                            : 0,
                                    minHeight: 3,
                                    backgroundColor: Colors.white24,
                                    valueColor:
                                        const AlwaysStoppedAnimation(
                                            Colors.white),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Avatar(
                          seed: item.pubkey,
                          label: name,
                          imageUrl: profile?.picture,
                          size: 32,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                ),
                              ),
                              Text(
                                relativeTime(item.createdAt),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Like button + count
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: _toggleLike,
                              icon: Icon(
                                _liked ? Icons.favorite : Icons.favorite_border,
                                color: _liked ? Colors.redAccent : Colors.white,
                                size: 22,
                              ),
                              tooltip: _liked ? 'Beğeniyi kaldır' : 'Beğen',
                            ),
                            if (_likesCount > 0)
                              Text(
                                '$_likesCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            const SizedBox(width: 4),
                            // Viewers/likers list
                            IconButton(
                              onPressed: _showViewersAndLikers,
                              icon: const Icon(
                                Icons.remove_red_eye_outlined,
                                color: Colors.white,
                                size: 22,
                              ),
                              tooltip: 'Görüntüleyenler ve beğenenler',
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.close, color: Colors.white),
                          tooltip: 'Kapat',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Alt yazı.
            if (item.content.isNotEmpty && image != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 28,
                    bottom: MediaQuery.of(context).padding.bottom + 20,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: Text(
                    item.content,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TextStory extends StatelessWidget {
  const _TextStory({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1D1B2E), Color(0xFF3A1F2B)],
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Text(
        text.isEmpty ? 'Hikâye' : text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    );
  }
}

class _Loader extends StatelessWidget {
  const _Loader();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 26,
        height: 26,
        child: CircularProgressIndicator(
            strokeWidth: 2.5, color: AppColors.accent),
      ),
    );
  }
}

/// Hikâye görüntüleyenler ve beğenenler listesi.
class _ViewersSheet extends StatelessWidget {
  const _ViewersSheet({
    required this.viewers,
    required this.likers,
    required this.session,
  });

  final Set<String> viewers;
  final Set<String> likers;
  final AppSession session;

  @override
  Widget build(BuildContext context) {
    final allViewers = viewers.toList()
      ..sort((a, b) => likers.contains(b) ? 1 : likers.contains(a) ? -1 : 0);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      maxChildSize: 0.85,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    'Görüntüleyenler (${viewers.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (likers.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.favorite,
                              color: Colors.redAccent, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '${likers.length}',
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: allViewers.isEmpty
                  ? const Center(
                      child: Text(
                        'Henüz kimse görmemiş',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: allViewers.length,
                      itemBuilder: (context, i) {
                        final pk = allViewers[i];
                        final profile = session.profiles[pk];
                        final isLiker = likers.contains(pk);
                        final isMe = pk == session.keys?.publicKeyHex;
                        return ListTile(
                          leading: Avatar(
                            seed: pk,
                            label: profile?.displayName,
                            imageUrl: profile?.picture,
                            size: 40,
                          ),
                          title: Text(
                            isMe ? 'Sen' : (profile?.displayName ?? '${pk.substring(0, 8)}…'),
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: isMe ? const Text('Sen', style: TextStyle(color: Colors.white54)) : null,
                          trailing: isLiker
                              ? const Icon(Icons.favorite, color: Colors.redAccent, size: 18)
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
