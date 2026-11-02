import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../core/media/image_mime.dart';
import '../../core/media/media_uploader.dart';
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

  Uint8List? _mediaBytes;
  String _mediaMime = 'image/jpeg';
  MediaType _mediaType = MediaType.image;
  bool _viewOnce = false;

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
                mediaBytes: _mediaBytes,
                mediaMime: _mediaMime,
                mediaType: _mediaType,
                viewOnce: _viewOnce,
                onMediaPick: _showMediaPicker,
                onMediaRemove: () => setState(() {
                  _mediaBytes = null;
                  _mediaType = MediaType.image;
                  _viewOnce = false;
                }),
                onViewOnceToggle: (v) => setState(() => _viewOnce = v),
                onSend: _send,
              ),
            ],
          );
        },
      ),
    );
  }

  void _showMediaPicker() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_photo_alternate_outlined),
              title: const Text('Fotoğraf seç'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Video seç'),
              onTap: () {
                Navigator.pop(ctx);
                _pickVideo();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 82,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _mediaBytes = bytes;
      _mediaMime = detectImageMime(bytes);
      _mediaType = MediaType.image;
      _viewOnce = false;
    });
  }

  Future<void> _pickVideo() async {
    final file = await ImagePicker().pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 3),
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _mediaBytes = bytes;
      _mediaMime = 'video/mp4';
      _mediaType = MediaType.video;
      _viewOnce = false;
    });
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
      final decrypted = decryptMessage(
          event.content, session.keys?.privateKeyHex ?? '', widget.recipientPubkey);
      // Parse JSON format: {"text": "...", "media": {...}} -> return just text
      try {
        final data = jsonDecode(decrypted);
        if (data is Map && data['text'] is String) {
          return data['text'] as String;
        }
      } catch (_) {
        // Not JSON, return as-is
      }
      return decrypted;
    } catch (_) {
      return 'Şifreli mesaj';
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _mediaBytes == null) return;
    if (_sending) return;
    setState(() => _sending = true);
    final ok = await AppSession.instance.sendDm(
      widget.recipientPubkey,
      text,
      mediaBytes: _mediaBytes,
      mediaMime: _mediaMime,
      mediaType: _mediaType,
      viewOnce: _viewOnce,
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (ok) {
        _controller.clear();
        _mediaBytes = null;
        _mediaType = MediaType.image;
        _viewOnce = false;
      }
    });
    _focus.requestFocus();
    if (!ok && context.mounted) {
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
    final parsed = _parseMessage(text);

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
            if (parsed.text.isNotEmpty)
              Text(
                parsed.text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: mine ? AppColors.accentInk : AppColors.text,
                  height: 1.35,
                ),
              ),
            if (parsed.media != null) ...[
              if (parsed.text.isNotEmpty) const SizedBox(height: 8),
              _MediaDisplay(media: parsed.media!, mine: mine),
            ],
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

  _ParsedMessage _parseMessage(String content) {
    try {
      final data = jsonDecode(content);
      if (data is Map) {
        final text = (data['text'] as String?) ?? '';
        final media = data['media'] as Map?;
        if (media != null) {
          return _ParsedMessage(
            text: text,
            media: _DecryptedMedia(
              url: media['url'] as String?,
              mime: media['mime'] as String?,
              type: media['type'] as String?,
              viewOnce: media['viewOnce'] as bool? ?? false,
            ),
          );
        }
        return _ParsedMessage(text: text);
      }
    } catch (_) {
      // Not JSON, treat as plain text
    }
    return _ParsedMessage(text: content);
  }
}

class _ParsedMessage {
  const _ParsedMessage({required this.text, this.media});
  final String text;
  final _DecryptedMedia? media;
}

class _DecryptedMedia {
  const _DecryptedMedia({
    required this.url,
    required this.mime,
    required this.type,
    required this.viewOnce,
  });
  final String? url;
  final String? mime;
  final String? type;
  final bool viewOnce;

