// Faz 1 duman testi: iki ayrı istemci, tek relay.
//
//   dart run tool/nostr_smoke.dart
//
// 1) Bech32 gidiş-dönüş testi
// 2) Alice anahtar üretir, kind:0 profil yayınlar
// 3) Bob (ikinci istemci) abone olur ve aynı eventi alır
//
// Android/emülatör gerektirmez. Relay çalışıyor olmalı:
//   ./scripts/relay-start.sh
//
// Konsol aracı olduğu için print kullanımı bilinçlidir.
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sosyal/core/nostr/bech32.dart';
import 'package:sosyal/core/nostr/event.dart';
import 'package:sosyal/core/nostr/keys.dart';
import 'package:sosyal/core/nostr/relay_client.dart';

Future<void> waitConnected(RelayClient client, {Duration timeout = const Duration(seconds: 10)}) async {
  if (client.currentState == RelayState.connected) return;
  await client.state
      .firstWhere((s) => s == RelayState.connected)
      .timeout(timeout, onTimeout: () => throw TimeoutException('Relay bağlantısı kurulamadı: ${client.url}'));
}

void selfTest() {
  final key = KeyPair.generate();
  final decoded = bech32Decode(key.npub);
  if (decoded.hrp != 'npub' || bytesToHex(decoded.data) != key.publicKeyHex) {
    throw StateError('bech32 gidiş-dönüş hatası (npub)');
  }
  final decoded2 = bech32Decode(key.nsec);
  if (decoded2.hrp != 'nsec' || bytesToHex(decoded2.data) != key.privateKeyHex) {
    throw StateError('bech32 gidiş-dönüş hatası (nsec)');
  }
  final ev = NostrEvent.create(kind: 1, content: 'merhaba', keys: key);
  if (!ev.verify()) throw StateError('imza doğrulaması başarısız');
  print('  ✓ bech32 gidiş-dönüş');
  print('  ✓ imza üretimi ve doğrulaması');
  print('  ✓ npub: ${key.npub}');
}

Future<void> main(List<String> args) async {
  final relayUrl = Platform.environment['RELAY_URL'] ?? (args.isNotEmpty ? args.first : 'ws://127.0.0.1:7777');
  print('Relay: $relayUrl');

  print('[1/4] Yerel testler');
  selfTest();

  final alice = KeyPair.generate();

  print('[2/4] Alice bağlanıyor ve profil yayınlıyor');
  final clientA = RelayClient(relayUrl, reconnect: false);
  await clientA.connect();
  await waitConnected(clientA);

  final profile = NostrEvent.create(
    kind: EventKind.profile,
    content: jsonEncode({
      'name': 'smoke-${DateTime.now().millisecondsSinceEpoch}',
      'about': 'Faz 1 duman testi',
    }),
    keys: alice,
  );
  final accepted = await clientA.publish(profile);
  if (!accepted) {
    stderr.writeln('  ✗ Relay eventi kabul etmedi');
    await clientA.dispose();
    exit(1);
  }
  print('  ✓ Yayınlandı: ${profile.id.substring(0, 16)}…');

  print('[3/4] Bob bağlanıyor ve abone oluyor');
  final clientB = RelayClient(relayUrl, reconnect: false);
  final received = Completer<NostrEvent>();
  clientB.events.listen((e) {
    if (e.pubkey == alice.publicKeyHex && e.kind == EventKind.profile && !received.isCompleted) {
      received.complete(e);
    }
  });
  await clientB.connect();
  await waitConnected(clientB);
  clientB.subscribe('smoke', [
    {'kinds': [EventKind.profile], 'authors': [alice.publicKeyHex], 'limit': 5}
  ]);

  print('[4/4] Bekleniyor (10 sn)');
  try {
    final got = await received.future.timeout(const Duration(seconds: 10));
    final ok = got.id == profile.id && got.verify();
    print(ok ? '  ✓ Bob aynı eventi aldı ve imzayı doğruladı' : '  ✗ Event uyuşmuyor');
    await clientA.dispose();
    await clientB.dispose();
    exit(ok ? 0 : 1);
  } on TimeoutException {
    stderr.writeln('  ✗ Event 10 saniye içinde ulaşmadı');
    await clientA.dispose();
    await clientB.dispose();
    exit(1);
  }
}
