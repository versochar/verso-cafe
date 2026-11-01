/// Uygulama genelindeki sabitler.
///
/// Kullanıcıya görünen ad `name`'den gelir; `slug`/`domain`/`applicationId`
/// teknik kimlik olarak `sosyal` kaldı (bkz. docs/decisions.md → ADR-011).
class AppConfig {
  static const String name = 'Verso Cafe';
  /// `pubspec.yaml` → `version:` ile birlikte güncel tutulur.
  static const String version = '0.1.1';
  static const String slug = 'sosyal';
  static const String domain = 'sosyal.dpdns.org';

  /// Geliştirme relay'i. Derleme sırasında geçersiz kılınabilir:
  /// flutter run --dart-define=RELAY_URL=wss://relay.ornek.dpdns.org
  static const String relayUrl = String.fromEnvironment(
    'RELAY_URL',
    defaultValue: 'ws://127.0.0.1:7777',
  );

  /// Medya sunucusu (fotoğraf yüklemeleri). Derleme sırasında geçersiz
  /// kılınabilir: --dart-define=MEDIA_URL=http://192.168.1.109:8080
  static const String mediaUrl = String.fromEnvironment(
    'MEDIA_URL',
    defaultValue: 'http://127.0.0.1:8080',
  );
}
