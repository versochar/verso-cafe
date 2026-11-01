import 'package:flutter_test/flutter_test.dart';
import 'package:sosyal/core/config/app_config.dart';
import 'package:sosyal/core/config/endpoints.dart';

void main() {
  group('network.json doğrulama', () {
    test('şifreli adresler kabul edilir', () {
      final p = Endpoints.parse({
        'relay': 'wss://rica-pulse-repairs-trademark.trycloudflare.com',
        'media': 'https://questionnaire-executed-actress-watches.trycloudflare.com',
      });
      expect(p.relay, startsWith('wss://'));
      expect(p.media, startsWith('https://'));
    });

    test('şifresiz şema yalnız yerel geliştirme adreslerinde geçer', () {
      for (final relay in ['ws://127.0.0.1:7777', 'ws://localhost:7777',
          'ws://10.0.2.2:7777']) {
        expect(Endpoints.parse({'relay': relay}).relay, relay, reason: relay);
      }
      // İnternet üzerinden gelen yapılandırma uygulamayı cleartext'e düşüremez.
      expect(Endpoints.parse({'relay': 'ws://ornek.com:7777'}).relay, isNull);
      expect(Endpoints.parse({'media': 'http://ornek.com:8080'}).media, isNull);
      expect(Endpoints.parse({'relay': 'http://127.0.0.1:7777'}).relay, isNull);
    });

    test('boş, eksik ve yanlış şemalı alanlar yok sayılır', () {
      expect(Endpoints.parse({}).relay, isNull);
      expect(Endpoints.parse({}).media, isNull);
      expect(Endpoints.parse({'relay': ''}).relay, isNull);
      expect(Endpoints.parse({'relay': 'wss://'}).relay, isNull);
      expect(Endpoints.parse({'relay': 'ftp://ornek.com'}).relay, isNull);
      expect(Endpoints.parse({'relay': 'sadece-metin'}).relay, isNull);
    });

    test('geçerli alan, geçersiz komşusunu kurtarmaz', () {
      final p = Endpoints.parse({
        'relay': 'wss://relay.ornek.com',
        'media': 'bozuk',
      });
      expect(p.relay, 'wss://relay.ornek.com');
      expect(p.media, isNull);
    });
  });

  group('apply', () {
    test('adresleri değiştirir, ikinci kez değişiklik bildirmez', () {
      final oldRelay = AppConfig.relayUrl;
      final oldMedia = AppConfig.mediaUrl;
      addTearDown(() {
        AppConfig.relayUrl = oldRelay;
        AppConfig.mediaUrl = oldMedia;
      });

      const json = {
        'relay': 'wss://relay.ornek.com',
        'media': 'https://medya.ornek.com',
      };
      expect(Endpoints.apply(json), isTrue);
      expect(AppConfig.relayUrl, 'wss://relay.ornek.com');
      expect(AppConfig.mediaUrl, 'https://medya.ornek.com');
      expect(Endpoints.apply(json), isFalse);
    });

    test('geçersiz içerik gömülü adresi bozmaz', () {
      final oldRelay = AppConfig.relayUrl;
      addTearDown(() => AppConfig.relayUrl = oldRelay);

      expect(Endpoints.apply({'relay': 'ws://kotu.example'}), isFalse);
      expect(AppConfig.relayUrl, oldRelay);
    });
  });
}
