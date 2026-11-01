import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sosyal/core/nostr/bech32.dart';
import 'package:sosyal/core/nostr/keys.dart';
import 'package:sosyal/core/nostr/nip44.dart';

void main() {
  final vectors =
      jsonDecode(File('test/data/nip44.vectors.json').readAsStringSync())
          as Map<String, dynamic>;
  final v2 = vectors['v2'] as Map<String, dynamic>;
  final valid = v2['valid'] as Map<String, dynamic>;
  final invalid = v2['invalid'] as Map<String, dynamic>;

  Uint8List u8(String hex) => Uint8List.fromList(hexToBytes(hex));
  String sha(List<int> bytes) => sha256.convert(bytes).toString();

  group('NIP-44 v2 — resmi vektörler', () {
    test('get_conversation_key', () {
      for (final t in valid['get_conversation_key'] as List) {
        final got =
            bytesToHex(conversationKey(t['sec1'] as String, t['pub2'] as String));
        expect(got, t['conversation_key'], reason: 'sec1=${t['sec1']}');
      }
    });

    test('get_message_keys', () {
      final t = valid['get_message_keys'] as Map<String, dynamic>;
      final conv = u8(t['conversation_key'] as String);
      for (final k in t['keys'] as List) {
        final keys = messageKeys(conv, u8(k['nonce'] as String));
        expect(bytesToHex(keys.chachaKey), k['chacha_key']);
        expect(bytesToHex(keys.chachaNonce), k['chacha_nonce']);
        expect(bytesToHex(keys.hmacKey), k['hmac_key']);
      }
    });

    test('calc_padded_len', () {
      for (final pair in valid['calc_padded_len'] as List) {
        expect(calcPaddedLen(pair[0] as int), pair[1] as int,
            reason: 'unpadded=${pair[0]}');
      }
    });

    test('encrypt_decrypt (sabit nonce ile byte-byte)', () {
      for (final t in valid['encrypt_decrypt'] as List) {
        final conv = u8(t['conversation_key'] as String);
        final nonce = u8(t['nonce'] as String);
        final plain = t['plaintext'] as String;
        expect(encryptWithKeys(plain, conv, nonce), t['payload'],
            reason: 'plaintext=${plain.substring(0, plain.length.clamp(0, 30))}');
        expect(decryptWithKeys(t['payload'] as String, conv), plain);
      }
    });

    test('encrypt_decrypt_long_msg (desenli uzun mesaj, sha256)', () {
      for (final t in valid['encrypt_decrypt_long_msg'] as List) {
        final conv = u8(t['conversation_key'] as String);
        final nonce = u8(t['nonce'] as String);
        final repeat = int.parse(t['repeat'].toString());
        final plain = (t['pattern'] as String) * repeat;
        expect(sha(utf8.encode(plain)), t['plaintext_sha256']);
        final payload = encryptWithKeys(plain, conv, nonce);
        expect(sha(utf8.encode(payload)), t['payload_sha256']);
        expect(decryptWithKeys(payload, conv), plain);
      }
    });

    test('geçerli anahtarlarla uçtan uca gidiş-dönüş', () {
      for (final t in valid['encrypt_decrypt'] as List) {
        final sec1 = t['sec1'] as String;
        final sec2 = t['sec2'] as String;
        final pub1 = KeyPair.fromPrivateHex(sec1).publicKeyHex;
        final pub2 = KeyPair.fromPrivateHex(sec2).publicKeyHex;
        // conversation_key hem (sec1,pub2) hem (sec2,pub1) ile aynı olmalı
        expect(bytesToHex(conversationKey(sec2, pub1)), t['conversation_key']);
        final plain = t['plaintext'] as String;
        final sealed = nip44Encrypt(plain, sec1, pub2);
        expect(nip44Decrypt(sealed, sec2, pub1), plain);
        final back = nip44Encrypt(plain, sec2, pub1);
        expect(nip44Decrypt(back, sec1, pub2), plain);
      }
    });
  });

  group('NIP-44 v2 — geçersiz girdiler', () {
    test('invalid get_conversation_key fırlatır', () {
      for (final t in invalid['get_conversation_key'] as List) {
        expect(
            () => conversationKey(t['sec1'] as String, t['pub2'] as String),
            throwsA(anything),
            reason: 'sec1=${t['sec1']} pub2=${t['pub2']} (${t['note']})');
      }
    });

    test('invalid decrypt fırlatır', () {
      for (final t in invalid['decrypt'] as List) {
        expect(
            () => decryptWithKeys(t['payload'] as String,
                u8(t['conversation_key'] as String)),
            throwsA(anything),
            reason: t['note'] as String? ?? 'decrypt');
      }
    });

    test('invalid encrypt uzunlukları fırlatır', () {
      final mk = valid['get_message_keys'] as Map<String, dynamic>;
      final conv = u8(mk['conversation_key'] as String);
      final nonce = u8((mk['keys'] as List).first['nonce'] as String);
      for (final len in invalid['encrypt_msg_lengths'] as List) {
        final fake = 'a' * (len as int);
        expect(() => encryptWithKeys(fake, conv, nonce), throwsA(anything),
            reason: 'length=$len');
      }
    });
  });
}
