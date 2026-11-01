import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sosyal/core/update/update_info.dart';

void main() {
  group('sürüm karşılaştırma', () {
    test('yeni sürüm algılanır', () {
      expect(compareVersions('0.2.0', '0.1.1'), greaterThan(0));
      expect(compareVersions('0.10.0', '0.9.9'), greaterThan(0));
      expect(compareVersions('1.0.0', '0.99.99'), greaterThan(0));
    });

    test('eşit ve eski sürümler güncelleme sayılmaz', () {
      expect(compareVersions('0.1.1', '0.1.1'), 0);
      expect(compareVersions('0.1.0', '0.1.1'), lessThan(0));
      expect(isUpdateAvailable('0.2.0', '0.1.1'), isFalse);
      expect(isUpdateAvailable('0.2.0', null), isFalse);
      expect(isUpdateAvailable('0.2.0', ''), isFalse);
    });

    test('eksik parçalar sıfır sayılır', () {
      expect(compareVersions('0.2', '0.2.0'), 0);
      expect(compareVersions('0.2.1', '0.2'), greaterThan(0));
    });
  });

  group('version.json çözümleme', () {
    test('evrensel asset ve sha256 okunur', () {
      final info = UpdateInfo.tryParse(jsonDecode('''
      {
        "version": "0.2.0",
        "versionCode": 3,
        "notes": "Yeni özellikler",
        "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        "assets": {
          "universal": "https://example.com/u.apk",
          "arm64-v8a": "https://example.com/a64.apk"
        }
      }''') as Map<String, dynamic>);
      expect(info, isNotNull);
      expect(info!.version, '0.2.0');
      expect(info.url, 'https://example.com/u.apk');
      expect(info.sha256, startsWith('01234567'));
      expect(info.notes, 'Yeni özellikler');
    });

    test('evrenzel yoksa arm64’e düşülür', () {
      final info = UpdateInfo.tryParse(jsonDecode('''
      {
        "version": "0.2.0",
        "assets": { "arm64-v8a": "https://example.com/a64.apk" }
      }''') as Map<String, dynamic>);
      expect(info!.url, 'https://example.com/a64.apk');
      expect(info.sha256, isNull);
    });

    test('geçersiz json reddedilir', () {
      expect(UpdateInfo.tryParse({'notes': 'sürümsüz'}), isNull);
      expect(
          UpdateInfo.tryParse({
            'version': '1.0.0',
            'assets': {'universal': 'ftp://olmaz'}
          }),
          isNull);
      // Geçersiz sha256 sürüm bilgisini bozmaz, sadece yok sayılır.
      final info = UpdateInfo.tryParse({
        'version': '1.0.0',
        'sha256': 'kısa',
        'assets': {'universal': 'https://example.com/u.apk'}
      });
      expect(info!.sha256, isNull);
    });
  });

  group('cihaz mimarisine göre paket seçimi', () {
    const sha64 =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const sha32 =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    final json = {
      'version': '0.2.0',
      'assets': {
        'arm64-v8a': 'https://example.com/a64.apk',
        'armeabi-v7a': 'https://example.com/a32.apk',
      },
      'sha256': {'arm64-v8a': sha64, 'armeabi-v7a': sha32},
    };

    test('armv7 telefon armv7 paketini ve onun özetini alır', () {
      final info = UpdateInfo.tryParse(json, abi: 'armeabi-v7a');
      expect(info!.url, 'https://example.com/a32.apk');
      expect(info.sha256, sha32);
    });

    test('arm64 telefon arm64 paketini alır', () {
      final info = UpdateInfo.tryParse(json, abi: 'arm64-v8a');
      expect(info!.url, 'https://example.com/a64.apk');
      expect(info.sha256, sha64);
    });

    test('mimarisi bilinmeyen cihaz evrensel varsa evrenseli seçer', () {
      final info = UpdateInfo.tryParse({
        'version': '0.2.0',
        'sha256': sha64,
        'assets': {
          'universal': 'https://example.com/u.apk',
          'arm64-v8a': 'https://example.com/a64.apk',
        },
      }, abi: 'bilinmeyen');
      expect(info!.url, 'https://example.com/u.apk');
      expect(info.sha256, sha64);
    });

    test('başka mimarinin özeti kullanılmaz', () {
      final info = UpdateInfo.tryParse({
        'version': '0.2.0',
        'assets': {'arm64-v8a': 'https://example.com/a64.apk'},
        'sha256': {'armeabi-v7a': sha32},
      }, abi: 'arm64-v8a');
      expect(info!.url, 'https://example.com/a64.apk');
      expect(info.sha256, isNull);
    });
  });
}
