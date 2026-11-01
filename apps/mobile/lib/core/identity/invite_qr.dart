import 'dart:convert';

import '../nostr/keys.dart';

/// Faz 2: Davet QR kodu — `npub` + relay adresini bir `note` (NIP-19 `note`) olarak
/// kodlar; alıcı QR'ı tarayıp bu kişiyi takip edebilir.
///
/// Örnek içerik (JSON):
/// ```json
/// {"npub":"npub1...","relay":"wss://relay.sosyal.dpdns.org","name":"Mitsune"}
/// ```
class InviteQr {
  InviteQr._();

  static String encodeInvite(KeyPair keys, String relayUrl, {String? displayName}) {
    final payload = jsonEncode({
      'npub': keys.npub,
      'relay': relayUrl,
      if (displayName != null) 'name': displayName,
    });
    return payload;
  }

  /// [inviteString] davet QR içeriği. `npub` ve `relay` döndürür.
  static ({String npub, String? relay, String? name}) decodeInvite(String inviteString) {
    try {
      final data = jsonDecode(inviteString);
      final npub = data['npub']?.toString();
      if (npub == null || !npub.startsWith('npub')) {
        throw const FormatException('Geçersiz npub');
      }
      // `npub`'dan `publicKeyHex`'i çıkarmaya gerek yok — sadece gösterim.
      return (
        npub: npub,
        relay: data['relay']?.toString(),
        name: data['name']?.toString(),
      );
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Geçersiz davet içeriği: $e');
    }
  }
}
