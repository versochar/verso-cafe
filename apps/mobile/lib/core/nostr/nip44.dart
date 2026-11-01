/// NIP-44 v2: secp256k1 ECDH + HKDF + ChaCha20 + HMAC-SHA256 tabanlı gerçek
/// uçtan uca şifreleme. Resmi spesifikasyona ve `test/data/nip44.vectors.json`
/// vektörlerine birebir uygundur (paulmillr/nip44 test paketiyle doğrulanır).
///
/// Yük biçimi: base64( 0x02 | nonce(32) | ciphertext | mac(32) )
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/ecc/api.dart' as pc;
import 'package:pointycastle/ecc/curves/secp256k1.dart';

import 'bech32.dart';

final _random = Random.secure();

/// secp256k1 eğrisi (grup mertebesi `_curve.n` üzerinden okunur).
final ECCurve_secp256k1 _curve = ECCurve_secp256k1();

const _salt = 'nip44-v2';
const _minPlaintext = 1;
// Şifreleme tarafı 65535 bayt ile sınırlıdır (referans vektörlerin kabul
// ettiği davranış); çözme tarafı 6 baytlık genişletilmiş öneki kabul eder.
const _maxPlaintext = 65535;
const _extendedPrefixThreshold = 65536;

/// [privHex] ile [pubHex] arasındaki uzun ömürlü konuşma anahtarı (32 bayt).
///
/// ECDH: x-only pubkey (çift Y) noktasının priv ile çarpımı; sonuç noktanın
/// x koordinatı hash'lenmeden HKDF-extract tuzu ile karıştırılır.
Uint8List conversationKey(String privHex, String pubHex) {
  final d = BigInt.tryParse(privHex, radix: 16);
  if (d == null || d < BigInt.one || d >= _curve.n) {
    throw const FormatException('Özel anahtar secp256k1 aralığında değil');
  }
  final xBytes = hexToBytes(pubHex);
  if (xBytes.length != 32) {
    throw const FormatException('Herkese açık anahtar 32 bayt olmalı');
  }
  // BIP-340 x-only: Y her zaman çift seçilir (0x02 ön eki).
  final pc.ECPoint point;
  try {
    final decoded = _curve.curve.decodePoint([0x02, ...xBytes]);
    if (decoded == null) throw ArgumentError();
    point = decoded;
  } on ArgumentError {
    throw const FormatException('Herkese açık anahtar eğri üzerinde değil');
  }
  if (point.isInfinity) {
    throw const FormatException('Nokta noktada değil (infinity)');
  }
  final shared = point * d;
  if (shared == null || shared.isInfinity) {
    throw const FormatException('Paylaşılan nokta geçersiz');
  }
  final sharedX = _bigTo32(shared.x!.toBigInteger()!);

  // HKDF-extract: HMAC-SHA256(key = utf8('nip44-v2'), msg = shared_x)
  return Uint8List.fromList(
    Hmac(sha256, utf8.encode(_salt)).convert(sharedX).bytes,
  );
}

/// Konuşma anahtarı + tek kullanımlık nonce'tan mesaj anahtarları:
/// chacha_key(32) | chacha_nonce(12) | hmac_key(32).
({Uint8List chachaKey, Uint8List chachaNonce, Uint8List hmacKey})
    messageKeys(Uint8List conversation, Uint8List nonce) {
  if (conversation.length != 32) {
    throw const FormatException('Geçersiz konuşma anahtarı uzunluğu');
  }
  if (nonce.length != 32) {
    throw const FormatException('Geçersiz nonce uzunluğu');
  }
  // HKDF-expand(PRK = conversation, info = nonce, L = 76)
  final keys = _hkdfExpand(conversation, nonce, 76);
  return (
    chachaKey: keys.sublist(0, 32),
    chachaNonce: keys.sublist(32, 44),
    hmacKey: keys.sublist(44, 76),
  );
}

/// Dolgu uzunluğu: 32 bayt tabanlı, 2'nin kuvvetleriyle yumuşatılmış.
int calcPaddedLen(int unpaddedLen) {
  if (unpaddedLen <= 0) throw const FormatException('Geçersiz uzunluk');
  if (unpaddedLen <= 32) return 32;
  final nextPower = 1 << (_floorLog2(unpaddedLen - 1) + 1);
  final chunk = nextPower <= 256 ? 32 : nextPower >> 3;
  return chunk * ((unpaddedLen - 1) ~/ chunk + 1);
}

