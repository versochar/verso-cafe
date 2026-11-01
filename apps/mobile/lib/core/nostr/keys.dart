import 'dart:math';

import 'package:bip340/bip340.dart' as bip340;

import 'bech32.dart';

final _random = Random.secure();

/// Ed25519 değil, Nostr'un kullandığı secp256k1 + Schnorr anahtar çifti.
class KeyPair {
  KeyPair._(this.privateKeyHex, this.publicKeyHex);

  /// 32 bayt, 64 karakter hex.
  final String privateKeyHex;

  /// 32 bayt x-only public key, 64 karakter hex.
  final String publicKeyHex;

  String get npub => bech32Encode('npub', hexToBytes(publicKeyHex));
  String get nsec => bech32Encode('nsec', hexToBytes(privateKeyHex));

  static List<int> _randomBytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256));

  /// Yeni anahtar üretir. Geçersiz skaler (çok düşük olasılık) gelirse tekrar dener.
  factory KeyPair.generate() {
    while (true) {
      final priv = bytesToHex(_randomBytes(32));
      try {
        final pub = bip340.getPublicKey(priv);
        if (pub.length == 64) return KeyPair._(priv, pub.toLowerCase());
      } catch (_) {
        // geçersiz skaler, yeniden dene
      }
    }
  }

  factory KeyPair.fromPrivateHex(String privateKeyHex) {
    final hex = privateKeyHex.toLowerCase();
    if (hex.length != 64) {
      throw const FormatException('Özel anahtar 64 karakter hex olmalı');
    }
    final pub = bip340.getPublicKey(hex).toLowerCase();
    return KeyPair._(hex, pub);
  }

  factory KeyPair.fromNsec(String nsec) {
    final decoded = bech32Decode(nsec.trim());
    if (decoded.hrp != 'nsec' || decoded.data.length != 32) {
      throw const FormatException('Geçersiz nsec');
    }
    return KeyPair.fromPrivateHex(bytesToHex(decoded.data));
  }

  /// BIP-340 Schnorr imzası. [messageHex] 32 baytlık hex (event id).
  String sign(String messageHex) {
    final aux = bytesToHex(_randomBytes(32));
    return bip340.sign(privateKeyHex, messageHex, aux).toLowerCase();
  }

  static bool verify(String publicKeyHex, String messageHex, String signatureHex) {
    try {
      return bip340.verify(
        publicKeyHex.toLowerCase(),
        messageHex.toLowerCase(),
        signatureHex.toLowerCase(),
      );
    } catch (_) {
      return false;
    }
  }

  @override
  String toString() => npub;
}