  bool get isVideo => type == 'video';
}

class _MediaDisplay extends StatelessWidget {
  const _MediaDisplay({required this.media, required this.mine});

  final _DecryptedMedia media;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    if (media.url == null || media.mime == null) return const SizedBox.shrink();

    if (media.isVideo) {
      return ClipRRect(
        borderRadius: Radii.card,
        child: SizedBox(
          height: 200,
          child: VideoPlayerWidget(url: media.url!),
        ),
      );
    }

    // Image
    return GestureDetector(
      onTap: () {
        // Full screen image viewer
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _FullScreenImage(url: media.url!),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: Radii.card,
        child: Image.network(
          media.url!,
          height: 200,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            height: 200,
            color: AppColors.surface,
            child: const Icon(Icons.broken_image_outlined,
                color: AppColors.textFaint),
          ),
        ),
      ),
    );
  }
}

class _FullScreenImage extends StatelessWidget {
  const _FullScreenImage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined,
                color: Colors.white, size: 48),
          ),
        ),
      ),
    );
  }
}

class VideoPlayerWidget extends StatefulWidget {
  const VideoPlayerWidget({super.key, required this.url});
  final String url;

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _initialized = true);
          _controller.setLooping(true);
          _controller.play();
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return Container(
        height: 200,
        color: AppColors.surface,
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return AspectRatio(
      aspectRatio: _controller.value.aspectRatio,
      child: VideoPlayer(_controller),
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.focus,
    required this.sending,
    required this.mediaBytes,
    required this.mediaMime,
    required this.mediaType,
    required this.viewOnce,
    required this.onMediaPick,
    required this.onMediaRemove,
    required this.onViewOnceToggle,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool sending;
  final Uint8List? mediaBytes;
  final String mediaMime;
  final MediaType mediaType;
  final bool viewOnce;
  final VoidCallback onMediaPick;
  final VoidCallback onMediaRemove;
  final ValueChanged<bool> onViewOnceToggle;
  final VoidCallback onSend;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  @override
  Widget build(BuildContext context) {
    final hasMedia = widget.mediaBytes != null;

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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasMedia) ...[
            Stack(
              children: [
                ClipRRect(
                  borderRadius: Radii.card,
                  child: widget.mediaType == MediaType.video
                      ? Container(
                          height: 120,
                          width: double.infinity,
                          color: AppColors.surface,
                          child: const Center(
                            child: Icon(Icons.videocam,
                                size: 36, color: AppColors.textMuted),
                          ),
                        )
                      : Image.memory(
                          widget.mediaBytes!,
                          height: 120,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton.filledTonal(
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.sending ? null : widget.onMediaRemove,
                    icon: const Icon(Icons.close, size: 14),
                  ),
                ),
                if (widget.mediaType == MediaType.video)
                  const Positioned.fill(
                    child: Center(
                      child: Icon(Icons.play_circle_fill,
                          size: 36, color: Colors.white),
                    ),
                  ),
              ],
            ),
            if (widget.mediaType == MediaType.image)
              Row(
                children: [
                  Checkbox(
                    value: widget.viewOnce,
                    onChanged: widget.sending
                        ? null
                        : (v) => widget.onViewOnceToggle(v ?? false),
                    shape: const CircleBorder(),
                    activeColor: AppColors.accent,
                  ),
                  Text(
                    'Tek görüntüleme (View once)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              if (!hasMedia)
                IconButton(
                  onPressed: widget.sending ? null : widget.onMediaPick,
                  tooltip: 'Medya ekle',
                  icon: Icon(
                    Icons.add_photo_alternate_outlined,
                    color: AppColors.accent,
                  ),
                ),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: widget.focus,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => widget.onSend(),
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
                  onTap: widget.sending ? null : widget.onSend,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: widget.sending
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
        ],
      ),
    );
  }
}
