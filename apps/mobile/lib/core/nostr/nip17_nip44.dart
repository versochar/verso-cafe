/// `NIP-17` hediye sarma içeriği için `NIP-44` şifreleme cephesi.
///
/// Gerçek kriptografi `nip44.dart` içinde uygulanır (secp256k1 ECDH + HKDF +
/// ChaCha20 + HMAC-SHA256). Konuşma anahtarı simetriktir:
/// `conversationKey(benimGizli, karşıtınAçık) == conversationKey(karşıtınGizli, benimAçık)`,
/// bu yüzden her iki yönde de karşı tarafın açık anahtarı kullanılır.
library;

import 'nip44.dart';

String encryptMessage(String message, String myPrivHex, String peerPubHex) =>
    nip44Encrypt(message, myPrivHex, peerPubHex);

String decryptMessage(String payload, String myPrivHex, String peerPubHex) =>
    nip44Decrypt(payload, myPrivHex, peerPubHex);
