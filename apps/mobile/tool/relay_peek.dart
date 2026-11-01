// Relay'i dışarıdan yoklar: verilen türdeki son event'leri basar.
//
//   RELAY_URL=wss://… dart run tool/relay_peek.dart 1 5
//
// Uygulamanın/public relay'in gerçekten aynı veriyi gördüğünü doğrulamak için
// kullanılır (telefon ile sunucu arasındaki yolu bağımsız kanıtlar).
// Konsol aracı olduğu için print kullanımı bilinçlidir.
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:sosyal/core/nostr/relay_client.dart';

Future<void> main(List<String> args) async {
  final relayUrl =
      Platform.environment['RELAY_URL'] ?? (args.length > 2 ? args[2] : 'ws://127.0.0.1:7777');
  final kinds = (args.isNotEmpty ? args.first : '1')
      .split(',')
      .map(int.parse)
      .toList(growable: false);
  final limit = args.length > 1 ? int.parse(args[1]) : 5;

  final client = RelayClient(relayUrl, reconnect: false);
  final seen = <String>{};
  final done = Completer<void>();
  client.events.listen((e) {
    if (!seen.add(e.id)) return;
    final when = DateTime.fromMillisecondsSinceEpoch(e.createdAt * 1000)
        .toIso8601String()
        .substring(0, 19);
    final text = e.content.replaceAll(RegExp(r'\s+'), ' ');
    print('kind=${e.kind}  ${e.pubkey.substring(0, 8)}  $when  '
        '${text.length > 60 ? '${text.substring(0, 60)}…' : text}  '
        '${e.verify() ? '✓' : '✗ imza'}');
    if (seen.length >= limit && !done.isCompleted) done.complete();
  });

  await client.connect();
  // `state` yalnız değişimde yayar; connect() sırasında bağlandıysa kaçar.
  if (client.currentState != RelayState.connected) {
    await client.state
        .firstWhere((s) => s == RelayState.connected)
        .timeout(const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException('bağlanılamadı: $relayUrl'));
  }
  client.subscribe('peek', [
    {'kinds': kinds, 'limit': limit}
  ]);

  await done.future.timeout(const Duration(seconds: 12), onTimeout: () {});
  print('— ${seen.length} event alındı ($relayUrl)');
  await client.dispose();
  exit(0);
}
