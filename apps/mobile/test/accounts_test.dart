import 'package:flutter_test/flutter_test.dart';
import 'package:sosyal/core/accounts/account_service.dart';
import 'package:sosyal/core/nostr/keys.dart';
import 'package:sosyal/core/nostr/nip49.dart';

void main() {
  group('kullanıcı adı → e-posta köprüsü', () {
    test('ad, hesap alanına e-postaya çevrilir', () {
      expect(emailForUsername('hosthesap'), 'hosthesap@hesap.verso.app');
      expect(emailForUsername('a_b.c9'), 'a_b.c9@hesap.verso.app');
    });

    test('geçerli adlar: küçük harf, rakam, alt çizgi, nokta (3-32)', () {
      for (final ok in ['abc', 'a1b', 'hosthesap', 'a_b', 'a.b', 'x' * 32]) {
        expect(usernamePattern.hasMatch(ok), isTrue, reason: ok);
      }
    });

    test('geçersiz adlar reddedilir', () {
      for (final bad in ['ab', 'a b', 'BuyukHarf', 'üst', 'a' * 33, 'a-b', '']) {
        expect(usernamePattern.hasMatch(bad), isFalse, reason: bad);
      }
    });

    test('köprü çakışamaz: ad deseni @ ve boşluk içermez', () {
      // Gerçek bir e-posta ("someone@gmail") ad olamaz; iki alan karışmaz.
      expect(usernamePattern.hasMatch('someone@gmail'), isFalse);
    });
  });

  group('roller ve yetkiler', () {
    test('bilinmeyen/eksik rol güvenli varsayılana düşer', () {
      expect(AccountRole.parse(null), AccountRole.user);
      expect(AccountRole.parse('yönetici'), AccountRole.user);
      expect(AccountRole.parse('mod'), AccountRole.mod);
      expect(AccountRole.parse('host'), AccountRole.host);
    });

    test('duyuru yazma yetkisi yalnız host ve modda', () {
      Account acc(AccountRole role) =>
          Account(uid: 'u', username: 'a', role: role, pubkey: 'ff');
      expect(acc(AccountRole.host).canAnnounce, isTrue);
      expect(acc(AccountRole.mod).canAnnounce, isTrue);
      expect(acc(AccountRole.user).canAnnounce, isFalse);
      expect(acc(AccountRole.anon).canAnnounce, isFalse);
      expect(acc(AccountRole.user).isHost, isFalse);
      expect(acc(AccountRole.host).isHost, isTrue);
    });

    test('belgeden hesap okuma: eksik alanlar makul varsayılana döner', () {
      final a = Account.fromDoc('uid1', {'username': 'ada', 'role': 'mod'});
      expect(a.username, 'ada');
      expect(a.role, AccountRole.mod);
      final b = Account.fromDoc('uid2', {});
      expect(b.username, 'uid2');
      expect(b.role, AccountRole.user);
      expect(b.canAnnounce, isFalse);
    });
  });

  group('kayıt akışının kriptografi yarısı', () {
    test('üretilen anahtar çifti parola ile paketlenip geri açılır', () async {
      // register() → users/{uid}.ncryptsec → signIn() döngüsünün yerel hâli.
      final keys = KeyPair.generate();
      final packed = await Nip49.encrypt(keys.privateKeyHex, 'parola-1');
      final hex = await Nip49.decrypt(packed, 'parola-1');
      expect(hex, keys.privateKeyHex);
      expect(KeyPair.fromPrivateHex(hex).publicKeyHex, keys.publicKeyHex);
    });

    test('yanlış parola anahtarı geri vermez (giriş reddi)', () async {      final keys = KeyPair.generate();
      final packed = await Nip49.encrypt(keys.privateKeyHex, 'dogru-parola');
      await expectLater(
        Nip49.decrypt(packed, 'yanlis-parola'),
        throwsA(isA<Nip49Exception>()),
      );
    });
  });
}
