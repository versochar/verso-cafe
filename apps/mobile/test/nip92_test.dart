import 'package:flutter_test/flutter_test.dart';

import 'package:sosyal/core/media/nip92.dart';

void main() {
  group('NIP-92', () {
    test('buildImetaTag', () {
      final tag = buildImetaTag(
        url: 'https://example.com/img.webp',
        mimeType: 'image/webp',
        sha256Hex: 'aabbcc',
        sizeBytes: 1024,
        dimensions: '800x600',
        altText: 'test',
      );
      expect(tag.contains('url https://example.com/img.webp'), isTrue);
      expect(tag.contains('m image/webp'), isTrue);
      expect(tag.contains('x aabbcc'), isTrue);
      expect(tag.contains('size 1024'), isTrue);
      expect(tag.contains('dim 800x600'), isTrue);
      expect(tag.contains('alt test'), isTrue);
    });

    test('imetaTags', () {
      final tags = imetaTags(url: 'https://x', mimeType: 'image/png');
      expect(tags, isA<List<List<String>>>());
      expect(tags[0][0], 'imeta');
      expect(tags[0][1], 'https://x');
      expect(tags[0][2], 'm image/png');
    });
  });
}