/// [message] metnini düz metin olarak şifreler; base64 NIP-44 yükü döner.
String nip44Encrypt(String message, String privHex, String pubHex,
    {Uint8List? nonce}) {
  final conv = conversationKey(privHex, pubHex);
  final n = nonce ?? Uint8List.fromList(List.generate(32, (_) => _random.nextInt(256)));
  final payload = encryptWithKeys(message, conv, n);
  return payload;
}

/// NIP-44 yükünü çözer. MAC veya dolgu hatalıysa [FormatException] fırlatılır.
String nip44Decrypt(String payload, String privHex, String pubHex) {
  final conv = conversationKey(privHex, pubHex);
  return decryptWithKeys(payload, conv);
}

/// Konuşma anahtarı hazır olduğunda doğrudan şifreleme (test vektörleri için).
String encryptWithKeys(String message, Uint8List conversation, Uint8List nonce) {
  final keys = messageKeys(conversation, nonce);
  final padded = _pad(message);
  final ciphertext =
      _chacha20(keys.chachaKey, keys.chachaNonce, padded);
  final mac = Hmac(sha256, keys.hmacKey)
      .convert([...nonce, ...ciphertext])
      .bytes;
  return base64Encode([2, ...nonce, ...ciphertext, ...mac]);
}

/// Konuşma anahtarı hazır olduğunda doğrudan çözme.
String decryptWithKeys(String payload, Uint8List conversation) {
  if (payload.isEmpty || payload.startsWith('#')) {
    throw const FormatException('Desteklenmeyen NIP-44 sürümü');
  }
  if (payload.length < 132) {
    throw const FormatException('Yük çok kısa');
  }
  final Uint8List data;
  try {
    data = base64Decode(payload);
  } catch (_) {
    throw const FormatException('Geçersiz base64 yük');
  }
  if (data.length < 99) {
    throw const FormatException('Yük çok kısa');
  }
  if (data[0] != 2) {
    throw FormatException('Bilinmeyen NIP-44 sürümü: ${data[0]}');
  }
  final nonce = data.sublist(1, 33);
  final ciphertext = data.sublist(33, data.length - 32);
  final mac = data.sublist(data.length - 32);

  final keys = messageKeys(conversation, nonce);
  final calculated = Hmac(sha256, keys.hmacKey)
      .convert([...nonce, ...ciphertext])
      .bytes;
  if (!_constantTimeEquals(calculated, mac)) {
    throw const FormatException('MAC doğrulanamadı');
  }
  final padded = _chacha20(keys.chachaKey, keys.chachaNonce, ciphertext);
  return _unpad(padded);
}

// ---------------------------------------------------------------- internals

Uint8List _hkdfExpand(Uint8List prk, Uint8List info, int length) {
  final out = Uint8List(length);
  final hmac = Hmac(sha256, prk);
  var previous = const <int>[];
  var offset = 0;
  var counter = 1;
  while (offset < length) {
    previous = hmac.convert([...previous, ...info, counter]).bytes;
    final take = min(32, length - offset);
    out.setRange(offset, offset + take, previous);
    offset += take;
    counter++;
  }
  return out;
}

int _floorLog2(int value) => value <= 0 ? -1 : value.bitLength - 1;

Uint8List _pad(String message) {
  final unpadded = utf8.encode(message);
  final len = unpadded.length;
  if (len < _minPlaintext || len > _maxPlaintext) {
    throw const FormatException('Geçersiz düz metin uzunluğu');
  }
  final Uint8List prefix;
  if (len >= _extendedPrefixThreshold) {
    prefix = Uint8List(6)
      ..[2] = (len >> 24) & 0xFF
      ..[3] = (len >> 16) & 0xFF
      ..[4] = (len >> 8) & 0xFF
      ..[5] = len & 0xFF;
  } else {
    prefix = Uint8List(2)
      ..[0] = (len >> 8) & 0xFF
      ..[1] = len & 0xFF;
  }
  final paddedLen = calcPaddedLen(len);
  final out = Uint8List(prefix.length + paddedLen);
  out.setRange(0, prefix.length, prefix);
  out.setRange(prefix.length, prefix.length + len, unpadded);
  return out;
}

