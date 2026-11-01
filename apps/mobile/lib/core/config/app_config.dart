/// Uygulama genelindeki sabitler.
///
/// Kullanıcıya görünen ad `name`'den gelir; `slug`/`domain`/`applicationId`
/// teknik kimlik olarak `sosyal` kaldı (bkz. docs/decisions.md → ADR-011).
class AppConfig {
  static const String name = 'Verso Cafe';
  /// `pubspec.yaml` → `version:` ile birlikte güncel tutulur.
  /// Test sürümleri `--dart-define=APP_VERSION=…` ile geçersiz kılınabilir.
  static const String version =
      String.fromEnvironment('APP_VERSION', defaultValue: '0.3.0');

  /// Güncelleme bildirimi dosyası (ADR-012).
  static const String updateUrl = String.fromEnvironment(
    'UPDATE_URL',
    defaultValue:
        'https://github.com/versochar/verso-cafe/releases/latest/download/version.json',
  );
  static const String slug = 'sosyal';
  static const String domain = 'sosyal.dpdns.org';

  /// Geliştirme relay'i. Derleme sırasında geçersiz kılınabilir:
  /// flutter run --dart-define=RELAY_URL=wss://relay.ornek.dpdns.org
  ///
  /// Çalışma zamanında `Endpoints` tarafından değiştirilebilir (network.json):
  /// tünel adresi değişince APK yeniden derlenmeden yeni adrese geçilir.
  static String relayUrl = const String.fromEnvironment(
    'RELAY_URL',
    defaultValue: 'ws://127.0.0.1:7777',
  );

  /// Medya sunucusu (fotoğraf yüklemeleri). Derleme sırasında geçersiz
  /// kılınabilir: --dart-define=MEDIA_URL=http://192.168.1.109:8080
  static String mediaUrl = const String.fromEnvironment(
    'MEDIA_URL',
    defaultValue: 'http://127.0.0.1:8080',
  );

  /// Hesap servisi (kullanıcı adı/parola, roller, duyurular). Firebase yerine
  /// ev sunucusunda çalışır; varsayılan yerel geliştirme adresidir.
  static String accountUrl = const String.fromEnvironment(
    'ACCOUNT_URL',
    defaultValue: 'http://127.0.0.1:8090',
  );

  /// Ağ adreslerinin çalışma zamanı kaynağı (ADR-014).
  ///
  /// Depodaki `network.json`; tünel adresi değişince yalnız bu dosya güncellenir
  /// (`scripts/publish-network.sh`) ve kurulu uygulamalar bir sonraki açılışta
  /// yeni adrese geçer.
  static const String networkUrl = String.fromEnvironment(
    'NETWORK_URL',
    defaultValue:
        'https://raw.githubusercontent.com/versochar/verso-cafe/main/network.json',
  );
}
