import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/accounts/account_service.dart';
import '../../core/background/background_watch.dart';
import '../../core/config/app_config.dart';
import '../../core/identity/invite_qr.dart';
import '../../core/identity/key_storage.dart';
import '../../core/media/image_mime.dart';
import '../../core/media/media_uploader.dart';
import '../../core/nostr/event.dart';
import '../../core/nostr/nip49.dart';
import '../../core/session/app_session.dart';
import '../../ui/format.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../announcements/announcements_sheet.dart';
import '../feed/post_tile.dart';
import '../feed/user_sheet.dart';
import '../identity/scan_page.dart';

/// Profil: kimlik özeti, istatistikler, gönderi ızgarası ve hesap işlemleri.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;

    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final myKey = session.keys?.publicKeyHex ?? '';
          final me = session.profiles[myKey];
          final mine = session.notesBy(myKey);
          final name = (me?.name?.trim().isNotEmpty ?? false)
              ? me!.name!
              : 'İsimsiz kullanıcı';

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              // Banner image
              if (me?.banner != null && me!.banner!.isNotEmpty)
                ClipRRect(
                  child: Image.network(
                    me.banner!,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(height: 160),
                  ),
                )
              else
                Container(
                  height: 160,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.accent.withValues(alpha: 0.15),
                        AppColors.surface,
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name.toLowerCase().replaceAll(' ', '_'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    CircleIconButton(
                      icon: Icons.settings_outlined,
                      tooltip: 'Ayarlar',
                      onTap: () => _openSettings(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Insets.lg),
              Row(
                children: [
                  const SizedBox(width: 24),
                  Avatar(
                    seed: myKey,
                    label: name,
                    imageUrl: me?.picture,
                    size: 84,
                    ring: true,
                  ),
                  const Spacer(),
                  _TappableStat(
                    value: mine.length,
                    label: 'Gönderi',
                    onTap: () {}, // no list for posts
                  ),
                  const Spacer(),
                  _TappableStat(
                    value: session.followingCount(myKey),
                    label: 'Takip',
                    onTap: () => _showFollowingList(context, myKey),
                  ),
                  const Spacer(),
                  _TappableStat(
                    value: session.followerCount(myKey),
                    label: 'Takipçi',
                    onTap: () => _showFollowerList(context, myKey),
                  ),
                  const Spacer(),
                  const SizedBox(width: 24),
                ],
              ),
              const SizedBox(height: Insets.md),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(
                            ClipboardData(text: session.keys?.npub ?? ''));
                        _toast(context, 'npub kopyalandı');
                      },
                      child: Row(
                        children: [
                          Text(
                            shortNpub(session.keys?.npub),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  fontFamily: 'monospace',
                                  color: AppColors.textMuted,
                                ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.copy,
                              size: 12, color: AppColors.textFaint),
                        ],
                      ),
                    ),
                    if ((me?.about?.trim().isNotEmpty ?? false)) ...[
                      const SizedBox(height: Insets.sm),
                      Text(me!.about!,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ],
                    const SizedBox(height: Insets.lg),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: () => _openEdit(context),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(36),
                              backgroundColor: AppColors.surfaceAlt,
                              foregroundColor: AppColors.text,
                              side: const BorderSide(
                                  color: AppColors.lineStrong),
                              textStyle: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600),
                            ),
                            child: const Text('Profili düzenle'),
                          ),
                        ),
                        const SizedBox(width: Insets.sm),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => _openInvite(context),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(36),
                              backgroundColor: AppColors.surfaceAlt,
                              foregroundColor: AppColors.text,
                              side: const BorderSide(
                                  color: AppColors.lineStrong),
                              textStyle: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600),
                            ),
                            child: const Text('Davet et'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Insets.lg),
              const Divider(),
              if (mine.isEmpty)
                const EmptyState(
                  icon: Icons.grid_view_outlined,
                  title: 'Henüz gönderin yok',
                  message: 'Aşağıdaki + düğmesiyle ilk paylaşımını yap.',
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
                  itemCount: mine.length,
                  itemBuilder: (context, i) => _GridThumb(event: mine[i]),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showFollowingList(BuildContext context, String pubkey) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FollowListSheet(
        pubkey: pubkey,
        mode: FollowListMode.following,
      ),
    );
  }

  void _showFollowerList(BuildContext context, String pubkey) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FollowListSheet(
        pubkey: pubkey,
        mode: FollowListMode.followers,
      ),
    );
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openEdit(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _EditProfileSheet(),
    );
  }

  void _openInvite(BuildContext context) {
    final session = AppSession.instance;
    final invite = InviteQr.encodeInvite(
      session.keys!,
      AppConfig.relayUrl,
      displayName: session.profiles[session.keys!.publicKeyHex]?.name,
    );

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.lineStrong, borderRadius: Radii.pill),
            ),
            const SizedBox(height: Insets.lg),
            Text('Davet et', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Arkadaşın bu kodu okutarak seni ekleyebilir.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: Insets.lg),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: Radii.card,
              ),
              child: QrImageView(
                data: invite,
                size: 180,
                padding: EdgeInsets.zero,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: Insets.lg),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: invite));
                Navigator.pop(ctx);
                _toast(context, 'Davet bağlantısı kopyalandı');
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Daveti kopyala'),
            ),
            const SizedBox(height: Insets.sm),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                showScanQr(context);
              },
              icon: const Icon(Icons.qr_code_scanner, size: 18),
              label: const Text('Davet QR’ı tara'),
            ),
          ],
        ),
      ),
    );
  }

  void _openSettings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const _SettingsSheet(),
    );
  }
}

