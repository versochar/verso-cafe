/// `version.json` modeli ve sürüm karşılaştırması (ADR-012).
///
/// Kaynak: `https://github.com/versochar/verso-cafe/releases/latest/download/version.json`
library;

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
  /// Evrensel (her telefon) APK tercih edilir; yoksa `android` düz alanına
  /// ya da asset haritasındaki arm64 girdisine düşülür.
  static UpdateInfo? tryParse(Map<String, dynamic> json) {
    final version = json['version']?.toString();
    if (version == null || version.isEmpty) return null;

    String? url = json['assets']?['universal']?.toString();
    url ??= json['android']?.toString();
    url ??= json['assets']?['arm64-v8a']?.toString();
    if (url == null || !url.startsWith('http')) return null;

    final sha = json['sha256']?.toString().toLowerCase();
    return UpdateInfo(
      version: version,
      notes: json['notes']?.toString() ?? '',
      url: url,
      sha256: (sha != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) ? sha : null,
      publishedAt: json['publishedAt']?.toString(),
    );
  }
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
