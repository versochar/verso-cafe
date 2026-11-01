/// `version.json` modeli ve sürüm karşılaştırması (ADR-012).
///
/// Kaynak: `https://github.com/versochar/verso-cafe/releases/latest/download/version.json`
library;

import 'dart:ffi' show Abi;

/// Yayınlanmış sürüm bildirimi.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.url,
    this.sha256,
    this.publishedAt,
  });

  final String version;

  /// Kullanıcıya gösterilecek yenilik metni (Türkçe, kısa).
  final String notes;

  /// İndirilecek APK'nın tam URL'i.
  final String url;

  /// İndirilen dosyanın doğrulanması için beklenen sha256 (hex, küçük harf).
  final String? sha256;

  final String? publishedAt;

  /// `version.json` içeriğinden çözümler.
  ///
  /// APK **cihazın mimarisine** göre seçilir ([abi] verilmezse cihazdan
  /// okunur); yoksa evrensel APK'ya, o da yoksa arm64'e düşülür. Aksi hâlde
  /// eski (armv7) telefonlar arm64 paketini indirip "kurulamadı" hatası alırdı.
  static UpdateInfo? tryParse(Map<String, dynamic> json, {String? abi}) {
    final version = json['version']?.toString();
    if (version == null || version.isEmpty) return null;

    final asset = resolveAsset(json, abi ?? currentAbi());
    if (asset == null) return null;

    return UpdateInfo(
      version: version,
      notes: json['notes']?.toString() ?? '',
      url: asset.url,
      sha256: asset.sha256,
      publishedAt: json['publishedAt']?.toString(),
    );
  }

  /// Cihazın APK mimarisi anahtarı (`arm64-v8a`, `armeabi-v7a`, …).
  ///
  /// Masaüstü/test ortamında `null` döner; o zaman evrensel/arm64'e düşülür.
  static String? currentAbi() {
    try {
      return switch (Abi.current()) {
        Abi.androidArm64 => 'arm64-v8a',
        Abi.androidArm => 'armeabi-v7a',
        Abi.androidX64 => 'x86_64',
        Abi.androidIA32 => 'x86',
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }
}

/// `version.json`'dan indirilecek APK'yı ve sha256'sını seçer.
///
/// Sıra: cihaz mimarisi → `assets.universal` (ya da `android`) → arm64 →
/// armv7. `sha256` tek metin (evrensel paket) ya da mimari→metin haritası
/// olabilir; seçilen paketinki kullanılır. Geçersiz özet `null` sayılır.
({String url, String? sha256})? resolveAsset(
  Map<String, dynamic> json,
  String? abi,
) {
  final assets = <String, String>{};
  final raw = json['assets'];
  if (raw is Map) {
    for (final entry in raw.entries) {
      final url = entry.value?.toString();
      if (url != null && url.startsWith('http')) {
        assets[entry.key.toString()] = url;
      }
    }
  }
  final plain = json['android']?.toString();
  if (plain != null && plain.startsWith('http')) assets['universal'] = plain;
  if (assets.isEmpty) return null;

  final key = <String>[
    if (abi != null && assets.containsKey(abi)) abi,
    if (assets.containsKey('universal')) 'universal',
    if (assets.containsKey('arm64-v8a')) 'arm64-v8a',
    if (assets.containsKey('armeabi-v7a')) 'armeabi-v7a',
  ].first;

  final shaRaw = json['sha256'];
  String? sha;
  if (shaRaw is Map) {
    sha = shaRaw[key]?.toString();
  } else if (shaRaw is String) {
    sha = shaRaw;
  }
  sha = sha?.toLowerCase();
  if (sha == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) sha = null;

  return (url: assets[key]!, sha256: sha);
}

/// Semver benzeri karşılaştırma: `a`, `b`'den yeniyse pozitif.
///
/// `0.2.0` > `0.1.9`; eşit uzunlukta olmayan parçalar sıfırla doldurulur.
int compareVersions(String a, String b) {
  final pa = a.split(RegExp(r'[.+-]'));
  final pb = b.split(RegExp(r'[.+-]'));
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final na = int.tryParse(i < pa.length ? pa[i] : '0') ?? 0;
    final nb = int.tryParse(i < pb.length ? pb[i] : '0') ?? 0;
    if (na != nb) return na.compareTo(nb);
  }
  return 0;
}

/// `güncel` sürüme göre yeni bir yayın var mı?
bool isUpdateAvailable(String current, String? latest) =>
    latest != null && latest.isNotEmpty && compareVersions(latest, current) > 0;