class _TappableStat extends StatelessWidget {
  const _TappableStat({
    required this.value,
    required this.label,
    required this.onTap,
  });

  final int value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          children: [
            Text('$value',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

enum FollowListMode { following, followers }

class _FollowListSheet extends StatefulWidget {
  const _FollowListSheet({required this.pubkey, required this.mode});

  final String pubkey;
  final FollowListMode mode;

  @override
  State<_FollowListSheet> createState() => _FollowListSheetState();
}

class _FollowListSheetState extends State<_FollowListSheet> {
  late final Set<String> _list;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadList();
  }

  Future<void> _loadList() async {
    final session = AppSession.instance;
    final following = session.contacts[widget.pubkey] ?? <String>{};
    final followers = <String>{};
    for (final entry in session.contacts.entries) {
      if (entry.value.contains(widget.pubkey.toLowerCase())) {
        followers.add(entry.key);
      }
    }
    if (!mounted) return;
    setState(() {
      _list = widget.mode == FollowListMode.following ? following : followers;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;
    final title = widget.mode == FollowListMode.following ? 'Takip edilenler' : 'Takipçiler';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, scrollController) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
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
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: Insets.lg),
              if (_loading)
                const Center(
                    child: CircularProgressIndicator())
              else if (_list.isEmpty)
                const EmptyState(
                  icon: Icons.people_outline,
                  title: 'Liste boş',
                  message: 'Henüz kimse yok.',
                )
              else
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: _list.length,
                    itemBuilder: (context, i) {
                      final pk = _list.elementAt(i);
                      final profile = session.profiles[pk];
                      final isMe = pk == session.keys?.publicKeyHex;
                      return ListTile(
                        leading: Avatar(
                          seed: pk,
                          label: profile?.displayName,
                          imageUrl: profile?.picture,
                          size: 40,
                        ),
                        title: Text(
                            profile?.displayName ?? '${pk.substring(0, 8)}…'),
                        subtitle: isMe
                            ? const Text('Sen')
                            : null,
                        trailing: !isMe
                            ? FilledButton(
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 36),
                                  backgroundColor:
                                      session.isFollowing(pk)
                                          ? AppColors.surfaceAlt
                                          : null,
                                  foregroundColor:
                                      session.isFollowing(pk)
                                          ? AppColors.text
                                          : null,
                                  side: session.isFollowing(pk)
                                      ? const BorderSide(color: AppColors.lineStrong)
                                      : null,
                                ),
                                onPressed: () async {
                                  final messenger = ScaffoldMessenger.of(context);
                                  final ok = await session.followPerson(pk);
                                  messenger.showSnackBar(SnackBar(
                                    content: Text(ok
                                        ? (session.isFollowing(pk)
                                            ? 'Takipten çıkarılamadı'
                                            : 'Takip ediliyor')
                                        : 'İşlem gönderilemedi'),
                                  ));
                                },
                                child: Text(session.isFollowing(pk)
                                    ? 'Takip ediliyor'
                                    : 'Takip et'),
                              )
                            : null,
                        onTap: () {
                          Navigator.pop(context);
                          showUserSheet(context, pk);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Profil ızgarasındaki kare; dokununca gönderi detayı açılır.
class _GridThumb extends StatelessWidget {
  const _GridThumb({required this.event});

  final NostrEvent event;

  @override
  Widget build(BuildContext context) {
    final color = Avatar.colorFor(event.pubkey);
    final likes = AppSession.instance.reactionCount(event.id);

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
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  event.content.isEmpty ? '·' : event.content,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    height: 1.35,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              if (likes > 0)
                Row(
                  children: [
                    const Icon(Icons.favorite,
                        size: 11, color: AppColors.accent),
                    const SizedBox(width: 3),
                    Text('$likes',
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet();

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _name;
  late final TextEditingController _about;
  bool _saving = false;

  Uint8List? _pictureBytes;
  String? _pictureMime;
  Uint8List? _bannerBytes;
  String? _bannerMime;
  String? _pictureUrl;
  String? _bannerUrl;

  @override
  void initState() {
    super.initState();
    final session = AppSession.instance;
    final me = session.profiles[session.keys?.publicKeyHex];
    _name = TextEditingController(text: me?.name ?? '');
    _about = TextEditingController(text: me?.about ?? '');
    _pictureUrl = me?.picture;
    _bannerUrl = me?.banner;
  }

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    super.dispose();
  }

  Future<void> _pickPicture() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 82,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _pictureBytes = bytes;
      _pictureMime = detectImageMime(bytes);
    });
  }

  Future<void> _pickBanner() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 1024,
      imageQuality: 82,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _bannerBytes = bytes;
      _bannerMime = detectImageMime(bytes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;
    final me = session.profiles[session.keys?.publicKeyHex];

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          Text('Profili düzenle',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Bu bilgiler relay\'e `kind:0` olarak yayınlanır.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: Insets.lg),
          // Profile picture
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: AppColors.surface,
                  backgroundImage: _pictureBytes != null
                      ? MemoryImage(_pictureBytes!)
                      : (_pictureUrl != null && _pictureUrl!.isNotEmpty
                          ? NetworkImage(_pictureUrl!)
                          : null) as ImageProvider?,
                  child: _pictureBytes == null &&
                          (_pictureUrl == null || _pictureUrl!.isEmpty)
                      ? Text(
                          (me?.name?.isNotEmpty ?? false)
                              ? me!.name!.trim().characters.first.toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: Avatar.colorFor(session.keys!.publicKeyHex),
                          ),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: IconButton.filledTonal(
                    visualDensity: VisualDensity.compact,
                    onPressed: _saving ? null : _pickPicture,
                    icon: const Icon(Icons.camera_alt, size: 16),
                    tooltip: 'Profil fotoğrafı değiştir',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.md),
          // Banner image
          if (_bannerBytes != null || (_bannerUrl != null && _bannerUrl!.isNotEmpty))
            Stack(
              children: [
                ClipRRect(
                  borderRadius: Radii.card,
                  child: Image.memory(
                    _bannerBytes!,
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: IconButton.filledTonal(
                    visualDensity: VisualDensity.compact,
                    onPressed: _saving ? null : () => setState(() => _bannerBytes = null),
                    icon: const Icon(Icons.close, size: 16),
                    tooltip: 'Banner kaldır',
                  ),
                ),
              ],
            )
          else
            OutlinedButton.icon(
              onPressed: _saving ? null : _pickBanner,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('Banner ekle'),
            ),
          const SizedBox(height: Insets.lg),
          TextField(
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Görünen ad'),
          ),
          const SizedBox(height: Insets.md),
          TextField(
            controller: _about,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Hakkında'),
          ),
          const SizedBox(height: Insets.lg),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.accentInk),
                  )
                : const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final session = AppSession.instance;
    final keys = session.keys;
    if (keys == null) {
      setState(() => _saving = false);
      messenger.showSnackBar(const SnackBar(content: Text('Anahtar yok')));
      return;
    }

    String? pictureUrl = _pictureUrl;
    String? bannerUrl = _bannerUrl;

    // Upload profile picture if changed
    if (_pictureBytes != null) {
      try {
        final ref = await MediaUploader(AppConfig.mediaUrl).upload(
          bytes: _pictureBytes!,
          mime: _pictureMime!,
          keys: keys,
        );
        pictureUrl = ref.url;
      } catch (e) {
        if (!mounted) return;
        setState(() => _saving = false);
        messenger.showSnackBar(SnackBar(content: Text('Profil fotoğrafı yüklenemedi: $e')));
        return;
      }
    }

    // Upload banner if changed
    if (_bannerBytes != null) {
      try {
        final ref = await MediaUploader(AppConfig.mediaUrl).upload(
          bytes: _bannerBytes!,
          mime: _bannerMime!,
          keys: keys,
        );
        bannerUrl = ref.url;
      } catch (e) {
        if (!mounted) return;
        setState(() => _saving = false);
        messenger.showSnackBar(SnackBar(content: Text('Banner yüklenemedi: $e')));
        return;
      }
    }

    final ok = await session.publishProfile(
      name: _name.text,
      about: _about.text,
      picture: pictureUrl,
      banner: bannerUrl,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
      content: Text(ok ? 'Profil güncellendi' : 'Profil güncellenemedi'),
    ));
  }
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
            Text('Ayarlar', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Insets.lg),
            RowsGroup(
              label: 'Hesap',
              children: [
                if (AccountService.instance.account case final acc?) ...[
                  RowItem(
                    icon: Icons.person_outline,
                    title: acc.username,
                    subtitle: 'Rol: ${acc.role.labelTR}',
                  ),
                  RowItem(
                    icon: Icons.password_outlined,
                    title: 'Parola değiştir',
                    subtitle: 'Anahtar yeni parolayla yeniden şifrelenir',
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => const _PasswordDialog(),
                    ),
                  ),
                  RowItem(
                    icon: Icons.logout,
                    title: 'Oturumu kapat',
                    subtitle: 'Anahtar sunucuda parolanla duruyor',
                    onTap: () => _signOut(context),
                  ),
                ],
                RowItem(
                  icon: Icons.vpn_key_outlined,
                  title: 'Anahtarı yedekle',
                  subtitle: 'Parola ile şifrele (NIP-49)',
                  onTap: () => _showBackup(context),
                ),
                RowItem(
                  icon: Icons.copy_all_outlined,
                  title: 'Genel anahtarı kopyala',
                  subtitle: shortNpub(session.keys?.npub),
                  onTap: () {
                    Clipboard.setData(
                        ClipboardData(text: session.keys?.npub ?? ''));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('npub kopyalandı')),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: Insets.lg),
            RowsGroup(
              label: 'Topluluk',
              children: [
                RowItem(
                  icon: Icons.campaign_outlined,
                  title: 'Duyurular',
                  subtitle: 'Host ve mod duyuruları',
                  onTap: () {
                    Navigator.pop(context);
                    showAnnouncements(context);
                  },
                ),
                if (AccountService.instance.account?.isHost ?? false)
                  RowItem(
                    icon: Icons.shield_outlined,
                    title: 'Yetki yönetimi',
                    subtitle: 'Mod ata, hostluğu devret',
                    onTap: () {
                      Navigator.pop(context);
                      showRoleAdmin(context);
                    },
                  ),
              ],
            ),
            const SizedBox(height: Insets.lg),
            RowsGroup(
              label: 'Gizlilik',
              children: [
                RowItem(
                  icon: Icons.block_outlined,
                  title: 'Engellenenler',
                  subtitle: session.mutedAuthors.isEmpty
                      ? 'Henüz kimseyi engellemedin'
                      : '${session.mutedAuthors.length} kişi',
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const _BlockedSheet(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Insets.lg),
            RowsGroup(
              label: 'Bağlantı',
              children: [
                RowItem(
                  icon: Icons.dns_outlined,
                  title: 'Relay',
                  subtitle: relayHost(AppConfig.relayUrl),
                  trailing: ConnectionBadge(connected: session.connected),
                ),
                const _BackgroundRow(),
                const RowItem(
                  icon: Icons.lock_outline,
                  title: 'Anahtar saklama',
                  subtitle: 'Android Keystore',
                  trailing: Icon(Icons.check,
                      size: 18, color: AppColors.online),
                ),
              ],
            ),
            const SizedBox(height: Insets.lg),
            Text(
              '${AppConfig.name} ${AppConfig.version} · ${AppConfig.domain}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// Hesap oturumuyla çıkış: anahtar cihazdan silinir (parolayla
  /// sunucuda durduğu için kayıp değil) ve uygulama kapanır; açılışta
  /// yeniden giriş istenir.
  Future<void> _signOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: const Text('Oturumu kapat'),
        content: const Text(
          'Anahtar bu cihazdan silinir; bir dahaki açılışta kullanıcı adı + '
          'parolanla aynı hesaba ve anahtarlarına dönebilirsin.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kapat')),
        ],
      ),
    );
    if (ok != true) return;
    await AccountService.instance.signOut();
    await KeyStorage().deleteKeys();
    if (context.mounted) Navigator.pop(context); // ayarları kapat
    SystemNavigator.pop(); // uygulamayı kapat (sonraki açılış: giriş)
  }

  void _showBackup(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const _BackupDialog(),
    );
  }
}

/// "Arka plan bağlantısı" ayar satırı: uygulamasız relay izleyicisi anahtarı.
class _BackgroundRow extends StatefulWidget {
  const _BackgroundRow();

  @override
  State<_BackgroundRow> createState() => _BackgroundRowState();
}

class _BackgroundRowState extends State<_BackgroundRow> {
  bool? _running; // null: henüz okunmadı
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    BackgroundWatch.isRunning().then((v) {
      if (mounted) setState(() => _running = v);
    });
  }

  Future<void> _toggle(bool wanted) async {
    if (_busy) return;
    setState(() => _busy = true);
    String? message;
    if (wanted) {
      final ok = await BackgroundWatch.enable();
      _running = ok;
      if (!ok) message = 'Bildirim izni verilmeden arka plan çalışamaz';
    } else {
      await BackgroundWatch.disable();
      _running = false;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = _running == true;
    return RowItem(
      icon: Icons.notifications_active_outlined,
      title: 'Arka plan bağlantısı',
      subtitle: running
          ? 'Uygulama kapalıyken relay dinleniyor'
          : 'Kapalıyken mesaj/beğeni bildirimi gelmez',
      trailing: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Switch(
              value: running,
              onChanged: (v) => _toggle(v),
            ),
    );
  }
}

class _BackupDialog extends StatefulWidget {
  const _BackupDialog();

  @override
  State<_BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends State<_BackupDialog> {
  final _password = TextEditingController();
  String? _backup;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;
    return AlertDialog(
      title: const Text('Anahtarı yedekle'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Özel anahtarın parolanla şifrelenir. Yedeği güvenli bir yerde sakla; '
              'parolanı kaybedersen geri alınamaz.',
            ),
            const SizedBox(height: Insets.lg),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Parola',
                helperText: 'En az 8 karakter önerilir',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: Insets.sm),
              Text(_error!,
                  style: const TextStyle(color: AppColors.offline, fontSize: 12)),
            ],
            if (_backup != null) ...[
              const SizedBox(height: Insets.md),
              SelectableText(
                _backup!,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10.5,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: Insets.sm),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _backup!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Yedek kopyalandı')),
                  );
                },
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('Kopyala'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kapat'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: _busy || session.keys == null
              ? null
              : (_backup == null ? _encrypt : _verify),
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_backup == null ? 'Oluştur' : 'Doğrula'),
        ),
      ],
    );
  }

  Future<void> _encrypt() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await Nip49.encrypt(
          AppSession.instance.keys!.privateKeyHex, _password.text);
      if (!mounted) return;
      setState(() => _backup = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Yedek oluşturulamadı: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await Nip49.decrypt(_backup!, _password.text);
      final ok = result == AppSession.instance.keys?.privateKeyHex;
      if (!mounted) return;
      setState(() {
        _error = ok ? null : 'Parola yedekle eşleşmiyor';
      });
      if (ok) {
        await AppSession.instance.keyStorage.setBackupPending(false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yedek doğrulandı')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Doğrulanamadı: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Hesap parolasını değiştirir: eski parolayla anahtarı çözer, yeni
/// parolayla yeniden şifreleyip sunucuya gönderir (diğer cihaz oturumları
/// kapanır, bu cihaz devam eder).
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _old = TextEditingController();
  final _fresh = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _old.dispose();
    _fresh.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_fresh.text != _repeat.text) {
      setState(() => _error = 'Yeni parolalar eşleşmiyor.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AccountService.instance.changePassword(_old.text, _fresh.text);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Parola güncellendi')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = accountErrorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Parola değiştir'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Anahtarın yeni parolayla yeniden şifrelenir. Diğer cihazlardaki '
              'oturumlar kapanır; bu cihaz açık kalır.',
            ),
            const SizedBox(height: Insets.lg),
            TextField(
              controller: _old,
              obscureText: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Mevcut parola'),
            ),
            const SizedBox(height: Insets.sm),
            TextField(
              controller: _fresh,
              obscureText: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Yeni parola',
                helperText: 'En az 6 karakter',
              ),
            ),
            const SizedBox(height: Insets.sm),
            TextField(
              controller: _repeat,
              obscureText: true,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(labelText: 'Yeni parola (tekrar)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: Insets.sm),
              Text(_error!,
                  style:
                      const TextStyle(color: AppColors.offline, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Değiştir'),
        ),
      ],
    );
  }
}

/// Engellenenler listesi; her satır tek dokunuşla engeli kaldırır.
class _BlockedSheet extends StatelessWidget {
  const _BlockedSheet();

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (context, scrollController) => ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final muted = session.mutedAuthors;
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
              Text('Engellenenler',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Engellediklerinin gönderileri akışından ve keşfetten düşer.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: Insets.lg),
              if (muted.isEmpty)
                const EmptyState(
                  icon: Icons.sentiment_satisfied_outlined,
                  title: 'Liste boş',
                  message: 'Engellediğin kişiler burada görünecek.',
                )
              else
                RowsGroup(
                  children: [
                    for (final pk in muted)
                      RowItem(
                        icon: Icons.person_off_outlined,
                        title: session.profiles[pk]?.displayName ??
                            '${pk.substring(0, 8)}…',
                        subtitle: 'gönderileri gizli',
                        trailing: const Icon(Icons.remove_circle_outline,
                            size: 18, color: AppColors.textMuted),
                        onTap: () => session.toggleMute(pk),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