String _unpad(Uint8List padded) {
  if (padded.length < 4) throw const FormatException('Geçersiz dolgu');
  final firstTwo = (padded[0] << 8) | padded[1];
  int unpaddedLen;
  int prefixLen;
  if (firstTwo == 0) {
    if (padded.length < 6) throw const FormatException('Geçersiz dolgu');
    unpaddedLen = (padded[2] << 24) | (padded[3] << 16) | (padded[4] << 8) | padded[5];
    if (unpaddedLen < _extendedPrefixThreshold) {
      throw const FormatException('Geçersiz genişletilmiş önek');
    }
    prefixLen = 6;
  } else {
    unpaddedLen = firstTwo;
    prefixLen = 2;
  }
  if (unpaddedLen == 0 ||
      padded.length < prefixLen + unpaddedLen ||
      padded.length != prefixLen + calcPaddedLen(unpaddedLen)) {
    throw const FormatException('Geçersiz dolgu uzunluğu');
  }
  try {
    return utf8.decode(padded.sublist(prefixLen, prefixLen + unpaddedLen));
  } on FormatException {
    throw const FormatException('UTF-8 çözümü başarısız');
  }
}

/// ChaCha20 (RFC 8439, blok sayacı 0'dan başlar; NIP-44 gereksinimi).
Uint8List _chacha20(Uint8List key, Uint8List nonce, Uint8List input) {
  if (key.length != 32) throw const FormatException('ChaCha anahtarı 32 bayt olmalı');
  if (nonce.length != 12) throw const FormatException('ChaCha nonce 12 bayt olmalı');

  final state = Uint32List(16);
  state[0] = 0x61707865;
  state[1] = 0x3320646e;
  state[2] = 0x79622d32;
  state[3] = 0x6b206574;
  for (var i = 0; i < 8; i++) {
    state[4 + i] = _le32(key, i * 4);
  }
  // state[12] blok sayacı, state[13..15] nonce
  state[13] = _le32(nonce, 0);
  state[14] = _le32(nonce, 4);
  state[15] = _le32(nonce, 8);

  final output = Uint8List(input.length);
  const mask32 = 0xFFFFFFFF;
  for (var block = 0; block * 64 < input.length; block++) {
    state[12] = block & mask32;
    final working = Uint32List.fromList(state);
    for (var i = 0; i < 10; i++) {
      _qr(working, 0, 4, 8, 12);
      _qr(working, 1, 5, 9, 13);
      _qr(working, 2, 6, 10, 14);
      _qr(working, 3, 7, 11, 15);
      _qr(working, 0, 5, 10, 15);
      _qr(working, 1, 6, 11, 12);
      _qr(working, 2, 7, 8, 13);
      _qr(working, 3, 4, 9, 14);
    }
    for (var i = 0; i < 16; i++) {
      working[i] = (working[i] + state[i]) & mask32;
    }
    final start = block * 64;
    final end = min(start + 64, input.length);
    for (var i = start; i < end; i++) {
      final j = i - start;
      output[i] = input[i] ^ (working[j >> 2] >> (8 * (j & 3)) & 0xFF);
    }
  }
  return output;
}

void _qr(Uint32List s, int a, int b, int c, int d) {
  const mask = 0xFFFFFFFF;
  s[a] = (s[a] + s[b]) & mask;
  s[d] = _rotl(s[d] ^ s[a], 16);
  s[c] = (s[c] + s[d]) & mask;
  s[b] = _rotl(s[b] ^ s[c], 12);
  s[a] = (s[a] + s[b]) & mask;
  s[d] = _rotl(s[d] ^ s[a], 8);
  s[c] = (s[c] + s[d]) & mask;
  s[b] = _rotl(s[b] ^ s[c], 7);
}

int _rotl(int v, int n) => ((v << n) | (v >> (32 - n))) & 0xFFFFFFFF;

int _le32(Uint8List b, int i) =>
    b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24);

Uint8List _bigTo32(BigInt v) {
  final out = Uint8List(32);
  var t = v;
  for (var i = 31; i >= 0; i--) {
    out[i] = (t & BigInt.from(0xFF)).toInt();
    t = t >> 8;
  }
  return out;
}

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
