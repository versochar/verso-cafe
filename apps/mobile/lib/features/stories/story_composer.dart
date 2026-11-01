/// Hikâye oluşturma: fotoğraf + isteğe bağlı yazı, 24 saat yayında.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/config/app_config.dart';
import '../../core/media/image_mime.dart';
import '../../core/media/media_uploader.dart';
import '../../core/session/app_session.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

Future<void> showStoryComposer(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const StoryComposer(),
  );
}

class StoryComposer extends StatefulWidget {
  const StoryComposer({super.key});

  @override
  State<StoryComposer> createState() => _StoryComposerState();
}

class _StoryComposerState extends State<StoryComposer> {
  final _caption = TextEditingController();
  final _picker = ImagePicker();
  Uint8List? _bytes;
  String _mime = 'image/jpeg';
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _caption.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 2400,
        imageQuality: 82,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _mime = detectImageMime(bytes);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Fotoğraf seçilemedi: $e')));
    }
  }

  Future<void> _send() async {
    final bytes = _bytes;
    if (bytes == null || _sending) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final session = AppSession.instance;
    final keys = session.keys;
    if (keys == null) {
      setState(() => _sending = false);
      return;
    }

    List<List<String>> tags = const [];
    try {
      final ref = await MediaUploader(AppConfig.mediaUrl).upload(
        bytes: bytes,
        mime: _mime,
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
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Medya sunucusuna ulaşılamadı')),
      );
      return;
    }

    final ok = await session.publishStory(_caption.text, tags: tags);
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
            const SnackBar(content: Text('Hikâye 24 saat yayında')));
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('Hikâye paylaşılamadı — bağlantı?')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage = _bytes != null;
    final caption = _caption.text.trim();

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 14,
          bottom: MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: SingleChildScrollView(
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
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.auto_awesome,
                      color: AppColors.accent, size: 20),
                  const SizedBox(width: 8),
                  Text('Hikâye ekle', style: theme.textTheme.titleLarge),
                  const Spacer(),
                  Text('24 saat',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: AppColors.textFaint)),
                ],
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: _sending ? null : () => _pick(ImageSource.gallery),
                borderRadius: Radii.card,
                child: Container(
                  height: 260,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: Radii.card,
                    border: Border.all(color: AppColors.line),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: hasImage
                      ? Image.memory(_bytes!, fit: BoxFit.cover)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_photo_alternate_outlined,
                                size: 42, color: AppColors.textMuted),
                            const SizedBox(height: 10),
                            Text('Bir fotoğraf seç',
                                style: theme.textTheme.bodyMedium),
                            const SizedBox(height: 4),
                            Text('Dokun → galeri',
                                style: theme.textTheme.labelSmall),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        _sending ? null : () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Galeri'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed:
                        _sending ? null : () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: const Text('Kamera'),
                  ),
                  const Spacer(),
                  ConnectionBadge(connected: AppSession.instance.connected),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _caption,
                minLines: 2,
                maxLines: 4,
                maxLength: 200,
                buildCounter: (_,
                        {required currentLength,
                        required isFocused,
                        maxLength}) =>
                    null,
                decoration: const InputDecoration(
                  labelText: 'Yazı (isteğe bağlı)',
                  hintText: 'Hikâyene bir not ekle…',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed:
                    (!hasImage || _sending) ? null : _send,
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 50)),
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: AppColors.accentInk),
                      )
                    : Text(caption.isEmpty ? 'Hikâyeyi paylaş' : 'Paylaş'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
