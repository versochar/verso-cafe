// Demo arkadaş "B": relay'e ikinci kimlik olarak not, beğeni, yorum,
// repost ve gerçek NIP-44 şifreli DM gönderir. Uçtan uca canlı test aracı.
//
// Kullanım: dart run tool/demo_peer.dart <benim-pub-hex> <not-id>
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:sosyal/core/nostr/event.dart';
import 'package:sosyal/core/nostr/keys.dart';
import 'package:sosyal/core/nostr/nip44.dart';
import 'package:sosyal/core/nostr/relay_client.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('kullanım: dart run tool/demo_peer.dart <pub-hex> <not-id>');
    exit(2);
  }
  final myPub = args[0].toLowerCase();
  final noteId = args[1].toLowerCase();

  // Sabit test anahtarı (yalnızca demo; gerçek kimlik değil).
  final b = KeyPair.fromPrivateHex(
      '0000000000000000000000000000000000000000000000000000000000000002');
  print('B pub: ${b.publicKeyHex}');

  final client = RelayClient('ws://192.168.1.109:7777', reconnect: false);
  await client.connect();

  Future<void> send(String label, NostrEvent event) async {
    final ok = await client.publish(event);
    print('$label: ${ok ? 'GÖNDERİLDİ' : 'REDDEDİLDİ'} (${event.id.substring(0, 12)}…)');
  }

  await send('not   ', NostrEvent.create(
    kind: EventKind.note,
    content: 'Selam mitsune! Ben demo arkadaş B. Bu gönderi akışına düşmeli.',
    keys: b,
  ));
  await send('beğeni', NostrEvent.create(
    kind: EventKind.reaction,
    content: '+',
    keys: b,
    tags: [
      ['e', noteId],
      ['p', myPub],
    ],
  ));
  await send('yorum ', NostrEvent.create(
    kind: EventKind.comment,
    content: 'Süper gönderi! Yorumum da görünsün istiyorum.',
    keys: b,
    tags: [
      ['e', noteId, '', 'root'],
      ['p', myPub],
    ],
  ));
  await send('repost', NostrEvent.create(
    kind: EventKind.repost,
    content: '',
    keys: b,
    tags: [
      ['e', noteId],
      ['p', myPub],
    ],
  ));
  await send('DM    ', NostrEvent.create(
    kind: EventKind.giftWrap,
    content: nip44Encrypt(
      'Merhaba! Bu mesaj gerçek NIP-44 (ECDH+ChaCha20) ile şifrelendi.',
      b.privateKeyHex,
      myPub,
    ),
    keys: b,
    tags: [
      ['p', myPub],
    ],
  ));

  await Future<void>.delayed(const Duration(seconds: 1));
  client.dispose();
  exit(0);
}
