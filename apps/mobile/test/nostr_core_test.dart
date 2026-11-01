import 'package:flutter_test/flutter_test.dart';
import 'package:sosyal/core/nostr/bech32.dart';
import 'package:sosyal/core/nostr/event.dart';
import 'package:sosyal/core/nostr/keys.dart';

void main() {
  group('bech32 / NIP-19', () {
    // NIP-19 dokümanındaki örnek.
    const privHex = '67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffa';
    const privBech = 'nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5';

    test('bilinen nsec vektörü çözülür', () {
      final decoded = bech32Decode(privBech);
      expect(decoded.hrp, 'nsec');
      expect(bytesToHex(decoded.data), privHex);
    });

    test('nsec yeniden kodlanır', () {
      expect(bech32Encode('nsec', hexToBytes(privHex)), privBech);
    });

    test('npub gidiş-dönüş', () {
      final key = KeyPair.generate();
      final decoded = bech32Decode(key.npub);
      expect(decoded.hrp, 'npub');
      expect(bytesToHex(decoded.data), key.publicKeyHex);
    });

    test('bozuk sağlama toplamı reddedilir', () {
      final broken = '${privBech.substring(0, privBech.length - 1)}q';
      expect(() => bech32Decode(broken), throwsFormatException);
    });
  });

  group('event', () {
    test('imza ve id doğrulanır', () {
      final keys = KeyPair.generate();
      final event = NostrEvent.create(kind: 1, content: 'merhaba dünya', keys: keys);
      expect(event.verify(), isTrue);
    });

    test('içerik değiştirilirse doğrulama başarısız olur', () {
      final keys = KeyPair.generate();
      final event = NostrEvent.create(kind: 1, content: 'orijinal', keys: keys);
      final tampered = NostrEvent(
        id: event.id,
        pubkey: event.pubkey,
        createdAt: event.createdAt,
        kind: event.kind,
        tags: event.tags,
        content: 'değiştirilmiş',
        sig: event.sig,
      );
      expect(tampered.verify(), isFalse);
    });

    test('kind:0 profil içeriği json olarak saklanır', () {
      final keys = KeyPair.generate();
      final event = NostrEvent.create(
        kind: EventKind.profile,
        content: '{"name":"test"}',
        keys: keys,
      );
      expect(event.kind, 0);
      expect(event.content, contains('test'));
      expect(event.verify(), isTrue);
    });
  });
}
