import 'package:flutter_test/flutter_test.dart';
import 'package:sosyal/core/nostr/bech32.dart';
import 'package:sosyal/core/nostr/nip49.dart';

void main() {
  group('NIP-49', () {
    // NIP-49 dokümanındaki resmi vektör.
    const vectorCipher =
        'ncryptsec1qgg9947rlpvqu76pj5ecreduf9jxhselq2nae2kghhvd5g7dgjtcxfqtd67p9m0w5'
        '7lspw8gsq6yphnm8623nsl8xn9j4jdzz84zm3frztj3z7s35vpzmqf6ksu8r89qk5z2zxfmu5gv8'
        'th8wclt0h4p';
    const vectorPassword = 'nostr';
    const vectorPrivHex =
        '3501454135014541350145413501453fefb02227e449e57cf4d3a3ce05378683';

    test('resmi vektör doğru çözülür', () async {
      final hex = await Nip49.decrypt(vectorCipher, vectorPassword);
      expect(hex, vectorPrivHex);
    });

    test('log_n vektörden okunur', () {
      expect(Nip49.logNOf(vectorCipher), 16);
    });

    test('yanlış parola reddedilir', () async {
      await expectLater(
        Nip49.decrypt(vectorCipher, 'yanlis-parola'),
        throwsA(isA<Nip49Exception>()),
      );
    });

    test('gidiş-dönüş: şifrele → çöz', () async {
      const privHex =
          '67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffa';
      final encrypted = await Nip49.encrypt(privHex, 'çok gizli 🔐 parola');
      expect(encrypted.startsWith('ncryptsec1'), isTrue);
      // 91 bayt → 146 bech32 karakter + hrp + '1' + 6 sağlama
      expect(encrypted.length, 'ncryptsec1'.length + 146 + 6);
      expect(await Nip49.decrypt(encrypted, 'çok gizli 🔐 parola'), privHex);
    });

    test('Unicode parola NFKC normalize edilir (resmi vektör)', () async {
      // "ÅΩẛ̣" → NFKC → "ÅΩẹ"
      const raw = '\u212B\u2126\u1E9B\u0323';
      const normalized = '\u00C5\u03A9\u1E69';
      const privHex =
          '67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffa';

      final encrypted = await Nip49.encrypt(privHex, raw, logN: 10);
      // Normalize edilmemiş parola ile de açılmalı: implementasyon NFKC uygular.
      expect(await Nip49.decrypt(encrypted, normalized), privHex);
      expect(await Nip49.decrypt(encrypted, raw), privHex);
    });

    test('boş parola reddedilir', () async {
      expect(
        () => Nip49.encrypt(
          '67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffa',
          '',
        ),
        throwsA(isA<Nip49Exception>()),
      );
    });

    test('nsec yedeği ncryptsec olarak algılanmaz', () async {
      await expectLater(
        Nip49.decrypt(
          'nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5',
          'nostr',
        ),
        throwsA(isA<Nip49Exception>()),
      );
    });

    test('tek karakteri bozulmuş yedek reddedilir', () async {
      final broken = vectorCipher.replaceFirst('qgg9', 'qgg8');
      await expectLater(
        Nip49.decrypt(broken, vectorPassword),
        throwsA(isA<Nip49Exception>()),
      );
    });

    test('bech32 uzun stringleri destekler', () {
      final bytes = List<int>.generate(91, (i) => i);
      final encoded = bech32Encode('ncryptsec', bytes);
      expect(encoded.length, greaterThan(90));
      expect(bech32Decode(encoded).data, bytes);
    });
  });
}
