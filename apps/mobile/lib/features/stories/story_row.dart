/// Akışın üstündeki hikâye şeridi.
///
/// Kendi hikâyen varsa halkaya dokununca açılır; yoksa doğrudan besteci
/// açılır. + rozeti her zaman yeni hikâye ekler. Görülmemiş hikâyeler
/// turuncu halkayla işaretlenir; görüldü durumu cihazda (Keystore) tutulur.
library;

import 'package:flutter/material.dart';

import '../../core/identity/key_storage.dart';
import '../../core/session/app_session.dart';
import '../../core/stories/story.dart';
import '../../ui/widgets.dart';
import 'story_composer.dart';
import 'story_viewer.dart';

class StoryRow extends StatefulWidget {
  const StoryRow({super.key});

  @override
  State<StoryRow> createState() => _StoryRowState();
}

class _StoryRowState extends State<StoryRow> {
  Set<String> _seen = const {};

  @override
  void initState() {
    super.initState();
    _loadSeen();
  }

  Future<void> _loadSeen() async {
    final seen = await KeyStorage().loadSeenStories();
    if (mounted) setState(() => _seen = seen);
  }

  Future<void> _open(
      BuildContext context, List<StoryGroup> groups, int index) async {
    await showStoryViewer(context, groups: groups, initialGroup: index);
    if (mounted) await _loadSeen();
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final groups = session.storyGroups;
        final myKey = session.keys?.publicKeyHex;
        StoryGroup? mine;
        final others = <StoryGroup>[];
        for (final g in groups) {
          if (g.pubkey == myKey) {
            mine = g;
          } else {
            others.add(g);
          }
        }

        return SizedBox(
          height: 100,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            children: [
              StoryItem(
                seed: myKey ?? '',
                label: 'Sen',
                imageUrl: session.me.picture,
                isMe: true,
                active: mine?.hasUnseen(_seen) ?? false,
                onTap: () {
                  final group = mine;
                  if (group == null) {
                    showStoryComposer(context);
                  } else {
                    _open(context, groups, groups.indexOf(group));
                  }
                },
                onAdd: () => showStoryComposer(context),
              ),
              for (final g in others)
                StoryItem(
                  seed: g.pubkey,
                  label: session.profiles[g.pubkey]?.displayName ??
                      '${g.pubkey.substring(0, 6)}…',
                  imageUrl: session.profiles[g.pubkey]?.picture,
                  active: g.hasUnseen(_seen),
                  onTap: () => _open(context, groups, groups.indexOf(g)),
                ),
            ],
          ),
        );
      },
    );
  }
}
