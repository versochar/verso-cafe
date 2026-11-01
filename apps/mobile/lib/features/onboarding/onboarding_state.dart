/// Faz 2: Onboarding adımları
///
/// 1. Hoş geldin ekranı
/// 2. Anahtar üretimi (KeyPair.generate)
/// 3. ZORUNLU yedek: parola gir → NIP-49 (`ncryptsec`) üret → QR ile dışa aktar
/// 4. Yedek doğrulama: kullanıcı `ncryptsec`'i tarar veya girer → doğrulama
/// 5. Profil (`kind:0`) yayınlanır
/// 6. Davet QR'ı gösterilir
///
/// Yedek tamamlanmadan (adım 4) ana ekran açılamaz.
library;

import '../../core/nostr/nip49.dart';

/// Onboarding durum makinesi için durumlar.
enum OnboardingState {
  welcome,           // hoş geldin
  generateKeys,      // anahtar üretildi
  createBackupPassword, // parola seçimi (zorunlu)
  confirmBackup,     // `ncryptsec` gösterildi / doğrulanıyor
  profileSetup,      // profil bilgisi
  invite,            // davet QR'ı gösteriliyor
  complete,          // onboarding tamamlandı
}

/// Yedek doğrulama: kullanıcı `ncryptsec`'i tarar veya parola ile açar.
/// Parola doğruysa `true`, değilse `false` (hata fırlatılmaz; kullanıcı tekrar dener).
Future<bool> verifyBackup(
  String ncryptsec,
  String password,
) async {
  try {
    await Nip49.decrypt(ncryptsec, password);
    return true;
  } on Nip49Exception {
    return false;
  }
}
