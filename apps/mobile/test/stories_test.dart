import 'package:flutter_test/flutter_test.dart';
import 'package:sosyal/core/nostr/event.dart';
import 'package:sosyal/core/nostr/keys.dart';
import 'package:sosyal/core/stories/story.dart';

NostrEvent note(
  KeyPair keys, {
  List<List<String>> tags = const [],
  String content = 'merhaba',
  int? createdAt,
}) =>
    NostrEvent.create(
      kind: EventKind.note,
      content: content,
      keys: keys,
      tags: tags,
      createdAt: createdAt,
    );

void main() {
  final ada = KeyPair.fromPrivateHex('01' * 32);
  final bora = KeyPair.fromPrivateHex('02' * 32);
  final now = DateTime.fromMillisecondsSinceEpoch(1800000000000);
  final nowSec = now.millisecondsSinceEpoch ~/ 1000;

  group('hikâye tanıma', () {
    test('t=story etiketli not hikâyedir (büyük/küçük harf duyarsız)', () {
      expect(Story.isStory(note(ada, tags: [['t', 'story']])), isTrue);
      expect(Story.isStory(note(ada, tags: [['t', 'STORY']])), isTrue);
    });

    test('etiketsiz not hikâye değildir', () {
      expect(Story.isStory(note(ada)), isFalse);
      expect(Story.isStory(note(ada, tags: [['t', 'gündem']])), isFalse);
    });

    test('hikâye yalnız kind:1 ile tanınır', () {
      final profile = NostrEvent.create(
        kind: EventKind.profile,
        content: '{}',
        keys: ada,
        tags: [
          ['t', 'story']
        ],
      );
      expect(Story.isStory(profile), isFalse);
    });
  });

  group('son kullanma', () {
    test('NIP-40 expiration etiketi okunur', () {
      final e = note(ada, tags: [
        ['expiration', '${nowSec + 60}']
      ]);
      expect(Story.expirationSeconds(e), nowSec + 60);
    });

    test('expiration yoksa yaştan hesaplanır (24 saat)', () {
      final fresh = note(ada, createdAt: nowSec - 60);
      final stale = note(ada, createdAt: nowSec - Story.ttl.inSeconds - 1);
      expect(Story.isExpired(fresh, now: now), isFalse);
      expect(Story.isExpired(stale, now: now), isTrue);
    });

    test('expiration geçmişse süre dolmuştur', () {
      final e = note(ada, createdAt: nowSec - 5, tags: [
        ['expiration', '${nowSec - 1}']
      ]);
      expect(Story.isExpired(e, now: now), isTrue);
    });
  });

  group('yayın etiketleri', () {
    test('t=story ve 24 saat sonrası expiration eklenir', () {
      final tags = Story.tagsFor(now: now);
      expect(tags.first, ['t', 'story']);
      final exp = tags.firstWhere((t) => t[0] == 'expiration');
      expect(int.parse(exp[1]), nowSec + Story.ttl.inSeconds);
    });
  });

  group('gruplama', () {
    test('süresi dolan ve sessize alınanlar dışarıda kalır', () {
      final active = note(ada, tags: [
        ['t', 'story']
      ], createdAt: nowSec - 10);
      final expired = note(bora, tags: [
        ['t', 'story'],
        ['expiration', '${nowSec - 10}'],
      ], createdAt: nowSec - 20);
      final muted = note(bora, tags: [
        ['t', 'story']
      ], createdAt: nowSec - 5);

      final groups = Story.group(
        [active, expired, muted],
        now: now,
        isMuted: (pk) => pk == bora.publicKeyHex,
      );
      expect(groups.length, 1);
      expect(groups.single.pubkey, ada.publicKeyHex);
    });

    test('grup içi eskiden yeniye, gruplar en yeniye göre sıralı', () {
      final aOld = note(ada, tags: [
        ['t', 'story']
      ], createdAt: nowSec - 50);
      final aNew = note(ada, tags: [
        ['t', 'story']
      ], createdAt: nowSec - 10);
      final b = note(bora, tags: [
        ['t', 'story']
      ], createdAt: nowSec - 30);

      final groups = Story.group([aOld, aNew, b], now: now);
      expect(groups.map((g) => g.pubkey).toList(),
          [ada.publicKeyHex, bora.publicKeyHex]);
      expect(groups.first.items.map((e) => e.createdAt).toList(),
          [nowSec - 50, nowSec - 10]);
      expect(groups.first.latest.id, aNew.id);
    });

    test('görülmemiş hikâye kontrolü', () {
      final a = note(ada, tags: [
        ['t', 'story']
      ], createdAt: nowSec - 10);
      final b = note(ada, tags: [
        ['t', 'story']
      ], createdAt: nowSec - 5);
      final group = Story.group([a, b], now: now).single;
      expect(group.hasUnseen({a.id}), isTrue);
      expect(group.hasUnseen({a.id, b.id}), isFalse);
    });
  });
}
