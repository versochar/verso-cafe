import 'package:flutter/material.dart';

import '../../core/session/app_session.dart';
import '../../core/update/update_gate.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../dm/messages_page.dart';
import '../explore/explore_page.dart';
import '../feed/compose_sheet.dart';
import '../feed/feed_page.dart';
import '../profile/profile_page.dart';
import '../search/search_page.dart';

/// Alt gezinme çubuğu ve sekmeler.
///
/// Instagram benzeri altı yuva: Akış · Keşfet · Ara · (+) · Mesajlar · Profil.
/// Ortadaki `+` sekme değiştirmez, besteciyi açar. İçerik `IndexedStack`
/// içinde tutulur; sekme değişiminde kaydırma konumu korunur.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _index = widget.initialIndex;

  @override
  void initState() {
    super.initState();
    // Otomatik güncelleme kontrolü: açılıştan kısa bir süre sonra bir kez
    // (kimlik yüklenmişse hemen, değilse hazır olur olmaz).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 4), () {
        if (!mounted) return;
        if (AppSession.instance.ready) {
          UpdateGate.maybeCheck(context);
          return;
        }
        void onReady() {
          if (!AppSession.instance.ready) return;
          AppSession.instance.removeListener(onReady);
          if (mounted) UpdateGate.maybeCheck(context);
        }
        AppSession.instance.addListener(onReady);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSession.instance,
      builder: (context, _) {
        if (!AppSession.instance.ready) return const _BootScreen();
        return Scaffold(
          body: IndexedStack(
            index: _index,
            children: const [
              FeedPage(),      // 0
              ExplorePage(),   // 1
              SearchPage(),    // 2
              MessagesPage(),  // 3
              ProfilePage(),   // 4
            ],
          ),
          bottomNavigationBar: _BottomBar(
            index: _index,
            onSelect: (i) => setState(() => _index = i),
            onCreate: () => showComposer(context),
          ),
        );
      },
    );
  }
}

/// Açılış: kimlik yüklenirken kısa, markalı bekleme ekranı.
class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

/// Yuva düzeni: 0 akış, 1 keşfet, 2 ara, 3 oluştur, 4 mesajlar, 5 profil.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.index,
    required this.onSelect,
    required this.onCreate,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final me = AppSession.instance.me;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              Expanded(
                child: _NavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: 'Akış',
                  selected: index == 0,
                  onTap: () => onSelect(0),
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.explore_outlined,
                  activeIcon: Icons.explore_rounded,
                  label: 'Keşfet',
                  selected: index == 1,
                  onTap: () => onSelect(1),
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.search_outlined,
                  activeIcon: Icons.search_rounded,
                  label: 'Ara',
                  selected: index == 2,
                  onTap: () => onSelect(2),
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.add_circle_outline,
                  activeIcon: Icons.add_circle,
                  label: 'Paylaş',
                  selected: false,
                  emphasized: true,
                  onTap: onCreate,
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.mode_comment_outlined,
                  activeIcon: Icons.mode_comment,
                  label: 'Mesajlar',
                  selected: index == 3,
                  onTap: () => onSelect(3),
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                  label: 'Profil',
                  selected: index == 4,
                  avatarSeed: me.pubkey,
                  avatarLabel: me.name,
                  avatarUrl: me.picture,
                  onTap: () => onSelect(4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.emphasized = false,
    this.avatarSeed,
    this.avatarLabel,
    this.avatarUrl,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool emphasized;
  final String? avatarSeed;
  final String? avatarLabel;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.text : AppColors.textFaint;
    final accent = emphasized ? AppColors.accent : color;

    final Widget visual;
    if (avatarSeed != null && avatarSeed!.isNotEmpty) {
      visual = Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: ClipOval(
          child: Avatar(
            seed: avatarSeed!,
            label: avatarLabel,
            imageUrl: avatarUrl,
            size: 26,
            ring: false,
          ),
        ),
      );
    } else {
      visual = Icon(selected ? activeIcon : icon, size: 24, color: accent);
    }

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 58,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            visual,
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontSize: 9.5,
                height: 1,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: emphasized ? AppColors.textMuted : color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
