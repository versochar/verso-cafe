/// Güncelleme kontrolü ve APK indirme servisi.
///
/// Sürüm bilgisi GitHub Releases'taki statik `version.json`'dan okunur
/// (ADR-012 — API kota limiti yok). İndirme bitince sha256 doğrulanır ve
/// sistem kurucu (PACKAGE_INSTALL) ekranı açılır; Android sessiz kuruma
/// izin vermediği için son "Kur" onayı her zaman kullanıcıdadır.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import 'update_info.dart';

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

class UpdateService {
  UpdateService._();

  static const _channel = MethodChannel('verso/update');

  /// `version.json`'ı indirir; erişilemezse/bozuksa `null`.
  static Future<UpdateInfo?> fetchInfo({
    String? url,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..userAgent = 'VersoCafe/${AppConfig.version}';
    try {
      final req = await client.getUrl(Uri.parse(url ?? AppConfig.updateUrl));
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      return UpdateInfo.tryParse(jsonDecode(body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// APK'yı uygulamanın iç depolama alanına indirir.
  ///
  /// [onProgress] toplam bayt içinde gelinen bayt (0..1 oranı için bölünür —
  /// `Content-Length` yoksa `-1` döner). sha256 uyumsuzsa dosya silinir ve
  /// [UpdateException] fırlatılır. İndirilen dosyanın yolu döner.
  static Future<String> downloadApk(
    UpdateInfo info, {
    void Function(int received, int total)? onProgress,
  }) async {
    final dir = await _filesDir();
    final out = File('$dir/updates/${info.version}.apk');
    await out.parent.create(recursive: true);

    final client = HttpClient()..userAgent = 'VersoCafe/${AppConfig.version}';
    IOSink? sink;
    try {
      final req = await client.getUrl(Uri.parse(info.url));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw UpdateException('İndirme başarısız (HTTP ${res.statusCode}).');
      }
      final total = res.contentLength;
      final expected = info.sha256;

      sink = out.openWrite();
      var received = 0;
      final hasher = _Sha();
      await for (final chunk in res) {
        received += chunk.length;
        hasher.add(chunk);
        sink.add(chunk);
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      final actual = hasher.hex();
      if (expected != null && actual != expected) {
        await out.delete();
        throw const UpdateException(
            'Dosya doğrulanamadı (sha256 uyuşmuyor). Tekrar deneyin.');
      }
      return out.path;
    } on UpdateException {
      if (out.existsSync()) await out.delete();
      rethrow;
    } catch (e) {
      if (out.existsSync()) await out.delete();
      throw UpdateException('İndirme yarıda kesildi: $e');
    } finally {
      await sink?.close();
      client.close(force: true);
    }
  }

  /// Sistem "bilinmeyen kaynaklardan kurulum"a izinli mi?
  static Future<bool> canInstall() async {
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Ayarlar → bilinmeyen uygulama ekranını açar.
  static Future<void> openInstallSettings() =>
      _channel.invokeMethod<void>('openInstallSettings');

  /// indirilen APK için sistem kurucusunu açar.
  static Future<void> openInstaller(String path) =>
      _channel.invokeMethod<void>('installApk', {'path': path});

  static Future<String> _filesDir() async {
    final dir = await _channel.invokeMethod<String>('filesDir');
    if (dir == null) throw const UpdateException('Depolama alanı bulunamadı.');
    return dir;
  }
}

/// Akışa verilen baytlardan sha256 hesaplayan ince sarmalayıcı.
class _Sha {
  final _bytes = BytesBuilder(copy: false);
  void add(List<int> data) => _bytes.add(data);
  String hex() => sha256.convert(_bytes.takeBytes()).toString();
}
