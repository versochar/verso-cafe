/// Ağ adreslerinin (relay + medya + hesap) çalışma zamanı yapılandırması.
///
/// Adresler normalde derleme sırasında APK'ya gömülür. Ev sunucusu Cloudflare
/// tüneliyle yayınlandığında adres tünel yeniden başlayınca değişir; her
/// seferinde yeni APK yayınlamak yerine uygulama açılışta `network.json`'u
/// okur ve gömülü adresin üzerine yazar (ADR-014).
///
/// Okunan değer cihazda saklanır: çevrimdışı açılışta son bilinen adres
/// kullanılır, GitHub'a ulaşılamazsa uygulama yine açılır (gömülü adres).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_config.dart';

class Endpoints {
  Endpoints._();

  static const _cacheKey = 'network.v1';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  /// Açılışta çağrılır: önce cihazdaki son yapılandırma, sonra `network.json`.
  ///
  /// Hata dışarı sızmaz — ağ yoksa ya da dosya bozuksa gömülü adresler geçerli
  /// kalır. Zaman aşımı kısa tutulur ki çevrimdışı açılış beklemesin.
  ///
  /// `NETWORK_URL` boşsa (ör. tamamen çevrimdışı geliştirme) ne önbellek ne
  /// uzak yapılandırma uygulanır: gömülü yerel adresler korunur.
  static Future<void> load({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (AppConfig.networkUrl.isEmpty) return;
    await _applyCached();
    final json = await _fetch(timeout);
    if (json == null) return;
    if (apply(json)) {
      try {
        await _storage.write(key: _cacheKey, value: jsonEncode(json));
      } catch (_) {
        // Önbellek yazılamazsa da yeni adresler bu oturum için geçerli.
      }
    }
  }

  /// Adresleri JSON'dan uygular; en az biri değiştiyse `true` döner.
  static bool apply(Map<String, dynamic> json) {
    final parsed = parse(json);
    var changed = false;
    if (parsed.relay != null && parsed.relay != AppConfig.relayUrl) {
      AppConfig.relayUrl = parsed.relay!;
      changed = true;
    }
    if (parsed.media != null && parsed.media != AppConfig.mediaUrl) {
      AppConfig.mediaUrl = parsed.media!;
      changed = true;
    }
    if (parsed.account != null && parsed.account != AppConfig.accountUrl) {
      AppConfig.accountUrl = parsed.account!;
      changed = true;
    }
    return changed;
  }

  /// `network.json` içeriğini doğrular. Geçersiz/eksik alan `null` olur.
  ///
  /// Beklenen biçim:
  /// `{"relay": "wss://…", "media": "https://…", "account": "https://…"}`.
  static ({String? relay, String? media, String? account}) parse(
      Map<String, dynamic> json) {
    final relay = json['relay']?.toString().trim();
    final media = json['media']?.toString().trim();
    final account = json['account']?.toString().trim();
    return (
      relay: relay != null && _validRelay(relay) ? relay : null,
      media: media != null && _validMedia(media) ? media : null,
      account: account != null && _validMedia(account) ? account : null,
    );
  }

  static bool _validRelay(String value) =>
      _valid(value, secure: 'wss', plain: 'ws');

  static bool _validMedia(String value) =>
      _valid(value, secure: 'https', plain: 'http');

  /// Şifresiz şema yalnız yerel geliştirme adreslerinde kabul edilir: internet
  /// üzerinden gelen bir yapılandırma uygulamayı cleartext'e düşüremez
  /// (Android zaten yalnız bu adresler için cleartext'e izin veriyor).
  static bool _valid(
    String value, {
    required String secure,
    required String plain,
  }) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return false;
    if (uri.scheme == secure) return true;
    if (uri.scheme != plain) return false;
    const local = {'127.0.0.1', 'localhost', '10.0.2.2', '::1'};
    return local.contains(uri.host);
  }

  static Future<Map<String, dynamic>?> _fetch(Duration timeout) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..userAgent = 'VersoCafe/${AppConfig.version}';
    try {
      final req = await client.getUrl(Uri.parse(AppConfig.networkUrl));
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join().timeout(timeout);
      final json = jsonDecode(body);
      return json is Map<String, dynamic> ? json : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> _applyCached() async {
    try {
      final raw = await _storage.read(key: _cacheKey);
      if (raw == null || raw.isEmpty) return;
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) apply(json);
    } catch (_) {
      // Bozuk önbellek: yok say, gömülü adresler geçerli.
    }
  }
}
