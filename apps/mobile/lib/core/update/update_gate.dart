/// Otomatik güncelleme akışının arayüz cephesi.
///
/// Uygulama açılınca `maybeCheck` çağrılır: `version.json`'da yeni sürüm varsa
/// indirme Kendiliğinden başlar; bitince sistem kurucusu açılır. Kullanıcı
/// "bir daha hatırlatma" derse o sürüm numarası Keystore'a yazılır ve bir daha
/// sorulmaz (daha yeni bir sürüm çıkana dek).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../identity/key_storage.dart';
import '../../ui/theme.dart';
import 'update_info.dart';
import 'update_service.dart';

class UpdateGate {
  UpdateGate._();

  static bool _ran = false;

  /// Açılışta bir kez dener. Hata durumunda sessiz kalır (söylenmez).
  static Future<void> maybeCheck(BuildContext context) async {
    if (_ran) return;
    _ran = true;

    final info = await UpdateService.fetchInfo();
    if (info == null || !isUpdateAvailable(AppConfig.version, info.version)) {
      return;
    }
    if (!context.mounted) return;

    final storage = KeyStorage();
    if (await storage.loadUpdateSkipped() == info.version) return;
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpdateDialog(info: info, storage: storage),
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.info, required this.storage});

  final UpdateInfo info;
  final KeyStorage storage;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

enum _Phase { downloading, ready, installing, error }

class _UpdateDialogState extends State<_UpdateDialog> {
  _Phase _phase = _Phase.downloading;
  double _progress = 0;
  String _error = '';
  String _apkPath = '';
  bool _installPermissionAsked = false;

  @override
  void initState() {
    super.initState();
    // İndirme kendiliğinden başlar ("yeni sürüm gelince otomatik indirsin").
    unawaited(_download());
  }

  Future<void> _download() async {
    setState(() {
      _phase = _Phase.downloading;
      _progress = 0;
    });
    try {
      _apkPath = await UpdateService.downloadApk(
        widget.info,
        onProgress: (received, total) {
          if (total <= 0 || !mounted) return;
          final p = received / total;
          // Çizgiyi çok sık yenileme.
          if ((p * 100).floor() != (_progress * 100).floor()) {
            setState(() => _progress = p);
          }
        },
      );
      if (!mounted) return;
      setState(() => _phase = _Phase.ready);
    } on UpdateException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = e.message;
      });
    }
  }

  Future<void> _install() async {
    setState(() => _phase = _Phase.installing);
    if (!await UpdateService.canInstall()) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.ready;
        _installPermissionAsked = true;
      });
      await UpdateService.openInstallSettings();
      return;
    }
    try {
      await UpdateService.openInstaller(_apkPath);
    } catch (_) {
      if (mounted) {
        setState(() {
          _phase = _Phase.ready;
          _error = 'Kurucu açılamadı — dosya: updates/${widget.info.version}.apk';
        });
      }
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _dismiss() {
    unawaited(widget.storage.saveUpdateSkipped(widget.info.version));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return AlertDialog(
      backgroundColor: AppColors.surfaceAlt,
      title: Row(
        children: [
          const Icon(Icons.system_update_alt, color: AppColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text('v${info.version} hazır',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (info.notes.isNotEmpty) ...[
            Text(info.notes, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 14),
          ],
          switch (_phase) {
            _Phase.downloading => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: Radii.pill,
                    child: LinearProgressIndicator(
                      value: _progress,
                      minHeight: 8,
                      backgroundColor: AppColors.line,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'İndiriliyor · %${(_progress * 100).floor()}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            _Phase.ready || _Phase.installing => Row(
                children: [
                  const Icon(Icons.verified_outlined,
                      size: 16, color: AppColors.online),
                  const SizedBox(width: 6),
                  Text('İndirildi ve doğrulandı',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            _Phase.error => Text(
                _error,
                style: const TextStyle(color: AppColors.offline),
              ),
          },
          if (_error.isNotEmpty && _phase != _Phase.error) ...[
            const SizedBox(height: 8),
            Text(_error,
                style: const TextStyle(color: AppColors.offline, fontSize: 12)),
          ],
          if (_installPermissionAsked) ...[
            const SizedBox(height: 8),
            Text(
              'Açılan ekrandan "Bu uygulamaya izin ver"i aç, sonra geri dönüp '
              'tekrar Kur’a bas.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: [
        if (_phase == _Phase.downloading)
          TextButton(onPressed: _dismiss, child: const Text('Şimdi değil')),
        if (_phase == _Phase.error) ...[
          TextButton(onPressed: _dismiss, child: const Text('Vazgeç')),
          FilledButton(onPressed: _download, child: const Text('Yeniden dene')),
        ],
        if (_phase == _Phase.ready || _phase == _Phase.installing) ...[
          TextButton(onPressed: _dismiss, child: const Text('Sonraya')),
          FilledButton.icon(
            onPressed: _phase == _Phase.installing ? null : _install,
            icon: const Icon(Icons.install_mobile, size: 18),
            label: Text(_phase == _Phase.installing
                ? 'Kurucuda onayla…'
                : 'Kur'),
          ),
        ],
      ],
    );
  }
}
