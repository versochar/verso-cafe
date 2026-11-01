import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/config/app_config.dart';
import '../../core/media/media_uploader.dart';
import '../../core/session/app_session.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Alt bardaki `+` ya da akıştaki besteci satırından açılan paylaşım formu.
Future<void> showComposer(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const ComposeSheet(),
  );
}

class ComposeSheet extends StatefulWidget {
  const ComposeSheet({super.key});

  @override
  State<ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<ComposeSheet> {
  final _controller = TextEditingController();
  bool _sending = false;

  Uint8List? _imageBytes;
  String _imageMime = 'image/jpeg';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
      _imageBytes = bytes;
      _imageMime = _detectMime(bytes);
    });
  }

  static String _detectMime(Uint8List b) {
    if (b.length > 11) {
      if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'image/jpeg';
      if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
        return 'image/png';
      }
      if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x38) {
        return 'image/gif';
      }
      if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
          b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42) {
        return 'image/webp';
      }
    }
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = _controller.text.trim();
    final me = AppSession.instance.me;
    final length = _controller.text.characters.length;

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
                color: AppColors.lineStrong,
                borderRadius: Radii.pill,
              ),
            ),
          ),
          const SizedBox(height: Insets.lg),
          Row(
            children: [
              Avatar(
                seed: me.pubkey,
                label: me.name,
                imageUrl: me.picture,
                size: 34,
              ),
              const SizedBox(width: Insets.md),
              Text('Yeni gönderi', style: theme.textTheme.titleMedium),
              const Spacer(),
              Text(
                '$length/280',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: length > 280 ? AppColors.offline : AppColors.textFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            maxLength: 280,
            buildCounter:
                (_, {required currentLength, required isFocused, maxLength}) =>
                    null,
            style: theme.textTheme.bodyLarge,
            decoration: const InputDecoration(
              hintText: 'Aklındakini paylaş…',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          if (_imageBytes != null) ...[
            const SizedBox(height: Insets.sm),
            Stack(
              children: [
                ClipRRect(
                  borderRadius: Radii.card,
                  child: Image.memory(
                    _imageBytes!,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: IconButton.filledTonal(
                    visualDensity: VisualDensity.compact,
                    onPressed: _sending
                        ? null
                        : () => setState(() => _imageBytes = null),
                    icon: const Icon(Icons.close, size: 16),
                  ),
                ),
              ],
            ),
          ],
          const Divider(),
          const SizedBox(height: Insets.md),
          Row(
            children: [
              IconButton(
                onPressed: _sending ? null : _pickImage,
                tooltip: 'Fotoğraf ekle',
                icon: Icon(
                  _imageBytes == null
                      ? Icons.add_photo_alternate_outlined
                      : Icons.image_outlined,
                  color: AppColors.accent,
                ),
              ),
              ConnectionBadge(connected: AppSession.instance.connected),
              const Spacer(),
              FilledButton(
                onPressed:
                    (_sending || (text.isEmpty && _imageBytes == null) ||
                            length > 280)
                        ? null
                        : _send,
                style: FilledButton.styleFrom(minimumSize: const Size(112, 44)),
                child: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.accentInk),
                      )
                    : const Text('Paylaş'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final session = AppSession.instance;

    // Fotoğraf varsa önce medya sunucusuna yükle (NIP-98 imzalı).
    List<List<String>> tags = const [];
    final bytes = _imageBytes;
    if (bytes != null) {
      final keys = session.keys;
      if (keys == null) {
        if (!mounted) return;
        setState(() => _sending = false);
        return;
      }
      try {
        final ref = await MediaUploader(AppConfig.mediaUrl).upload(
          bytes: bytes,
          mime: _imageMime,
          keys: keys,
        );
        tags = [ref.toImetaTag()];
      } on MediaUploadException catch (e) {
        if (!mounted) return;
        setState(() => _sending = false);
        messenger.showSnackBar(
          SnackBar(content: Text('Fotoğraf yüklenemedi — ${e.message}')),
        );
        return;
      } catch (e) {
        if (!mounted) return;
        setState(() => _sending = false);
        messenger.showSnackBar(
          const SnackBar(content: Text('Medya sunucusuna ulaşılamadı')),
        );
        return;
      }
    }

    final ok = await session.publishNote(_controller.text.trim(), tags: tags);
    if (!mounted) return;
    setState(() => _sending = false);
    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(ok ? 'Gönderi paylaşıldı' : 'Gönderi paylaşılamadı'),
        ),
      );
  }
}
