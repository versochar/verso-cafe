import 'dart:typed_data';

/// Görsel baytlarının ilk imzasından MIME türünü çıkarır.
///
/// Desteklenenler medya sunucusunun kabul ettiği türlerdir; tanınmayan
/// içerik JPEG varsayılır (sunucu yine doğrular).
String detectImageMime(Uint8List b) {
  if (b.length > 11) {
    if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'image/jpeg';
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      return 'image/png';
    }
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x38) {
      return 'image/gif';
    }
    if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42) {
      return 'image/webp';
    }
  }
  return 'image/jpeg';
}
