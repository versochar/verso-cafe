/// NIP-92: Gönderi içi medya (`imeta`) etiketi.
///
/// Format:
/// ```
/// ["imeta",
///  "url <url>",
///  "m <mime-type>",
///  "x <sha256>",
///  "ox <sha256>",
///  "size <bytes>",
///  "dim <width>x<height>",
///  "alt <description>",
///  "fallback <url>"]
/// ```
/// `url` zorunlu, `m` (mime), `x` (sha256), `ox` (orijinal sha256) tavsiye edilir.
library;

import 'package:crypto/crypto.dart';

String buildImetaTag({
  required String url,
  String? mimeType,
  String? sha256Hex,
  String? originalSha256Hex,
  int? sizeBytes,
  String? dimensions,
  String? altText,
  String? fallbackUrl,
}) {
  final parts = <String>['url $url'];
  if (mimeType != null && mimeType.isNotEmpty) parts.add('m $mimeType');
  if (sha256Hex != null && sha256Hex.isNotEmpty) parts.add('x $sha256Hex');
  if (originalSha256Hex != null && originalSha256Hex.isNotEmpty) {
    parts.add('ox $originalSha256Hex');
  }
  if (sizeBytes != null) parts.add('size $sizeBytes');
  if (dimensions != null && dimensions.isNotEmpty) parts.add('dim $dimensions');
  if (altText != null && altText.isNotEmpty) parts.add('alt $altText');
  if (fallbackUrl != null && fallbackUrl.isNotEmpty) parts.add('fallback $fallbackUrl');
  return ['imeta', ...parts].join('|');
}

/// `imeta` etiketini NIP-01 tags formatına dönüştürür.
/// Örnek: `tags: [['imeta', 'url ...', 'm image/webp', ...]]`
List<List<String>> imetaTags({
  required String url,
  String? mimeType,
  String? sha256Hex,
  String? originalSha256Hex,
  int? sizeBytes,
  String? dimensions,
  String? altText,
  String? fallbackUrl,
}) {
  return [
    ['imeta', url,
      if (mimeType != null) 'm $mimeType',
      if (sha256Hex != null) 'x $sha256Hex',
      if (originalSha256Hex != null) 'ox $originalSha256Hex',
      if (sizeBytes != null) 'size $sizeBytes',
      if (dimensions != null) 'dim $dimensions',
      if (altText != null) 'alt $altText',
      if (fallbackUrl != null) 'fallback $fallbackUrl',
    ].whereType<String>().toList(),
  ];
}

/// SHA256 hesaplar (dosya veya URL içeriği için).
String sha256OfString(String content) {
  return sha256.convert(content.codeUnits).toString();
}
