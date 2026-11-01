/// NIP-49: `ncryptsec` — özel anahtarın parola ile şifrelenmesi.
///
/// Biçim (91 bayt, sonra bech32):
/// ```
/// version(1) | log_n(1) | salt(16) | nonce(24) | security_byte(1) | ciphertext(48)
/// ```
/// `ciphertext` = XChaCha20-Poly1305(anahtar, nonce, aad=security_byte) çıktısı
/// (32 bayt şifreli metin + 16 bayt MAC).
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/scrypt.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'bech32.dart';

class Nip49Exception implements Exception {
  const Nip49Exception(this.message);

  final String message;

  @override
  String toString() => message;
}

/// `ncryptsec` üretir ve çözer.
///
/// scrypt bilinçli olarak pahalıdır (64 MiB / log_n=16). Bu yüzden türetme
/// ayrı bir isolate'te yapılır; UI donmaz.
class Nip49 {
  Nip49._();

  /// 0x02 = XChaCha20-Poly1305 (güncel sürüm).
  static const int version = 0x02;

  /// 16 → 64 MiB bellek, ~100-500 ms. Telefon için makul denge.
  static const int defaultLogN = 16;

  /// Yedeğin güvenli olmayan bir ortamda kullanılmadığını belirtir.
  static const int securityByteDefault = 0x02; // istemci bu bilgiyi takip etmiyor

  static const int _saltLength = 16;
  static const int _nonceLength = 24;
  static const int _macLength = 16;
  static const int _keyLength = 32;
  static const int _payloadLength = 1 + 1 + 16 + 24 + 1 + 48; // 91

  static final _random = Random.secure();

  static Uint8List _randomBytes(int length) =>
      Uint8List.fromList(List<int>.generate(length, (_) => _random.nextInt(256)));

  /// NIP-49: parola NFKC normalize edilir, scrypt(log_n, r=8, p=1) ile 32 bayt.
  static Future<Uint8List> _deriveKey(
    String password,
    Uint8List salt,
    int logN,
  ) {
    final normalized = Uint8List.fromList(utf8.encode(unorm.nfkc(password)));
    return Isolate.run(() {
      final scrypt = Scrypt()
        ..init(ScryptParameters(1 << logN, 8, 1, _keyLength, salt));
      final out = Uint8List(_keyLength);
      scrypt.deriveKey(normalized, 0, out, 0);
      return out;
    });
  }

  /// [privateKeyHex] 64 karakter hex. Dönen değer `ncryptsec1...`.
  static Future<String> encrypt(
    String privateKeyHex,
    String password, {
    int logN = defaultLogN,
    int securityByte = securityByteDefault,
  }) async {
    if (password.isEmpty) {
      throw const Nip49Exception('Parola boş olamaz');
    }
    if (logN < 10 || logN > 22) {
      throw const Nip49Exception('Geçersiz log_n');
    }
    final privateBytes = hexToBytes(privateKeyHex.toLowerCase());
    if (privateBytes.length != _keyLength) {
      throw const Nip49Exception('Özel anahtar 32 bayt olmalı');
    }

    final salt = _randomBytes(_saltLength);
    final nonce = _randomBytes(_nonceLength);
    final key = await _deriveKey(password, salt, logN);

    final box = await Xchacha20.poly1305Aead().encrypt(
      privateBytes,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: [securityByte],
    );

    final cipherText = Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);

    final payload = Uint8List(_payloadLength)
      ..[0] = version
      ..[1] = logN
      ..setRange(2, 18, salt)
      ..setRange(18, 42, nonce)
      ..[42] = securityByte
      ..setRange(43, 91, cipherText);

    return bech32Encode('ncryptsec', payload);
  }

  /// `ncryptsec1...` + parola → özel anahtar (64 karakter hex).
  static Future<String> decrypt(String ncryptsec, String password) async {
    if (password.isEmpty) {
      throw const Nip49Exception('Parola boş olamaz');
    }

    final ({String hrp, List<int> data}) decoded;
    try {
      decoded = bech32Decode(ncryptsec.trim());
    } on FormatException catch (e) {
      throw Nip49Exception('Geçersiz yedek: ${e.message}');
    }
    if (decoded.hrp != 'ncryptsec') {
      throw const Nip49Exception('Bu bir ncryptsec yedeği değil');
    }
    final payload = decoded.data;
    if (payload.length != _payloadLength) {
      throw const Nip49Exception('Yedek uzunluğu hatalı');
    }
    if (payload[0] != version) {
      throw const Nip49Exception('Desteklenmeyen yedek sürümü');
    }

    final logN = payload[1];
    if (logN < 10 || logN > 22) {
      throw const Nip49Exception('Yedekteki log_n geçersiz');
    }
    final salt = Uint8List.fromList(payload.sublist(2, 18));
    final nonce = payload.sublist(18, 42);
    final securityByte = payload[42];
    final cipherText = payload.sublist(43, 91);

    final key = await _deriveKey(password, salt, logN);

    try {
      final plain = await Xchacha20.poly1305Aead().decrypt(
        SecretBox(
          cipherText.sublist(0, _keyLength),
          nonce: nonce,
          mac: Mac(cipherText.sublist(_keyLength, _keyLength + _macLength)),
        ),
        secretKey: SecretKey(key),
        aad: [securityByte],
      );
      if (plain.length != _keyLength) {
        throw const Nip49Exception('Çözülen anahtar 32 bayt değil');
      }
      return bytesToHex(plain);
    } on SecretBoxAuthenticationError {
      throw const Nip49Exception('Parola yanlış veya yedek bozuk');
    }
  }

  /// Yedekteki `log_n` değerini okur (parola sormadan).
  static int logNOf(String ncryptsec) {
    final decoded = bech32Decode(ncryptsec.trim());
    if (decoded.hrp != 'ncryptsec' || decoded.data.length < 2) {
      throw const Nip49Exception('Geçersiz ncryptsec');
    }
    return decoded.data[1];
  }
}
