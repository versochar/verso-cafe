import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/config/app_config.dart';
import '../../core/identity/invite_qr.dart';
import '../../core/nostr/bech32.dart';
import '../../core/session/app_session.dart';
import '../../ui/theme.dart';
import '../feed/user_sheet.dart';

/// Davet QR'ı tarar; bulunursa kişinin kullanıcı sheet'ini açar.
Future<void> showScanQr(BuildContext context) async {
  final result = await Navigator.of(context).push<_ScanResult>(
    MaterialPageRoute(builder: (_) => const ScanQrPage()),
  );
  if (result == null || !context.mounted) return;

  final session = AppSession.instance;
  if (result.pubkey == session.keys?.publicKeyHex) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bu senin kendi kodun 🙂')),
    );
    return;
  }
  // Takip listesinde olsa da olmasa da sheet açılır; sheet karar verir.
  await showUserSheet(context, result.pubkey);
  if (result.relayWarning && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Davet başka bir relay işaret ediyor; bu sürüm tek relay ile çalışır.',
        ),
      ),
    );
  }
}

class _ScanResult {
  const _ScanResult({required this.pubkey, required this.relayWarning});

  final String pubkey;
  final bool relayWarning;
}

/// Tam ekran QR tarayıcı.
class ScanQrPage extends StatefulWidget {
  const ScanQrPage({super.key});

  @override
  State<ScanQrPage> createState() => _ScanQrPageState();
}

class _ScanQrPageState extends State<ScanQrPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handled = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (raw == null) return;

    final decoded = _decode(raw.trim());
    if (decoded == null) {
      setState(() => _error = 'Bu bir ${AppConfig.name} davet kodu değil');
      return;
    }
    _handled = true;
    _controller.stop();
    Navigator.of(context).pop(decoded);
  }

  /// QR'ı galeriden seçilen bir görselde arar (ekran görüntüsü olarak
  /// gönderilen davet kodları için).
  Future<void> _scanFromGallery() async {
    if (_handled) return;
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null || _handled) return;
    final capture = await _controller.analyzeImage(file.path);
    final raw = capture?.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (raw == null) {
      if (mounted) setState(() => _error = 'Bu görselde QR bulunamadı');
      return;
    }
    final decoded = _decode(raw.trim());
    if (decoded == null) {
      if (mounted) setState(() => _error = 'Bu bir ${AppConfig.name} davet kodu değil');
      return;
    }
    _handled = true;
    await _controller.stop();
    if (mounted) Navigator.of(context).pop(decoded);
  }

  /// Davet JSON'ını ya da çıplak `npub1…`/hex değeri pubkey'e çözer.
  _ScanResult? _decode(String value) {
    try {
      String npub;
      String? relay;
      if (value.startsWith('{')) {
        final invite = InviteQr.decodeInvite(value);
        npub = invite.npub;
        relay = invite.relay;
      } else if (value.startsWith('npub1')) {
        npub = value;
      } else if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
        return _ScanResult(
          pubkey: value.toLowerCase(),
          relayWarning: false,
        );
      } else {
        return null;
      }
      final decoded = bech32Decode(npub);
      if (decoded.hrp != 'npub' || decoded.data.length != 32) return null;
      return _ScanResult(
        pubkey: bytesToHex(decoded.data).toLowerCase(),
        relayWarning: relay != null && relay != AppConfig.relayUrl,
      );
    } on FormatException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => ColoredBox(
              color: AppColors.background,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.no_photography_outlined,
                          size: 48, color: AppColors.textFaint),
                      const SizedBox(height: Insets.md),
                      Text(
                        'Kamera açılamadı.\n'
                        'Ayarlar → Uygulamalar → ${AppConfig.name} → İzinler → Kamera.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Tarama çerçevesi
          Center(
            child: SizedBox(
              width: 240,
              height: 240,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.accent, width: 2),
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
              ),
            ),
          ),
          // Üst çubuk
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: 'Kapat',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.photo_library_outlined,
                        color: Colors.white),
                    tooltip: 'Galeriden tara',
                    onPressed: _scanFromGallery,
                  ),
                  ValueListenableBuilder<MobileScannerState>(
                    valueListenable: _controller,
                    builder: (context, state, _) => IconButton(
                      icon: Icon(
                        state.torchState == TorchState.on
                            ? Icons.flash_on
                            : Icons.flash_off,
                        color: state.torchState == TorchState.on
                            ? AppColors.accent
                            : Colors.white,
                      ),
                      tooltip: 'Işık',
                      onPressed: () => _controller.toggleTorch(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Alt bilgi
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  _error ?? 'Arkadaşının davet QR’ını bu çerçeveye okut',
                  style: TextStyle(
                    color: _error != null
                        ? AppColors.offline
                        : Colors.white70,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
